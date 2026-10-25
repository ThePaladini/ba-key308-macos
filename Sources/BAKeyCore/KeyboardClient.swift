import Foundation

public struct DeviceInfo: Sendable, Equatable {
    public var name: String
    public var transport: String
    public var viaReceiver: Bool
    public var firmware: String
    public var hardware: String
    public var pid: Int = 0
    public var modelName: String = ""
}

public struct BatteryState: Sendable, Equatable {
    public enum Status: UInt8, Sendable { case discharging = 0, charging = 1, full = 2 }
    public var status: Status?
    public var level: Int
}

public struct LEDAttributes: Sendable, Equatable {
    public var region: UInt8
    public var type: UInt8
    public var fps: Int
    public var rows: Int
    public var columns: Int
    /// Effect IDs the firmware supports for this region, in the firmware's order.
    public var effects: [UInt8]
}

public struct EffectState: Sendable, Equatable {
    public var effect: UInt8
    /// Direction for Wave: 0 = left to right, 1 = right to left.
    public var flag: UInt8
    public var speed: UInt8
    /// 0...5 colors. Empty = firmware palette.
    public var colors: [RGB]

    public init(effect: UInt8, flag: UInt8 = 0, speed: UInt8 = 2, colors: [RGB] = []) {
        self.effect = effect; self.flag = flag; self.speed = speed; self.colors = colors
    }
}

/// High-level, synchronous API over one open device.
///
/// Not thread-safe: call it from a single serial queue (the app uses `HIDWorker`).
/// Every request is SET-feature followed by GET-feature polling until the firmware
/// echoes the command with status READY.
public final class KeyboardClient {
    public let hid: HIDDevice
    /// Target nibble for byte [1]: 0 = the device itself, (slot + 1) << 4 = keyboard behind the receiver.
    public private(set) var target: UInt8 = 0
    /// PID of the keyboard being talked to (directly, or behind the receiver).
    public private(set) var keyboardPID: Int
    /// Whether the one-packet fill (`PacketBuilder.fillPacket`) may be used on this link.
    ///
    /// Only over Bluetooth, where it was verified and where it saves time (~154 ms per packet).
    /// **Through the 2.4G receiver a single fill packet makes the receiver reset**: it drops off USB
    /// ~3 s later and re-enumerates (measured 2026-10-24). Over USB it isn't needed, so it's not used there either.
    public var supportsFillPacket: Bool { !hid.isReceiver && hid.transport.localizedCaseInsensitiveContains("bluetooth") }

    /// The keyboard model, which decides the key layout. nil for an unknown PID.
    public var model: KeyboardModel? { KeyboardModel.forPID(keyboardPID) }
    public var log: ((String) -> Void)?

    /// Minimum gap between effect writes that change a region's colors.
    ///
    /// Measured on the BA-KEY308 over Bluetooth (2026-10-20, `bakey lab-stress`): color changes sent
    /// back to back (~2 per second) freeze the firmware within a few writes. The radio stops
    /// acknowledging and macOS drops the link with a supervision timeout (reason 708), then the keyboard
    /// reconnects by itself. The same writes 1 s apart survived 41/41; brightness, effect and speed changes
    /// back to back survived 100+ each. See docs/BLUETOOTH.md.
    ///
    /// 2026-10-24, second BA-KEY308 (white): 1.2 s was not enough. Color writes ~1.6 s apart dropped the
    /// link after 8; ~1.7 s apart survived 58 and ~4.2 s survived 34. It's rate-dependent, with a
    /// threshold around 1.6-1.7 s that varies per unit, so the gap is now 2.5 s (~2.9 s per write).
    public static let colorWriteSpacing: TimeInterval = 2.5
    /// Any other lighting write waits this long after a color change (e.g. the brightness slider right
    /// after picking a color), so the firmware has finished applying the color.
    public static let quietAfterColor: TimeInterval = 1.0
    private var lastColorWrite: [UInt8: (time: Date, colors: [RGB])] = [:]
    private var lastAnyColorWrite: Date?

    private func waitAfterColorWrite() {
        guard let t = lastAnyColorWrite else { return }
        let wait = Self.quietAfterColor + t.timeIntervalSinceNow
        if wait > 0 { Thread.sleep(forTimeInterval: wait) }
    }

    /// SET commands this client is allowed to send. Everything else must be a GET.
    /// This is the second safety layer after `CommandClass` (see docs/SAFETY.md).
    static let allowedSets: Set<[UInt8]> = [
        [CommandClass.lighting.rawValue, 0x02], // LED effect
        [CommandClass.lighting.rawValue, 0x03], // LED brightness
        [CommandClass.lighting.rawValue, 0x04], // per-key frame
        [CommandClass.profile.rawValue, 0x03],  // active profile
        [CommandClass.power.rawValue, 0x02],    // sleep time
    ]

    public init(hid: HIDDevice) throws {
        self.hid = hid
        self.keyboardPID = hid.productID
        try hid.open()
        if hid.isReceiver {
            do { try selectKeyboardBehindReceiver() } catch { hid.close(); throw error }
        }
    }

