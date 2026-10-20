import BAKeyCore
import Foundation

/// `bakey showcase`: a timed light show for filming the keyboard (e.g. a promo video).
/// Prints a cue for each scene and restores the original lighting at the end.
///
/// It adapts to the link. Over Bluetooth every frame packet costs ~154 ms (docs/BLUETOOTH.md), so
/// full-frame Mac animations are choppy. There the show uses the keyboard's own animations instead,
/// plus Mac animations built from one packet per step (row sweep), and paints scenes as one fill
/// packet followed by only the rows that have highlights.
enum Showcase {
    static func run(_ kb: KeyboardClient, countdown: Int) throws {
        let region = LEDRegion.backlight.rawValue
        let profile = try kb.activeProfile()
        let original = try kb.effect(region: region, profile: profile)
        let lit = KeyLayout.keys.filter { !$0.cells.isEmpty }
        let slow = kb.hid.transport.localizedCaseInsensitiveContains("bluetooth")
        var differ = FrameDiffer()
        let start = Date()

        func cue(_ text: String) {
            print(String(format: "[%5.1fs] %@", -start.timeIntervalSinceNow, text))
        }
        func streaming() throws {
            try kb.setEffect(EffectState(effect: LightingEffect.streamingID), region: region, profile: profile)
            differ.reset()
        }
        func firmware(_ effect: UInt8, speed: UInt8 = 2, colors: [RGB] = []) throws {
            try kb.setEffect(EffectState(effect: effect, speed: speed, colors: colors), region: region, profile: profile)
            differ.reset()
        }
        func all(_ c: RGB) -> [Int: RGB] { Dictionary(uniqueKeysWithValues: lit.map { ($0.id, c) }) }
        /// Background in one fill packet, then only the rows that contain highlights.
        func paint(base: RGB, highlight labels: Set<String> = [], color: RGB = .black) throws {
            try differ.push(KeyLayout.frame(from: all(base)), via: kb)
            guard !labels.isEmpty else { return }
            var colors = all(base)
            for k in lit where labels.contains(k.label) { colors[k.id] = color }
            try differ.push(KeyLayout.frame(from: colors), via: kb)
        }
        func hold(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }

        print(slow ? "Bluetooth: using keyboard-driven and one-packet-per-step scenes."
                   : "USB: using smooth Mac-driven scenes.")
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
        try paint(base: .black)
        hold(2)

        if slow {
            cue("2. Rainbow wave (keyboard-driven)")
            try firmware(5, speed: 3)
            hold(6)
        } else {
            cue("2. Rainbow wave from the Mac")
            try streaming()
            let t0 = Date()
            while -t0.timeIntervalSinceNow < 6 {
                let phase = -t0.timeIntervalSinceNow / 2
                var colors: [Int: RGB] = [:]
                for k in lit {
                    let h = (k.rect.midX / KeyLayout.size.width + phase).truncatingRemainder(dividingBy: 1)
                    colors[k.id] = RGB(hue: h)
                }
                try differ.push(KeyLayout.frame(from: colors), via: kb)
            }
        }

        cue("3. Row sweep from the Mac")
        try streaming()
        try paint(base: .black)
        // One row packet per step: smooth enough over Bluetooth (~6 steps/s), very fast on USB.
        let sweep: [RGB] = [RGB(0, 255, 200), RGB(255, 0, 160), RGB(255, 200, 0)]
        let stepDelay = slow ? 0.0 : 0.12
        for color in sweep {
            for row in 0..<KeyLayout.rows {
                try kb.sendPackets([PacketBuilder.rowPacket(reportID: kb.hid.reportID, target: kb.target, region: region,
                                                            row: row, colors: [RGB](repeating: color, count: KeyLayout.columns))])
                hold(stepDelay)
            }
        }
        differ.reset()

        cue("4. Per-key: WASD red")
        try paint(base: RGB(0, 30, 120), highlight: ["W", "A", "S", "D"], color: RGB(255, 0, 0))
        hold(3.5)

        cue("5. Per-key: arrows + Esc orange")
        try paint(base: RGB(20, 20, 20), highlight: ["↑", "↓", "←", "→", "Esc"], color: RGB(255, 120, 0))
        hold(3)

        cue("6. Keyboard effect: Rainbow Wheel, fast")
        try firmware(20, speed: 40)
        hold(5)

        cue("7. Keyboard effect: Breathing purple")
        try firmware(2, speed: 3, colors: [RGB(160, 0, 255)])
        hold(4.5)

        cue("8. Area Reactive. TYPE NOW!")
        try firmware(24, speed: 1, colors: [.white])
        hold(8)
    }
}
