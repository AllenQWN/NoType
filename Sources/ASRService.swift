import Foundation

/// 本地语音识别：调用 sherpa-onnx-offline（SenseVoice）对 16kHz 单声道 WAV 做离线转写。
final class ASRService {
    static let shared = ASRService()

    /// 转写一个 WAV 文件，返回识别文字（后台线程执行，结果回调到调用方自行切主线程）。
    /// 仅本地离线识别（SenseVoice）；线上识别由 SpeechService 的双向流式会话处理。
    func transcribe(wavURL: URL, completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let text = try self.run(from: wavURL)
                completion(.success(text))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func run(from wavURL: URL) throws -> String {
        let mgr = ASREngineManager.shared
        guard mgr.isReady() else {
            throw NSError(domain: "ASR", code: -1, userInfo: [NSLocalizedDescriptionKey: "本地识别引擎未就绪，请先在设置中安装"])
        }

        let p = Process()
        p.executableURL = mgr.offlineBinary
        p.arguments = [
            "--tokens=\(mgr.tokensFile.path)",
            "--sense-voice-model=\(mgr.modelFile.path)",
            "--sense-voice-use-itn=1",
            "--sense-voice-language=auto",
            wavURL.path
        ]
        // sherpa-onnx-offline 通过 @rpath 依赖 libonnxruntime.dylib，用环境变量补齐查找路径
        var env = ProcessInfo.processInfo.environment
        if let existing = env["DYLD_LIBRARY_PATH"], !existing.isEmpty {
            env["DYLD_LIBRARY_PATH"] = mgr.libDir.path + ":" + existing
        } else {
            env["DYLD_LIBRARY_PATH"] = mgr.libDir.path
        }
        p.environment = env

        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err

        nlog("ASR: 开始识别 \(wavURL.lastPathComponent)")
        let start = Date()
        try p.run()
        p.waitUntilExit()
        let elapsed = Date().timeIntervalSince(start)
        nlog(String(format: "ASR: 识别完成，耗时 %.3fs", elapsed))

        let outStr = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard p.terminationStatus == 0 else {
            let eStr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "ASR", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: eStr.isEmpty ? "识别失败" : eStr.trimmingCharacters(in: .whitespacesAndNewlines)])
        }

        guard let text = Self.extractText(from: outStr) else {
            throw NSError(domain: "ASR", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法解析识别结果"])
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "ASR", code: -1, userInfo: [NSLocalizedDescriptionKey: "未识别到有效语音内容"])
        }
        return trimmed
    }

    // stdout 形如 {"lang":"...", "text":"...", ...}，取 text 字段
    private static func extractText(from output: String) -> String? {
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            return nil
        }
        return text
    }
}