import SwiftUI

enum AppSection: String, CaseIterable {
    case home
    case history
    case settings
}

enum HistoryMode: String, Codable {
    case dictate
    case translate
}

struct HistoryItem: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let mode: HistoryMode
    let original: String
    let result: String

    var charCount: Int { result.count }
}

final class AppModel: ObservableObject {
    @Published var section: AppSection = .home
    @Published var totalWordCount = 0
    @Published var permissionMessage = ""
    @Published var history: [HistoryItem] = []

    private let historyKey = "notype.history"
    private let countKey = "notype.totalWordCount"

    init() {
        load()
    }

    func addHistory(mode: HistoryMode, original: String, result: String) {
        let item = HistoryItem(id: UUID(), timestamp: Date(), mode: mode, original: original, result: result)
        history.insert(item, at: 0)
        totalWordCount += item.charCount
        save()
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let items = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            history = items
        }
        totalWordCount = UserDefaults.standard.integer(forKey: countKey)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
        UserDefaults.standard.set(totalWordCount, forKey: countKey)
    }
}