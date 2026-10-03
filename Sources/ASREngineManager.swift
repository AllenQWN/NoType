import Foundation

/// 本地语音识别引擎（SenseVoice，跑在 sherpa-onnx 上）的一键安装与状态管理。
/// 不依赖 Homebrew / Python / pip：下载 sherpa-onnx 预编译运行时与 SenseVoice 模型，
/// 解包到 NoType 自己的数据目录，自包含离线运行。下载走 GitHub 镜像（国内可访问）优先、直连兜底。
final class ASREngineManager: ObservableObject {

    enum Phase: Equatable {
        case idle              // 尚未检测
        case notInstalled      // 引擎未装或部分未装
        case ready             // 引擎 + 模型就绪，识别可用
        case working           // 正在执行安装流程（步骤见 detail）
        case failed            // 出错（原因见 detail）
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var detail: String = ""
    @Published private(set) var progress: Double = -1   // 0~1，-1 表示不确定

    static let shared = ASREngineManager()

    // 下载源（GitHub release），镜像前缀依次尝试，最后直连兜底
    private let runtimeRawPath = "https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.8/sherpa-onnx-v1.13.8-osx-arm64-shared.tar.bz2"
    private let modelRawPath = "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09.tar.bz2"
    private let mirrors = ["https://gh-proxy.com/", "https://ghfast.top/"]

    private var working = false

    // MARK: - 路径

    private var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("NoType", isDirectory: true)
    }
    private var asrDir: URL { supportDir.appendingPathComponent("asr", isDirectory: true) }

    var offlineBinary: URL { asrDir.appendingPathComponent("bin/sherpa-onnx-offline") }
    var libDir: URL { asrDir.appendingPathComponent("lib", isDirectory: true) }
    var modelFile: URL { asrDir.appendingPathComponent("model/model.int8.onnx") }
    var tokensFile: URL { asrDir.appendingPathComponent("model/tokens.txt") }

    private var onnxruntimeLib: URL { libDir.appendingPathComponent("libonnxruntime.dylib") }

    func isRuntimeReady() -> Bool {
        FileManager.default.isExecutableFile(atPath: offlineBinary.path)
            && FileManager.default.fileExists(atPath: onnxruntimeLib.path)
    }
    func isModelReady() -> Bool {
        FileManager.default.fileExists(atPath: modelFile.path)
            && FileManager.default.fileExists(atPath: tokensFile.path)
    }
    func isReady() -> Bool { isRuntimeReady() && isModelReady() }

    // MARK: - 状态刷新

