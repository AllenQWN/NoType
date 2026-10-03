import Foundation
import Combine
import AVFoundation

/// 语音录音服务：用本地 SenseVoice 引擎做离线识别，替代系统 SFSpeechRecognizer。
/// 按住期间录音（硬件采样率收集 PCM + 音量），同时每 1.2 秒做一次增量识别、把文字实时显示在语音条上；
/// 松开后重采样到 16kHz 写成 WAV 交给 ASRService 做最终识别。
final class SpeechService: NSObject, ObservableObject {
    @Published var isListening = false
    @Published var liveText = ""
    @Published var volume: Float = 0
    @Published var permissionError: String?
    private(set) var finalText = ""

    /// 启动失败回调（App 收到后弹提示，避免静默失败）
    var onFailure: ((String) -> Void)?

    /// 线上流式识别最终结果回调（松手后拿到整句结果时触发；本地模式不使用）
    var onStreamResult: ((Result<String, Error>) -> Void)?

    // 线上流式会话（边说边发音频、实时收增量文本）
    private var onlineSession: VolcengineStreamSession?
    private var streamSendTimer: DispatchSourceTimer?
    private var streamSentSampleCount = 0

    private var isOnlineMode: Bool {
        (UserDefaults.standard.string(forKey: "notype.asrMode") ?? "local") == "online"
    }

    private let audioEngine = AVAudioEngine()
    private let samplesLock = NSLock()
    private var recordedSamples: [Float] = []   // 硬件采样率 float32 mono
    private var recordedSampleRate: Double = 16000

    // 分段识别（录音期间增量识别，实时上屏）
    private var partialTimer: DispatchSourceTimer?
    private var isRecognizingPartial = false
    private var lastDisplayedSampleCount = 0

    /// 松开后 AI 优化/翻译进行中（语音条转 loading）
    @Published var isProcessing = false
    @Published var processingHint = "正在优化…"

    // 流式打印：识别结果逐字追加显示（不删改），说话时更自然
    private var typewriterTarget = ""
    private var typewriterGeneration = 0

