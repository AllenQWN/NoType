import Foundation

// MARK: - 豆包流式语音识别（火山引擎）协议常量与工具
// 鉴权：新版控制台 X-Api-Key（请求头）。
// 资源：流式语音识别 1.0 小时版 = volc.bigasr.sauc.duration；2.0 小时版 = volc.seedasr.sauc.duration。

/// 二进制协议帧头（4 字节，见官方「流式语音识别 WebSocket」协议详情）
/// byte0: 0x11 = 协议版本 0b0001 | 头大小 0b0001
/// byte1: 高4位=消息类型(1=full client / 2=audio only / 9=full server response)，低4位=类型补充(0=普通，2=最后一包负包)
/// byte2: 高4位=序列化(1=JSON)，低4位=压缩(0=无)
/// byte3: 保留 0
fileprivate let kFullClientHeader: [UInt8] = [0x11, 0x10, 0x10, 0x00]
fileprivate let kAudioHeader: [UInt8] = [0x11, 0x20, 0x00, 0x00]
fileprivate let kLastPacketHeader: [UInt8] = [0x11, 0x22, 0x00, 0x00]

fileprivate func asrSend(_ ws: URLSessionWebSocketTask, header: [UInt8], payload: Data,
                         completion: ((Error?) -> Void)? = nil) {
    var frame = Data(header)
    asrAppendBigEndian(UInt32(payload.count), to: &frame)
    frame.append(payload)
    ws.send(.data(frame)) { err in completion?(err) }
}

fileprivate func asrAppendBigEndian(_ value: UInt32, to data: inout Data) {
    data.append(UInt8((value >> 24) & 0xFF))
    data.append(UInt8((value >> 16) & 0xFF))
    data.append(UInt8((value >> 8) & 0xFF))
    data.append(UInt8(value & 0xFF))
}

/// 解析服务端响应帧。
/// 结构：[header 4B][sequence 4B（flags 0b0001/0b0011 时）][payload size 4B 大端][JSON]
/// JSON 形如 {"audio_info":{"duration":...}, "result":{"text":"...","utterances":[...]}}
/// 双向流式（bigmodel）下 `result.text` 逐包递增，最后一包为负包（flags=0b0011）。
fileprivate func asrParseResponse(_ data: Data) -> (code: Int, isLast: Bool, text: String, message: String) {
    var code = 0
    var isLast = false
    var text = ""
    var message = ""
    guard data.count >= 8 else { return (code, isLast, text, message) }
    let bytes = [UInt8](data)
    // byte1 低4位：0=无序号 1=正序号 2=负包(无序号) 3=负包(带序号)
    let flags = bytes[1] & 0x0F
    let compression = bytes[2] & 0x0F   // 0=无压缩 1=gzip
    var offset = 4
    if flags == 0b0001 || flags == 0b0011 {
        offset += 4                        // 跳过 sequence number
    }
    guard offset + 4 <= data.count else { return (code, isLast, text, message) }
    let sb = [UInt8](data.subdata(in: offset..<offset + 4))
    let size = (Int(sb[0]) << 24) | (Int(sb[1]) << 16) | (Int(sb[2]) << 8) | Int(sb[3])
    let payload = data.subdata(in: offset + 4..<min(offset + 4 + size, data.count))
    if compression == 1 {
        nlog("VolcengineStreamASR: 响应为 gzip 压缩，当前版本未解压，可能无法解析")
    }
    guard let json = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] else {
        return (code, isLast, text, message)
    }
    code = json["code"] as? Int ?? 0
    isLast = (flags == 0b0011) || (flags == 0b0010)
    message = json["message"] as? String ?? ""
    // 流式响应无 payload_msg 包裹，最终文本直接位于 result.text
    if let result = json["result"] as? [String: Any],
       let t = result["text"] as? String {
        text = t
    }
    return (code, isLast, text, message)
}

fileprivate func asrMeaningfulError(_ e: Error) -> Error {
    let ns = e as NSError
    let raw = ns.localizedDescription
    nlog("VolcengineStreamASR: 原始错误 domain=\(ns.domain) code=\(ns.code) desc=\(raw)")
    if raw.contains("403") || raw.contains("forbidden") || raw.contains("not granted") || ns.code == -1011 {
        return NSError(domain: "VolcengineStreamASR", code: ns.code,
                       userInfo: [NSLocalizedDescriptionKey: "流式识别资源未开通或 API Key 无效：请到火山引擎控制台开通「流式语音识别」（1.0 或 2.0）小时版，并确认 API Key 正确"])
    }
    if ns.code == -1001 || ns.code == -1004 {
        return NSError(domain: "VolcengineStreamASR", code: ns.code,
                       userInfo: [NSLocalizedDescriptionKey: "连接识别服务超时，请检查网络"])
    }
    if ns.domain == NSPOSIXErrorDomain && (ns.code == 57 || ns.code == 54) {
        return NSError(domain: "VolcengineStreamASR", code: ns.code,
                       userInfo: [NSLocalizedDescriptionKey: "识别连接被服务端关闭，可能音频格式异常或服务端拒绝"])
    }
    return e
}

fileprivate func asrErrorMeaning(_ code: Int) -> String {
    switch code {
    case 0: return "识别成功"
    case 20000003: return "识别到静音音频，没有说话内容"
    case 45000001: return "请求参数无效"
    case 45000002: return "空音频"
    case 45000030: return "流式识别资源未开通，请到火山引擎控制台开通「流式语音识别」（1.0 或 2.0）小时版"
    case 45000151: return "音频格式不正确"
    case 55000031: return "服务繁忙，请稍后重试"
    default: return "识别失败（错误码 \(code)）"
    }
}

