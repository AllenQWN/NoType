import SwiftUI

struct HistoryView: View {
    @ObservedObject var model: AppModel
    @State private var filter = 0

    private let filters = ["全部", "听写", "翻译"]

    private var filtered: [HistoryItem] {
        switch filter {
        case 1: return model.history.filter { $0.mode == .dictate }
        case 2: return model.history.filter { $0.mode == .translate }
        default: return model.history
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("历史记录")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Theme.text)
                Spacer()
                Text("🔒 你的数据仅存本机，只有你能访问")
                    .font(.system(size: 12.5))
                    .foregroundColor(Theme.text3)
            }

            HStack(spacing: 8) {
                ForEach(0..<filters.count, id: \.self) { i in
                    Button(action: { filter = i }) {
                        Text(filters[i])
                            .font(.system(size: 12.5))
                            .foregroundColor(filter == i ? Theme.text : Theme.text2)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 5)
                            .background(filter == i ? Theme.selected : Color.clear)
                            .cornerRadius(99)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.top, 14)
            .padding(.bottom, 14)

            if filtered.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 28))
                        .foregroundColor(Theme.text3)
                    Text("还没有记录")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.text3)
                    Text("开始一次听写或翻译，内容会出现在这里。")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.text3)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filtered) { item in
                            itemRow(item)
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.winBg)
    }

    private func itemRow(_ item: HistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(item.mode == .dictate ? "听写" : "翻译")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.brand)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Theme.brandSoft)
                    .cornerRadius(5)
                Text(Self.timeString(item.timestamp))
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.text3)
                Spacer()
                Text("\(item.charCount) 字")
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.text3)
            }
            Text(item.result)
                .font(.system(size: 13))
                .foregroundColor(Theme.text)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Theme.panel)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()

    private static func timeString(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }
}