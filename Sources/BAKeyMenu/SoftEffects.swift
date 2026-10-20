import BAKeyCore
import Foundation

/// Effects rendered on the Mac and streamed to the keyboard as per-key frames (effect 18).
///
/// Why they exist: the firmware's effects have fixed parameters. Raindrop's speed byte only goes
/// *faster* than the default (1 = default = slowest, 255 = very fast; 0 is rejected), so a slower
/// Raindrop has to be drawn by the host. See docs/SOFT-EFFECTS.md.
enum SoftEffect: Int, CaseIterable, Identifiable {
    // Declaration order = menu order.
    case ripple = 203
    case raindrop = 200
    case wave = 201
    case breathing = 202

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .ripple: return "Raindrop (Mac, on key press)"
        case .raindrop: return "Rain (Mac, random)"
        case .wave: return "Wave (Mac)"
        case .breathing: return "Breathing (Mac)"
        }
    }

    /// Needs key presses (and therefore the Input Monitoring permission).
    var isReactive: Bool { self == .ripple }
}

/// Stateful frame generator. `speed` is a multiplier: 1.0 ≈ the firmware's default pace.
struct SoftRenderer {
    let effect: SoftEffect
    private var time = 0.0            // effect time (scaled by speed)
    private var drops: [Int: (born: Double, color: RGB)] = [:]
    private var ripples: [(center: CGPoint, born: Double, color: RGB)] = []
    private var rng = SystemRandomNumberGenerator()

    private static let litKeys = KeyLayout.keys.filter { !$0.cells.isEmpty }
    private static let width = KeyLayout.size.width
    /// HID usage → key, for reactive effects.
    static let keyForUsage: [Int: KeyDef] = {
        var map: [Int: KeyDef] = [:]
        for k in litKeys where map[k.hidUsage] == nil { map[k.hidUsage] = k }
        return map
    }()

    // Ripple tuning, in effect time (so the speed slider scales all of them).
    private static let rippleLife = 1.4      // s until a ripple has faded completely
    private static let rippleSpeed = 300.0   // layout units per second (one key ≈ 40)
    private static let rippleWidth = 38.0    // ring thickness, ≈ one key

    /// Slow link (Bluetooth): ripples stay small (about 2 keys), so they touch ~3 rows instead of 6.
    var compact = false
    private static let compactRadius = 85.0

    init(effect: SoftEffect) { self.effect = effect }

    /// True when there is nothing to draw, so the engine can stop sending frames.
    var isIdle: Bool { effect == .ripple && ripples.isEmpty }

    /// A key was pressed (reactive effects only).
    mutating func press(_ key: KeyDef, color: RGB?) {
        let center = CGPoint(x: key.rect.midX, y: key.rect.midY)
        ripples.append((center, time, color ?? RGB(hue: Double.random(in: 0..<1, using: &rng))))
        if ripples.count > 24 { ripples.removeFirst(ripples.count - 24) }
    }

    /// - Parameters:
    ///   - dt: wall-clock seconds since the previous frame (capped, so a slow link doesn't burst).
    ///   - color: nil = random/rainbow colors.
    mutating func frame(dt: Double, speed: Double, color: RGB?) -> [[RGB]] {
        let step = min(dt, 1.0) * speed
        time += step
        var colors: [Int: RGB] = [:]

        switch effect {
        case .ripple:
            // Each press: the key flashes, then a ring spreads outward and fades, like a drop in water.
            ripples.removeAll { time - $0.born >= Self.rippleLife }
            for key in Self.litKeys {
                let p = CGPoint(x: key.rect.midX, y: key.rect.midY)
                var best = RGB.black
                for r in ripples {
                    let age = time - r.born
                    let fade = 1 - age / Self.rippleLife
                    let d = hypot(p.x - r.center.x, p.y - r.center.y)
                    let ringD = (d - Self.rippleSpeed * age) / Self.rippleWidth
                    var ring = exp(-ringD * ringD)
                    if compact { ring *= max(0, 1 - Self.rippleSpeed * age / Self.compactRadius) }
                    let core = d < 1 ? max(0, 1 - age / (Self.rippleLife * 0.5)) : 0
                    best = best.maxed(r.color.scaled(max(ring, core) * fade * fade))
                }
                if best != .black { colors[key.id] = best }
            }

        case .raindrop:
            // About 5 new drops per second at 1x; each lives 1.6 s (fade in 15%, fade out 85%).
            let life = 1.6
            var expected = 5.0 * step
            while expected > 0 {
                if Double.random(in: 0..<1, using: &rng) < expected,
                   let key = Self.litKeys.randomElement(using: &rng), drops[key.id] == nil {
                    drops[key.id] = (time, color ?? RGB(hue: Double.random(in: 0..<1, using: &rng)))
                }
                expected -= 1
            }
            for (id, d) in drops {
                let age = time - d.born
                if age >= life { drops[id] = nil; continue }
                let rise = life * 0.15
                let k = age < rise ? age / rise : 1 - (age - rise) / (life - rise)
                colors[id] = d.color.scaled(k)
            }

        case .wave:
            for key in Self.litKeys {
                let x = key.rect.midX / Self.width
                if let color {
                    let k = 0.5 + 0.5 * sin(2 * Double.pi * (x - time * 0.4))
                    colors[key.id] = color.scaled(k)
                } else {
                    let h = (x - time * 0.4).truncatingRemainder(dividingBy: 1)
                    colors[key.id] = RGB(hue: h < 0 ? h + 1 : h)
                }
            }

        case .breathing:
            // One breath every 4 s at 1x; rainbow mode shifts hue each breath.
            let k = pow(0.5 - 0.5 * cos(2 * Double.pi * time / 4), 1.6)
            let c = color ?? RGB(hue: (time / 24).truncatingRemainder(dividingBy: 1))
            for key in Self.litKeys { colors[key.id] = c.scaled(k) }
        }
        return KeyLayout.frame(from: colors)
    }
}

extension RGB {
    func scaled(_ k: Double) -> RGB {
        let k = min(max(k, 0), 1)
        return RGB(UInt8(Double(r) * k), UInt8(Double(g) * k), UInt8(Double(b) * k))
    }

    func maxed(_ o: RGB) -> RGB { RGB(max(r, o.r), max(g, o.g), max(b, o.b)) }
}
