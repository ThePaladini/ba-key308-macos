import Foundation

/// One 65-byte feature report.
///
/// ```
/// [0] report ID      (7 over Bluetooth LE, 0 over USB; taken from the report descriptor)
/// [1] request: target device in the high nibble (0 = direct, n = receiver slot n)
///     response: status in the low nibble (see ResponseStatus)
/// [2] payload length
/// [3] command class
/// [4] command ID, bit 7 set = GET
/// [5] profile ID (1...6, 0 = not applicable)
/// [6] reserved (0)
/// [7...64] payload, multi-byte values big-endian
/// ```
public struct Packet: Sendable, Equatable {
    public var bytes: [UInt8]

    public init(bytes: [UInt8]) {
        var b = bytes
        if b.count < BAKey.reportLength { b += [UInt8](repeating: 0, count: BAKey.reportLength - b.count) }
        self.bytes = Array(b.prefix(BAKey.reportLength))
    }

    public init(reportID: UInt8, target: UInt8 = 0, commandClass: UInt8, command: UInt8,
                profile: UInt8 = 0, payload: [UInt8] = [], length: UInt8? = nil) {
        precondition(payload.count <= BAKey.reportLength - 7, "payload too long")
        var b = [UInt8](repeating: 0, count: BAKey.reportLength)
        b[0] = reportID
        b[1] = target
        b[2] = length ?? UInt8(payload.count)
        b[3] = commandClass
        b[4] = command
        b[5] = profile
        b.replaceSubrange(7..<(7 + payload.count), with: payload)
        self.bytes = b
    }

    public var reportID: UInt8 { bytes[0] }
    public var statusRaw: UInt8 { bytes[1] & 0x0F }
    public var status: ResponseStatus? { ResponseStatus(rawValue: statusRaw) }
    public var length: UInt8 { bytes[2] }
    public var commandClass: UInt8 { bytes[3] }
    public var command: UInt8 { bytes[4] }
    public var profile: UInt8 { bytes[5] }
    /// Bytes [7...64].
    public var data: ArraySlice<UInt8> { bytes[7...] }

    /// Byte at absolute offset (so `self[8]` matches the offsets used throughout the docs).
    public subscript(_ i: Int) -> UInt8 { bytes[i] }

    public func uint16(at i: Int) -> UInt16 { UInt16(bytes[i]) << 8 | UInt16(bytes[i + 1]) }

    public var hex: String { bytes.map { String(format: "%02x", $0) }.joined(separator: " ") }
}

/// Pure encoders for multi-packet commands, kept separate so they can be unit tested.
public enum PacketBuilder {
    /// Packets for one per-key frame (class 3, command 0x04, sent without waiting for a reply).
    ///
    /// Each packet carries one row segment: `[7]=region [8]=flags [9]=row [10]=first col [11]=last col [12...]=RGB`.
    /// `flags` is 0x01, plus 0x80 on the final packet of the frame.
    public static func framePackets(reportID: UInt8, target: UInt8 = 0, region: UInt8, rows: [[RGB]]) -> [Packet] {
        var packets: [Packet] = []
        for (r, row) in rows.enumerated() {
            var start = 0
            while start < row.count {
                let n = min(BAKey.frameChunk, row.count - start)
                let isLast = r == rows.count - 1 && start + n == row.count
                var payload: [UInt8] = [region, isLast ? 0x81 : 0x01, UInt8(r), UInt8(start), UInt8(start + n - 1)]
                for c in row[start..<(start + n)] { payload += c.bytes }
                packets.append(Packet(reportID: reportID, target: target, commandClass: CommandClass.lighting.rawValue,
                                      command: 0x04, payload: payload, length: UInt8(6 + 3 * n)))
                start += n
            }
        }
        return packets
    }
}
