import BAKeyCore
import Foundation

let usage = """
bakey — command-line control for the BA-KEY308 keyboard

USAGE
  bakey info                          Device, firmware, battery, current lighting
  bakey effects                       Effects supported by each lighting region
  bakey effect <region> <id|name> [--color RRGGBB] [--speed 1-3] [--reverse]
                                      Set a hardware effect. region: back | side
  bakey brightness <region> <0-100>   Set brightness in percent
  bakey fill <RRGGBB>                 Per-key mode, all keys one color
  bakey keys <label=RRGGBB>... [--base RRGGBB]
                                      Per-key mode, color individual keys (e.g. W=ff0000)
  bakey layout                        Print key labels, IDs and LED cells
  bakey get <class> <cmd> [byte...]   Raw GET (read-only) for exploring; hex or decimal
  bakey bench                         Measure command latency and frame rate of the current link
  bakey demo [seconds]                Host-driven rainbow animation (per-key mode)
  bakey showcase [countdown]          ~40 s timed light show for filming (adapts to Bluetooth/USB), then restores lighting
  Add -v to any command to print the raw packets.

EXAMPLES
  bakey effect back wave --speed 3
  bakey effect side static --color ff0000
  bakey keys W=ff0000 A=ff0000 S=ff0000 D=ff0000 --base 001030
"""

var args = Array(CommandLine.arguments.dropFirst())
let verbose = args.contains("-v")
args.removeAll { $0 == "-v" }

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return v
}

func flag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i)
    return true
}

func region(_ s: String) -> UInt8 {
    switch s.lowercased() {
    case "back", "backlight", "keys", "1": return LEDRegion.backlight.rawValue
    case "side", "sidelight", "4": return LEDRegion.sidelight.rawValue
    default: fail("Unknown region '\(s)'. Use back or side.")
    }
}

func number(_ s: String) -> UInt8? {
    s.lowercased().hasPrefix("0x") ? UInt8(s.dropFirst(2), radix: 16) : UInt8(s)
}

func connect() -> KeyboardClient {
    // Any 0x260D device with the 64-byte configuration channel, so unknown models can be reported.
    let monitor = DeviceMonitor(scheduleOnMainRunLoop: false, anyProduct: true)
    CFRunLoopRunInMode(.defaultMode, 0.05, false)
    var lastError: Error = BAKeyError.noDevice
    for hid in monitor.candidates() {
        do {
            let c = try KeyboardClient(hid: hid)
            if verbose { c.log = { print($0) } }
            KeyLayout.current = c.model ?? .baKey308
            return c
        } catch { lastError = error }
    }
    fail("Error: \(lastError.localizedDescription)")
}

