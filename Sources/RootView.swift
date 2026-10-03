import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var dropdownHost = DropdownHost.shared

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                sidebar
                contentArea
            }
            .frame(minWidth: 930, maxWidth: .infinity, minHeight: 580, maxHeight: .infinity)
            .background(Theme.winBg)

            if let menu = dropdownHost.active {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onTapGesture { dropdownHost.close() }
                    .zIndex(1)

                FloatingMenuView(options: menu.options, width: menu.anchor.width)
                    .offset(x: menu.anchor.minX, y: menu.anchor.minY + menu.anchor.height + 6)
                    .zIndex(2)
            }
        }
        .coordinateSpace(name: "root")
    }

    // MARK: 左侧导航
    private var sidebar: some View {
        VStack(spacing: 3) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Theme.logo)
                        .frame(width: 26, height: 26)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                }
                Text("NoType")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Theme.text)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)

            navButton(.home, icon: "house", label: "主页")
            navButton(.history, icon: "clock", label: "历史")

            Spacer()

            VStack(alignment: .leading, spacing: 2) {
                Text("\(model.totalWordCount)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Theme.text)
                Text("总字数")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.text3)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.panel)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
            .padding(.horizontal, 6)

            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .frame(width: 16, alignment: .center)
                Text("设置")
                    .font(.system(size: 13))
                Spacer(minLength: 0)
            }
            .foregroundColor(model.section == .settings ? Theme.text : Theme.text2)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(model.section == .settings ? Theme.selected : Color.clear)
            .cornerRadius(8)
            .contentShape(Rectangle())
            .onTapGesture { model.section = .settings }
            .padding(.horizontal, 6)
            .padding(.top, 6)
        }
        .padding(.top, 30)
        .padding(.bottom, 14)
        .padding(.horizontal, 10)
        .frame(minWidth: 196, maxWidth: 196, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.winBg)
        .overlay(alignment: .trailing) { Rectangle().frame(width: 1).foregroundColor(Theme.border) }
    }

    private func navButton(_ section: AppSection, icon: String, label: String) -> some View {
        let active = model.section == section
        return HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .frame(width: 16, alignment: .center)
                .opacity(active ? 0.9 : 0.7)
            Text(label)
            Spacer(minLength: 0)
        }
        .foregroundColor(active ? Theme.text : Theme.text2)
        .fontWeight(active ? .semibold : .regular)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(active ? Theme.selected : Color.clear)
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture { model.section = section }
    }

    // MARK: 内容区
    @ViewBuilder
    private var contentArea: some View {
        switch model.section {
        case .home:
            HomeView(model: model)
        case .history:
            HistoryView(model: model)
        case .settings:
            SettingsView(model: model)
        }
    }
}