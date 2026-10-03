import SwiftUI
import Combine
import CoreAudio

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var ai = AIEngineManager.shared
    @ObservedObject private var asr = ASREngineManager.shared
    @ObservedObject private var mic = MicrophoneManager.shared

    @AppStorage("notype.aiMode") private var aiMode: String = "local"
    @AppStorage("notype.asrMode") private var asrMode: String = "local"

    @AppStorage("notype.aiProvider") private var aiProvider = "OpenAI"
    @AppStorage("notype.aiKey") private var aiKey = ""
    @AppStorage("notype.aiModelName") private var aiModelName = ""
    @AppStorage("notype.asrProvider") private var asrProvider = "豆包"
    @AppStorage("notype.asrKey") private var asrKey = ""
    @AppStorage("notype.asrModelName") private var asrModelName = ""
    @AppStorage("notype.asrVersion") private var asrVersion = "2.0"

    @State private var aiSaveLabel = "保存配置"
    @State private var asrSaveLabel = "保存配置"

    // 行内标签宽度 + 与控件的间距，用于让按钮行等元素与控件列对齐
    private let labelWidth: CGFloat = 78
    private let fieldSpacing: CGFloat = 14

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("设置")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Theme.text)

                VStack(alignment: .leading, spacing: 0) {
                    micSection
                    separator
                    aiSection
                    separator
                    asrSection
                }
                .padding(.horizontal, 22)
                .background(Theme.panel)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
            }
            .padding(24)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.winBg)
        .onAppear { ai.refreshStatus(); asr.refreshStatus(); mic.refresh() }
    }

    // MARK: - 麦克风

    private var micSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            groupTitle("麦克风")
            field("输入设备") { micPicker }
            field("输入电平") { LevelMeterView(level: mic.level, isLive: mic.isMetering) }
            primaryButton(mic.isMetering ? "停止测试" : "测试麦克风") {
                if mic.isMetering { mic.stopMetering() } else { mic.startMetering() }
            }
            .padding(.leading, labelWidth + fieldSpacing)
        }
        .padding(.vertical, 18)
    }

    private var micPicker: some View {
        Dropdown(
            options: mic.devices.map { DropdownOption(label: $0.name, value: $0.id) },
            selection: Binding<AudioDeviceID>(
                get: { mic.selectedDeviceID },
                set: { newID in
                    if let d = mic.devices.first(where: { $0.id == newID }) {
                        mic.select(d)
                    }
                }
            )
        )
    }

    // MARK: - AI 引擎

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            groupTitle("AI 引擎")
            field("类型") { modeSelect($aiMode) }
            if aiMode == "online" { aiOnlinePanel } else { aiLocalPanel }
        }
        .padding(.vertical, 18)
    }

    private var aiLocalPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            field("模型") { modelRow("qwen2.5:7b", on: ai.phase == .ready, label: ai.phase == .ready ? "已就绪" : aiStatusShort) }

            if ai.phase == .working && ai.progress >= 0 {
                ProgressView(value: ai.progress)
                    .progressViewStyle(.linear)
                    .tint(Theme.brand)
                    .padding(.leading, labelWidth + fieldSpacing)
                    .padding(.bottom, 14)
            }

            HStack(spacing: 12) {
                primaryButton(buttonTitle, disabled: !canInstall) { ai.install() }
                if ai.phase == .ready {
                    hint("本地离线 · 4.7GB")
                }
            }
            .padding(.leading, labelWidth + fieldSpacing)
        }
    }

    private var aiOnlinePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            field("服务商") {
                Dropdown(
                    options: [
                        DropdownOption(label: "OpenAI", value: "OpenAI"),
                        DropdownOption(label: "通义千问", value: "通义千问"),
                        DropdownOption(label: "DeepSeek", value: "DeepSeek"),
                        DropdownOption(label: "Moonshot (Kimi)", value: "Moonshot (Kimi)"),
                        DropdownOption(label: "自定义", value: "自定义")
                    ],
                    selection: $aiProvider
                )
            }
            field("API Key") {
                SecureField("sk-…", text: $aiKey)
                    .textFieldStyle(.plain)
                    .padding(9)
                    .background(Theme.panel2)
                    .cornerRadius(9)
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.border))
            }
            field("模型名") {
                TextField("例如 gpt-4o-mini / qwen-max", text: $aiModelName)
                    .textFieldStyle(.plain)
                    .padding(9)
                    .background(Theme.panel2)
                    .cornerRadius(9)
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.border))
            }
            HStack(spacing: 12) {
                primaryButton(aiSaveLabel) { saveOnlineAI() }
                hint("密钥仅保存在本机")
            }
            .padding(.leading, labelWidth + fieldSpacing)
        }
    }

    // MARK: - 语音识别

    private var asrSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            groupTitle("语音识别")
            field("类型") { modeSelect($asrMode) }
            if asrMode == "online" { asrOnlinePanel } else { asrLocalPanel }
        }
        .padding(.vertical, 18)
    }

    private var asrLocalPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            field("模型") { modelRow("SenseVoice", on: asr.phase == .ready, label: asr.phase == .ready ? "已就绪" : asrStatusShort) }

            if asr.phase == .working && asr.progress >= 0 {
                ProgressView(value: asr.progress)
                    .progressViewStyle(.linear)
                    .tint(Theme.brand)
                    .padding(.leading, labelWidth + fieldSpacing)
                    .padding(.bottom, 14)
            }

            HStack(spacing: 12) {
                primaryButton(asrButtonTitle, disabled: !asrCanInstall) { asr.install() }
                if asr.phase == .ready {
                    hint("本地离线 · 166MB")
                }
            }
            .padding(.leading, labelWidth + fieldSpacing)
        }
    }

    private var asrOnlinePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            field("服务商") {
                Dropdown(
                    options: [
                        DropdownOption(label: "豆包", value: "豆包"),
                        DropdownOption(label: "自定义", value: "自定义")
                    ],
                    selection: $asrProvider
                )
            }
            field("模型版本") {
                Dropdown(
                    options: [
                        DropdownOption(label: "流式语音识别 2.0（推荐）", value: "2.0"),
                        DropdownOption(label: "流式语音识别 1.0", value: "1.0")
                    ],
                    selection: $asrVersion
                )
            }
            field("API Key") {
                SecureField("火山引擎控制台的 API Key", text: $asrKey)
                    .textFieldStyle(.plain)
                    .padding(9)
                    .background(Theme.panel2)
                    .cornerRadius(9)
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.border))
            }
            HStack(spacing: 12) {
                primaryButton(asrSaveLabel) { saveOnlineASR() }
                hint("大模型流式识别(小时版) · 按量计费 · 密钥仅保存在本机")
            }
            .padding(.leading, labelWidth + fieldSpacing)
        }
    }

    // MARK: - 保存动作（线上配置目前仅本地保存草稿）

    private func saveOnlineAI() {
        aiSaveLabel = "已保存 ✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { aiSaveLabel = "保存配置" }
    }

    private func saveOnlineASR() {
        asrSaveLabel = "已保存 ✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { asrSaveLabel = "保存配置" }
    }

    // MARK: - 通用小组件

    private var separator: some View {
        Rectangle().fill(Theme.border).frame(height: 1)
    }

    private func groupTitle(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(Theme.text)
            .padding(.bottom, 16)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: fieldSpacing) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.text2)
                .frame(width: labelWidth, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 14)
    }

    private func modeSelect(_ selection: Binding<String>) -> some View {
        Dropdown(
            options: [
                DropdownOption(label: "本地", value: "local"),
                DropdownOption(label: "线上", value: "online")
            ],
            selection: selection
        )
    }

    private func modelRow(_ name: String, on: Bool, label: String) -> some View {
        HStack {
            Text(name)
                .font(.system(size: 13))
                .foregroundColor(Theme.text)
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(on ? noTypeGreen : Theme.text3)
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(on ? noTypeGreen : Theme.text3)
            }
        }
        .padding(9)
        .background(Theme.panel2)
        .cornerRadius(9)
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.border))
    }

    private func primaryButton(_ title: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 15)
                .padding(.vertical, 8)
                .background(disabled ? Theme.text3 : Theme.brand)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func hint(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 11))
            .foregroundColor(Theme.text3)
    }

    // MARK: - AI 状态

    private var aiStatusShort: String {
        switch ai.phase {
        case .working: return "安装中…"
        case .failed: return "安装失败"
        case .ready: return "已就绪"
        default: return "未安装"
        }
    }

    private var buttonTitle: String {
        switch ai.phase {
        case .working: return "安装中…"
        case .ready: return "已就绪"
        case .failed: return "重试安装"
        default: return "安装本地模型"
        }
    }

    private var canInstall: Bool {
        switch ai.phase {
        case .working, .ready: return false
        default: return true
        }
    }

    // MARK: - ASR 状态

    private var asrStatusShort: String {
        switch asr.phase {
        case .working: return "安装中…"
        case .failed: return "安装失败"
        case .ready: return "已就绪"
        default: return "未安装"
        }
    }

    private var asrButtonTitle: String {
        switch asr.phase {
        case .working: return "安装中…"
        case .ready: return "已就绪"
        case .failed: return "重试安装"
        default: return "安装本地模型"
        }
    }

    private var asrCanInstall: Bool {
        switch asr.phase {
        case .working, .ready: return false
        default: return true
        }
    }
}

