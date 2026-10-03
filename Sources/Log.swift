import Foundation

/// 全局日志：同时写系统日志（NSLog）和 ~/notype_debug.log，方便排查整条链路。
func nlog(_ msg: String) {
    NSLog("[NoType] %@", msg)
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("notype_debug.log")
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    let line = "\(formatter.string(from: Date())) \(msg)\n"
    guard let data = line.data(using: .utf8) else { return }
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    } else {
        try? data.write(to: url)
    }
}