// MARK: - 豆包流式识别入口

final class VolcengineStreamASR {
    static let shared = VolcengineStreamASR()

    /// 双向流式模式（bigmodel）：边录音边发，实时返回增量文本。
    private let endpoint = "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel"

    /// 模型版本 → 资源 ID（均为小时版计费，对应控制台开通的「流式语音识别」时长）：
    /// 1.0（历史版本）：volc.bigasr.sauc.duration
    /// 2.0（推荐）：volc.seedasr.sauc.duration
    /// 1.0 与 2.0 共用同一端点与二进制协议，仅资源 ID 不同。
    private var resourceId: String {
        let v = (UserDefaults.standard.string(forKey: "notype.asrVersion") ?? "2.0")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return v == "1.0" ? "volc.bigasr.sauc.duration" : "volc.seedasr.sauc.duration"
    }

    /// 建立双向流式会话：连接后立即返回，后台持续 receive 并回调增量文本。
    func startStream(onPartial: @escaping (String) -> Void,
                     onDone: @escaping (Result<String, Error>) -> Void) throws -> VolcengineStreamSession {
        let apiKey = Self.apiKey()
        guard !apiKey.isEmpty else {
            throw NSError(domain: "VolcengineStreamASR", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "请先在设置中填写豆包语音识别的 API Key"])
        }
        let jsonData = try JSONSerialization.data(withJSONObject: Self.fullJSON(apiKey: apiKey))
        guard let url = URL(string: endpoint) else {
            throw NSError(domain: "VolcengineStreamASR", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "识别接口地址无效"])
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 60
        req.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        req.setValue(resourceId, forHTTPHeaderField: "X-Api-Resource-Id")
        req.setValue(UUID().uuidString, forHTTPHeaderField: "X-Api-Request-Id")

        let ws = URLSession.shared.webSocketTask(with: req)
        ws.resume()
        // 先发 full client request（鉴权 + 音频配置），随后可陆续发音频分片
        asrSend(ws, header: kFullClientHeader, payload: jsonData)
        let session = VolcengineStreamSession(ws: ws, onPartial: onPartial, onDone: onDone)
        session.begin()
        return session
    }

    // MARK: - 公共配置

    private static func apiKey() -> String {
        return (UserDefaults.standard.string(forKey: "notype.asrKey") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fullJSON(apiKey: String) -> [String: Any] {
        return [
            "user": ["uid": apiKey],
            "audio": ["format": "pcm", "codec": "raw", "rate": 16000, "bits": 16, "channel": 1],
            "request": [
                "model_name": "bigmodel",
                "enable_itn": true,
                "enable_punc": true,
                "enable_ddc": true
            ]
        ]
    }
}

// MARK: - 双向流式会话

/// 双向流式会话：调用方边发音频边收增量文本，发 last 后拿到最终结果。
/// 回调约定均切到主线程。
final class VolcengineStreamSession {
    private let ws: URLSessionWebSocketTask
    private let onPartial: (String) -> Void
    private let onDone: (Result<String, Error>) -> Void
    private var finalText = ""
    private var finished = false

    init(ws: URLSessionWebSocketTask, onPartial: @escaping (String) -> Void,
         onDone: @escaping (Result<String, Error>) -> Void) {
        self.ws = ws
        self.onPartial = onPartial
        self.onDone = onDone
    }

    func begin() {
        receiveLoop()
    }

    /// 发送一段 16kHz/16bit/单声道 PCM 分片。
    func send(pcm: Data) {
        guard !finished, !pcm.isEmpty else { return }
        asrSend(ws, header: kAudioHeader, payload: pcm)
    }

    /// 发送最后一包（负包），通知服务端结束识别。
    func sendLast() {
        guard !finished else { return }
        asrSend(ws, header: kLastPacketHeader, payload: Data())
    }

    /// 主动收尾关闭连接（发完 last 后稍等结果回调时调用）。
    func close() {
        ws.cancel(with: .goingAway, reason: nil)
    }

    // MARK: - 接收循环（异步回调式）

    private func receiveLoop() {
        ws.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let msg):
                var d: Data?
                switch msg {
                case .data(let x): d = x
                case .string(let s): d = s.data(using: .utf8)
                @unknown default: break
                }
                if let d = d { self.handle(d) }
                if !self.finished { self.receiveLoop() }
            case .failure(let e):
                self.handleFailure(e)
            }
        }
    }

    private func handle(_ d: Data) {
        let r = asrParseResponse(d)
        if !r.text.isEmpty {
            finalText = r.text
            let t = r.text
            DispatchQueue.main.async { [weak self] in
                self?.onPartial(t)
            }
        }
        if r.isLast {
            self.finishWithText()
        }
    }

    private func handleFailure(_ e: Error) {
        if finished { return }
        // 服务端发完负包后正常关闭连接：已拿到结果则视为正常结束
        if !finalText.isEmpty {
            finishWithText()
            return
        }
        finished = true
        let err = asrMeaningfulError(e)
        DispatchQueue.main.async { [weak self] in
            self?.onDone(.failure(err))
        }
    }

    private func finishWithText() {
        guard !finished else { return }
        finished = true
        let text = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.onDone(.failure(NSError(domain: "VolcengineStreamASR", code: -1,
                                              userInfo: [NSLocalizedDescriptionKey: "未识别到有效语音内容"])))
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.onDone(.success(text))
            }
        }
    }
}