func run() throws {
    guard let command = args.first else { print(usage); return }
    args.removeFirst()

    switch command {
    case "info":
        let kb = connect()
        let i = try kb.info()
        let b = try kb.battery()
        let locks = try kb.locks()
        let profile = try kb.activeProfile()
        print("\(i.name) via \(i.transport)  (report ID \(kb.hid.reportID))")
        if kb.model == nil {
            print(String(format: "Model: unknown (PID 0x%04X). Not a model this app knows yet; this output is useful for a", kb.keyboardPID)
                  + " compatibility report: github.com/ThePaladini/ba-key308-macos/issues")
        }
        if let m = kb.model {
            print("Model: \(m.name), \(m.layoutName), PID \(String(format: "0x%04X", kb.keyboardPID))"
                  + (m.tested ? "" : "  [not tested with this app yet: please report at github.com/ThePaladini/ba-key308-macos/issues]")
                  + (m.ledMapCalibrated ? "" : "  [per-key LED map inferred]"))
        }
        print("Firmware \(i.firmware), hardware \(i.hardware)")
        print("Battery \(b.level)% \(b.status.map { "\($0)" } ?? "")")
        print("Profile \(profile) of \(try kb.profileIDs().count), Win lock \(locks.winLock ? "on" : "off"), Mac mode \(locks.macMode ? "on" : "off")")
        print("Backlight idle-off after \(try kb.sleepSeconds()) s")
        for r in LEDRegion.allCases {
            let e = try kb.effect(region: r.rawValue, profile: profile)
            let br = try kb.brightness(region: r.rawValue)
            let colors = e.colors.isEmpty ? "default colors" : e.colors.map(\.hex).joined(separator: ",")
            print("\(r.name): \(LightingEffect(id: e.effect).name), speed \(e.speed), dir \(e.flag), \(colors), brightness \(Int(br) * 100 / 255)%")
        }

    case "effects":
        let kb = connect()
        for r in LEDRegion.allCases {
            let a = try kb.ledAttributes(r.rawValue)
            print("\(r.name) (region \(r.rawValue)): \(a.rows)x\(a.columns) LEDs, \(a.fps) fps")
            for id in a.effects { print(String(format: "  %3d  %@", id, LightingEffect(id: id).name)) }
        }

    case "effect":
        guard args.count >= 2 else { fail(usage) }
        let reg = region(args[0])
        let color = option("--color")
        let speed = option("--speed").flatMap(UInt8.init) ?? 2
        let reverse = flag("--reverse")
        let name = args[1].lowercased()
        let kb = connect()
        let supported = try kb.ledAttributes(reg).effects.map(LightingEffect.init(id:))
        guard let effect = supported.first(where: { String($0.id) == name || $0.name.lowercased().hasPrefix(name) }) else {
            fail("Effect '\(args[1])' not supported here. Try: \(supported.map(\.name).joined(separator: ", "))")
        }
        var colors: [RGB] = []
        if let color { guard let c = RGB(hex: color) else { fail("Bad color \(color)") }; colors = [c] }
        let profile = try kb.activeProfile()
        try kb.setEffect(EffectState(effect: effect.id, flag: reverse ? 1 : 0, speed: speed, colors: colors),
                         region: reg, profile: profile)
        print("\(LEDRegion(rawValue: reg)!.name): \(effect.name)")

    case "brightness":
        guard args.count == 2, let pct = Int(args[1]), (0...100).contains(pct) else { fail(usage) }
        let kb = connect()
        try kb.setBrightness(UInt8(pct * 255 / 100), region: region(args[0]), profile: try kb.activeProfile())

    case "fill", "keys":
        var colors: [Int: RGB] = [:]
        let base = option("--base").flatMap(RGB.init(hex:)) ?? .black
        if command == "fill" {
            guard args.count == 1, let c = RGB(hex: args[0]) else { fail(usage) }
            for k in KeyLayout.keys { colors[k.id] = c }
        } else {
            for k in KeyLayout.keys { colors[k.id] = base }
            for a in args {
                let parts = a.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2, let c = RGB(hex: parts[1]) else { fail("Bad argument \(a)") }
                let matches = KeyLayout.keys.filter { $0.label.lowercased() == parts[0].lowercased() || String($0.id) == parts[0] }
                guard !matches.isEmpty else { fail("Unknown key '\(parts[0])'. See: bakey layout") }
                for k in matches { colors[k.id] = c }
            }
        }
        let kb = connect()
        let profile = try kb.activeProfile()
        if try kb.effect(region: LEDRegion.backlight.rawValue, profile: profile).effect != LightingEffect.streamingID {
            try kb.setEffect(EffectState(effect: LightingEffect.streamingID), region: LEDRegion.backlight.rawValue, profile: profile)
        }
        try kb.sendFrame(KeyLayout.frame(from: colors))

    case "effect-raw":
        // Experiment: sends effect/flag/speed bytes exactly as given, bypassing the 1...3 speed clamp.
        guard args.count >= 4, let e = number(args[1]), let f = number(args[2]), let s = number(args[3]) else {
            fail("Usage: bakey effect-raw <back|side> <effect> <flag> <speed> [RRGGBB]")
        }
        let reg = region(args[0])
        let colors = args.count > 4 ? (RGB(hex: args[4]).map { [$0] } ?? []) : []
        let kb = connect()
        let profile = try kb.activeProfile()
        let payload = [reg, e, f, s, UInt8(colors.count)] + colors.flatMap(\.bytes)
        print(try kb.transact(.lighting, 0x02, profile: profile, payload: payload).hex.prefix(48))

    case "bench":
        // Measures link speed. The frames are all black; they only show if the backlight is in per-key mode.
        let kb = connect()
        print("Transport: \(kb.hid.isReceiver ? "2.4G receiver" : kb.hid.transport), report ID \(kb.hid.reportID)")
        var t = Date()
        for _ in 0..<20 { _ = try kb.transact(.device, 0x80, length: 2) }
        print(String(format: "GET round trip:   %6.1f ms", -t.timeIntervalSinceNow * 1000 / 20))
        let frame = KeyLayout.frame(from: [:])
        t = Date()
        let frames = 20
        for _ in 0..<frames { try kb.sendFrame(frame) }
        let perFrame = -t.timeIntervalSinceNow / Double(frames)
        print(String(format: "Full frame:       %6.1f ms  (%.1f fps, %d packets)", perFrame * 1000, 1 / perFrame, KeyLayout.rows))

    case "demo":
        // A host-driven rainbow animation, to see what the link can do. Ctrl-C to stop.
        let seconds = Double(args.first ?? "10") ?? 10
        let kb = connect()
        let profile = try kb.activeProfile()
        try kb.setEffect(EffectState(effect: LightingEffect.streamingID), region: LEDRegion.backlight.rawValue, profile: profile)
        let start = Date()
        var n = 0
        while -start.timeIntervalSinceNow < seconds {
            let phase = -start.timeIntervalSinceNow / 2
            var colors: [Int: RGB] = [:]
            for k in KeyLayout.keys {
                let h = (k.rect.midX / KeyLayout.size.width + phase).truncatingRemainder(dividingBy: 1)
                colors[k.id] = RGB(hue: h)
            }
            try kb.sendFrame(KeyLayout.frame(from: colors))
            n += 1
        }
        print(String(format: "%d frames in %.1f s = %.1f fps", n, seconds, Double(n) / seconds))

    case "lab":
        let kb = connect()
        print("Transport: \(kb.hid.isReceiver ? "2.4G receiver" : kb.hid.transport)")
        try Lab.run(args.first ?? "", kb, Array(args.dropFirst()))

    case "listen":
        // Diagnostics for reactive effects: which key-press source works, and what it reports.
        let seconds = Double(args.first ?? "15") ?? 15
        let m = KeyPressMonitor()
        var count = 0
        m.onKeyDown = { usage in
            count += 1
            let key = KeyLayout.keys.first { $0.hidUsage == usage }
            print(String(format: "  usage 0x%02X  %@", usage, key?.label ?? "?"))
        }
        let ok = m.start()
        print("started: \(ok)  source: \(m.source)  \(m.lastFailure ?? "")")
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { CFRunLoopRunInMode(.defaultMode, 0.1, false) }
        print("\(count) key presses in \(Int(seconds)) s")

    case "showcase":
        // Timed light show for filming. Optional countdown in seconds (default 5).
        let kb = connect()
        print("Transport: \(kb.hid.isReceiver ? "2.4G receiver" : kb.hid.transport)")
        try Showcase.run(kb, countdown: Int(args.first ?? "5") ?? 5)

    case "layout":
        for k in KeyLayout.keys.sorted(by: { ($0.cells.first?.row ?? 9, $0.cells.first?.col ?? 0) < ($1.cells.first?.row ?? 9, $1.cells.first?.col ?? 0) }) {
            let cells = k.cells.map { "r\($0.row)c\($0.col)" }.joined(separator: " ")
            print(String(format: "%-6@ id %3d  %@", k.label as NSString, k.id, cells.isEmpty ? "(no LED)" : cells))
        }

    case "get":
        guard args.count >= 2, let c = number(args[0]), let cls = CommandClass(rawValue: c), let cmd = number(args[1]) else {
            fail("Usage: bakey get <class> <cmd> [payload bytes]. Classes: 0 device, 1 key, 3 lighting, 5 profile, 6 macro, 7 power")
        }
        guard cmd & getFlag != 0 else { fail("Only GET commands (bit 7 set, e.g. 0x80) are allowed here.") }
        let payload = args.dropFirst(2).compactMap(number)
        let kb = connect()
        print(try kb.transact(cls, cmd, payload: Array(payload)).hex)

    default:
        print(usage)
    }
}

do { try run() } catch { fail("Error: \(error.localizedDescription)") }

extension RGB {
    /// Fully saturated color for a hue in 0..<1.
    init(hue: Double) {
        let h = hue * 6, x = 1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)
        let (r, g, b): (Double, Double, Double)
        switch Int(h) % 6 {
        case 0: (r, g, b) = (1, x, 0)
        case 1: (r, g, b) = (x, 1, 0)
        case 2: (r, g, b) = (0, 1, x)
        case 3: (r, g, b) = (0, x, 1)
        case 4: (r, g, b) = (x, 0, 1)
        default: (r, g, b) = (1, 0, x)
        }
        self.init(UInt8(r * 255), UInt8(g * 255), UInt8(b * 255))
    }
}
