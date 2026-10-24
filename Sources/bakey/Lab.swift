import BAKeyCore
import Foundation
import IOKit.hid

/// Experiments for making per-key lighting faster over Bluetooth. See docs/BLUETOOTH.md.
enum Lab {
    static func run(_ test: String, _ kb: KeyboardClient, _ args: [String]) throws {
        let region = LEDRegion.backlight.rawValue
        func ensureStreaming() throws {
            try kb.setEffect(EffectState(effect: LightingEffect.streamingID), region: region, profile: try kb.activeProfile())
        }
        func rowPacket(_ row: Int, _ color: RGB, last: Bool) -> Packet {
            let rgb = [RGB](repeating: color, count: KeyLayout.columns).flatMap(\.bytes)
            return Packet(reportID: kb.hid.reportID, target: kb.target, commandClass: 3, command: 0x04,
                          payload: [region, last ? 0x81 : 0x01, UInt8(row), 0, UInt8(KeyLayout.columns - 1)] + rgb,
                          length: UInt8(6 + rgb.count))
        }

        switch test {
        case "sustained":
            // Does the link speed up under steady traffic (connection parameter update)?
            try ensureStreaming()
            for round in 1...6 {
                let t = Date()
                for i in 0..<10 { try kb.hid.setFeature(rowPacket(i % 6, .black, last: i % 6 == 5)) }
                print(String(format: "round %d: %.0f ms per packet", round, -t.timeIntervalSinceNow * 100))
            }

        case "async":
            // Pipelining: queue N SetReports without waiting for each to finish.
            try ensureStreaming()
            let n = Int(args.first ?? "12") ?? 12
            print(String(format: "%d packets pipelined: %.0f ms per packet", n, try pipelined(kb, n, rowPacket) * 1000))

        case "partial":
            // Visual: whole board blue, then ONLY row 2 (Tab...Del) red, sent as a single packet.
            try ensureStreaming()
            try kb.sendFrame([[RGB]](repeating: [RGB](repeating: RGB(0, 0, 255), count: 15), count: 6))
            Thread.sleep(forTimeInterval: 2)
            let t = Date()
            try kb.hid.setFeature(rowPacket(2, RGB(255, 0, 0), last: args.first != "nocommit"))
            print(String(format: "single row packet sent in %.0f ms", -t.timeIntervalSinceNow * 1000))

        case "fill":
            // One-packet fill: flags 0x03 with RGB in [9...11] (from SetLedFrameALL in the Windows app).
            try ensureStreaming()
            let c = RGB(hex: args.first ?? "00ff00") ?? RGB(0, 255, 0)
            let p = Packet(reportID: kb.hid.reportID, target: kb.target, commandClass: 3, command: 0x04,
                           payload: [region, 0x03, c.r, c.g, c.b], length: 6)
            let t = Date()
            try kb.hid.setFeature(p)
            print(String(format: "fill packet sent in %.0f ms", -t.timeIntervalSinceNow * 1000))

        case "stress":
            print("use: bakey lab-stress <scenario> <seconds> [interval-ms]")
        default:
            print("bakey lab sustained | async [n] | partial [nocommit] | fill [RRGGBB]")
        }
    }

