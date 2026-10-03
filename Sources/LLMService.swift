import Foundation

/// 本地 LLM 客户端：Ollama（OpenAI 兼容接口），负责用 Prompt 处理语音转写文字
final class LLMService {
    static let shared = LLMService()

    private let endpoint = URL(string: "http://localhost:11434/v1/chat/completions")!
    private let model = "qwen2.5:7b"

    /// 用指定 Prompt 处理文字（翻译类 Prompt 的 {target} 占位符运行时替换为目标语言）
    func run(_ prompt: Prompt, text: String, completion: @escaping (Result<String, Error>) -> Void) {
        let system = prompt.prompt.replacingOccurrences(of: "{target}", with: PromptStore.targetLanguage)
        chat(system: system, user: text, completion: completion)
    }

    private func chat(system: String, user: String, completion: @escaping (Result<String, Error>) -> Void) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "stream": false
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any],
                  let content = message["content"] as? String,
                  !content.isEmpty else {
                completion(.failure(NSError(
                    domain: "LLMService",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "解析 Ollama 响应失败"]
                )))
                return
            }
            completion(.success(content))
        }.resume()
    }
}