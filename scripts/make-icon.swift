// Draws the i-con app icon and writes Resources/AppIcon.icns.
// Run from the project root: swift scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

/// macOS's icon shape: a superellipse ("squircle") inside the standard 824pt body.
func squircle(in rect: CGRect, exponent: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let steps = 720
    for step in 0...steps {
        let t = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let cosT = cos(t), sinT = sin(t)
        let x = pow(abs(cosT), 2 / exponent) * (cosT < 0 ? -1 : 1)
        let y = pow(abs(sinT), 2 / exponent) * (sinT < 0 ? -1 : 1)
        let point = CGPoint(x: rect.midX + x * rect.width / 2, y: rect.midY + y * rect.height / 2)
        step == 0 ? path.move(to: point) : path.addLine(to: point)
    }
    path.closeSubpath()
    return path
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// `scale` is pixels per design point. Shadows ignore the transform, so they're scaled by hand
/// (and their y offset is negative to fall downward in the unflipped base space).
func drawIcon(in context: CGContext, scale: CGFloat) {
    // Top-left origin, like the design coordinates below.
    context.translateBy(x: 0, y: canvas)
    context.scaleBy(x: 1, y: -1)

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(in: body)

    // Body with a soft drop shadow.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 24 * scale, color: color(0x000000, 0.28))
    context.addPath(shape)
    context.setFillColor(color(0x4B6BFF))
    context.fillPath()
    context.restoreGState()

    // Blue-violet gradient.
    context.saveGState()
    context.addPath(shape)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(0x3D8BFF), color(0x5B5BF6), color(0x8A45F0)] as CFArray,
        locations: [0, 0.55, 1]
    )!
    context.drawLinearGradient(gradient, start: CGPoint(x: body.minX, y: body.minY), end: CGPoint(x: body.maxX, y: body.maxY), options: [])
    // A gentle top highlight.
    let shine = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(shine, start: CGPoint(x: 0, y: body.minY), end: CGPoint(x: 0, y: body.midY), options: [])
    context.restoreGState()

    // Menu bar strip.
    let bar = CGRect(x: 180, y: 222, width: 664, height: 112)
    context.addPath(roundedRect(bar, 56))
    context.setFillColor(color(0xFFFFFF, 0.24))
    context.fillPath()

    // Visible icons in the bar.
    for x in [252.0, 332.0, 412.0] {
        context.addEllipse(in: CGRect(x: x - 23, y: bar.midY - 23, width: 46, height: 46))
    }
    context.setFillColor(color(0xFFFFFF, 0.9))
    context.fillPath()

    // The ▾ button, highlighted.
    let button = CGRect(x: 662, y: 238, width: 156, height: 80)
    context.addPath(roundedRect(button, 40))
    context.setFillColor(color(0xFFFFFF))
    context.fillPath()
    context.setStrokeColor(color(0x5B5BF6))
    context.setLineWidth(17)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.move(to: CGPoint(x: button.midX - 30, y: button.midY - 13))
    context.addLine(to: CGPoint(x: button.midX, y: button.midY + 15))
    context.addLine(to: CGPoint(x: button.midX + 30, y: button.midY - 13))
    context.strokePath()

    // The popup hanging from the button, with a pointer.
    let card = CGRect(x: 332, y: 404, width: 512, height: 380)
    let popup = CGMutablePath()
    popup.addPath(roundedRect(card, 60))
    popup.move(to: CGPoint(x: button.midX - 34, y: card.minY + 1))
    popup.addLine(to: CGPoint(x: button.midX, y: card.minY - 34))
    popup.addLine(to: CGPoint(x: button.midX + 34, y: card.minY + 1))
    popup.closeSubpath()
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -18 * scale), blur: 36 * scale, color: color(0x1A0B5C, 0.35))
    context.addPath(popup)
    context.setFillColor(color(0xFFFFFF))
    context.fillPath()
    context.restoreGState()

    // Hidden icons inside the popup.
    let tiles: [UInt32] = [0xFF9F0A, 0x30D158, 0xFF375F, 0x40C8E0, 0xFFD60A, 0xBF5AF2]
    let tileSize: CGFloat = 112, gap: CGFloat = 36
    let gridWidth = tileSize * 3 + gap * 2, gridHeight = tileSize * 2 + gap
    let origin = CGPoint(x: card.midX - gridWidth / 2, y: card.midY - gridHeight / 2)
    for (index, hex) in tiles.enumerated() {
        let column = CGFloat(index % 3), row = CGFloat(index / 3)
        let tile = CGRect(x: origin.x + column * (tileSize + gap), y: origin.y + row * (tileSize + gap), width: tileSize, height: tileSize)
        context.addPath(roundedRect(tile, 30))
        context.setFillColor(color(hex))
        context.fillPath()
    }
}

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    let scale = CGFloat(size) / canvas
    context.scaleBy(x: scale, y: scale)
    context.interpolationQuality = .high
    drawIcon(in: context, scale: scale)
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(filePath: FileManager.default.currentDirectoryPath)
let iconset = URL(filePath: NSTemporaryDirectory()).appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try render(size: points).write(to: iconset.appending(path: "icon_\(points)x\(points).png"))
    try render(size: points * 2).write(to: iconset.appending(path: "icon_\(points)x\(points)@2x.png"))
}
if CommandLine.arguments.count > 1 {
    // Optional preview PNG for checking the design.
    try render(size: 1024).write(to: URL(filePath: CommandLine.arguments[1]))
}

let iconutil = Process()
iconutil.executableURL = URL(filePath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appending(path: "Resources/AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