    /// 只申请麦克风权限（本地引擎不需要系统「语音识别」权限）
    func ensurePermissions(completion: @escaping (Bool, String?) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            nlog("麦克风权限: 已授权")
            completion(true, nil)
        case .notDetermined:
            nlog("请求麦克风权限")
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    nlog("麦克风权限请求结果: granted=\(granted)")
                    completion(granted, granted ? nil : "需要在「系统设置 → 隐私与安全性 → 麦克风」中允许 NoType")
                }
            }
        default:
            nlog("麦克风权限: 被拒绝")
            completion(false, "需要在「系统设置 → 隐私与安全性 → 麦克风」中允许 NoType")
        }
    }

    func start() {
        stop(clearText: true)
        samplesLock.lock()
        recordedSamples.removeAll()
        samplesLock.unlock()
        nlog("start: 开始录音")

        // 线上模式：先建立双向流式会话（边录边发），失败则中止本次录音
        if isOnlineMode, !startOnlineStream() {
            return
        }

        let inputNode = audioEngine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)
        recordedSampleRate = hwFormat.sampleRate
        nlog("硬件音频格式: sampleRate=\(hwFormat.sampleRate), channels=\(hwFormat.channelCount)")

        // 关键：tap 用硬件格式（format 传 nil）。不要指定 16kHz，
        // 否则 AVAudioEngine 会在 inputNode 上插入采样率转换器，导致 start() 卡死、isListening 永远不置 true。
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.updateVolume(buffer)
            if let ch = buffer.floatChannelData?[0] {
                self.samplesLock.lock()
                self.recordedSamples.append(contentsOf: UnsafeBufferPointer(start: ch, count: Int(buffer.frameLength)))
                self.samplesLock.unlock()
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            let msg = "音频引擎启动失败：\(error.localizedDescription)"
            nlog("错误: \(msg)")
            permissionError = msg
            onFailure?(msg)
            return
        }

        isListening = true
        isProcessing = false
        liveText = ""
        lastDisplayedSampleCount = 0
        if isOnlineMode {
            startStreamSendTimer()
        } else {
            startPartialTimer()
        }
        nlog("开始聆听（isListening=true）")
    }

    /// 停止录音。本地模式把音频重采样写成 WAV 返回；线上模式发剩余音频 + last，结果走 onStreamResult，返回 nil。
    @discardableResult
    func stop(clearText: Bool = false) -> URL? {
        stopPartialTimer()
        stopStreamSendTimer()
        typewriterGeneration += 1
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isListening = false
        volume = 0
        let snap = snapshotSamples()
        nlog("stop: clearText=\(clearText), 采样数=\(snap.samples.count)")

        if isOnlineMode {
            // 松手：把最后一段未发送的音频发出去，再发 last 收尾；最终结果走 onStreamResult
            sendRemainingChunk()
            if let session = onlineSession {
                session.sendLast()
                // 发完 last 稍后主动断开，避免连接空占
                DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) { [weak session] in
                    session?.close()
                }
            } else {
                onlineSession = nil
                if !clearText {
                    onStreamResult?(.failure(NSError(domain: "SpeechService", code: -1,
                                                     userInfo: [NSLocalizedDescriptionKey: "线上识别会话未就绪"])))
                }
            }
            samplesLock.lock()
            recordedSamples.removeAll()
            samplesLock.unlock()
            if clearText {
                liveText = ""
                finalText = ""
            }
            return nil
        }

        let wav = makeWAV(samples: snap.samples, sampleRate: snap.rate)
        samplesLock.lock()
        recordedSamples.removeAll()
        samplesLock.unlock()
        if clearText {
            liveText = ""
            finalText = ""
        }
        return wav
    }

    /// 设置识别结果（松开后离线识别完成时调用，同时填充 liveText 供语音条显示）
    func setResult(_ text: String) {
        setLiveText(text)
        finalText = text
    }

    // MARK: - 流式显示

    /// 流式更新显示文字：从当前已显示文本出发逐字打印到目标，不重置已显示内容。
    /// 说话时「说到哪显示到哪」，且不删改已显示的字，避免闪烁。
    func setLiveText(_ target: String) {
        guard target != liveText else { return }
        typewriterTarget = target
        typewriterGeneration += 1
        let gen = typewriterGeneration
        nlog("流式: 目标 \(target.count) 字，当前已显示 \(liveText.count) 字")
        typewriterStep(gen: gen)
    }

    /// 流式单步：每 50ms 打印一个字符。前缀一致就追加；前缀变了（ASR 修正）则整段替换，不出现删改空窗。
    private func typewriterStep(gen: Int) {
        guard gen == typewriterGeneration else { return }
        let cur = liveText
        let tgt = typewriterTarget
        guard cur != tgt else { return }
        let n = cur.count + 1
        if tgt.hasPrefix(cur), n <= tgt.count {
            let idx = tgt.index(tgt.startIndex, offsetBy: n)
            liveText = String(tgt[..<idx])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.typewriterStep(gen: gen)
            }
        } else {
            liveText = tgt
        }
    }

    /// 设置/取消 processing 态（松开后 AI 优化或翻译期间，语音条转 loading）
    func setProcessing(_ on: Bool, hint: String = "正在优化…") {
        isProcessing = on
        processingHint = hint
    }

    // MARK: - 分段识别

    private func startPartialTimer() {
        stopPartialTimer()
        isRecognizingPartial = false
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
        timer.schedule(deadline: .now() + 1.2, repeating: 1.2)
        timer.setEventHandler { [weak self] in self?.recognizePartial() }
        timer.resume()
        partialTimer = timer
    }

    private func stopPartialTimer() {
        partialTimer?.cancel()
        partialTimer = nil
    }

    // MARK: - 线上流式（边说边发音频、实时收增量文本）

    /// 建立双向流式会话并绑定增量/最终回调。失败返回 false（同时触发 onFailure）。
    @discardableResult
    private func startOnlineStream() -> Bool {
        do {
            let session = try VolcengineStreamASR.shared.startStream(
                onPartial: { [weak self] text in
                    DispatchQueue.main.async {
                        guard let self = self, self.isListening else { return }
                        self.setLiveText(text)   // 增量文本打字机上屏
                    }
                },
                onDone: { [weak self] res in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        self.onlineSession = nil
                        if self.isListening {
                            // 录音中途会话异常结束，忽略；松手后由「无会话兜底」处理
                            nlog("线上流式会话中途结束：\(res)")
                        } else {
                            self.onStreamResult?(res)
                        }
                    }
                }
            )
            onlineSession = session
            streamSentSampleCount = 0
            nlog("线上流式会话已建立")
            return true
        } catch {
            nlog("线上流式启动失败: \(error.localizedDescription)")
            onFailure?(error.localizedDescription)
            return false
        }
    }

    private func startStreamSendTimer() {
        stopStreamSendTimer()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
        timer.schedule(deadline: .now() + 0.2, repeating: 0.2)
        timer.setEventHandler { [weak self] in self?.sendStreamChunk() }
        timer.resume()
        streamSendTimer = timer
    }

    private func stopStreamSendTimer() {
        streamSendTimer?.cancel()
        streamSendTimer = nil
    }

    /// 把尚未发送的新增音频重采样成 16kHz PCM 发给会话。
    private func sendStreamChunk() {
        guard let session = onlineSession else { return }
        let snap = snapshotSamples()
        guard snap.samples.count > streamSentSampleCount else { return }
        let newSamples = Array(snap.samples[streamSentSampleCount...])
        streamSentSampleCount = snap.samples.count
        let pcm = pcm16(from: newSamples, rate: snap.rate)
        guard !pcm.isEmpty else { return }
        session.send(pcm: pcm)
    }

    private func sendRemainingChunk() {
        sendStreamChunk()
    }

    /// 把 float 采样重采样到 16kHz 并转成 16bit 小端 PCM。
    private func pcm16(from input: [Float], rate inputRate: Double) -> Data {
        let samples: [Float]
        if abs(inputRate - 16000) > 1 {
            samples = resample(input, fromRate: inputRate, toRate: 16000)
        } else {
            samples = input
        }
        guard !samples.isEmpty else { return Data() }
        let int16s = samples.map { s -> Int16 in
            let c = max(-1.0, min(1.0, s))
            return Int16(c * 32767.0)
        }
        var data = Data()
        int16s.withUnsafeBytes { raw in
            data.append(contentsOf: raw)
        }
        return data
    }

    private func recognizePartial() {
        guard isListening, !isRecognizingPartial else { return }
        // 线上识别（Vertex）延迟较大且按次计费，录音期间不做增量识别，松开后一次性识别
        guard (UserDefaults.standard.string(forKey: "notype.asrMode") ?? "local") == "local" else { return }
        let snap = snapshotSamples()
        let minCount = Int(snap.rate * 1.2)   // 至少 1.2 秒
        guard snap.samples.count >= minCount else { return }
        // 与上次已显示相比新增不足 1 秒就跳过，避免频繁重复识别
        guard snap.samples.count - lastDisplayedSampleCount >= Int(snap.rate * 1.0) else { return }
        guard let wav = makeWAV(samples: snap.samples, sampleRate: snap.rate) else { return }

        let submitted = snap.samples.count
        isRecognizingPartial = true
        nlog("分段识别: 提交 \(submitted) 采样")
        ASRService.shared.transcribe(wavURL: wav) { [weak self] res in
            self?.isRecognizingPartial = false
            defer { try? FileManager.default.removeItem(at: wav) }
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard self.isListening else { return }
                // 只接受更长音频的结果，避免旧的短音频结果回退覆盖
                if submitted >= self.lastDisplayedSampleCount {
                    self.lastDisplayedSampleCount = submitted
                    if case .success(let text) = res, !text.isEmpty {
                        self.setLiveText(text)
                    }
                }
            }
        }
    }

    // MARK: - 采样快照（线程安全）

    private func snapshotSamples() -> (samples: [Float], rate: Double) {
        samplesLock.lock()
        defer { samplesLock.unlock() }
        return (recordedSamples, recordedSampleRate)
    }

    // MARK: - WAV 写出

    private func makeWAV(samples input: [Float], sampleRate inputRate: Double) -> URL? {
        // 重采样到 16kHz（SenseVoice 固定 16kHz 单声道）
        let samples: [Float]
        if abs(inputRate - 16000) > 1 {
            samples = resample(input, fromRate: inputRate, toRate: 16000)
        } else {
            samples = input
        }
        let n = samples.count
        let minCount = 16000 / 5   // 至少 0.2 秒
        guard n >= minCount else {
            nlog("writeWAV: 音频过短（\(n) 采样 / 原始 \(input.count)），忽略")
            return nil
        }
        let sampleRate: UInt32 = 16000
        let channels: UInt16 = 1
        let bits: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bits / 8)
        let blockAlign = UInt16(channels * (bits / 8))
        let dataSize = UInt32(n * 2)

        var data = Data()
        appendASCII("RIFF", to: &data)
        appendLE(UInt32(36 + dataSize), to: &data)
        appendASCII("WAVE", to: &data)
        appendASCII("fmt ", to: &data)
        appendLE(UInt32(16), to: &data)
        appendLE(UInt16(1), to: &data)           // PCM
        appendLE(channels, to: &data)
        appendLE(sampleRate, to: &data)
        appendLE(byteRate, to: &data)
        appendLE(blockAlign, to: &data)
        appendLE(bits, to: &data)
        appendASCII("data", to: &data)
        appendLE(dataSize, to: &data)

        let int16s = samples.map { s -> Int16 in
            let c = max(-1.0, min(1.0, s))
            return Int16(c * 32767.0)
        }
        int16s.withUnsafeBytes { raw in
            data.append(contentsOf: raw)   // arm64 小端，即 little-endian PCM
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("notype-asr-\(UUID().uuidString).wav")
        do {
            try data.write(to: url)
            nlog("writeWAV: 已写 \(url.lastPathComponent)（\(n) 采样 ≈ \(String(format: "%.1f", Double(n)/16000.0))s）")
            return url
        } catch {
            nlog("writeWAV 失败: \(error.localizedDescription)")
            return nil
        }
    }

    private func appendASCII(_ s: String, to data: inout Data) {
        data.append(s.data(using: .ascii)!)
    }

    private func appendLE<T: FixedWidthInteger>(_ v: T, to data: inout Data) {
        var x = v.littleEndian
        data.append(Data(bytes: &x, count: MemoryLayout<T>.size))
    }

    /// 高质量重采样：用 AVAudioConverter（内置抗混叠低通）把硬件采样率降到 16kHz。
    /// 之前的「每 3 点取平均」抗混叠不足，8kHz 以上高频会折叠回语音频段，
    /// 污染 s/sh/z/c/zh/ch/f 等擦音声母，导致这类音识别不稳。
    private func resample(_ samples: [Float], fromRate: Double, toRate: Double) -> [Float] {
        guard fromRate > 0, toRate > 0 else { return samples }
        guard fromRate > toRate else { return samples }
        guard let srcFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: fromRate, channels: 1, interleaved: false),
              let dstFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: toRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: srcFormat, to: dstFormat) else {
            return samples
        }
        let inFrames = AVAudioFrameCount(samples.count)
        guard inFrames > 0, let inBuf = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: inFrames) else {
            return samples
        }
        inBuf.frameLength = inFrames
        samples.withUnsafeBufferPointer { s in
            guard let dst = inBuf.floatChannelData?[0], let src = s.baseAddress else { return }
            dst.update(from: src, count: samples.count)
        }
        let outCapacity = AVAudioFrameCount(samples.count)
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: outCapacity) else {
            return samples
        }
        var error: NSError?
        var fed = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return inBuf
        }
        let status = converter.convert(to: outBuf, error: &error, withInputFrom: inputBlock)
        guard status != .error, error == nil else { return samples }
        let n = Int(outBuf.frameLength)
        guard n > 0 else { return samples }
        return Array(UnsafeBufferPointer(start: outBuf.floatChannelData![0], count: n))
    }

    // MARK: - 音量

    private func updateVolume(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }
        var sum: Float = 0
        for i in 0..<count {
            let v = channel[i]
            sum += v * v
        }
        let rms = sqrt(sum / Float(count))
        let db = 20 * log10(max(rms, 0.00001))
        let norm = max(0, min(1, (db + 50) / 50))
        DispatchQueue.main.async {
            self.volume = norm
        }
    }
}