    func bootstrap() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.refreshStatus()
        }
    }

    func refreshStatus() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            if self.isReady() {
                self.publish(.ready, "本地识别引擎已就绪，SenseVoice 可用", 1)
            } else if self.isRuntimeReady() {
                self.publish(.notInstalled, "识别引擎已装，模型未下载", -1)
            } else {
                self.publish(.notInstalled, "尚未安装本地识别引擎", -1)
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
            try FileManager.default.createDirectory(at: asrDir, withIntermediateDirectories: true)

            if !isRuntimeReady() {
                try installRuntime()
            }
            if !isModelReady() {
                try installModel()
            }
            publish(.ready, "本地识别引擎已就绪，SenseVoice 可用", 1)
        } catch {
            publish(.failed, "安装失败：\(friendlyError(error))", -1)
        }
    }

    private func installRuntime() throws {
        progressTo(0.0, "正在下载识别引擎运行时（约 20MB）…")
        let tarPath = asrDir.appendingPathComponent("sherpa-runtime.tar.bz2")
        guard let url = resolveURL(runtimeRawPath) else {
            throw NSError(domain: "ASR", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "无法访问引擎下载源，请检查网络或使用代理后重试"])
        }
        try download(url: url, to: tarPath) { [weak self] d, t, s in
            guard let self = self else { return }
            let f = t > 0 ? Double(d) / Double(t) : 0
            var text = "正在下载识别引擎运行时… \(Int(f * 100))%"
            if s > 0 { text += " · \(self.formatSpeed(s))" }
            self.publish(.working, text, 0.30 * f)
        }
        defer { try? FileManager.default.removeItem(at: tarPath) }

        progressTo(0.30, "正在解压识别引擎…")
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("notype-asr-rt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        try runCmd("/usr/bin/tar", ["-xjf", tarPath.path, "-C", tmp.path])

        let all = findAll(in: tmp)
        guard let bin = all.first(where: { $0.lastPathComponent == "sherpa-onnx-offline" }),
              let lib = all.first(where: { $0.lastPathComponent == "libonnxruntime.dylib" }) else {
            throw NSError(domain: "ASR", code: -1, userInfo: [NSLocalizedDescriptionKey: "引擎包中未找到所需文件"])
        }
        try FileManager.default.createDirectory(at: offlineBinary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: libDir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: offlineBinary.path) { try FileManager.default.removeItem(at: offlineBinary) }
        if FileManager.default.fileExists(atPath: onnxruntimeLib.path) { try FileManager.default.removeItem(at: onnxruntimeLib) }
        try FileManager.default.copyItem(at: bin, to: offlineBinary)
        try FileManager.default.copyItem(at: lib, to: onnxruntimeLib)
        try runCmd("/bin/chmod", ["+x", offlineBinary.path])
    }

    private func installModel() throws {
        progressTo(0.31, "正在下载识别模型（约 166MB）…")
        let tarPath = asrDir.appendingPathComponent("sensevoice.tar.bz2")
        guard let url = resolveURL(modelRawPath) else {
            throw NSError(domain: "ASR", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法访问模型下载源，请检查网络后重试"])
        }
        try download(url: url, to: tarPath) { [weak self] d, t, s in
            guard let self = self else { return }
            let f = t > 0 ? Double(d) / Double(t) : 0
            var text = "正在下载识别模型… \(Int(f * 100))%"
            if s > 0 { text += " · \(self.formatSpeed(s))" }
            if t > 0 { text += "  (\(self.formatBytes(d)) / \(self.formatBytes(t)))" }
            self.publish(.working, text, 0.31 + 0.60 * f)
        }
        defer { try? FileManager.default.removeItem(at: tarPath) }

        progressTo(0.92, "正在解压识别模型…")
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("notype-asr-model-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        try runCmd("/usr/bin/tar", ["-xjf", tarPath.path, "-C", tmp.path])

        let all = findAll(in: tmp)
        guard let onnx = all.first(where: { $0.lastPathComponent == "model.int8.onnx" }),
              let tokens = all.first(where: { $0.lastPathComponent == "tokens.txt" }) else {
            throw NSError(domain: "ASR", code: -1, userInfo: [NSLocalizedDescriptionKey: "模型包中未找到所需文件"])
        }
        try FileManager.default.createDirectory(at: modelFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        for (src, dst) in [(onnx, modelFile), (tokens, tokensFile)] {
            if FileManager.default.fileExists(atPath: dst.path) { try FileManager.default.removeItem(at: dst) }
            try FileManager.default.copyItem(at: src, to: dst)
        }
    }

    // MARK: - 工具

    private func findAll(in dir: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { return [] }
        var r: [URL] = []
        for case let url as URL in e { r.append(url) }
        return r
    }

    // 按「镜像优先、直连兜底」选一个可访问的下载源。
    private func resolveURL(_ rawPath: String) -> URL? {
        for m in mirrors {
            if let u = URL(string: m + rawPath), probeOK(u) { return u }
        }
        if let direct = URL(string: rawPath), probeOK(direct) { return direct }
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
            throw NSError(domain: "ASR", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: str.trimmingCharacters(in: .whitespacesAndNewlines)])
        }
        return str
    }

    private func download(url: URL, to dest: URL, progress: @escaping (Int64, Int64, Int64) -> Void) throws {
        let delegate = ASRDownloader()
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
        if case .none = result { throw NSError(domain: "ASR", code: -1, userInfo: [NSLocalizedDescriptionKey: "下载无响应"]) }
        guard let tmp = delegate.finishedURL else {
            throw NSError(domain: "ASR", code: -1, userInfo: [NSLocalizedDescriptionKey: "下载未完成"])
        }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
    }

    // MARK: - 进度与状态发布

    private func progressTo(_ p: Double, _ text: String) {
        publish(.working, text, p)
    }

    private func publish(_ phase: Phase, _ detail: String, _ progress: Double) {
        DispatchQueue.main.async {
            self.phase = phase
            self.detail = detail
            self.progress = progress
            nlog("ASREngine: \(detail)")
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
private final class ASRDownloader: NSObject, URLSessionDownloadDelegate {
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