// Draws the app icon and writes Resources/AppIcon.icns. Usage: swift scripts/make-icon.swift
//
// The icon is drawn in code so it can be regenerated without design tools: a cool blue squircle
// holding a menubar strip over a tiled-window layout (one tall pane, two stacked), which is what
// the app does. Geometry follows Apple's macOS icon grid: an 824 pt body centred on 1024.
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let output = root.appendingPathComponent("Resources/AppIcon.icns")

func draw(in ctx: CGContext, size: CGFloat) {
    let s = size / 1024
    ctx.scaleBy(x: s, y: s)

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Drop shadow, as on system icons.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(bodyPath)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Body: indigo at the bottom to cyan at the top.
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let colors = [
        CGColor(srgbRed: 0.16, green: 0.20, blue: 0.55, alpha: 1),
        CGColor(srgbRed: 0.15, green: 0.45, blue: 0.85, alpha: 1),
        CGColor(srgbRed: 0.30, green: 0.80, blue: 0.95, alpha: 1),
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: body.minX, y: body.minY), end: CGPoint(x: body.maxX, y: body.maxY), options: [])

    // Soft highlight across the top half.
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.06))
    ctx.fillEllipse(in: CGRect(x: 0, y: 560, width: 1024, height: 700))

    // Menubar strip with three status items.
    let bar = CGRect(x: body.minX, y: 754, width: body.width, height: 74)
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.22))
    ctx.fill(CGRect(x: bar.minX, y: bar.minY, width: bar.width, height: body.maxY - bar.minY))
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.95))
    for (x, width) in [(610.0, 40.0), (676, 40), (742, 110)] {
        let item = CGRect(x: x, y: bar.midY - 13, width: width, height: 26)
        ctx.addPath(CGPath(roundedRect: item, cornerWidth: 13, cornerHeight: 13, transform: nil))
    }
    ctx.fillPath()

    // Tiled windows: one tall pane on the left, two stacked on the right.
    let area = CGRect(x: body.minX + 70, y: body.minY + 70, width: body.width - 140, height: bar.minY - body.minY - 120)
    let gap: CGFloat = 32
    let leftWidth = (area.width - gap) * 0.55
    let rightWidth = area.width - gap - leftWidth
    let half = (area.height - gap) / 2
    let panes = [
        CGRect(x: area.minX, y: area.minY, width: leftWidth, height: area.height),
        CGRect(x: area.minX + leftWidth + gap, y: area.minY + half + gap, width: rightWidth, height: half),
        CGRect(x: area.minX + leftWidth + gap, y: area.minY, width: rightWidth, height: half),
    ]
    for (i, pane) in panes.enumerated() {
        let path = CGPath(roundedRect: pane, cornerWidth: 34, cornerHeight: 34, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: CGColor(gray: 0, alpha: 0.25))
        ctx.addPath(path)
        ctx.setFillColor(CGColor(gray: 1, alpha: i == 0 ? 0.96 : 0.82))
        ctx.fillPath()
        ctx.restoreGState()

        // Title bar dots.
        ctx.setFillColor(CGColor(srgbRed: 0.15, green: 0.35, blue: 0.75, alpha: i == 0 ? 0.55 : 0.4))
        for d in 0..<3 {
            ctx.fillEllipse(in: CGRect(x: pane.minX + 30 + CGFloat(d) * 34, y: pane.maxY - 50, width: 20, height: 20))
        }
    }
    ctx.restoreGState()
}

func png(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    draw(in: ctx.cgContext, size: CGFloat(pixels))
    ctx.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try! png(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try! png(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try! iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
try? FileManager.default.removeItem(at: iconset)
print("Wrote \(output.path)")
