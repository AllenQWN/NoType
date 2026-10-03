import AppKit
import Foundation

// 生成带透明圆角的 macOS 图标（源图可能是 jpeg，统一转成透明圆角 PNG）
func makeRounded(_ src: String, _ dst: String, _ pixels: Int) {
    guard let image = NSImage(contentsOfFile: src),
          let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        FileHandle.standardError.write("load fail\n".data(using: .utf8)!)
        exit(1)
    }
    let side = CGFloat(pixels)
    let rect = NSRect(x: 0, y: 0, width: side, height: side)

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { exit(1) }
    rep.size = rect.size

    NSGraphicsContext.saveGraphicsState()
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
    NSGraphicsContext.current = ctx
    let radius = side * 0.2237
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
    image.draw(in: rect)
    NSGraphicsContext.restoreGraphicsState()

    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: dst))
    } else {
        exit(1)
    }
    _ = cg
}

let args = CommandLine.arguments
if args.count >= 3 {
    let px = args.count >= 4 ? (Int(args[3]) ?? 1024) : 1024
    makeRounded(args[1], args[2], px)
    exit(0)
}
exit(1)