private let noTypeGreen = Color(red: 47.0/255.0, green: 179.0/255.0, blue: 68.0/255.0)

// MARK: - 下拉浮层（画在 RootView 顶层，跨层锚定，避免 popover 遮挡 / 撑开布局）

struct MenuOption: Identifiable {
    let id: String
    let label: String
    let isSelected: Bool
    let action: () -> Void
}

struct ActiveMenu {
    let options: [MenuOption]
    let anchor: CGRect
}

final class DropdownHost: ObservableObject {
    static let shared = DropdownHost()
    @Published var active: ActiveMenu? = nil
    @Published var owner: UUID? = nil

    func open(_ menu: ActiveMenu, owner: UUID) {
        active = menu
        self.owner = owner
    }

    func close(owner: UUID? = nil) {
        if let o = owner, self.owner != o { return }
        active = nil
        self.owner = nil
    }
}

struct FloatingMenuView: View {
    let options: [MenuOption]
    let width: CGFloat
    @State private var hovered: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(options) { opt in
                optionRow(opt)
            }
        }
        .padding(4)
        .frame(width: width, alignment: .leading)
        .background(Theme.panel)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
        .shadow(color: .black.opacity(0.15), radius: 18, x: 0, y: 8)
    }

    private func optionRow(_ opt: MenuOption) -> some View {
        Button {
            opt.action()
        } label: {
            HStack(spacing: 8) {
                Text(opt.label)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if opt.isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Theme.brand)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(hovered == opt.id ? Theme.brandSoft : Color.clear)
        .cornerRadius(5)
        .onHover { inside in
            hovered = inside ? opt.id : (hovered == opt.id ? nil : hovered)
        }
    }
}

