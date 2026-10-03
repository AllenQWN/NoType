import AppKit
import ApplicationServices
import CoreGraphics

/// 文本注入：说完后一次性「剪贴板 + ⌘V」粘贴到目标输入框。
/// ⚠️ 中文不能用 keyboardSetUnicodeString + virtualKey 0（Electron 会忽略 unicode 字符串、
/// 按 keycode 自行转换），只能用剪贴板粘贴。
enum TextInjector {
    private static let cmdKey: CGKeyCode = 55    // kVK_Command
    private static let vKey: CGKeyCode = 9       // kVK_ANSI_V
    private static let src = CGEventSource(stateID: .hidSystemState)
    private static var savedClipboard: String?

    /// 开始说话前快照剪贴板
    static func begin() {
        savedClipboard = NSPasteboard.general.string(forType: .string)
    }

    /// 一次性注入 text 到当前焦点输入框；粘贴完成后延迟恢复用户原剪贴板。
    static func commit(_ text: String, then: (() -> Void)? = nil) {
        guard !text.isEmpty else { then?(); return }
        nlog("一次性注入: \"\(text)\"")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        pasteCommand()
        // ⌘V 是异步投递，立即恢复剪贴板会导致目标 App 粘到旧内容，故延迟恢复
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            finish()
            then?()
        }
    }

    /// 结束后恢复用户原剪贴板
    static func finish() {
        guard let old = savedClipboard else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(old, forType: .string)
        savedClipboard = nil
        nlog("已恢复剪贴板")
    }

    /// 完整模拟 ⌘V（Command down/up 配平，避免修饰键状态残留）
    private static func pasteCommand() {
        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: cmdKey, keyDown: true)
        cmdDown?.post(tap: .cghidEventTap)
        usleep(12000)

        let vDown = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        vDown?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)
        usleep(12000)

        let vUp = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        vUp?.flags = .maskCommand
        vUp?.post(tap: .cghidEventTap)
        usleep(12000)

        let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: cmdKey, keyDown: false)
        cmdUp?.post(tap: .cghidEventTap)
        usleep(20000)
    }
}