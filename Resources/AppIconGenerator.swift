import AppKit
import CoreGraphics

private let fileManager = FileManager.default
private let root = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
private let iconset = root.appendingPathComponent("Resources/AppIcon.iconset", isDirectory: true)
private let assetIconset = root.appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
private let icns = root.appendingPathComponent("Resources/AppIcon.icns")
private let preview = root.appendingPathComponent("screenshots/app-icon.png")

private struct IconTarget {
    let filename: String
    let pixels: Int
}

private let targets = [
    IconTarget(filename: "icon_16x16.png", pixels: 16),
    IconTarget(filename: "icon_16x16@2x.png", pixels: 32),
    IconTarget(filename: "icon_32x32.png", pixels: 32),
    IconTarget(filename: "icon_32x32@2x.png", pixels: 64),
    IconTarget(filename: "icon_128x128.png", pixels: 128),
    IconTarget(filename: "icon_128x128@2x.png", pixels: 256),
    IconTarget(filename: "icon_256x256.png", pixels: 256),
    IconTarget(filename: "icon_256x256@2x.png", pixels: 512),
    IconTarget(filename: "icon_512x512.png", pixels: 512),
    IconTarget(filename: "icon_512x512@2x.png", pixels: 1024),
]

private func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

private func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

private func drawIcon(pixels: Int) throws -> Data {
    let size = CGFloat(pixels)
    let scale = size / 1024
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "AppIconGenerator", code: 1)
    }

    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    // Big Sur / Sequoia rounded-square silhouette.
    let canvas = CGRect(x: 36 * scale, y: 36 * scale, width: 952 * scale, height: 952 * scale)
    let canvasPath = roundedRect(canvas, radius: 218 * scale)
    context.saveGState()
    context.addPath(canvasPath)
    context.clip()
    let background = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color(0x20E47C), color(0x0BB89A), color(0x075B59)] as CFArray,
        locations: [0, 0.53, 1]
    )!
    context.drawLinearGradient(
        background,
        start: CGPoint(x: 130 * scale, y: 930 * scale),
        end: CGPoint(x: 900 * scale, y: 90 * scale),
        options: []
    )

    // Soft playful glow and a glass-like top highlight.
    let glow = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color(0xD8FFE8, alpha: 0.42), color(0xD8FFE8, alpha: 0)] as CFArray,
        locations: [0, 1]
    )!
    context.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: 250 * scale, y: 820 * scale),
        startRadius: 20 * scale,
        endCenter: CGPoint(x: 250 * scale, y: 820 * scale),
        endRadius: 560 * scale,
        options: []
    )
    context.setFillColor(color(0xFFFFFF, alpha: 0.10))
    context.fillEllipse(in: CGRect(x: -60 * scale, y: 650 * scale, width: 850 * scale, height: 480 * scale))
    context.restoreGState()

    // Wearable strap loop behind the passport card.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12 * scale), blur: 26 * scale, color: color(0x003C38, alpha: 0.22))
    context.setFillColor(color(0x073F3B))
    context.addPath(roundedRect(CGRect(x: 406 * scale, y: 742 * scale, width: 212 * scale, height: 154 * scale), radius: 72 * scale))
    context.fillPath()
    context.restoreGState()
    context.setFillColor(color(0x19C989))
    context.addPath(roundedRect(CGRect(x: 452 * scale, y: 785 * scale, width: 120 * scale, height: 56 * scale), radius: 28 * scale))
    context.fillPath()

    // The warm card contrasts with the energetic brand gradient.
    let card = CGRect(x: 206 * scale, y: 170 * scale, width: 612 * scale, height: 650 * scale)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -18 * scale), blur: 36 * scale, color: color(0x003A35, alpha: 0.34))
    context.setFillColor(color(0xFFF9E9))
    context.addPath(roundedRect(card, radius: 88 * scale))
    context.fillPath()
    context.restoreGState()

    let cardShine = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color(0xFFFFFF, alpha: 0.72), color(0xFFFFFF, alpha: 0)] as CFArray,
        locations: [0, 1]
    )!
    context.saveGState()
    context.addPath(roundedRect(card, radius: 88 * scale))
    context.clip()
    context.drawLinearGradient(
        cardShine,
        start: CGPoint(x: 270 * scale, y: 800 * scale),
        end: CGPoint(x: 720 * scale, y: 360 * scale),
        options: []
    )
    context.restoreGState()

    // FoloToy-inspired friendly character portrait.
    let ink = color(0x07534F)
    context.setStrokeColor(ink)
    context.setFillColor(color(0xD9F8DF))
    context.setLineWidth(34 * scale)
    context.setLineJoin(.round)
    context.setLineCap(.round)

    let head = CGRect(x: 318 * scale, y: 430 * scale, width: 388 * scale, height: 258 * scale)
    context.addPath(roundedRect(head, radius: 116 * scale))
    context.fillPath()
    context.addPath(roundedRect(head, radius: 116 * scale))
    context.strokePath()

    // Character ears and antenna make the mark recognizable at small sizes.
    context.setFillColor(color(0xFFCA58))
    context.addEllipse(in: CGRect(x: 274 * scale, y: 510 * scale, width: 82 * scale, height: 90 * scale))
    context.fillPath()
    context.addEllipse(in: CGRect(x: 668 * scale, y: 510 * scale, width: 82 * scale, height: 90 * scale))
    context.fillPath()
    context.setStrokeColor(ink)
    context.setLineWidth(28 * scale)
    context.move(to: CGPoint(x: 512 * scale, y: 688 * scale))
    context.addLine(to: CGPoint(x: 512 * scale, y: 738 * scale))
    context.strokePath()
    context.setFillColor(color(0xFFCA58))
    context.fillEllipse(in: CGRect(x: 480 * scale, y: 724 * scale, width: 64 * scale, height: 64 * scale))

    // Eyes and smile.
    context.setFillColor(ink)
    context.fillEllipse(in: CGRect(x: 400 * scale, y: 557 * scale, width: 48 * scale, height: 58 * scale))
    context.fillEllipse(in: CGRect(x: 576 * scale, y: 557 * scale, width: 48 * scale, height: 58 * scale))
    context.setStrokeColor(ink)
    context.setLineWidth(24 * scale)
    context.move(to: CGPoint(x: 420 * scale, y: 520 * scale))
    context.addCurve(
        to: CGPoint(x: 604 * scale, y: 520 * scale),
        control1: CGPoint(x: 458 * scale, y: 462 * scale),
        control2: CGPoint(x: 566 * scale, y: 462 * scale)
    )
    context.strokePath()

    // Passport lines and a playful verification stamp.
    context.setFillColor(color(0x0B8B72, alpha: 0.78))
    context.addPath(roundedRect(CGRect(x: 304 * scale, y: 326 * scale, width: 210 * scale, height: 26 * scale), radius: 13 * scale))
    context.fillPath()
    context.setFillColor(color(0x0B8B72, alpha: 0.38))
    context.addPath(roundedRect(CGRect(x: 304 * scale, y: 270 * scale, width: 166 * scale, height: 22 * scale), radius: 11 * scale))
    context.fillPath()

    let stampCenter = CGPoint(x: 656 * scale, y: 306 * scale)
    context.setStrokeColor(color(0xFF8D52))
    context.setLineWidth(22 * scale)
    context.addEllipse(in: CGRect(x: 588 * scale, y: 238 * scale, width: 136 * scale, height: 136 * scale))
    context.strokePath()
    context.setLineWidth(14 * scale)
    for angle in stride(from: CGFloat(0), to: .pi * 2, by: .pi / 4) {
        let inner = CGPoint(x: stampCenter.x + cos(angle) * 28 * scale, y: stampCenter.y + sin(angle) * 28 * scale)
        let outer = CGPoint(x: stampCenter.x + cos(angle) * 48 * scale, y: stampCenter.y + sin(angle) * 48 * scale)
        context.move(to: inner)
        context.addLine(to: outer)
    }
    context.strokePath()

    // Subtle outer border keeps the icon crisp on light and dark desktops.
    context.setStrokeColor(color(0xFFFFFF, alpha: 0.18))
    context.setLineWidth(10 * scale)
    context.addPath(canvasPath)
    context.strokePath()

    guard let image = context.makeImage() else {
        throw NSError(domain: "AppIconGenerator", code: 2)
    }
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "AppIconGenerator", code: 3)
    }
    return png
}

try? fileManager.removeItem(at: iconset)
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
try fileManager.createDirectory(at: assetIconset, withIntermediateDirectories: true)
try fileManager.createDirectory(at: preview.deletingLastPathComponent(), withIntermediateDirectories: true)

for target in targets {
    let png = try drawIcon(pixels: target.pixels)
    try png.write(to: iconset.appendingPathComponent(target.filename), options: .atomic)
    try png.write(to: assetIconset.appendingPathComponent(target.filename), options: .atomic)
    if target.pixels == 1024 {
        try png.write(to: preview, options: .atomic)
    }
}

try? fileManager.removeItem(at: icns)
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    throw NSError(domain: "AppIconGenerator", code: Int(process.terminationStatus))
}

print("已生成 \(icns.path)")
print("预览图 \(preview.path)")
