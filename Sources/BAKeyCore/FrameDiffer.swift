import Foundation

/// Sends per-key frames using as few packets as possible.
///
/// Each frame packet costs ~154 ms over Bluetooth LE (vs ~1.3 ms over USB), and that cost is per
/// packet, not per byte. Tested on the real keyboard (2026-10-20, BLE):
/// - a single row packet updates just that row and leaves the others alone ("partial update");
/// - a fill packet (flags 0x03 + RGB) paints the whole region in one packet;
/// - pipelining packets or sustained traffic does not make the link faster.
///
/// So this keeps track of what the keyboard currently shows and only sends rows that changed,
/// or one fill packet when every lit key has the same color. With `maxPackets: 1` on a slow link
/// it sends the most-changed row first, so a key press shows up after one packet.
/// See docs/BLUETOOTH.md.
public struct FrameDiffer {
    /// What the keyboard is showing, as far as we know (lit cells only are meaningful).
    public private(set) var shown: [[RGB]]?

    /// Cells that have an LED under a key. Only these are compared.
    static var litMask: [[Bool]] {
        var m = [[Bool]](repeating: [Bool](repeating: false, count: KeyLayout.columns), count: KeyLayout.rows)
        for k in KeyLayout.keys { for c in k.cells { m[c.row][c.col] = true } }
        return m
    }

    public init() {}

    /// Forget the keyboard's state (after reconnecting or switching effects).
    public mutating func reset() { shown = nil }

    /// The single color of all lit cells, if they share one.
    public static func uniformColor(_ frame: [[RGB]]) -> RGB? {
        var color: RGB?
        let lit = litMask
        for r in 0..<frame.count {
            for c in 0..<frame[r].count where lit[r][c] {
                if let color, color != frame[r][c] { return nil }
                color = frame[r][c]
            }
        }
        return color
    }

    /// Rows whose lit cells differ from what is shown, most-changed first.
    ///
    /// `minScore` skips rows whose total change (sum of |ΔR|+|ΔG|+|ΔB|) is below it, to save packets
    /// on a slow link. Rows going completely dark are always included, so nothing stays faintly lit.
    public func dirtyRows(_ frame: [[RGB]], minScore: Int = 1) -> [Int] {
        guard let shown else { return Array(0..<frame.count) }
        var scored: [(row: Int, score: Int)] = []
        let lit = Self.litMask
        for r in 0..<frame.count {
            var score = 0
            var dark = true
            for c in 0..<frame[r].count where lit[r][c] {
                let a = frame[r][c], b = shown[r][c]
                score += abs(Int(a.r) - Int(b.r)) + abs(Int(a.g) - Int(b.g)) + abs(Int(a.b) - Int(b.b))
                if a != .black { dark = false }
            }
            if score >= max(minScore, 1) || (score > 0 && dark) { scored.append((r, score)) }
        }
        return scored.sorted { $0.score > $1.score }.map(\.row)
    }

    /// The packets to bring the keyboard to `frame`, at most `maxPackets` of them.
    public func plan(_ frame: [[RGB]], reportID: UInt8, target: UInt8 = 0,
                     region: UInt8 = LEDRegion.backlight.rawValue, maxPackets: Int = .max,
                     minScore: Int = 1) -> [Packet] {
        let dirty = dirtyRows(frame, minScore: minScore)
        guard !dirty.isEmpty else { return [] }
        if dirty.count > 1, let c = Self.uniformColor(frame) {
            return [PacketBuilder.fillPacket(reportID: reportID, target: target, region: region, color: c)]
        }
        return dirty.prefix(maxPackets).map {
            PacketBuilder.rowPacket(reportID: reportID, target: target, region: region, row: $0, colors: frame[$0])
        }
    }

    /// Records that `packets` (from `plan`) were delivered.
    public mutating func applied(_ packets: [Packet], frame: [[RGB]]) {
        var s = shown ?? [[RGB]](repeating: [RGB](repeating: .black, count: KeyLayout.columns), count: KeyLayout.rows)
        for p in packets {
            if p[8] == 0x03 { s = frame; break }   // fill: every lit cell now matches the frame
            s[Int(p[9])] = frame[Int(p[9])]
        }
        shown = s
    }

    /// Plans, sends and records. Returns the number of packets sent.
    @discardableResult
    public mutating func push(_ frame: [[RGB]], via kb: KeyboardClient, maxPackets: Int = .max) throws -> Int {
        let packets = plan(frame, reportID: kb.hid.reportID, target: kb.target, maxPackets: maxPackets)
        guard !packets.isEmpty else { return 0 }
        try kb.sendPackets(packets)
        applied(packets, frame: frame)
        return packets.count
    }
}

extension PacketBuilder {
    /// One full row, committed on its own (flags 0x81). Verified to leave other rows unchanged.
    public static func rowPacket(reportID: UInt8, target: UInt8 = 0, region: UInt8, row: Int, colors: [RGB]) -> Packet {
        let n = min(colors.count, BAKey.frameChunk)
        let payload: [UInt8] = [region, 0x81, UInt8(row), 0, UInt8(n - 1)] + colors.prefix(n).flatMap(\.bytes)
        return Packet(reportID: reportID, target: target, commandClass: CommandClass.lighting.rawValue,
                      command: 0x04, payload: payload, length: UInt8(6 + 3 * n))
    }

    /// Whole region in one color, one packet: flags 0x03, RGB at [9...11].
    /// (The Windows app's SetLedFrameALL puts R in all three bytes; R,G,B is what works.)
    public static func fillPacket(reportID: UInt8, target: UInt8 = 0, region: UInt8, color: RGB) -> Packet {
        Packet(reportID: reportID, target: target, commandClass: CommandClass.lighting.rawValue, command: 0x04,
               payload: [region, 0x03, color.r, color.g, color.b], length: 6)
    }
}
