import AppKit
import BAKeyCore
import SwiftUI

/// Built-in per-key layouts.
enum Presets {
    private static var litKeys: [KeyDef] { KeyLayout.keys.filter { !$0.cells.isEmpty } }

    private static func all(_ c: RGB) -> [Int: RGB] {
        Dictionary(uniqueKeysWithValues: litKeys.map { ($0.id, c) })
    }

    private static func highlight(_ labels: Set<String>, _ color: RGB, base: RGB) -> [Int: RGB] {
        var out = all(base)
        for k in litKeys where labels.contains(k.label) { out[k.id] = color }
        return out
    }

    static let wasd = highlight(["W", "A", "S", "D"], RGB(255, 0, 0), base: RGB(0, 40, 160))
    static let arrows = highlight(["↑", "↓", "←", "→", "Esc"], RGB(255, 140, 0), base: RGB(30, 30, 30))

    /// Hue follows the horizontal position of each key.
    static var rainbow: [Int: RGB] {
        let width = KeyLayout.size.width
        return Dictionary(uniqueKeysWithValues: litKeys.map { k in
            (k.id, RGB(hue: k.rect.midX / width))
        })
    }

    static let builtIn: [(String, [Int: RGB])] = [
        ("WASD (red on blue)", wasd),
        ("Arrows + Esc", arrows),
        ("Rainbow", rainbow),
        ("All white", all(.white)),
        ("All off", all(.black)),
    ]
}

extension RGB {
    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(UInt8((ns.redComponent * 255).rounded().clamped(0, 255)),
                  UInt8((ns.greenComponent * 255).rounded().clamped(0, 255)),
                  UInt8((ns.blueComponent * 255).rounded().clamped(0, 255)))
    }

    init(hue: Double) {
        let ns = NSColor(hue: hue, saturation: 1, brightness: 1, alpha: 1)
        self.init(UInt8(ns.redComponent * 255), UInt8(ns.greenComponent * 255), UInt8(ns.blueComponent * 255))
    }

    var color: Color { Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255) }

    /// Perceived brightness, used to pick a readable label color.
    var isLight: Bool { 0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b) > 150 }
}

private extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double { Swift.min(Swift.max(self, lo), hi) }
}
