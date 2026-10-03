import SwiftUI

/// 统一配色（仿 Typeless 设计稿 light 主题）
enum Theme {
    static let winBg = Color(red: 250.0/255.0, green: 250.0/255.0, blue: 250.0/255.0)   // #fafafa
    static let deskA = Color(red: 253.0/255.0, green: 252.0/255.0, blue: 250.0/255.0)   // #fdfcfa
    static let deskB = Color(red: 220.0/255.0, green: 233.0/255.0, blue: 251.0/255.0)   // #dce9fb
    static let panel = Color(red: 1.0, green: 1.0, blue: 1.0)
    static let panel2 = Color(red: 244.0/255.0, green: 244.0/255.0, blue: 246.0/255.0)  // #f4f4f6
    static let selected = Color(red: 233.0/255.0, green: 233.0/255.0, blue: 237.0/255.0) // #e9e9ed
    static let border = Color(red: 230.0/255.0, green: 230.0/255.0, blue: 234.0/255.0)  // #e6e6ea
    static let text = Color(red: 17.0/255.0, green: 17.0/255.0, blue: 19.0/255.0)       // #111113
    static let text2 = Color(red: 91.0/255.0, green: 91.0/255.0, blue: 97.0/255.0)      // #5b5b61
    static let text3 = Color(red: 154.0/255.0, green: 154.0/255.0, blue: 162.0/255.0)   // #9a9aa2
    static let brand = Color(red: 47.0/255.0, green: 125.0/255.0, blue: 246.0/255.0)    // #2f7df6
    static let brandPurple = Color(red: 106.0/255.0, green: 92.0/255.0, blue: 255.0/255.0) // #6a5cff
    static let brandSoft = Color(red: 228.0/255.0, green: 239.0/255.0, blue: 255.0/255.0)  // #e4efff
    static let keycap = Color(red: 240.0/255.0, green: 240.0/255.0, blue: 243.0/255.0)  // #f0f0f3

    static let cardGrad = LinearGradient(
        colors: [
            Color(red: 231.0/255.0, green: 240.0/255.0, blue: 255.0/255.0),  // #e7f0ff
            Color(red: 253.0/255.0, green: 254.0/255.0, blue: 255.0/255.0)   // #fdfeff
        ],
        startPoint: .top, endPoint: .bottom
    )

    static let logo = brandPurple    // 纯色品牌紫 #6a5cff
}