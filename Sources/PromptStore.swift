import Foundation
import Combine

/// Prompt 类型：听写、翻译是内置项；自定义项由用户新增。
enum PromptKind: String, Codable {
    case dictate
    case translate
    case custom
}

/// 一个「快捷指令」= 一段可自定义的提示词（Prompt）。
/// 听写、翻译是两个内置 Prompt；用户可新增自定义 Prompt、改提示词、改快捷键。
struct Prompt: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var prompt: String      // 提示词全文，{target} 为翻译目标语言占位符
    var keys: [String]      // 快捷键组合，如 ["Fn"] / ["Fn","⇧"] / ["⌘","1"]
    var kind: PromptKind

    var isBuiltin: Bool { kind != .custom }
    var isTranslate: Bool { kind == .translate }

    var icon: String {
        switch kind {
        case .dictate: return "mic.fill"
        case .translate: return "arrow.left.arrow.right"
        case .custom: return "sparkles"
        }
    }
}

/// Prompt 的存储与增删改查。数据持久化在 UserDefaults，默认值为两个内置 Prompt。
final class PromptStore: ObservableObject {
    static let shared = PromptStore()

    @Published private(set) var prompts: [Prompt]

    /// 翻译的目标语言（占位符 {target} 运行时替换为此值）
    static let targetLanguage = "English"

    static let defaultDictate = Prompt(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "听写 Dictate",
        prompt: "你是专业的文字润色助手。把用户的语音转写整理成精炼、通顺、可直接发送的文字：去掉口头语和重复、修正错别字和标点、保留原意和语气，不要添加新信息。只输出润色后的文字，不要解释。",
        keys: ["Fn"],
        kind: .dictate
    )

    static let defaultTranslate = Prompt(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "翻译 Translate",
        prompt: "你是专业翻译。把用户的话翻译成{target}，保留语气和原意。只输出译文，不要解释。",
        keys: ["Fn", "⇧"],
        kind: .translate
    )

    private static let storageKey = "notype.prompts"

    private init() {
        prompts = Self.loadDefaultsIfEmpty(Self.loadFromDisk())
    }

    /// 规范化单个按键 token 为标准符号：
    /// Cmd/Command→⌘、Shift→⇧、Ctrl/Control→⌃、Option/Alt→⌥、Fn→Fn、Space→Space，其余（主键）统一大写。
    static func normalizeKey(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch t {
        case "cmd", "command", "⌘": return "⌘"
        case "shift", "⇧": return "⇧"
        case "ctrl", "control", "⌃": return "⌃"
        case "opt", "option", "alt", "⌥": return "⌥"
        case "fn": return "Fn"
        case "space", " ": return "Space"
        default:
            return t.uppercased()
        }
    }

    // MARK: - 查询

    /// 根据按键组合查找 Prompt（集合匹配、顺序无关，内部统一规范化符号）
    func prompt(matching components: [String]) -> Prompt? {
        let target = Set(components.map { Self.normalizeKey($0) })
        return prompts.first { Set($0.keys.map { Self.normalizeKey($0) }) == target }
    }

    func firstPrompt() -> Prompt? {
        prompts.first
    }

    // MARK: - 增删改

    func add(name: String, prompt: String, keys: [String]) {
        let p = Prompt(id: UUID(), name: name, prompt: prompt, keys: keys, kind: .custom)
        prompts.append(p)
        save()
    }

    func update(_ p: Prompt) {
        guard let idx = prompts.firstIndex(where: { $0.id == p.id }) else { return }
        prompts[idx] = p
        save()
    }

    func delete(_ p: Prompt) {
        guard !p.isBuiltin else { return }   // 内置 Prompt 不允许删除
        prompts.removeAll { $0.id == p.id }
        save()
    }

    func resetToDefault(_ p: Prompt) {
        guard let idx = prompts.firstIndex(where: { $0.id == p.id }) else { return }
        let def: Prompt?
        switch p.kind {
        case .dictate: def = Self.defaultDictate
        case .translate: def = Self.defaultTranslate
        case .custom: def = nil
        }
        guard let d = def else { return }
        prompts[idx].name = d.name
        prompts[idx].prompt = d.prompt
        prompts[idx].keys = d.keys
        save()
    }

    // MARK: - 持久化

    private static func loadFromDisk() -> [Prompt] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let arr = try? JSONDecoder().decode([Prompt].self, from: data) else {
            return []
        }
        return arr
    }

    /// 兜底：确保两个内置 Prompt 始终存在（历史数据或异常情况）
    private static func loadDefaultsIfEmpty(_ arr: [Prompt]) -> [Prompt] {
        var result = arr
        if !result.contains(where: { $0.kind == .dictate }) {
            result.append(defaultDictate)
        }
        if !result.contains(where: { $0.kind == .translate }) {
            result.append(defaultTranslate)
        }
        return result
    }

    private func save() {
        if let data = try? JSONEncoder().encode(prompts) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}