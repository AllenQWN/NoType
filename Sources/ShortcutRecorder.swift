import SwiftUI
import AppKit

/// 快捷键录制框：点击进入录制态（旧值临时隐藏、显示提示），按下实际按键组合（如 ⌘1、⌃Space、Fn、⌥）自动识别并回填。
/// - 录到新键 → 用新键并退出录制态。
/// - Esc / 点击别处（未录到）→ 恢复原值。
/// - Backspace / Delete → 清空。
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let v = ShortcutRecorderView()
        v.onCapture = { comps in text = comps.joined(separator: " + ") }
        v.displayText = text
        return v
    }

    func updateNSView(_ v: ShortcutRecorderView, context: Context) {
        v.displayText = text
        v.needsDisplay = true
    }
}

final class ShortcutRecorderView: NSView {
    var onCapture: (([String]) -> Void)?

    var displayText: String = "" {
        didSet { needsDisplay = true }
    }

    private var fnHeld = false
    private var optionHeld = false
    private var isActive = false {
        didSet { needsDisplay = true }
    }
    /// 录制中：点击进入后为 true，录到新键 / Esc 取消 / 失焦后为 false
    private var isRecording = false {
        didSet { needsDisplay = true }
    }
    /// 本次录制是否已经通过 keyDown 产生有效结果（用于抑制随后 Option 松开的重复 capture）
    private var capturedViaKeyDown = false

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        isActive = true
        // 进入录制态：旧值临时隐藏，进入「等待录入」。原值仍保留在 displayText（外部 text 未变）
        isRecording = true
        capturedViaKeyDown = false
        fnHeld = false
        optionHeld = false
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        isActive = false
        isRecording = false
        fnHeld = false
        optionHeld = false
        return super.resignFirstResponder()
    }

    // 背景与边框由 SwiftUI 侧（.background / .overlay）绘制，这里只画文字
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let text: String
        let color: NSColor
        if isRecording {
            text = L("请按下新快捷键（Esc 取消）")
            color = NSColor.controlAccentColor
        } else if displayText.isEmpty {
            text = L("点这里，再按下快捷键（如 ⌘1）")
            color = NSColor(calibratedWhite: 0.50, alpha: 1)
        } else {
            text = displayText
            color = NSColor.labelColor
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font: NSFont.systemFont(ofSize: 13)
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let y = (bounds.height - size.height) / 2
        (text as NSString).draw(at: NSPoint(x: 11, y: y), withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {          // Esc：取消录制，恢复原值
            cancelRecording()
            return
        }
        if event.keyCode == 51 || event.keyCode == 117 {   // Backspace / Forward Delete：清空
            isRecording = false
            capturedViaKeyDown = true
            capture([])
            return
        }
        var comps: [String] = []
        let f = event.modifierFlags
        if f.contains(.shift) { comps.append("⇧") }
        if f.contains(.control) { comps.append("⌃") }
        if f.contains(.option) { comps.append("⌥") }
        if f.contains(.command) { comps.append("⌘") }
        if let c = event.characters(byApplyingModifiers: []), !c.isEmpty {
            let m = Self.mainKeySymbol(c)
            if !m.isEmpty { comps.append(m) }
        }
        isRecording = false
        capturedViaKeyDown = true
        capture(comps)
    }

    override func flagsChanged(with event: NSEvent) {
        let kc = event.keyCode
        if kc == 63 {                       // Fn 单独键（硬件键，只在 flagsChanged 出现）
            handleFnFlags(event)
        } else if kc == 58 || kc == 61 {    // 左 Option / 右 Option：独立修饰键
            handleOptionFlags(event)
        }
    }

    private func handleFnFlags(_ event: NSEvent) {
        let down = event.modifierFlags.contains(.function)
            || CGEventSource.flagsState(.hidSystemState).contains(.maskSecondaryFn)
        if down && !fnHeld {
            fnHeld = true
        } else if !down && fnHeld {
            fnHeld = false
            var comps = ["Fn"]
            let f = event.modifierFlags
            if f.contains(.shift) { comps.append("⇧") }
            if f.contains(.control) { comps.append("⌃") }
            if f.contains(.option) { comps.append("⌥") }
            if f.contains(.command) { comps.append("⌘") }
            finishCapture(comps)
        }
    }

    private func handleOptionFlags(_ event: NSEvent) {
        let down = event.modifierFlags.contains(.option)
        if down && !optionHeld {
            optionHeld = true
        } else if !down && optionHeld {
            optionHeld = false
            // 若刚才已经被 keyDown 录成 ⌥+主键，则不再重复录成独立 ⌥
            if capturedViaKeyDown {
                capturedViaKeyDown = false
                return
            }
            var comps = ["⌥"]
            let f = event.modifierFlags
            if f.contains(.shift) { comps.append("⇧") }
            if f.contains(.control) { comps.append("⌃") }
            if f.contains(.command) { comps.append("⌘") }
            finishCapture(comps)
        }
    }

    private func finishCapture(_ comps: [String]) {
        isRecording = false
        capture(comps)
    }

    private func cancelRecording() {
        isRecording = false
        fnHeld = false
        optionHeld = false
        needsDisplay = true
    }

    private func capture(_ comps: [String]) {
        onCapture?(comps)
        needsDisplay = true
    }

    static func mainKeySymbol(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "" }
        if t == " " { return "Space" }
        return t.uppercased()
    }
}