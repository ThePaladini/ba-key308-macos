import Foundation

/// Constants for the BA-KEY308 (OEM: Dareu "TK51G_0130") configuration protocol.
/// See docs/PROTOCOL.md for the full description of every field.
public enum BAKey {
    public static let vendorID = 0x260D
    /// The keyboard itself, over USB cable or Bluetooth LE.
    public static let keyboardPID = 0x0130
    /// The 2.4 GHz receiver ("Ba-KEY308 2.4G Receiver"). Commands are relayed to the keyboard.
    public static let donglePID = 0x0042

    /// Feature report = 1 report-ID byte + 64 payload bytes.
    public static let reportLength = 65
    public static let payloadLength = 64

    /// Largest chunk the firmware accepts in multi-packet transfers.
    public static let multiPacketChunk = 48
    /// Largest number of LEDs per per-key frame packet.
    public static let frameChunk = 16
}

/// Command classes (byte [3] of a packet).
///
/// Deliberately incomplete: firmware update (9), test/factory (10) and flash (12)
/// are not representable, so they cannot be sent by accident. See docs/SAFETY.md.
public enum CommandClass: UInt8, Sendable {
    case device = 0
    case key = 1
    case lighting = 3
    case profile = 5
    case macro = 6
    case power = 7
}

/// Response status, in the low nibble of byte [1].
public enum ResponseStatus: UInt8, Sendable {
    case empty = 0
    case busy = 1
    case ready = 2
    case error = 3
    case notSupported = 5
    case error2 = 6
}

/// Bit 7 of the command byte marks a GET (read). Clear means SET (write).
public let getFlag: UInt8 = 0x80

public enum BAKeyError: Error, LocalizedError, Sendable {
    case noDevice
    case openFailed(Int32)
    case ioFailed(String, Int32)
    case timeout(String)
    case notSupported(String)
    case blocked(String)
    case badResponse(String)
    case noKeyboardBehindReceiver

    public var errorDescription: String? {
        switch self {
        case .noDevice: return "BA-KEY308 not found"
        case .openFailed(let r): return String(format: "Could not open the keyboard (IOReturn 0x%08X)", r)
        case .ioFailed(let op, let r): return String(format: "HID %@ failed (IOReturn 0x%08X)", op, r)
        case .timeout(let what): return "Keyboard did not answer: \(what)"
        case .notSupported(let what): return "Not supported by the firmware: \(what)"
        case .blocked(let what): return "Blocked for safety: \(what)"
        case .badResponse(let what): return "Unexpected response: \(what)"
        case .noKeyboardBehindReceiver: return "The 2.4G receiver has no keyboard connected"
        }
    }
}

/// An RGB color as the firmware sees it.
public struct RGB: Hashable, Codable, Sendable {
    public var r: UInt8, g: UInt8, b: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }

    public static let black = RGB(0, 0, 0)
    public static let white = RGB(255, 255, 255)

    public var bytes: [UInt8] { [r, g, b] }

    /// "FF8800" or "#ff8800".
    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF))
    }

    public var hex: String { String(format: "%02X%02X%02X", r, g, b) }
}

/// Lighting regions on this keyboard (byte [7] of lighting commands).
public enum LEDRegion: UInt8, CaseIterable, Sendable {
    /// Per-key RGB backlight under the keycaps, 6 x 15 matrix.
    case backlight = 1
    /// Light strip on the side/back of the case.
    case sidelight = 4

    public var name: String {
        switch self {
        case .backlight: return "Backlight"
        case .sidelight: return "Side light"
        }
    }
}

/// A firmware lighting effect. IDs come from the Windows app's `LedEffectIndex` enum.
public struct LightingEffect: Identifiable, Hashable, Sendable {
    public let id: UInt8
    public let name: String
    /// Whether the speed byte means anything. The Windows UI only offers a slider for `windowsSpeedIDs`,
    /// but the firmware also speeds up others (verified: Raindrop at 255 is much faster than at 1).
    public let hasSpeed: Bool
    /// Wave can run left-to-right or right-to-left (byte "flag").
    public let hasDirection: Bool
    /// Whether a custom color makes sense. With 0 colors the firmware uses its own palette (usually rainbow).
    public let acceptsColor: Bool

    public static let streamingID: UInt8 = 18

    public static let windowsSpeedIDs: Set<UInt8> = [2, 3, 4, 5, 9, 10, 11, 19, 20, 21, 22, 24, 25, 26, 27, 28, 29]
    private static let noSpeedIDs: Set<UInt8> = [0, 1, 13, 14, 15, 16, 17, 18]
    private static let names: [UInt8: String] = [
        0: "Off", 1: "Static", 2: "Breathing", 3: "Neon", 4: "Reactive", 5: "Wave",
        6: "Raindrop", 7: "Gather", 8: "Ripple", 9: "Running Light", 10: "Diffusion",
        11: "Starlit", 12: "Heat-up", 13: "Custom 1", 14: "Custom 2", 15: "Custom 3",
        16: "Custom 4", 17: "Custom 5", 18: "Per-key (custom)", 19: "Lap", 20: "Rainbow Wheel",
        21: "Light Wave", 22: "Steady Stream", 23: "Start-up", 24: "Area Reactive",
        25: "Line Reactive", 26: "Waterfall", 27: "Scanning", 28: "Heartbeat", 29: "Fluxay",
        30: "Heart Breath", 31: "Moon Breath", 32: "Star Breath",
    ]

    public init(id: UInt8) {
        self.id = id
        self.name = Self.names[id] ?? "Effect \(id)"
        self.hasSpeed = !Self.noSpeedIDs.contains(id)
        self.hasDirection = id == 5
        self.acceptsColor = !(id == 0 || id == Self.streamingID || (13...17).contains(id))
    }

    public var isStreaming: Bool { id == Self.streamingID }
}

/// Valid speed bytes. 1 = the firmware's default and slowest pace, 255 = fastest.
/// The Windows app only uses 1...3. The firmware ignores writes with speed 0.
public let speedRange: ClosedRange<UInt8> = 1...255
