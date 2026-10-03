import SwiftUI
import Foundation

private let brandBlue = Color(red: 59.0/255.0, green: 130.0/255.0, blue: 246.0/255.0)    // #3b82f6
private let brandPurple = Color(red: 106.0/255.0, green: 92.0/255.0, blue: 255.0/255.0)  // #6a5cff
private let surface = Color(red: 27.0/255.0, green: 27.0/255.0, blue: 34.0/255.0)         // #1b1b22
private let surface2 = Color(red: 37.0/255.0, green: 37.0/255.0, blue: 48.0/255.0)        // #252530
private let micStroke = Color.white.opacity(0.10)                                           // rgba(255,255,255,.10)
private let iconColor = Color(red: 245.0/255.0, green: 245.0/255.0, blue: 247.0/255.0)    // #f5f5f7

/// 语音条（深色元素版，对齐 voicebar_ui_preview_whitebg.html）。
/// - 待命：深灰底麦克风圆 + 白图标。
/// - 说话中：深灰底文字气泡（白字），中央麦克风图标被蓝紫声浪替代。
/// - 处理中：声浪消失，圆缩小并变浅，外圈蓝紫渐变光环旋转。
struct VoiceBarView: View {
    @ObservedObject var speech: SpeechService

    var body: some View {
        VStack(spacing: 6) {
            if speech.isListening {
                TypeBox(text: speech.liveText, maxWidth: 240)
            }
            micBadge
        }
        // 固定画布 + 底部对齐：圆始终贴在画布底部（固定），字幕在圆上方向上扩展，圆不动。
        .frame(width: 260, height: 280, alignment: .bottom)
    }

    // MARK: - 麦克风区域

    private var micBadge: some View {
        ZStack {
            micCore
                .scaleEffect(speech.isProcessing ? 0.82 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: speech.isProcessing)
            if speech.isProcessing {
                SpinningGradientRing()
            }
        }
        .frame(width: 64, height: 64)
    }

    private var micCore: some View {
        ZStack {
            Circle()
                .fill(speech.isProcessing ? surface2 : surface)
                .frame(width: 46, height: 46)
                .overlay(Circle().stroke(micStroke, lineWidth: 1))

            if speech.isListening {
                Waveform()
            } else {
                Image(systemName: "mic.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(iconColor)
            }
        }
    }
}

/// 转写文字气泡：深灰底圆角框 + 白字 + 紫色闪烁光标。
struct TypeBox: View {
    let text: String
    var maxWidth: CGFloat = 240

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let show = Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            Text(makeString(show: show))
                .font(.system(size: 14))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: maxWidth, alignment: .leading)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(micStroke, lineWidth: 1)
        )
    }

    private func makeString(show: Bool) -> AttributedString {
        var result = AttributedString(text)
        result.foregroundColor = iconColor
        var caret = AttributedString("\u{258F}")
        caret.foregroundColor = show ? brandPurple : Color.clear
        return result + caret
    }
}

/// 说话时的声浪：5 根竖条横向 EQ 波形跳动（替代中央麦克风图标）。
struct Waveform: View {
    var body: some View {
        HStack(spacing: 3) {
            WaveBar(delay: 0.0)
            WaveBar(delay: 0.12)
            WaveBar(delay: 0.24)
            WaveBar(delay: 0.36)
            WaveBar(delay: 0.48)
        }
    }
}

struct WaveBar: View {
    let delay: Double
    @State private var up = false

    var body: some View {
        Capsule()
            .fill(LinearGradient(colors: [brandPurple, brandBlue], startPoint: .top, endPoint: .bottom))
            .frame(width: 3, height: 14)
            .scaleEffect(y: up ? 1.0 : 0.35, anchor: .center)
            .opacity(up ? 1.0 : 0.45)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true).delay(delay)) {
                    up = true
                }
            }
    }
}

/// 处理态：蓝紫渐变光环绕圆旋转。
struct SpinningGradientRing: View {
    @State private var rotate = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.8)
            .stroke(
                AngularGradient(
                    stops: [
                        Gradient.Stop(color: .clear, location: 0),
                        Gradient.Stop(color: brandBlue, location: 0.21),
                        Gradient.Stop(color: brandPurple, location: 0.56),
                        Gradient.Stop(color: .clear, location: 1)
                    ],
                    center: .center
                ),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
            )
            .frame(width: 54, height: 54)
            .rotationEffect(.degrees(rotate ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 1.05).repeatForever(autoreverses: false)) {
                    rotate = true
                }
            }
    }
}