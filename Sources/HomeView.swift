import SwiftUI

struct HomeView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var store = PromptStore.shared

    @State private var editorItem: PromptEditorItem?

    var body: some View {
        HStack(spacing: 0) {
            centerContent
            statsPanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.winBg)
        .sheet(item: $editorItem) { item in
            PromptEditorView(prompt: item.prompt, store: store)
        }
    }

    // MARK: 中间内容
    private var centerContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("说话，\n不用打字")
                    .font(.system(size: 34, weight: .heavy))
                    .tracking(-0.5)
                    .foregroundColor(Theme.text)
                Text("自然表达，把你说的话变成精炼、可发送的文字——实时完成。")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.text2)
                    .padding(.top, 6)

                HStack(spacing: 6) {
                    Text("快捷指令")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.text3)
                    Text("每一项都是一段可自定义的 Prompt，按一下对应快捷键开始、点 Edit 修改")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.text3)
                        .opacity(0.85)
                }
                .padding(.top, 24)
                .padding(.bottom, 10)

                VStack(spacing: 10) {
                    ForEach(store.prompts) { p in
                        promptCard(p)
                    }
                }

                Button {
                    editorItem = PromptEditorItem(prompt: nil)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                        Text("新增 Prompt")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundColor(Theme.text3)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Theme.text3.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 20)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func promptCard(_ p: Prompt) -> some View {
        HStack(spacing: 0) {
            // 主体：静态展示（触发靠 Fn / Fn+⇧ 快捷键）
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(Color.white)
                        .frame(width: 40, height: 40)
                        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.border))
                    Image(systemName: p.icon)
                        .font(.system(size: 18))
                        .foregroundColor(Theme.brand)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Theme.text)
                    Text(p.prompt)
                        .font(.system(size: 12.5))
                        .foregroundColor(Theme.text2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    ForEach(p.keys, id: \.self) { k in
                        keycap(k)
                    }
                }
                .padding(.trailing, 4)
            }
            .padding(.leading, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)

            // 编辑按钮：独立兄弟按钮，与主体互不穿透
            Button {
                editorItem = PromptEditorItem(prompt: p)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                    Text("Edit")
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .foregroundColor(Theme.brand)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Color.white)
                .cornerRadius(7)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.brand.opacity(0.35)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 16)
            .padding(.leading, 8)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.cardGrad)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
    }

    private func keycap(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
            .foregroundColor(Theme.text2)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.keycap)
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border))
    }

    // MARK: 右侧统计
    private var statsPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("使用统计")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.text3)
                Text("15 分钟")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundColor(Theme.text)
                Text("本周录音时长")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.text2)
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("122")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundColor(Theme.text)
                Text("字 / 分钟")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.text2)
            }
            Spacer()
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("🔒 你的数据仅保存在本机")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.text3)
                Text("Version 1.0.0")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.text3)
            }
        }
        .padding(18)
        .frame(minWidth: 210, maxWidth: 210, maxHeight: .infinity, alignment: .top)
        .background(Theme.winBg)
        .overlay(alignment: .leading) { Rectangle().frame(width: 1).foregroundColor(Theme.border) }
    }
}

/// 弹窗编辑目标：prompt 为 nil 表示新增，否则编辑对应 Prompt。
/// 用 Identifiable 包装以配合 .sheet(item:) —— 每次编辑/新增生成新的 id，
/// 保证弹窗按当前项重新渲染，而不是复用上一次的旧内容。
struct PromptEditorItem: Identifiable {
    let id = UUID()
    let prompt: Prompt?
}

// MARK: Prompt 编辑 / 新增弹窗

struct PromptEditorView: View {
    let prompt: Prompt?
    @ObservedObject var store: PromptStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var promptText = ""
    @State private var keysText = ""

    private var isNew: Bool { prompt == nil }
    private var canReset: Bool { prompt?.isBuiltin == true }
    private var canDelete: Bool {
        if let p = prompt { return !p.isBuiltin }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.brandSoft)
                        .frame(width: 30, height: 30)
                    Image(systemName: prompt?.icon ?? "sparkles")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.brand)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(isNew ? "新增 Prompt" : "编辑 Prompt")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Theme.text)
                    Text(isNew ? "定义一个属于你的快捷指令" : "修改「\(prompt?.name ?? "")」的提示词")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.text3)
                }
                Spacer()
            }

            fieldLabel("名称")
            TextField("例如：总结、回复邮件…", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(10)
                .background(Theme.panel2)
                .cornerRadius(9)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.border))

            fieldLabel("提示词 Prompt")
            TextEditor(text: $promptText)
                .font(.system(size: 12))
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Theme.panel2)
                .cornerRadius(9)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.border))

            fieldLabel("快捷键")
            ShortcutRecorder(text: $keysText)
                .frame(height: 38)
                .background(Theme.panel2)
                .cornerRadius(9)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.border))

            HStack(spacing: 8) {
                Button("保存") { save() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.brand)
                    .cornerRadius(8)

                Button("取消") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.text2)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.panel)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))

                Spacer()

                if canReset {
                    Button("恢复默认") { resetToDefault() }
                        .buttonStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.text3)
                }
                if canDelete {
                    Button("删除") { deletePrompt() }
                        .buttonStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(Color.red.opacity(0.85))
                }
            }
            .padding(.top, 2)
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            load()
            HotKeyManager.shared.isPaused = true
        }
        .onDisappear {
            HotKeyManager.shared.isPaused = false
        }
    }

    private func fieldLabel(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(Theme.text2)
    }

    private func load() {
        if let p = prompt {
            name = p.name
            promptText = p.prompt
            keysText = p.keys.joined(separator: " + ")
        }
    }

    private func parseKeys(_ s: String) -> [String] {
        s.split(whereSeparator: { $0 == "+" || $0 == "＋" || $0.isWhitespace })
            .map { PromptStore.normalizeKey(String($0)) }
            .filter { !$0.isEmpty }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedPrompt.isEmpty else { return }
        let keys = parseKeys(keysText)
        if var p = prompt {
            p.name = trimmedName
            p.prompt = trimmedPrompt
            p.keys = keys
            store.update(p)
        } else {
            store.add(name: trimmedName, prompt: trimmedPrompt, keys: keys)
        }
        dismiss()
    }

    private func resetToDefault() {
        guard let p = prompt else { return }
        switch p.kind {
        case .dictate:
            name = PromptStore.defaultDictate.name
            promptText = PromptStore.defaultDictate.prompt
            keysText = PromptStore.defaultDictate.keys.joined(separator: " + ")
        case .translate:
            name = PromptStore.defaultTranslate.name
            promptText = PromptStore.defaultTranslate.prompt
            keysText = PromptStore.defaultTranslate.keys.joined(separator: " + ")
        case .custom:
            break
        }
    }

    private func deletePrompt() {
        if let p = prompt {
            store.delete(p)
        }
        dismiss()
    }
}