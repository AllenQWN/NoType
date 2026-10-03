import Foundation

/// 本地 AI 引擎（Ollama）+ 千问模型的一键安装与状态管理。
/// 不依赖 Homebrew：下载 Ollama 官方包，解包到 NoType 自己的数据目录，自包含运行。
/// 引擎下载走 GitHub 镜像（国内可访问）优先、直连兜底。
final class AIEngineManager: ObservableObject {

    enum Phase: Equatable {
        case idle              // 尚未检测
        case notInstalled      // 引擎未安装
        case engineInstalled   // 引擎已装，但服务未跑 / 模型未拉
        case ready             // 模型就绪，润色可用
        case working           // 正在执行安装流程（步骤文字见 detail）
        case failed            // 出错（原因见 detail）
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var detail: String = ""
    @Published private(set) var progress: Double = -1   // 0~1，-1 表示不确定

    static let shared = AIEngineManager()
    static let modelName = "qwen2.5:7b"
    static let endpoint = "http://127.0.0.1:11434"

    // 引擎包实际下载路径（GitHub release），镜像前缀依次尝试，最后直连兜底
    private let engineRawPath = "https://github.com/ollama/ollama/releases/latest/download/Ollama.dmg"
    private let engineMirrors = ["https://gh-proxy.com/", "https://ghfast.top/"]

    private var serverProcess: Process?
    private var working = false

    // MARK: - 路径

    private var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("NoType", isDirectory: true)
    }
    private var selfAppDir: URL { supportDir.appendingPathComponent("Ollama.app") }
    private var selfCLI: URL { selfAppDir.appendingPathComponent("Contents/Resources/ollama") }

    private var candidateCLIs: [URL] {
        [
            selfCLI,
            URL(fileURLWithPath: "/opt/homebrew/bin/ollama"),
            URL(fileURLWithPath: "/usr/local/bin/ollama"),
            URL(fileURLWithPath: "/Applications/Ollama.app/Contents/Resources/ollama"),
        ]
    }