    deinit { hid.close() }

    // MARK: - Transport

    @discardableResult
    public func transact(_ cls: CommandClass, _ cmd: UInt8, profile: UInt8 = 0, payload: [UInt8] = [],
                         length: UInt8? = nil, expectReply: Bool = true,
                         timeout: TimeInterval = 2.0) throws -> Packet {
        if cmd & getFlag == 0 && !Self.allowedSets.contains([cls.rawValue, cmd]) {
            throw BAKeyError.blocked(String(format: "SET class %d cmd 0x%02X", cls.rawValue, cmd))
        }
        let req = Packet(reportID: hid.reportID, target: target, commandClass: cls.rawValue, command: cmd,
                         profile: profile, payload: payload, length: length)
        log?("> \(req.hex)")
        try hid.setFeature(req)
        guard expectReply else { return req }

        let what = String(format: "class %d cmd 0x%02X", cls.rawValue, cmd)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
            let r = try hid.getFeature()
            switch r.status {
            case .ready where r.commandClass == cls.rawValue && r.command == cmd:
                log?("< \(r.hex)")
                return r
            case .notSupported:
                throw BAKeyError.notSupported(what)
            default:
                continue // empty / busy / transient error: poll again
            }
        }
        throw BAKeyError.timeout(what)
    }

    /// Multi-packet GET (ID lists, names). First request returns the total length in [7];
    /// then chunks of up to 48 bytes are requested with [7]=total [8]=offset, data at [9...].
    public func multiGet(_ cls: CommandClass, _ cmd: UInt8, profile: UInt8 = 0) throws -> [UInt8] {
        let first = try transact(cls, cmd, profile: profile, length: 1)
        let total = Int(first[7])
        var out: [UInt8] = []
        var offset = 0
        while offset < total {
            let n = min(BAKey.multiPacketChunk, total - offset)
            let r = try transact(cls, cmd, profile: profile, payload: [UInt8(total), UInt8(offset)], length: UInt8(n + 2))
            out += r.bytes[9..<(9 + n)]
            offset += n
        }
        return out
    }

    // MARK: - Receiver

    /// Asks the receiver which keyboards are paired (class 0 cmd 0xA0) and targets the first BA-KEY308.
    /// Reply: [7] = N slots, then N x {status, PID high, PID low}.
    func selectKeyboardBehindReceiver() throws {
        let r = try transact(.device, 0xA0)
        let n = Int(r[7])
        for i in 0..<n {
            let base = 8 + i * 3
            guard base + 2 < r.bytes.count else { break }
            let pid = Int(r.uint16(at: base + 1))
            if r[base] != 0 && BAKey.keyboardPIDs.contains(pid) {
                target = UInt8((i + 1) << 4)
                keyboardPID = pid
                return
            }
        }
        throw BAKeyError.noKeyboardBehindReceiver
    }

    /// Whether the keyboard is awake behind the 2.4G receiver. Asks the receiver itself for its paired-keyboard
    /// list (class 0 cmd 0xA0): a sleeping keyboard's slot reads 0. The receiver answers while the keyboard
    /// sleeps, and the question doesn't wake it. Always true when not connected through a receiver.
    public func keyboardAwakeBehindReceiver() throws -> Bool {
        guard hid.isReceiver, target != 0 else { return true }
        let keyboardTarget = target
        target = 0
        defer { target = keyboardTarget }
        let r = try transact(.device, 0xA0)
        let base = 8 + (Int(keyboardTarget >> 4) - 1) * 3
        return base < r.bytes.count && r[base] != 0
    }

    // MARK: - Device

    public func info() throws -> DeviceInfo {
        func version(_ cmd: UInt8) throws -> String {
            let r = try transact(.device, cmd, length: 2)
            return "\(r[7]).\(r[8]).\(r[9])"
        }
        return DeviceInfo(name: model?.name ?? hid.name, transport: hid.isReceiver ? "2.4G receiver" : hid.transport,
                          viaReceiver: hid.isReceiver, firmware: try version(0x80), hardware: try version(0x81),
                          pid: keyboardPID, modelName: model?.name ?? "Unknown TK51G (PID \(String(format: "0x%04X", keyboardPID)))")
    }

    /// Win key lock and Mac mode, as toggled on the keyboard itself.
    public func locks() throws -> (winLock: Bool, macMode: Bool) {
        let r = try transact(.key, 0x86, length: 2)
        return (r[7] == 1, r[8] == 1)
    }

    public func battery() throws -> BatteryState {
        let r = try transact(.power, 0x80, length: 4)
        return BatteryState(status: .init(rawValue: r[7]), level: Int(r[8]))
    }

    /// Idle time before the keyboard goes to sleep (backlight off, wireless link dropped), in seconds.
    /// 0 = never. Stored per profile, like the Windows app's "Sleep time".
    public func sleepSeconds(profile: UInt8 = 1) throws -> Int {
        let r = try transact(.power, 0x82, profile: profile, length: 3)
        return r[7] == 0 ? 0 : Int(r.uint16(at: 8))
    }

    /// The values the Windows app offers, in minutes (0 = never).
    public static let sleepMinutesChoices = [1, 3, 5, 10, 20, 30, 40, 0]

    /// Sets the idle time before the keyboard sleeps; 0 = never. The Windows app sends
    /// `[7]` enabled, `[8..9]` seconds (big-endian) for the current profile.
    public func setSleepSeconds(_ seconds: Int, profile: UInt8 = 1) throws {
        let s = UInt16(clamping: max(seconds, 0))
        try transact(.power, 0x02, profile: profile, payload: [s == 0 ? 0 : 1, UInt8(s >> 8), UInt8(s & 0xFF)])
        // The keyboard acknowledges, then ignores requests for a moment (it is probably saving the setting):
        // a GET sent right after it never gets an answer. 0.5 s later it answers normally (tested 2026-10-25).
        Thread.sleep(forTimeInterval: 0.6)
    }

    // MARK: - Profiles

    public func profileIDs() throws -> [UInt8] { try multiGet(.profile, 0x80) }

    public func activeProfile() throws -> UInt8 {
        let r = try transact(.profile, 0x83)
        return max(r.profile, 1)
    }

    public func setActiveProfile(_ id: UInt8) throws {
        try transact(.profile, 0x03, profile: max(id, 1))
    }

    // MARK: - Lighting

    public func ledRegions() throws -> [UInt8] { try multiGet(.lighting, 0x80) }

    public func ledAttributes(_ region: UInt8) throws -> LEDAttributes {
        let r = try transact(.lighting, 0x81, payload: [region])
        let n = Int(r[12])
        return LEDAttributes(region: region, type: r[8], fps: Int(r[9]), rows: Int(r[10]), columns: Int(r[11]),
                             effects: Array(r.bytes[13..<min(13 + n, r.bytes.count)]))
    }

    public func effect(region: UInt8, profile: UInt8) throws -> EffectState {
        let r = try transact(.lighting, 0x82, profile: profile, payload: [region])
        let n = min(Int(r[11]), 5)
        let colors = (0..<n).map { i in RGB(r[12 + i * 3], r[13 + i * 3], r[14 + i * 3]) }
        return EffectState(effect: r[8], flag: r[9], speed: r[10], colors: colors)
    }

    public func setEffect(_ s: EffectState, region: UInt8, profile: UInt8) throws {
        let colors = Array(s.colors.prefix(5))
        let changesColor = !colors.isEmpty && lastColorWrite[region]?.colors != colors
        if changesColor, let last = lastColorWrite[region] {
            let wait = Self.colorWriteSpacing + last.time.timeIntervalSinceNow
            if wait > 0 {
                log?(String(format: "(waiting %.2f s between color changes)", wait))
                Thread.sleep(forTimeInterval: wait)
            }
        } else {
            waitAfterColorWrite()
        }
        defer {
            if !colors.isEmpty { lastColorWrite[region] = (Date(), colors) }
            if changesColor { lastAnyColorWrite = Date() }
        }
        // The firmware acknowledges but ignores a write with speed 0.
        let speed = min(max(s.speed, speedRange.lowerBound), speedRange.upperBound)
        let payload = [region, s.effect, s.flag, speed, UInt8(colors.count)] + colors.flatMap(\.bytes)
        try transact(.lighting, 0x02, profile: profile, payload: payload)
    }

    /// Current brightness, 0...255.
    ///
    /// Always read with profile 0. A read with profile 1 returns the value from *before* the
    /// last write (the firmware seems to persist it lazily), so the UI showed stale levels.
    /// Measured on 2026-10-19: after SET 190 then SET 255, profile 0 read 255 and profile 1 read 190.
    public func brightness(region: UInt8) throws -> UInt8 {
        try transact(.lighting, 0x83, profile: 0, payload: [region], length: 2)[8]
    }

    public func setBrightness(_ level: UInt8, region: UInt8, profile: UInt8) throws {
        waitAfterColorWrite()
        try transact(.lighting, 0x03, profile: profile, payload: [region, level])
    }

    /// Streams one per-key frame. The region must be in effect 18 (`LightingEffect.streamingID`)
    /// for it to show. Frames live in RAM: they survive the backlight's idle-off,
    /// but not a power cycle.
    public func sendFrame(_ rows: [[RGB]], region: UInt8 = LEDRegion.backlight.rawValue) throws {
        try sendPackets(PacketBuilder.framePackets(reportID: hid.reportID, target: target, region: region, rows: rows))
    }

    /// Sends prebuilt per-key frame packets (class 3, cmd 0x04 only), without waiting for replies.
    public func sendPackets(_ packets: [Packet]) throws {
        for p in packets {
            guard p.commandClass == CommandClass.lighting.rawValue, p.command == 0x04 else {
                throw BAKeyError.blocked("sendPackets only sends frame packets")
            }
            log?("> \(p.hex)")
            try hid.setFeature(p)
        }
    }
}
