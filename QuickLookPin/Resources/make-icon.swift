// 生成 AppIcon.icns：📌 放在 macOS 风格的圆角底板上。
//
//   swift Resources/make-icon.swift      # 在 QuickLookPin/ 下执行
//
// 产物 Resources/AppIcon.icns 已提交进仓库，改设计时才需要重跑。
import Cocoa

let out = URL(fileURLWithPath: "Resources/AppIcon.icns")
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024  // 按 1024 画布设计，再等比缩放

    // 底板：Apple 模板里 1024 画布上的内容区是 824，圆角约 185
    let plate = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let path = NSBezierPath(roundedRect: plate, xRadius: 185 * s, yRadius: 185 * s)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 20 * s
    shadow.shadowOffset = NSSize(width: 0, height: -8 * s)
    shadow.set()
    NSColor.white.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [NSColor(red: 0.99, green: 0.97, blue: 0.93, alpha: 1),
                        NSColor(red: 0.90, green: 0.93, blue: 0.98, alpha: 1)])!
        .draw(in: path, angle: -90)

    // 一张「被钉住的预览卡片」，暗示 Quick Look 窗口
    let card = NSRect(x: 250 * s, y: 215 * s, width: 524 * s, height: 480 * s)
    let cardPath = NSBezierPath(roundedRect: card, xRadius: 36 * s, yRadius: 36 * s)
    NSGraphicsContext.saveGraphicsState()
    let cardShadow = NSShadow()
    cardShadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    cardShadow.shadowBlurRadius = 24 * s
    cardShadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    cardShadow.set()
    NSColor.white.setFill()
    cardPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSColor(red: 0.80, green: 0.84, blue: 0.90, alpha: 1).setFill()
    for (i, w) in [380, 420, 300, 400, 250].enumerated() {
        let y = CGFloat(560 - i * 70)
        NSBezierPath(roundedRect: NSRect(x: 322 * s, y: y * s, width: CGFloat(w) * s, height: 26 * s),
                     xRadius: 13 * s, yRadius: 13 * s).fill()
    }

    // 📌 压在卡片右上角
    let pin = "📌" as NSString
    let font = NSFont(name: "Apple Color Emoji", size: 400 * s)!
    let attrs: [NSAttributedString.Key: Any] = [.font: font]
    let size = pin.size(withAttributes: attrs)
    pin.draw(at: NSPoint(x: 560 * s - size.width / 2, y: 610 * s - size.height / 2), withAttributes: attrs)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try! task.run()
task.waitUntilExit()
try! render(1024).write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon-preview.png"))
print(task.terminationStatus == 0 ? "已生成 \(out.path)" : "iconutil 失败")
print("预览: \(NSTemporaryDirectory())AppIcon-preview.png")