    /// Sends n packets with IOHIDDeviceSetReportWithCallback, all queued up front.
    /// Returns seconds per packet.
    private static func pipelined(_ kb: KeyboardClient, _ n: Int, _ make: (Int, RGB, Bool) -> Packet) throws -> Double {
        final class Box { var done = 0; var errors = 0 }
        let box = Box()
        let dev = kb.hid.device
        IOHIDDeviceScheduleWithRunLoop(dev, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        defer { IOHIDDeviceUnscheduleFromRunLoop(dev, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue) }
        var buffers: [UnsafeMutablePointer<UInt8>] = []
        let ctx = Unmanaged.passUnretained(box).toOpaque()
        let t = Date()
        for i in 0..<n {
            var bytes = make(i % 6, .black, i % 6 == 5).bytes
            let rid = kb.hid.reportID
            if rid == 0 { bytes.removeFirst() }
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bytes.count)
            buf.initialize(from: bytes, count: bytes.count)
            buffers.append(buf)
            let r = IOHIDDeviceSetReportWithCallback(dev, kIOHIDReportTypeFeature, CFIndex(rid), buf, bytes.count, 5.0, { ctx, result, _, _, _, _, _ in
                let b = Unmanaged<Box>.fromOpaque(ctx!).takeUnretainedValue()
                b.done += 1
                if result != kIOReturnSuccess { b.errors += 1 }
            }, ctx)
            if r != kIOReturnSuccess { print(String(format: "queue %d failed: 0x%08X", i, r)); box.done += 1; box.errors += 1 }
        }
        while box.done < n && -t.timeIntervalSinceNow < 30 {
            CFRunLoopRunInMode(.defaultMode, 0.01, false)
        }
        let elapsed = -t.timeIntervalSinceNow
        buffers.forEach { $0.deallocate() }
        if box.errors > 0 { print("\(box.errors) of \(n) reports failed") }
        return elapsed / Double(n)
    }
}

