// Draws the app icon: a glowing keycap with raindrop ripples, on a dark squircle.
// Usage: swift tools/make-icon.swift Resources/AppIcon.icns
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"

func draw(size s: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(s), pixelsHigh: Int(s),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let u = s / 1024 // design units: 1024 grid

    // Background squircle (macOS icon grid: 824 px body centered in 1024).
    let body = CGRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u)
    let bg = NSBezierPath(roundedRect: body, xRadius: 185 * u, yRadius: 185 * u)
    ctx.saveGState()
    bg.addClip()
    NSGradient(colors: [NSColor(red: 0.10, green: 0.11, blue: 0.20, alpha: 1),
                        NSColor(red: 0.02, green: 0.02, blue: 0.05, alpha: 1)])!
        .draw(in: body, angle: -90)

    // Ripples: concentric rings fading outward, rainbow hues.
    let center = CGPoint(x: 512 * u, y: 470 * u)
    let hues: [CGFloat] = [0.55, 0.70, 0.85, 0.98]
    for (i, hue) in hues.enumerated() {
        let r = (250 + CGFloat(i) * 95) * u
        let ring = NSBezierPath(ovalIn: CGRect(x: center.x - r, y: center.y - r * 0.62, width: r * 2, height: r * 1.24))
        ring.lineWidth = (26 - CGFloat(i) * 5) * u
        NSColor(hue: hue, saturation: 0.85, brightness: 1, alpha: 0.75 - CGFloat(i) * 0.16).setStroke()
        ring.stroke()
    }

    // Underglow of the key.
    let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [NSColor(hue: 0.52, saturation: 0.9, brightness: 1, alpha: 0.9).cgColor,
                                   NSColor(hue: 0.75, saturation: 0.9, brightness: 1, alpha: 0).cgColor] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: 300 * u, options: [])
    ctx.restoreGState()

    // Keycap: side (darker), then top face.
    let capW = 330 * u, capH = 300 * u
    let cap = CGRect(x: center.x - capW / 2, y: center.y - capH / 2 + 20 * u, width: capW, height: capH)
    let side = NSBezierPath(roundedRect: cap.offsetBy(dx: 0, dy: -34 * u), xRadius: 60 * u, yRadius: 60 * u)
    NSColor(white: 0.16, alpha: 1).setFill()
    side.fill()
    let top = NSBezierPath(roundedRect: cap.insetBy(dx: 18 * u, dy: 14 * u).offsetBy(dx: 0, dy: 10 * u), xRadius: 48 * u, yRadius: 48 * u)
    NSGradient(colors: [NSColor(white: 0.97, alpha: 1), NSColor(white: 0.80, alpha: 1)])!.draw(in: top, angle: -90)

    // Raindrop glyph on the keycap.
    let d = NSBezierPath()
    let dc = CGPoint(x: center.x, y: center.y + 10 * u)
    let dr = 62 * u
    d.move(to: CGPoint(x: dc.x, y: dc.y + dr * 2.0))
    d.curve(to: CGPoint(x: dc.x + dr, y: dc.y), controlPoint1: CGPoint(x: dc.x + dr * 0.25, y: dc.y + dr * 1.3),
            controlPoint2: CGPoint(x: dc.x + dr, y: dc.y + dr * 0.75))
    d.appendArc(withCenter: dc, radius: dr, startAngle: 0, endAngle: 180, clockwise: true)
    d.curve(to: CGPoint(x: dc.x, y: dc.y + dr * 2.0), controlPoint1: CGPoint(x: dc.x - dr, y: dc.y + dr * 0.75),
            controlPoint2: CGPoint(x: dc.x - dr * 0.25, y: dc.y + dr * 1.3))
    d.close()
    ctx.saveGState()
    d.addClip()
    NSGradient(colors: [NSColor(hue: 0.53, saturation: 0.9, brightness: 1, alpha: 1),
                        NSColor(hue: 0.72, saturation: 0.9, brightness: 0.9, alpha: 1)])!
        .draw(in: d.bounds, angle: -90)
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(getpid()).iconset")
try? FileManager.default.removeItem(at: tmp)
try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = CGFloat(base * scale)
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! draw(size: px).representation(using: .png, properties: [:])!.write(to: tmp.appendingPathComponent(name))
    }
}
try! draw(size: 1024).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: (out as NSString).deletingPathExtension + "-1024.png"))

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", tmp.path, "-o", out]
try! p.run()
p.waitUntilExit()
try? FileManager.default.removeItem(at: tmp)
print(p.terminationStatus == 0 ? "Wrote \(out)" : "iconutil failed")
