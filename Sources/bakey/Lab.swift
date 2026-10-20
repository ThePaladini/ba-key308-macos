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
