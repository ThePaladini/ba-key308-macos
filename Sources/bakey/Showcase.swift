import BAKeyCore
import Foundation

/// `bakey showcase`: a timed light show for filming the keyboard (e.g. a promo video).
/// Prints a cue for each scene so the camera operator knows what's coming, and restores the
/// original lighting at the end. Best over USB (smooth animation); Bluetooth works but the
/// Mac-driven scenes are choppy.
enum Showcase {
    static func run(_ kb: KeyboardClient, countdown: Int) throws {
        let region = LEDRegion.backlight.rawValue
        let profile = try kb.activeProfile()
        let original = try kb.effect(region: region, profile: profile)
        let lit = KeyLayout.keys.filter { !$0.cells.isEmpty }
        let start = Date()

        func cue(_ text: String) {
            print(String(format: "[%5.1fs] %@", -start.timeIntervalSinceNow, text))
        }
        func streaming() throws {
            try kb.setEffect(EffectState(effect: LightingEffect.streamingID), region: region, profile: profile)
        }
        func paint(_ colors: [Int: RGB]) throws { try kb.sendFrame(KeyLayout.frame(from: colors)) }
        func all(_ c: RGB) -> [Int: RGB] { Dictionary(uniqueKeysWithValues: lit.map { ($0.id, c) }) }
        func hold(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }

        for i in stride(from: countdown, to: 0, by: -1) {
            print("Starting in \(i)…")
            hold(1)
        }
        defer {
            try? kb.setEffect(original, region: region, profile: profile)
            cue("Done, original lighting restored.")
        }

        cue("1. Dark")
        try streaming()
        try paint(all(.black))
        hold(2.5)

        cue("2. Rainbow wave from the Mac")
        let t0 = Date()
        while -t0.timeIntervalSinceNow < 7 {
            let phase = -t0.timeIntervalSinceNow / 2
            var colors: [Int: RGB] = [:]
            for k in lit {
                let h = (k.rect.midX / KeyLayout.size.width + phase).truncatingRemainder(dividingBy: 1)
                colors[k.id] = RGB(hue: h)
            }
            try paint(colors)
        }

        cue("3. Per-key: WASD red")
        var wasd = all(RGB(0, 30, 120))
        for k in lit where ["W", "A", "S", "D"].contains(k.label) { wasd[k.id] = RGB(255, 0, 0) }
        try paint(wasd)
        hold(3.5)

        cue("4. Per-key: arrows + Esc orange")
        var arrows = all(RGB(20, 20, 20))
        for k in lit where ["↑", "↓", "←", "→", "Esc"].contains(k.label) { arrows[k.id] = RGB(255, 120, 0) }
        try paint(arrows)
        hold(3)

        cue("5. Keyboard effect: fast Wave")
        try kb.setEffect(EffectState(effect: 5, speed: 40), region: region, profile: profile)
        hold(5)

        cue("6. Keyboard effect: Breathing purple")
        try kb.setEffect(EffectState(effect: 2, speed: 3, colors: [RGB(160, 0, 255)]), region: region, profile: profile)
        hold(4.5)

        cue("7. Area Reactive. TYPE NOW!")
        try kb.setEffect(EffectState(effect: 24, speed: 1, colors: [.white]), region: region, profile: profile)
        hold(8)
    }
}
