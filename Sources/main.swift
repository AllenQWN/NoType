import SwiftUI
import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let speech = SpeechService()
    private var activePrompt: Prompt?
    private var mainWindow: NSWindow!
    private var voicePanel: NSPanel?
    private var frontmostAppAtRecord: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 单实例保护：已有 NoType 在跑时，本实例直接退出，避免多个实例抢快捷键、麦克风和剪贴板注入
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "com.notype.app")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty {
            nlog("检测到已有 NoType 实例在运行，本实例退出（对方 PID: \(others.map { String($0.processIdentifier) }.joined(separator: ","))）")
            NSApp.terminate(nil)
            return
        }
        nlog("applicationDidFinishLaunching, AXIsProcessTrusted=\(AXIsProcessTrusted())")
        NSApp.setActivationPolicy(.regular)
        buildMainMenu()
        buildMainWindow()
        HotKeyManager.shared.onHotKey = { [weak self] keys in
            self?.toggle(keys: keys)
        }
        HotKeyManager.shared.start()
        NSApp.activate(ignoringOtherApps: true)
        AIEngineManager.shared.bootstrap()   // 异步检测本地 AI，已装则自动拉起服务
        ASREngineManager.shared.bootstrap()  // 异步检测本地识别引擎
        promptPermissionsIfNeeded()
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        // App 菜单
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 NoType",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 NoType",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        // 编辑菜单：没有它 SwiftUI 的 TextEditor/TextField 无法响应 ⌘A/⌘C/⌘V/⌘X
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    private func buildMainWindow() {
        let root = RootView(
            model: model
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(rootView: root)
        window.contentMinSize = NSSize(width: 680, height: 500)
        window.center()
        window.makeKeyAndOrderFront(nil)
        mainWindow = window
    }

    // MARK: 触发

    /// 快捷键 toggle：按一下开始录音、再按一下结束并处理
    private func toggle(keys: [String]) {
        if speech.isListening {
            finishRecording(keys: keys)
        } else {
            activePrompt = PromptStore.shared.prompt(matching: keys) ?? PromptStore.shared.firstPrompt()
            beginRecording()
        }
    }

    private func beginRecording() {
        guard !speech.isListening else { return }
        frontmostAppAtRecord = NSWorkspace.shared.frontmostApplication
        nlog("beginRecording: 聚焦 \(frontmostAppAtRecord?.localizedName ?? "nil")")
        TextInjector.begin()   // 快照剪贴板，说完一次性注入后再恢复
        requestAndStart()
    }

    /// 第二次按下（结束录音）：处理开始录音时已确定的 Prompt（纯 Fn = 听写，Fn+⇧ = 翻译，⌥A 等 = 自定义）
    private func finishRecording(keys: [String]) {
        guard speech.isListening else { return }
        if activePrompt == nil {
            activePrompt = PromptStore.shared.prompt(matching: keys) ?? PromptStore.shared.firstPrompt()
        }
        stopListening()
    }

    private func requestAndStart() {
        speech.onFailure = { [weak self] msg in
            DispatchQueue.main.async {
                self?.dismissVoiceBar()
                self?.alert("无法开始录音：\(msg)")
            }
        }
        speech.ensurePermissions { [weak self] granted, msg in
            guard let self = self else { return }
            nlog("ensurePermissions 回调: granted=\(granted), msg=\(msg ?? "nil")")
            if granted {
                self.showVoiceBar()
                self.speech.start()
            } else {
                self.alert(msg ?? "缺少麦克风或语音识别权限")
            }
        }
    }

    private func stopListening() {
        nlog("stopListening 开始")
        let prompt = activePrompt ?? PromptStore.shared.firstPrompt() ?? PromptStore.defaultDictate
        // 停止录音后进入 loading：语音条转圈，等最终识别 + AI 处理完成
        speech.setProcessing(true, hint: prompt.isTranslate ? "正在翻译…" : "正在优化…")

        let isOnline = (UserDefaults.standard.string(forKey: "notype.asrMode") ?? "local") == "online"

        if isOnline {
            // 线上：识别结果由双向流式会话通过 onStreamResult 异步返回
            speech.onStreamResult = { [weak self] res in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.finishBy(res: res, prompt: prompt)
                }
            }
            speech.stop()
            return
        }

        // 本地：停止录音得到 WAV，走本地离线识别（SenseVoice）
        let wavURL = speech.stop()
        nlog("stopListening: wav=\(wavURL?.lastPathComponent ?? "nil")")
        guard let wavURL = wavURL else {
            dismissVoiceBar()
            TextInjector.finish()
            nlog("没有有效录音")
            return
        }
        ASRService.shared.transcribe(wavURL: wavURL) { [weak self] res in
            DispatchQueue.main.async {
                guard let self = self else { return }
                try? FileManager.default.removeItem(at: wavURL)
                self.finishBy(res: res, prompt: prompt)
            }
        }
    }

    /// 识别结果统一处理：成功后走对应 Prompt（润色/翻译）→ 注入；失败静默关闭语音条。
    private func finishBy(res: Result<String, Error>, prompt: Prompt) {
        switch res {
        case .success(let text):
            speech.setResult(text)
            nlog("识别结果：\(text)")
            handleRecognized(text, prompt: prompt)
        case .failure(let error):
            nlog("识别失败：\(error.localizedDescription)")
            speech.setProcessing(false)
            dismissVoiceBar()
            TextInjector.finish()
            // 不说话/识别不到有效内容时静默关闭语音条，不弹窗打断用户
        }
    }

    private func handleRecognized(_ result: String, prompt: Prompt) {
        LLMService.shared.run(prompt, text: result) { [weak self] res in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.speech.setProcessing(false)
                self.dismissVoiceBar()
                let mode: HistoryMode = prompt.isTranslate ? .translate : .dictate
                switch res {
                case .success(let out):
                    self.inject(out, original: result, mode: mode, note: "\(prompt.name)：\(out)")
                case .failure:
                    self.inject(result, original: result, mode: mode, note: "\(prompt.name)不可用，输入原文：\(result)")
                }
            }
        }
    }

    /// 注入文字到说话前的目标输入框：先激活目标 App 确保焦点正确，
    /// 稍等焦点稳定后 ⌘V 粘贴，粘贴完成后再恢复用户原剪贴板。
    private func inject(_ text: String, original: String, mode: HistoryMode, note: String) {
        frontmostAppAtRecord?.activate(options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self else { return }
            TextInjector.commit(text) {
                self.model.addHistory(mode: mode, original: original, result: text)
                nlog(note)
            }
        }
    }

    // MARK: 语音显示框

    private func showVoiceBar() {
        if voicePanel == nil {
            let width = voiceBarWidth()
            let hosting = NSHostingView(rootView: VoiceBarView(speech: speech))
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: width, height: 280),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false
            )
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = hosting
            voicePanel = panel
        }
        // 定位到屏幕底部中央（圆固定贴底，字幕向上扩展）
        if let panel = voicePanel, let screen = NSScreen.main {
            positionVoicePanel(panel, on: screen)
        }
        voicePanel?.orderFrontRegardless()
    }

    /// 语音条最大宽度：新竖排布局为紧凑小胶囊，固定一个适中宽度
    private func voiceBarWidth() -> CGFloat {
        return 260
    }

    private func positionVoicePanel(_ panel: NSPanel, on screen: NSScreen) {
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 16))
    }

    private func dismissVoiceBar() {
        voicePanel?.orderOut(nil)
    }

    private func alert(_ message: String) {
        let a = NSAlert()
        a.messageText = "NoType"
        a.informativeText = message
        a.alertStyle = .warning
        a.runModal()
    }

    private func promptPermissionsIfNeeded() {
        if HotKeyManager.shared.isTrusted { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.showAccessibilityHelp(textCopied: false)
        }
    }

    /// 辅助功能未授权时的统一引导
    private func showAccessibilityHelp(textCopied: Bool) {
        let a = NSAlert()
        a.alertStyle = .warning
        if textCopied {
            a.messageText = "文字已复制到剪贴板，但无法自动注入"
            a.informativeText = "NoType 尚未获得「辅助功能」权限，所以不能把文字自动粘贴到输入框（已帮你复制到剪贴板，可用 Cmd+V 手动粘贴）。\n\n开启后即可自动注入：\n① 打开「系统设置 → 隐私与安全性 → 辅助功能」\n② 如果列表里已有 NoType，先选中它点下方的「−」移除\n③ 再点「+」重新添加 NoType.app（位于 /Users/allenq/codes/NoType）\n④ 完全退出 NoType（Cmd+Q）后重新打开\n\n完成后按一下快捷键开始说话、再按一下结束即可自动注入。"
        } else {
            a.messageText = "需要开启「辅助功能」权限"
            a.informativeText = "NoType 用快捷键「按一下开始说话、再按一下结束」，需要一个系统权限：辅助功能（用于把文字粘贴到任意输入框）。\n\n开启步骤：\n① 打开「系统设置 → 隐私与安全性 → 辅助功能」\n② 如果列表里已有 NoType，先选中它点下方的「−」移除\n③ 再点「+」重新添加 NoType.app（位于 /Users/allenq/codes/NoType）\n④ 完全退出 NoType（Cmd+Q）后重新打开"
        }
        a.addButton(withTitle: "打开辅助功能设置")
        a.addButton(withTitle: "稍后")
        if a.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        speech.stop()
        HotKeyManager.shared.stop()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()