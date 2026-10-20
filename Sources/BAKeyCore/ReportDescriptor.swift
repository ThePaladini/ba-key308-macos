import Foundation

/// Minimal HID report descriptor parser.
///
/// We only need one answer from it: which report ID carries the 64-byte vendor feature report
/// used for configuration. Over Bluetooth LE that is report 7; over USB the configuration
/// interface has no report IDs (0). Reading it from the descriptor instead of hard-coding
/// it per transport keeps the code correct if a firmware update changes it.
public enum ReportDescriptor {
    /// Returns the report ID of the first Feature report whose size is `payloadBytes`,
    /// or nil if the descriptor has none. Returns 0 when the descriptor uses no report IDs.
    public static func featureReportID(in d: [UInt8], payloadBytes: Int = BAKey.payloadLength) -> UInt8? {
        var i = 0
        var reportID: UInt8 = 0
        var reportSize = 0
        var reportCount = 0
        var stack: [(UInt8, Int, Int)] = []

        while i < d.count {
            let prefix = d[i]
            if prefix == 0xFE { // long item: FE, size, tag, data...
                guard i + 1 < d.count else { break }
                i += 3 + Int(d[i + 1])
                continue
            }
            var size = Int(prefix & 0x03)
            if size == 3 { size = 4 }
            let type = (prefix >> 2) & 0x03
            let tag = prefix >> 4
            guard i + size < d.count else { break }
            var value: UInt32 = 0
            for k in 0..<size { value |= UInt32(d[i + 1 + k]) << (8 * k) }

            switch (type, tag) {
            case (1, 0x7): reportSize = Int(value)           // Report Size
            case (1, 0x8): reportID = UInt8(value & 0xFF)     // Report ID
            case (1, 0x9): reportCount = Int(value)          // Report Count
            case (1, 0xA): stack.append((reportID, reportSize, reportCount)) // Push
            case (1, 0xB):                                   // Pop
                if let s = stack.popLast() { (reportID, reportSize, reportCount) = s }
            case (0, 0xB):                                   // Main: Feature
                if reportSize * reportCount == payloadBytes * 8 { return reportID }
            default: break
            }
            i += 1 + size
        }
        return nil
    }
}