/// `bakey lab stress <scenario> <seconds> [interval-ms]`: reproduces what the app sends when settings
/// change, logging every command's latency and the exact time of any disconnect (HID removal).
/// Restores the original lighting at the end. See docs/BLUETOOTH.md ("Disconnect investigation").
enum Stress {
    static func run(scenario: String, seconds: Double, intervalMs: Double) throws {
        final class Flag { var removedAt: Date?; var events: [String] = [] }
        let flag = Flag()
        let monitor = DeviceMonitor()   // scheduled on the main run loop; pumped below
        let start = Date()
        func stamp() -> String { String(format: "%7.2fs", -start.timeIntervalSinceNow) }
        monitor.onChange = {
            let present = !monitor.candidates().isEmpty
            flag.events.append("\(stamp()) HID \(present ? "appeared" : "REMOVED")")
            print(flag.events.last!)
            if !present { flag.removedAt = Date() }
        }
        func pump(_ t: Double = 0) { CFRunLoopRunInMode(.defaultMode, t, false) }
        pump(0.2)

        func open() -> KeyboardClient? {
            for hid in monitor.candidates() { if let c = try? KeyboardClient(hid: hid) { return c } }
            return nil
        }
        guard var kb = open() else { throw BAKeyError.noDevice }
        let region = LEDRegion.backlight.rawValue
        let profile = try kb.activeProfile()
        let original = try kb.effect(region: region, profile: profile)
        let originalBrightness = try kb.brightness(region: region)
        let side = LEDRegion.sidelight.rawValue
        let originalSide = try kb.effect(region: side, profile: profile)
        let originalSideBrightness = try kb.brightness(region: side)
        print("scenario=\(scenario) seconds=\(seconds) interval=\(intervalMs)ms transport=\(kb.hid.transport)")
        print("original: effect \(original.effect) speed \(original.speed) brightness \(originalBrightness)")

        var ops = 0, failures = 0, disconnects = 0
        var latencies: [Double] = []
        var i = 0
        while -start.timeIntervalSinceNow < seconds {
            let t0 = Date()
            do {
                switch scenario {
                case "read":
                    _ = try kb.battery()
                case "brightness":   // slider drag: alternate levels
                    try kb.setBrightness(i % 2 == 0 ? 120 : 255, region: region, profile: profile)
                case "effect":       // picking effects in the menu
                    try kb.setEffect(EffectState(effect: i % 2 == 0 ? 6 : 1, speed: 2, colors: i % 2 == 0 ? [] : [.white]),
                                     region: region, profile: profile)
                case "speed":        // speed slider across the full 1...255 range
                    let speeds: [UInt8] = [1, 40, 120, 200, 255]
                    try kb.setEffect(EffectState(effect: 24, speed: speeds[i % speeds.count], colors: [.white]),
                                     region: region, profile: profile)
                case "color":        // color picker drag on the side light
                    try kb.setEffect(EffectState(effect: 1, colors: [RGB(hue: Double(i % 24) / 24)]),
                                     region: LEDRegion.sidelight.rawValue, profile: profile)
                case "color-back":   // same, on the backlight
                    try kb.setEffect(EffectState(effect: 1, colors: [RGB(hue: Double(i % 24) / 24)]),
                                     region: region, profile: profile)
                case "mix":          // mixer: a new color, then the brightness slider right after
                    try kb.setEffect(EffectState(effect: 1, colors: [RGB(hue: Double(i % 24) / 24)]), region: region, profile: profile)
                    try kb.setBrightness(i % 2 == 0 ? 190 : 255, region: region, profile: profile)
                case "two-regions":  // mixer on the backlight, then on the side light
                    let c = [RGB(hue: Double(i % 24) / 24)]
                    try kb.setEffect(EffectState(effect: 1, colors: c), region: i % 2 == 0 ? region : LEDRegion.sidelight.rawValue, profile: profile)
                case "side-toggle":  // side light effect changes, fixed color
                    try kb.setEffect(EffectState(effect: i % 2 == 0 ? 1 : 2, speed: 2, colors: [.white]),
                                     region: LEDRegion.sidelight.rawValue, profile: profile)
                case "frames":       // painter / Mac effects
                    if i == 0 { try kb.setEffect(EffectState(effect: LightingEffect.streamingID), region: region, profile: profile) }
                    let c = RGB(hue: Double(i % 12) / 12)
                    try kb.sendFrame([[RGB]](repeating: [RGB](repeating: c, count: KeyLayout.columns), count: KeyLayout.rows))
                default:
                    print("scenarios: read brightness effect speed color frames"); return
                }
                ops += 1
                latencies.append(-t0.timeIntervalSinceNow * 1000)
            } catch {
                failures += 1
                print("\(stamp()) op \(i) FAILED: \(error.localizedDescription)")
                // A transport error means the handle died (the link dropped, even if it is already back).
                if case BAKeyError.ioFailed = error { flag.removedAt = flag.removedAt ?? Date() }
                Thread.sleep(forTimeInterval: 0.3)
            }
            pump()
            if flag.removedAt != nil {
                disconnects += 1
                print("\(stamp()) disconnect #\(disconnects); waiting for the keyboard to come back…")
                let waitStart = Date()
                var again: KeyboardClient?
                while again == nil && -waitStart.timeIntervalSinceNow < 60 {
                    pump(0.5)
                    if !monitor.candidates().isEmpty, let c = open(), (try? c.info()) != nil { again = c }
                }
                guard let again else { print("did not come back within 60 s"); break }
                print(String(format: "%@ reconnected after %.1f s", stamp(), -waitStart.timeIntervalSinceNow))
                kb = again
                flag.removedAt = nil
            }
            i += 1
            if intervalMs > 0 { Thread.sleep(forTimeInterval: intervalMs / 1000) }
        }
        try? kb.setEffect(original, region: region, profile: profile)
        try? kb.setBrightness(originalBrightness, region: region, profile: profile)
        try? kb.setEffect(originalSide, region: side, profile: profile)
        try? kb.setBrightness(originalSideBrightness, region: side, profile: profile)
        latencies.sort()
        let p = { (q: Double) in latencies.isEmpty ? 0 : latencies[min(latencies.count - 1, Int(Double(latencies.count) * q))] }
        print(String(format: "RESULT %@: %d ok, %d failed, %d disconnects, latency p50 %.0f ms, p95 %.0f ms, max %.0f ms",
                     scenario, ops, failures, disconnects, p(0.5), p(0.95), latencies.last ?? 0))
    }
}