    private func existingCLI() -> URL? {
        candidateCLIs.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    // MARK: - 状态刷新

    /// App 启动时调用：已装引擎则尝试拉起服务，然后刷新整体状态；未装则标记 notInstalled。
    func bootstrap() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            guard let cli = self.existingCLI() else {
                self.publish(.notInstalled, "尚未安装本地 AI 引擎", -1)
                return
            }
            if !self.serverReachable() {
                try? self.spawnServer(cli: cli)
            }
            self.refreshStatus()
        }
    }

    /// 重新检测引擎 / 服务 / 模型状态。
    func refreshStatus() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            guard self.existingCLI() != nil else {
                self.publish(.notInstalled, "尚未安装本地 AI 引擎", -1)
                return
            }
            if !self.serverReachable() {
                self.publish(.engineInstalled, "引擎已安装，服务未启动", -1)
                return
            }
            if self.modelPulled() {
                self.publish(.ready, "本地 AI 已就绪，润色与翻译可用", 1)
            } else {
                self.publish(.engineInstalled, "引擎已就绪，尚未下载模型", -1)
            }
        }
    }

    // MARK: - 一键安装

    func install() {
        guard !working else { return }
        working = true
        publish(.working, "准备安装…", -1)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer { self?.working = false }
            self?.runInstall()
        }
    }

    private func runInstall() {
        do {
            // 1) 引擎
            var cli = existingCLI()
            if cli == nil {
                progressTo(0.0, "正在下载 Ollama 引擎（约 189MB）…")
                try downloadEngine()
                cli = selfCLI
            }
            guard let cli = cli else {
                publish(.failed, "未能定位 Ollama 引擎", -1)
                return
            }

            // 2) 启动服务
            progressTo(0.28, "正在启动本地服务…")
            if !serverReachable() {
                try spawnServer(cli: cli)
                try waitForServer(timeout: 30)
            }

            // 3) 拉模型
            if !modelPulled() {
                try pullModel(cli: cli)
            }

            publish(.ready, "本地 AI 已就绪，润色与翻译可用", 1)
        } catch {
            publish(.failed, "安装失败：\(friendlyError(error))", -1)
        }
    }

    // MARK: - 下载引擎

    private func downloadEngine() throws {
        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        let dmgPath = supportDir.appendingPathComponent("Ollama.dmg")
        guard let url = resolveEngineURL() else {
            throw NSError(domain: "AIEngine", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "无法访问 Ollama 下载源，请检查网络或使用代理后重试"])
        }
        try download(url: url, to: dmgPath) { [weak self] downloaded, total, speed in
            guard let self = self else { return }
            let fraction = total > 0 ? Double(downloaded) / Double(total) : 0
            var text = "正在下载 Ollama 引擎… \(Int(fraction * 100))%"
            if speed > 0 { text += " · \(self.formatSpeed(speed))" }
            if total > 0 { text += "  (\(self.formatBytes(downloaded)) / \(self.formatBytes(total)))" }
            self.publish(.working, text, 0.25 * fraction)
        }

        let mount = FileManager.default.temporaryDirectory
            .appendingPathComponent("notype-ollama-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: dmgPath)   // 释放磁盘
        }
        do {
            try runCmd("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-mountpoint", mount.path, dmgPath.path])
        } catch {
            throw NSError(domain: "AIEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "挂载 Ollama 安装包失败：\(friendlyError(error))"])
        }
        defer { _ = try? runCmd("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }

        let srcApp = mount.appendingPathComponent("Ollama.app")
        guard FileManager.default.fileExists(atPath: srcApp.path) else {
            throw NSError(domain: "AIEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "安装包中未找到 Ollama.app"])
        }
        if FileManager.default.fileExists(atPath: selfAppDir.path) {
            try FileManager.default.removeItem(at: selfAppDir)
        }
        try FileManager.default.copyItem(at: srcApp, to: selfAppDir)
    }

    // 按「镜像优先、直连兜底」选一个可访问的下载源。
    private func resolveEngineURL() -> URL? {
        for mirror in engineMirrors {
            if let u = URL(string: mirror + engineRawPath), probeOK(u) { return u }
        }
        if let direct = URL(string: engineRawPath), probeOK(direct) { return direct }
        return nil
    }

    // 用 Range 请求探测源是否可达（1 字节，不实际下载）。
    private func probeOK(_ url: URL) -> Bool {
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            if let r = resp as? HTTPURLResponse, (200...299).contains(r.statusCode), data != nil {
                ok = true
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 10)
        return ok
    }

    // MARK: - 服务与模型

    private func spawnServer(cli: URL) throws {
        let p = Process()
        p.executableURL = cli
        p.arguments = ["serve"]
        p.standardOutput = nil
        p.standardError = nil
        try p.run()
        serverProcess = p   // 保有引用，App 存活期间服务存活
    }

    private func waitForServer(timeout: Int) throws {
        let deadline = Date().addingTimeInterval(TimeInterval(timeout))
        while Date() < deadline {
            if serverReachable() { return }
            Thread.sleep(forTimeInterval: 0.5)
        }
        throw NSError(domain: "AIEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "服务启动超时"])
    }

    private func serverReachable() -> Bool {
        return (try? httpGet("/api/tags")) != nil
    }

    private func modelPulled() -> Bool {
        guard let json = try? httpGet("/api/tags"),
              let models = json["models"] as? [[String: Any]] else { return false }
        return models.contains {
            (($0["name"] as? String) ?? "").hasPrefix(Self.modelName)
        }
    }

    private func pullModel(cli: URL) throws {
        publish(.working, "正在下载千问模型（约 4.7GB，视网速几分钟）…", -1)
        let p = Process()
        p.executableURL = cli
        p.arguments = ["pull", Self.modelName]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe

        let parseQueue = DispatchQueue(label: "notype.pullparse")
        var lineBuffer = ""
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            parseQueue.async {
                guard let self = self else { return }
                lineBuffer += chunk
                while let nl = lineBuffer.firstIndex(of: "\n") {
                    let line = String(lineBuffer[..<nl]).trimmingCharacters(in: .whitespacesAndNewlines)
                    lineBuffer = String(lineBuffer[lineBuffer.index(after: nl)...])
                    self.handlePullLine(line)
                }
            }
        }

        try p.run()
        p.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil

        guard p.terminationStatus == 0 else {
            throw NSError(domain: "AIEngine", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "模型下载失败"])
        }
    }

    private func handlePullLine(_ line: String) {
        let clean = line.replacingOccurrences(of: "\u{001B}[", with: "")
        if clean.contains("manifest") {
            progressTo(0.30, "正在获取模型清单…")
        } else if clean.contains("success") {
            progressTo(1.0, "模型下载完成")
        } else if clean.contains("writing") {
            progressTo(0.98, "正在写入模型…")
        } else if clean.contains("verifying") {
            progressTo(0.96, "正在校验模型…")
        } else if let r = clean.range(of: #"(\d+(?:\.\d+)?)%"#, options: .regularExpression) {
            if let percent = Double(clean[r].replacingOccurrences(of: "%", with: "")) {
                let mapped = 0.30 + 0.66 * (percent / 100.0)
                var text = "正在下载千问模型… \(Int(percent))%"
                if let sp = clean.range(of: #"\d+(?:\.\d+)? ?(?:GB|MB|KB|B)/s"#, options: .regularExpression) {
                    text += " · \(clean[sp])"
                } else if let sz = lastSize(from: clean) {
                    text += " · 已下 \(sz)"
                }
                progressTo(mapped, text)
            }
        }
    }

    // 提取 ollama pull 行里的「X GB / Y GB」最后一段已下载大小
    private func lastSize(from line: String) -> String? {
        let matches = line.nsMatches(regex: #"[\d.]+ ?(?:GB|MB|KB|B)"#)
        guard let last = matches.last else { return nil }
        return (line as NSString).substring(with: last)
    }

    // MARK: - 基础工具

    @discardableResult
    private func runCmd(_ bin: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        try p.run()
        p.waitUntilExit()
        let str = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if p.terminationStatus != 0 {
            throw NSError(domain: "AIEngine", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: str.trimmingCharacters(in: .whitespacesAndNewlines)])
        }
        return str
    }

    private func httpGet(_ path: String) throws -> [String: Any] {
        guard let url = URL(string: "\(Self.endpoint)\(path)") else {
            throw NSError(domain: "AIEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "endpoint 无效"])
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        let sem = DispatchSemaphore(value: 0)
        var result: Result<[String: Any], Error>?
        URLSession.shared.dataTask(with: req) { data, _, err in
            if let err = err {
                result = .failure(err)
            } else if let d = data, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                result = .success(j)
            } else {
                result = .failure(NSError(domain: "AIEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "响应解析失败"]))
            }
            sem.signal()
        }.resume()
        sem.wait()
        switch result {
        case .success(let j): return j
        case .failure(let e): throw e
        case .none: throw NSError(domain: "AIEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "请求无结果"])
        }
    }

    private func download(url: URL, to dest: URL, progress: @escaping (Int64, Int64, Int64) -> Void) throws {
        let delegate = Downloader()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let sem = DispatchSemaphore(value: 0)
        var result: Result<Void, Error>?
        delegate.onProgress = { d, t, s in DispatchQueue.main.async { progress(d, t, s) } }
        delegate.onDone = { err in
            result = (err == nil) ? .success(()) : .failure(err!)
            sem.signal()
        }
        let task = session.downloadTask(with: url)
        task.resume()
        sem.wait()
        session.invalidateAndCancel()
        if case .failure(let e) = result { throw e }
        if case .none = result { throw NSError(domain: "AIEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "下载无响应"]) }
        guard let tmp = delegate.finishedURL else {
            throw NSError(domain: "AIEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "下载未完成"])
        }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
    }

    // MARK: - 进度与状态发布

    private func progressTo(_ p: Double, _ text: String) {
        self.publish(.working, text, p)
    }

    private func publish(_ phase: Phase, _ detail: String, _ progress: Double) {
        DispatchQueue.main.async {
            self.phase = phase
            self.detail = detail
            self.progress = progress
            nlog("AIEngine: \(detail)")
        }
    }

    private func friendlyError(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return "网络错误，请检查网络后重试"
        }
        let msg = ns.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return msg.isEmpty ? "未知错误" : msg
    }

    private func formatBytes(_ b: Int64) -> String {
        let d = Double(b)
        if d >= 1_000_000_000 { return String(format: "%.1f GB", d / 1_000_000_000) }
        if d >= 1_000_000 { return String(format: "%.1f MB", d / 1_000_000) }
        if d >= 1_000 { return String(format: "%.0f KB", d / 1_000) }
        return "\(b) B"
    }

    private func formatSpeed(_ bps: Int64) -> String {
        let d = Double(bps)
        if d >= 1_000_000 { return String(format: "%.1f MB/s", d / 1_000_000) }
        if d >= 1_000 { return String(format: "%.0f KB/s", d / 1_000) }
        return "\(bps) B/s"
    }
}

/// URLSessionDownloadDelegate 实现，用于带进度与速度下载。
private final class Downloader: NSObject, URLSessionDownloadDelegate {
    var onProgress: ((Int64, Int64, Int64) -> Void)?   // (已下载, 总量, 速度B/s)
    var onDone: ((Error?) -> Void)?
    var finishedURL: URL?
    private var startTime = Date()

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let elapsed = Date().timeIntervalSince(startTime)
        let speed = elapsed > 0.5 ? Int64(Double(totalBytesWritten) / elapsed) : 0
        onProgress?(totalBytesWritten, totalBytesExpectedToWrite, speed)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("notype-dl-\(UUID().uuidString)")
        try? FileManager.default.moveItem(at: location, to: tmp)
        finishedURL = tmp
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        onDone?(error)
    }
}

private extension String {
    func nsMatches(regex: String) -> [NSRange] {
        guard let re = try? NSRegularExpression(pattern: regex) else { return [] }
        return re.matches(in: self, range: NSRange(self.startIndex..., in: self))
            .map { $0.range }
    }
}