import Foundation
import Combine

/// 语言偏好：跟随系统 / 中文 / English
enum AppLanguage: String, CaseIterable {
    case system
    case zh
    case en
}

/// 轻量国际化模块。用「中文原文」作为 key，运行时按当前语言取 zh / en 文案。
/// 语言偏好持久化在 UserDefaults（notype.language），默认跟随系统。
final class L10n: ObservableObject {
    static let shared = L10n()

    private static let defaultsKey = "notype.language"

    /// 当前语言偏好。修改它会触发 @Published，让订阅它的根视图整树刷新。
    @Published var language: AppLanguage

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? ""
        language = AppLanguage(rawValue: raw) ?? .system
    }

    /// 设置语言并立即持久化
    func setLanguage(_ lang: AppLanguage) {
        language = lang
        UserDefaults.standard.set(lang.rawValue, forKey: Self.defaultsKey)
    }

    /// 实际展示是否为中文（system 时按系统首选语言判断）
    var isChinese: Bool {
        switch language {
        case .zh: return true
        case .en: return false
        case .system:
            let lang = Locale.preferredLanguages.first ?? "en"
            return lang.lowercased().hasPrefix("zh")
        }
    }

    /// 语言选项的显示名（语言本身用什么名就显示什么名）
    func displayName(_ lang: AppLanguage) -> String {
        switch lang {
        case .system: return tr("跟随系统")
        case .zh: return "中文"
        case .en: return "English"
        }
    }

    /// 取文案。key 未命中时原样返回。
    func tr(_ key: String) -> String {
        let pair = Self.table[key] ?? [key, key]
        return isChinese ? pair[0] : pair[1]
    }

    // MARK: - 文案映射表（key -> [zh, en]）

    private static let table: [String: [String]] = [
        // 通用 / 侧边栏
        "主页": ["主页", "Home"],
        "历史": ["历史", "History"],
        "设置": ["设置", "Settings"],
        "总字数": ["总字数", "Total characters"],
        "跟随系统": ["跟随系统", "Follow System"],
        "语言": ["语言", "Language"],
        "界面语言": ["界面语言", "Language"],

        // 菜单栏
        "关于 NoType": ["关于 NoType", "About NoType"],
        "退出 NoType": ["退出 NoType", "Quit NoType"],
        "编辑": ["编辑", "Edit"],
        "撤销": ["撤销", "Undo"],
        "重做": ["重做", "Redo"],
        "剪切": ["剪切", "Cut"],
        "复制": ["复制", "Copy"],
        "粘贴": ["粘贴", "Paste"],
        "全选": ["全选", "Select All"],

        // 设置页
        "麦克风": ["麦克风", "Microphone"],
        "输入设备": ["输入设备", "Input Device"],
        "输入电平": ["输入电平", "Input Level"],
        "停止测试": ["停止测试", "Stop Test"],
        "测试麦克风": ["测试麦克风", "Test Microphone"],
        "AI 引擎": ["AI 引擎", "AI Engine"],
        "类型": ["类型", "Type"],
        "模型": ["模型", "Model"],
        "服务商": ["服务商", "Provider"],
        "模型名": ["模型名", "Model Name"],
        "模型版本": ["模型版本", "Model Version"],
        "本地": ["本地", "Local"],
        "线上": ["线上", "Online"],
        "已就绪": ["已就绪", "Ready"],
        "未安装": ["未安装", "Not Installed"],
        "安装中…": ["安装中…", "Installing…"],
        "安装失败": ["安装失败", "Install Failed"],
        "重试安装": ["重试安装", "Retry Install"],
        "安装本地模型": ["安装本地模型", "Install Local Model"],
        "本地离线 · 4.7GB": ["本地离线 · 4.7GB", "Offline · 4.7GB"],
        "本地离线 · 166MB": ["本地离线 · 166MB", "Offline · 166MB"],
        "通义千问": ["通义千问", "Qwen (Tongyi)"],
        "自定义": ["自定义", "Custom"],
        "豆包": ["豆包", "Doubao"],
        "流式语音识别 2.0（推荐）": ["流式语音识别 2.0（推荐）", "Streaming ASR 2.0 (Recommended)"],
        "流式语音识别 1.0": ["流式语音识别 1.0", "Streaming ASR 1.0"],
        "例如 gpt-4o-mini / qwen-max": ["例如 gpt-4o-mini / qwen-max", "e.g. gpt-4o-mini / qwen-max"],
        "火山引擎控制台的 API Key": ["火山引擎控制台的 API Key", "API Key from Volcengine Console"],
        "保存配置": ["保存配置", "Save Config"],
        "已保存 ✓": ["已保存 ✓", "Saved ✓"],
        "密钥仅保存在本机": ["密钥仅保存在本机", "Keys are stored locally"],
        "大模型流式识别(小时版) · 按量计费 · 密钥仅保存在本机": ["大模型流式识别(小时版) · 按量计费 · 密钥仅保存在本机", "Streaming ASR (hourly) · pay-as-you-go · keys stored locally"],

        // 主页
        "说话，\n不用打字": ["说话，\n不用打字", "Just speak,\ndon't type"],
        "自然表达，把你说的话变成精炼、可发送的文字——实时完成。": ["自然表达，把你说的话变成精炼、可发送的文字——实时完成。", "Speak naturally and turn it into polished, send-ready text — in real time."],
        "快捷指令": ["快捷指令", "Quick Prompts"],
        "每一项都是一段可自定义的 Prompt，按一下对应快捷键开始、点 Edit 修改": ["每一项都是一段可自定义的 Prompt，按一下对应快捷键开始、点 Edit 修改", "Each is a customizable prompt. Press its hotkey to start, or click Edit to modify."],
        "新增 Prompt": ["新增 Prompt", "New Prompt"],
        "编辑 Prompt": ["编辑 Prompt", "Edit Prompt"],
        "使用统计": ["使用统计", "Usage Stats"],
        "15 分钟": ["15 分钟", "15 min"],
        "本周录音时长": ["本周录音时长", "Recording this week"],
        "字 / 分钟": ["字 / 分钟", "chars / min"],
        "🔒 你的数据仅保存在本机": ["🔒 你的数据仅保存在本机", "🔒 Your data stays on this device"],
        "定义一个属于你的快捷指令": ["定义一个属于你的快捷指令", "Create your own quick prompt"],
        "修改「{0}」的提示词": ["修改「{0}」的提示词", "Edit the prompt of \"{0}\""],
        "名称": ["名称", "Name"],
        "例如：总结、回复邮件…": ["例如：总结、回复邮件…", "e.g. Summarize, reply email..."],
        "提示词 Prompt": ["提示词 Prompt", "Prompt"],
        "快捷键": ["快捷键", "Shortcut"],
        "保存": ["保存", "Save"],
        "取消": ["取消", "Cancel"],
        "恢复默认": ["恢复默认", "Reset to Default"],
        "删除": ["删除", "Delete"],

        // 历史
        "历史记录": ["历史记录", "History"],
        "🔒 你的数据仅存本机，只有你能访问": ["🔒 你的数据仅存本机，只有你能访问", "🔒 Stored locally, only you can access"],
        "全部": ["全部", "All"],
        "听写": ["听写", "Dictate"],
        "翻译": ["翻译", "Translate"],
        "还没有记录": ["还没有记录", "No records yet"],
        "开始一次听写或翻译，内容会出现在这里。": ["开始一次听写或翻译，内容会出现在这里。", "Dictate or translate something and it will show up here."],
        "{0} 字": ["{0} 字", "{0} chars"],

        // 录音处理中提示
        "正在翻译…": ["正在翻译…", "Translating…"],
        "正在优化…": ["正在优化…", "Optimizing…"],

        // 快捷键录制
        "请按下新快捷键（Esc 取消）": ["请按下新快捷键（Esc 取消）", "Press a new shortcut (Esc to cancel)"],
        "点这里，再按下快捷键（如 ⌘1）": ["点这里，再按下快捷键（如 ⌘1）", "Click and press a shortcut (e.g. ⌘1)"],

        // 权限提示
        "需要在「系统设置 → 隐私与安全性 → 麦克风」中允许 NoType": ["需要在「系统设置 → 隐私与安全性 → 麦克风」中允许 NoType", "Allow NoType in System Settings → Privacy & Security → Microphone"],
        "缺少麦克风或语音识别权限": ["缺少麦克风或语音识别权限", "Missing microphone or speech recognition permission"],
        "无法开始录音：{0}": ["无法开始录音：{0}", "Can't start recording: {0}"],
        "文字已复制到剪贴板，但无法自动注入": ["文字已复制到剪贴板，但无法自动注入", "Text copied to clipboard, but can't auto-insert"],
        "需要开启「辅助功能」权限": ["需要开启「辅助功能」权限", "Accessibility permission required"],
        "打开辅助功能设置": ["打开辅助功能设置", "Open Accessibility Settings"],
        "稍后": ["稍后", "Later"],
        "ax_help_copied": [
            "NoType 尚未获得「辅助功能」权限，所以不能把文字自动粘贴到输入框（已帮你复制到剪贴板，可用 Cmd+V 手动粘贴）。\n\n开启后即可自动注入：\n① 打开「系统设置 → 隐私与安全性 → 辅助功能」\n② 如果列表里已有 NoType，先选中它点下方的「−」移除\n③ 再点「+」重新添加 NoType.app\n④ 完全退出 NoType（Cmd+Q）后重新打开\n\n完成后按一下快捷键开始说话、再按一下结束即可自动注入。",
            "NoType does not have Accessibility permission yet, so it can't paste text into the input box automatically (the text has been copied to your clipboard — press Cmd+V to paste it manually).\n\nTo enable auto-insert:\n① Open System Settings → Privacy & Security → Accessibility\n② If NoType is already in the list, select it and click the \"−\" button below to remove it\n③ Click \"+\" and add NoType.app\n④ Quit NoType completely (Cmd+Q) and reopen it\n\nThen press the hotkey once to start speaking, once again to stop, and it will auto-insert."
        ],
        "ax_help_default": [
            "NoType 用快捷键「按一下开始说话、再按一下结束」，需要一个系统权限：辅助功能（用于把文字粘贴到任意输入框）。\n\n开启步骤：\n① 打开「系统设置 → 隐私与安全性 → 辅助功能」\n② 如果列表里已有 NoType，先选中它点下方的「−」移除\n③ 再点「+」重新添加 NoType.app\n④ 完全退出 NoType（Cmd+Q）后重新打开",
            "NoType uses a hotkey (press to start speaking, press again to stop) and needs one system permission: Accessibility (to paste text into any input box).\n\nTo enable it:\n① Open System Settings → Privacy & Security → Accessibility\n② If NoType is already in the list, select it and click the \"−\" button below to remove it\n③ Click \"+\" and add NoType.app\n④ Quit NoType completely (Cmd+Q) and reopen it"
        ],
    ]
}

/// 全局取文案。支持可选参数：L("无法开始录音：{0}", msg)
func L(_ key: String, _ args: String...) -> String {
    var s = L10n.shared.tr(key)
    for (i, a) in args.enumerated() {
        s = s.replacingOccurrences(of: "{\(i)}", with: a)
    }
    return s
}