import Foundation
import AppKit
import CoreGraphics

/// 全局快捷键监听，统一 toggle（按一下开始、再按一下结束）：
/// 1) Fn 系（无主键）：通过 NSEvent flagsChanged 监听（Fn 虚拟键码 63，后台全局可用）。
/// 2) 独立全局热键（有主键，如 ⌥A、⌘1、⌃Space）：通过 CGEventTap 监听 keyDown。
///    —— NSEvent 的 global keyDown monitor 在 app 后台不稳定，改用 CGEventTap（依赖「输入监控」权限）。
final class HotKeyManager {
    static let shared = HotKeyManager()

    var onHotKey: (([String]) -> Void)?
    var isPaused = false

    // Fn：NSEvent flagsChanged
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var fnHeld = false
    private var optionHeld = false
    /// Option 按下期间是否出现过主键 keyDown（出现过则视为组合键 ⌥+主键，松开 ⌥ 不再触发独立 ⌥）
    private var optionHadKeyDown = false

    // 独立热键：CGEventTap keyDown
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isTrusted: Bool { AXIsProcessTrusted() }

    private static let modifierSymbols: Set<String> = ["⌘", "⌥", "⌃", "⇧"]

    func start() {
        startFlagsMonitors()
        startEventTap()
    }

    func stop() {
        if let m = globalFlagsMonitor { NSEvent.removeMonitor(m) }
        if let m = localFlagsMonitor { NSEvent.removeMonitor(m) }
        globalFlagsMonitor = nil
        localFlagsMonitor = nil
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }

    // MARK: Fn（NSEvent flagsChanged）

    private func startFlagsMonitors() {
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] e in
            self?.handleFlagsChanged(e)
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] e in
            self?.handleFlagsChanged(e)
            return e
        }
        nlog("NSEvent 已就绪（Fn 组合键 flagsChanged）")
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard !isPaused else { return }
        let kc = event.keyCode
        if kc == 63 {
            let modFn = event.modifierFlags.contains(.function)
            let hidFn = CGEventSource.flagsState(.hidSystemState).contains(.maskSecondaryFn)
            let down = modFn || hidFn
            let mods = modifierSymbols(from: event)
            applyFnState(down: down, modifiers: mods)
        } else if kc == 58 || kc == 61 {
            let down = event.modifierFlags.contains(.option)
            let mods = modifierSymbolsExcludingOption(from: event)
            applyOptionState(down: down, modifiers: mods)
        }
    }

    private func applyFnState(down: Bool, modifiers: [String]) {
        if down {
            guard !fnHeld else { return }
            fnHeld = true
            let comps = ["Fn"] + modifiers
            // 只有这个组合匹配到某个 Prompt 的快捷键才触发，避免改掉 Fn 后旧键仍兜底生效
            guard PromptStore.shared.prompt(matching: comps) != nil else { return }
            nlog("Fn 按下（\(modifiers)）→ toggle")
            onHotKey?(comps)
        } else {
            fnHeld = false
        }
    }

    private func applyOptionState(down: Bool, modifiers: [String]) {
        if down {
            guard !optionHeld else { return }
            optionHeld = true
            optionHadKeyDown = false
        } else {
            guard optionHeld else { return }
            optionHeld = false
            // 按下期间若出现过主键（⌥+A 等组合），不触发独立 ⌥
            guard !optionHadKeyDown else { return }
            let comps = ["⌥"] + modifiers
            guard PromptStore.shared.prompt(matching: comps) != nil else { return }
            nlog("⌥ 单击（\(modifiers)）→ toggle")
            onHotKey?(comps)
        }
    }

    // MARK: 独立热键（CGEventTap keyDown）

    private func startEventTap() {
        let listenOK = CGPreflightListenEventAccess()
        nlog("输入监控权限预检：\(listenOK)")
        if !listenOK {
            CGRequestListenEventAccess()
        }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { (_, type, event, info) -> Unmanaged<CGEvent>? in
                if let info = info {
                    let mgr = Unmanaged<HotKeyManager>.fromOpaque(info).takeUnretainedValue()
                    if mgr.handleTap(type: type, event: event) {
                        return nil  // 吞噬：快捷键字符不进入目标输入框
                    }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        ) else {
            nlog("CGEventTap 创建失败：请在「系统设置 → 隐私与安全性 → 输入监控」勾选 NoType 后重启")
            return
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        nlog("CGEventTap 已就绪（独立热键 keyDown）")
    }

    private func handleTap(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard type == .keyDown else { return false }
        guard !isPaused else { return false }
        // Option 按下期间出现任意主键 keyDown，标记为组合键（避免松开 ⌥ 时再触发独立 ⌥）
        if optionHeld { optionHadKeyDown = true }
        guard let ns = NSEvent(cgEvent: event) else { return false }
        let comps = components(from: ns)
        guard hasMainKey(comps) else { return false }
        // 命中某个 Prompt 的快捷键才拦截；否则放行让字符正常输入
        guard PromptStore.shared.prompt(matching: comps) != nil else { return false }
        // 命中：忽略 autorepeat 只触发一次，但事件始终吞噬，避免按键字符打进输入框
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            nlog("热键按下（\(comps)）→ toggle")
            onHotKey?(comps)
        }
        return true
    }

    // MARK: 解析

    private func modifierSymbols(from event: NSEvent) -> [String] {
        let ef = event.modifierFlags
        let hid = CGEventSource.flagsState(.hidSystemState)
        var mods: [String] = []
        if ef.contains(.shift) || hid.contains(.maskShift) { mods.append("⇧") }
        if ef.contains(.control) || hid.contains(.maskControl) { mods.append("⌃") }
        if ef.contains(.option) || hid.contains(.maskAlternate) { mods.append("⌥") }
        if ef.contains(.command) || hid.contains(.maskCommand) { mods.append("⌘") }
        return mods
    }

    private func modifierSymbolsExcludingOption(from event: NSEvent) -> [String] {
        let ef = event.modifierFlags
        let hid = CGEventSource.flagsState(.hidSystemState)
        var mods: [String] = []
        if ef.contains(.shift) || hid.contains(.maskShift) { mods.append("⇧") }
        if ef.contains(.control) || hid.contains(.maskControl) { mods.append("⌃") }
        if ef.contains(.command) || hid.contains(.maskCommand) { mods.append("⌘") }
        return mods
    }

    private func components(from event: NSEvent) -> [String] {
        var comps = modifierSymbols(from: event)
        if let raw = event.characters(byApplyingModifiers: []), !raw.isEmpty {
            comps.append(mainKeySymbol(raw))
        }
        return comps
    }

    private func mainKeySymbol(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "" }
        if t == " " { return "Space" }
        return t.uppercased()
    }

    private func hasMainKey(_ comps: [String]) -> Bool {
        comps.contains { !Self.modifierSymbols.contains($0) }
    }
}