fileprivate struct DropdownOption<T: Hashable>: Identifiable {
    let label: String
    let value: T
    var id: T { value }
}

struct DropdownAnchorKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

fileprivate struct Dropdown<T: Hashable>: View {
    let options: [DropdownOption<T>]
    @Binding var selection: T
    @ObservedObject private var host = DropdownHost.shared
    @State private var myId = UUID()
    @State private var anchorFrame: CGRect = .zero

    private var currentLabel: String {
        options.first(where: { $0.value == selection })?.label ?? options.first?.label ?? "—"
    }

    private var isOpen: Bool {
        host.owner == myId
    }

    var body: some View {
        Button {
            if isOpen { host.close(owner: myId) } else { open() }
        } label: {
            HStack(spacing: 6) {
                Text(currentLabel)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.text3)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Theme.panel)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isOpen ? Theme.brand.opacity(0.65) : Theme.border))
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: DropdownAnchorKey.self, value: [myId: geo.frame(in: .named("root"))])
            }
        )
        .onPreferenceChange(DropdownAnchorKey.self) { anchors in
            if let f = anchors[myId] { anchorFrame = f }
        }
    }

    private func open() {
        let mos = options.map { opt in
            MenuOption(
                id: "\(opt.value)",
                label: opt.label,
                isSelected: opt.value == selection,
                action: {
                    selection = opt.value
                    host.close(owner: myId)
                }
            )
        }
        host.open(ActiveMenu(options: mos, anchor: anchorFrame), owner: myId)
    }
}

// MARK: - 麦克风电平表（专业分段式：绿→黄→红渐变 + 峰值保持）

fileprivate struct LevelMeterView: View {
    let level: Float
    let isLive: Bool

    @State private var display: Float = 0
    private let timer = Timer.publish(every: 0.06, on: .main, in: .common).autoconnect()

    // 6 格信号条：从左到右由矮到高，亮的格数随音量增加
    private let barCount = 6
    private let heights: [CGFloat] = [7, 10, 13, 16, 19, 22]
    private let litColor = Color(red: 82/255, green: 178/255, blue: 86/255)
    private let dimColor = Color(red: 224/255, green: 224/255, blue: 228/255)

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i < litCount ? litColor : dimColor)
                    .frame(width: 6, height: heights[i])
            }
        }
        .frame(height: 22, alignment: .bottom)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onReceive(timer) { _ in tick() }
        .onChange(of: isLive) {
            if !isLive { display = 0 }
        }
    }

    private var litCount: Int {
        let n = Int((display * Float(barCount)).rounded())
        return min(max(n, 0), barCount)
    }

    // attack 快、release 慢，让格子逐格亮起 / 熄灭更自然
    private func tick() {
        let target = isLive ? level : 0
        if target > display {
            display += (target - display) * 0.5
        } else {
            display += (target - display) * 0.18
        }
        if display < 0.02 { display = 0 }
        if display > 0.998 { display = 1 }
    }
}