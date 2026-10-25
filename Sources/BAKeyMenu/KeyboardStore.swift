import BAKeyCore
import Foundation
import ServiceManagement
import SwiftUI

/// App state. Mirrors what is stored on the keyboard and pushes changes back to it.
///
/// Every UI change updates the model immediately (so the UI feels instant) and then
/// sends the command after a short debounce, so dragging a slider sends one
/// command instead of fifty.
@MainActor
final class KeyboardStore: ObservableObject {
    enum Status: Equatable {
        case searching
        case connecting
        case connected
        case failed(String)
    }

    struct RegionModel: Equatable {
        var region: LEDRegion
        var effects: [LightingEffect] = []
        var state = EffectState(effect: 0)
        /// Percent, 0...100.
        var brightness: Double = 100
    }

    @Published private(set) var status: Status = .searching
    @Published private(set) var info: DeviceInfo?
    @Published private(set) var battery: BatteryState?
    /// Idle seconds before the keyboard sleeps (0 = never); nil if the keyboard doesn't report it.
    @Published private(set) var sleepSeconds: Int?
    @Published private(set) var profiles: [UInt8] = [1]
    @Published private(set) var profile: UInt8 = 1
    @Published private(set) var regions: [LEDRegion: RegionModel] = [:]
    @Published private(set) var sendingFrame = false
    @Published var lastError: String?

    /// Per-key colors for the painter, keyed by firmware key ID.
    @Published private(set) var keyColors: [Int: RGB]
    @Published var livePreview: Bool { didSet { defaults.set(livePreview, forKey: Keys.live) } }
    @Published var restoreFrameOnConnect: Bool { didSet { defaults.set(restoreFrameOnConnect, forKey: Keys.restore) } }
    @Published var showBatteryInMenuBar: Bool { didSet { defaults.set(showBatteryInMenuBar, forKey: Keys.battery) } }
    @Published private(set) var savedLayouts: [String: [Int: RGB]] = [:]

    /// Mac-rendered backlight effect, or nil when the keyboard runs a firmware effect / painted keys.
    @Published private(set) var softEffect: SoftEffect?
    /// Speed multiplier for Mac effects (1 = about the firmware's default pace).
    @Published var softSpeed: Double { didSet { defaults.set(softSpeed, forKey: Keys.softSpeed) } }
    /// nil = rainbow / random colors.
    @Published private(set) var softColor: RGB?
    /// Frames per second the Mac effect is actually reaching (limited by the link).
    @Published private(set) var softFPS: Double = 0
    private var engineTask: Task<Void, Never>?
    /// The engine parks here while a key-press effect has nothing to animate; a key press or a colour change resumes it.
    private var engineWaiter: CheckedContinuation<Void, Never>?
    private var connectFailures = 0
    /// What the painter last sent; reset whenever something else draws on the keys.
    private var paintDiffer = FrameDiffer()
    private var keyMonitor: KeyPressMonitor?
    private var pendingPresses: [KeyDef] = []
    /// A reactive Mac effect is selected but macOS hasn't granted Input Monitoring.
    @Published private(set) var needsInputMonitoring = false
    @Published private(set) var keyMonitorFailure: String?
    @Published private(set) var keySourceNote: String?

    private let monitor = DeviceMonitor()
    private let worker = HIDWorker()
    private let defaults = UserDefaults.standard
    private var debouncers: [String: Task<Void, Never>] = [:]
    private var frameDirty = false
    private var batteryTimer: Timer?
    /// Over the 2.4G receiver no HID event marks the keyboard sleeping or waking, so the receiver is asked.
    private var receiverTimer: Timer?
    private var keyboardAwake = true

    private enum Keys {
        static let colors = "keyColors"
        static let layouts = "savedLayouts"
        static let live = "livePreview"
        static let restore = "restoreFrameOnConnect"
        static let battery = "showBatteryInMenuBar"
        static let softEffect = "softEffect"
        static let softSpeed = "softSpeed"
        static let softColor = "softColor"
    }

    init() {
        keyColors = Self.decode(UserDefaults.standard.dictionary(forKey: Keys.colors) as? [String: String])
            ?? Presets.wasd
        livePreview = defaults.object(forKey: Keys.live) as? Bool ?? true
        restoreFrameOnConnect = defaults.object(forKey: Keys.restore) as? Bool ?? true
        showBatteryInMenuBar = defaults.object(forKey: Keys.battery) as? Bool ?? true
        softEffect = SoftEffect(rawValue: defaults.integer(forKey: Keys.softEffect))
        softSpeed = defaults.object(forKey: Keys.softSpeed) as? Double ?? 0.5
        softColor = defaults.string(forKey: Keys.softColor).flatMap(RGB.init(hex:))
        if let raw = defaults.dictionary(forKey: Keys.layouts) as? [String: [String: String]] {
            savedLayouts = raw.compactMapValues(Self.decode)
        }

        monitor.onChange = { [weak self] in
            AppLog.write("HID devices changed")
            Task { @MainActor in self?.scheduleReconnect() }
        }
        scheduleReconnect()
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshBattery() }
        }
    }

    // MARK: - Connection

    /// Devices come and go in bursts (one event per HID interface), so wait a moment.
    func scheduleReconnect() {
        debounce("connect", delay: 0.6) { [weak self] in await self?.reconnect() }
    }

    func reconnect() async {
        receiverTimer?.invalidate()
        receiverTimer = nil
        let candidates = monitor.candidates()
        guard !candidates.isEmpty else {
            stopEngine()
            worker.disconnect()
            info = nil
            battery = nil
            status = .searching
            return
        }
        stopEngine()
        paintDiffer.reset()
        status = .connecting
        AppLog.write("connect: \(candidates.count) candidate(s): " + candidates.map { "\($0.name) [\($0.transport), PID \(String(format: "0x%04X", $0.productID)), rid \($0.reportID)]" }.joined(separator: ", "))
        do {
            info = try await worker.connect(to: candidates)
            AppLog.write("connected: \(info?.name ?? "?") via \(info?.transport ?? "?") fw \(info?.firmware ?? "?")"
                         + (connectFailures > 0 ? " after \(connectFailures) failed attempt(s)" : ""))
            connectFailures = 0
            // The key layout (painter, presets, Mac effects) follows the connected model.
            KeyLayout.current = info.flatMap { KeyboardModel.forPID($0.pid) } ?? .baKey308
            try await loadAll()
            status = .connected
            lastError = nil
            if info?.viaReceiver == true {
                keyboardAwake = true
                reapplyAfterWake()
                receiverTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                    Task { @MainActor in await self?.checkKeyboardAwake() }
                }
            }
            let streaming = regions[.backlight]?.state.effect == LightingEffect.streamingID
            if streaming, softEffect != nil {
                startEngine()
            } else if !streaming {
                setSoftEffect(nil) // a firmware effect was chosen elsewhere (Fn keys, Windows app)
            } else if restoreFrameOnConnect {
                requestFrameSend()
            }
        } catch {
            status = .failed(error.localizedDescription)
            // Retry on our own: e.g. switching the keyboard from Bluetooth to 2.4G removes the BLE device
            // while the receiver, already plugged in, has no keyboard paired yet; or the keyboard sleeps
            // behind the receiver. No HID event arrives when it comes back, so without this the app stayed
            // "failed". Back off 3, 6, 10 s (capped at 10 s, so after waking the keyboard reconnects within seconds).
            connectFailures += 1
            let delay = min(3 * pow(2, Double(min(connectFailures - 1, 2))), 10)
            if connectFailures <= 3 || connectFailures % 20 == 0 {
                AppLog.write("connect failed (#\(connectFailures)): \(error.localizedDescription); retrying in \(Int(delay)) s")
            }
            debounce("connect", delay: delay) { [weak self] in await self?.reconnect() }
        }
    }

    /// Reads everything the UI shows from the keyboard.
    func loadAll() async throws {
        let snapshot = try await worker.run { kb -> (UInt8, [UInt8], BatteryState?, Int?, [LEDRegion: RegionModel]) in
            let profile = try kb.activeProfile()
            let profiles = (try? kb.profileIDs()) ?? [profile]
            let battery = try? kb.battery()
            let sleep = try? kb.sleepSeconds(profile: profile)
            var regions: [LEDRegion: RegionModel] = [:]
            for region in LEDRegion.allCases {
                guard let attrs = try? kb.ledAttributes(region.rawValue) else { continue }
                var m = RegionModel(region: region)
                m.effects = attrs.effects.map(LightingEffect.init(id:))
                m.state = try kb.effect(region: region.rawValue, profile: profile)
                m.brightness = Double(try kb.brightness(region: region.rawValue)) / 2.55
                regions[region] = m
            }
            return (profile, profiles, battery, sleep, regions)
        }
        (profile, profiles, battery, sleepSeconds, regions) = snapshot
        if profiles.isEmpty { profiles = [profile] }
    }

    func refreshBattery() async {
        guard status == .connected, keyboardAwake else { return }
        if let b = try? await worker.run({ try $0.battery() }) { battery = b }
    }

    /// Over the 2.4G receiver, a keyboard that wakes from sleep lights its side light again even when the
    /// stored effect (and what it reports) is Off, and it ignores a write identical to the stored one
    /// (tested 2026-10-25; docs/PROTOCOL.md). Bluetooth isn't affected. Re-send the side light as two
    /// writes, the first with a different speed byte, so the second (the real state) is applied.
    /// The keyboard relights the side light a moment *after* it reconnects, so a write sent right away can be
    /// overwritten (seen 2026-10-25: re-applied 0.27 s after the wake, light still on). Send it 1.5 s and 5 s later.
    private func reapplyAfterWake() {
        for delay in [1.5, 5.0] {
            Task {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1e9))
                guard status == .connected, keyboardAwake else { return }
                await reapplySideLight()
            }
        }
    }

    private func reapplySideLight() async {
        guard let side = regions[.sidelight]?.state else { return }
        var nudge = side
        nudge.speed = side.speed == 3 ? 2 : 3
        let profile = self.profile
        do {
            try await worker.run { kb in
                try kb.setEffect(nudge, region: LEDRegion.sidelight.rawValue, profile: profile)
                try kb.setEffect(side, region: LEDRegion.sidelight.rawValue, profile: profile)
            }
            AppLog.write("side light re-applied (\(LightingEffect(id: side.effect).name))")
        } catch { report(error) }
    }

    private func checkKeyboardAwake() async {
        guard status == .connected, info?.viaReceiver == true,
              let awake = try? await worker.run({ try $0.keyboardAwakeBehindReceiver() }) else { return }
        guard awake != keyboardAwake else { return }
        keyboardAwake = awake
        AppLog.write(awake ? "keyboard woke (2.4G)" : "keyboard asleep (2.4G)")
        if awake {
            if lastError?.hasPrefix("The keyboard is asleep") == true { lastError = nil }
            reapplyAfterWake()
            await refreshBattery()
        }
    }

    func refresh() {
        Task {
            do { try await loadAll(); lastError = nil } catch { report(error) }
        }
    }

    // MARK: - Lighting

    func setEffect(_ id: UInt8, for region: LEDRegion) {
        guard var m = regions[region] else { return }
        if region == .backlight { setSoftEffect(nil) }
        let effect = LightingEffect(id: id)
        m.state.effect = id
        if m.state.speed == 0 { m.state.speed = 2 }
        if !effect.acceptsColor { m.state.colors = [] }
        if id == 1 && m.state.colors.isEmpty { m.state.colors = [.white] } // Static needs a color
        regions[region] = m
        pushEffect(region, delay: 0)
        if effect.isStreaming && region == .backlight { requestFrameSend() }
    }

    /// `nil` = firmware palette (rainbow).
    func setColor(_ color: RGB?, for region: LEDRegion) {
        guard var m = regions[region] else { return }
        m.state.colors = color.map { [$0] } ?? []
        regions[region] = m
        // Send only once the color settles: several quick adjustments (mixer drags, swatch clicks)
        // become one write. Rapid color writes freeze the firmware and drop Bluetooth
        // (see KeyboardClient.colorWriteSpacing).
        pushEffect(region, delay: 1.0)
    }

    func setSpeed(_ speed: Double, for region: LEDRegion) {
        guard var m = regions[region] else { return }
        m.state.speed = UInt8(min(max(speed.rounded(), 1), 255))
        regions[region] = m
        pushEffect(region)
    }

    func setReversed(_ reversed: Bool, for region: LEDRegion) {
        guard var m = regions[region] else { return }
        m.state.flag = reversed ? 1 : 0
        regions[region] = m
        pushEffect(region, delay: 0)
    }

    func setBrightness(_ percent: Double, for region: LEDRegion) {
        guard var m = regions[region] else { return }
        m.brightness = percent
        regions[region] = m
        let level = UInt8((percent * 2.55).rounded())
        let profile = self.profile
        debounce("brightness-\(region.rawValue)", delay: 0.2) { [weak self] in
            do {
                try await self?.worker.run { try $0.setBrightness(level, region: region.rawValue, profile: profile) }
            } catch { self?.report(error) }
        }
    }

    /// Sleep time in minutes, 0 = never. Stored on the keyboard (per profile).
    func setSleep(minutes: Int) {
        guard keyboardAwake else {
            lastError = "The keyboard is asleep. Press a key, then choose again."
            return
        }
        let previous = sleepSeconds
        sleepSeconds = minutes * 60
        let profile = self.profile
        Task {
            do {
                try await worker.run { try $0.setSleepSeconds(minutes * 60, profile: profile) }
                sleepSeconds = try await worker.run { try $0.sleepSeconds(profile: profile) }
            } catch {
                sleepSeconds = previous
                report(error)
            }
        }
    }

    func setProfile(_ id: UInt8) {
        profile = id
        Task {
            do {
                try await worker.run { try $0.setActiveProfile(id) }
                try await loadAll()
            } catch { report(error) }
        }
    }

    private func pushEffect(_ region: LEDRegion, delay: TimeInterval = 0.25) {
        guard let state = regions[region]?.state else { return }
        let profile = self.profile
        debounce("effect-\(region.rawValue)", delay: delay) { [weak self] in
            do {
                try await self?.worker.run { try $0.setEffect(state, region: region.rawValue, profile: profile) }
            } catch { self?.report(error) }
        }
    }

    // MARK: - Mac-rendered effects

    func setSoftEffect(_ effect: SoftEffect?) {
        softEffect = effect
        defaults.set(effect?.rawValue ?? 0, forKey: Keys.softEffect)
        if effect != nil { startEngine() } else { stopEngine() }
    }

    func setSoftColor(_ color: RGB?) {
        softColor = color
        defaults.set(color?.hex, forKey: Keys.softColor)
        wakeEngine()
    }

    private func wakeEngine() {
        engineWaiter?.resume()
        engineWaiter = nil
    }

    /// Render loop: draws a frame, sends it, repeats. Sending is awaited, so the loop runs as
    /// fast as the link allows (about 1 fps over Bluetooth, capped at 30 fps on USB).
    private func startEngine() {
        stopEngine()
        guard let effect = softEffect, status == .connected else { return }
        AppLog.write("engine start: \(effect.name)")
        if effect.isReactive { startKeyMonitor() }
        let profile = self.profile
        if var m = regions[.backlight] {
            m.state = EffectState(effect: LightingEffect.streamingID)
            regions[.backlight] = m
        }
        engineTask = Task { [weak self] in
            do {
                try await self?.worker.run {
                    try $0.setEffect(EffectState(effect: LightingEffect.streamingID),
                                     region: LEDRegion.backlight.rawValue, profile: profile)
                }
            } catch { self?.report(error); return }

            var renderer = SoftRenderer(effect: effect)
            var last = Date()
            var fpsWindow: [Date] = []
            // Only changed rows are sent (or one fill packet). On a slow link (Bluetooth, ~154 ms
            // per packet) one row per iteration, most-changed first, so key presses show quickly.
            var differ = FrameDiffer()
            var secondsPerPacket = 0.0
            var statFrames = 0, statPackets = 0, statStart = Date()
            while !Task.isCancelled, let self {
                if -statStart.timeIntervalSinceNow >= 5 {
                    AppLog.write(String(format: "engine: %d frames, %d packets in 5 s, %.1f ms/packet", statFrames, statPackets, secondsPerPacket * 1000))
                    statFrames = 0; statPackets = 0; statStart = Date()
                }
                let now = Date()
                for key in self.pendingPresses { renderer.press(key, color: self.softColor) }
                self.pendingPresses.removeAll()
                let slowLink = secondsPerPacket > 0.03
                renderer.compact = slowLink
                let frame = renderer.frame(dt: now.timeIntervalSince(last), speed: self.softSpeed, color: self.softColor)
                last = now
                var sent: [Packet] = []
                do {
                    let snapshot = differ
                    sent = try await self.worker.run { kb -> [Packet] in
                        let packets = snapshot.plan(frame, reportID: kb.hid.reportID, target: kb.target,
                                                    maxPackets: slowLink ? 1 : .max,
                                                    minScore: slowLink ? 120 : 1,
                                                    allowFill: kb.supportsFillPacket)
                        try kb.sendPackets(packets)
                        return packets
                    }
                    if !sent.isEmpty {
                        statFrames += 1; statPackets += sent.count
                        differ.applied(sent, frame: frame)
                        let per = Date().timeIntervalSince(now) / Double(sent.count)
                        secondsPerPacket = secondsPerPacket == 0 ? per : secondsPerPacket * 0.8 + per * 0.2
                        fpsWindow.append(Date())
                    }
                } catch {
                    self.report(error)
                    return
                }
                fpsWindow.removeAll { $0.timeIntervalSinceNow < -3 }
                // softFPS is @Published: every assignment redraws the panel and the menu bar item, so only on change.
                let fps = (Double(fpsWindow.count) / 3).rounded()
                if fps != self.softFPS { self.softFPS = fps }
                // A key-press effect with nothing left to animate: sleep until a key is pressed (or the colour
                // changes) instead of rendering identical frames 30 times a second. This kept the CPU busy for
                // hours (Activity Monitor, 2026-10-25: energy impact ~1000 while idle).
                if renderer.isIdle, sent.isEmpty, self.pendingPresses.isEmpty {
                    if self.softFPS != 0 { self.softFPS = 0 }
                    fpsWindow.removeAll()
                    await withCheckedContinuation { self.engineWaiter = $0 }
                    last = Date()
                    continue
                }
                let spent = Date().timeIntervalSince(now)
                if spent < 1.0 / 30 { try? await Task.sleep(nanoseconds: UInt64((1.0 / 30 - spent) * 1e9)) }
            }
        }
    }

    private func stopEngine() {
        if engineTask != nil { paintDiffer.reset(); AppLog.write("engine stop") }
        engineTask?.cancel()
        engineTask = nil
        wakeEngine() // a parked loop wakes, sees the cancellation and ends
        softFPS = 0
        keyMonitor?.stop()
        pendingPresses.removeAll()
    }

    /// Listens for key presses on the BA-KEY308 for reactive effects.
    private func startKeyMonitor() {
        // Fresh monitor each time: the best source can change with the transport
        // (Karabiner seizes the USB keyboard but not the Bluetooth one).
        keyMonitor?.stop()
        keyMonitor = nil
        let m = KeyPressMonitor()
        m.onKeyDown = { [weak self] usage in
            Task { @MainActor in
                guard let self, let key = SoftRenderer.keyForUsage[usage] else { return }
                self.pendingPresses.append(key)
                self.wakeEngine()
            }
        }
        keyMonitor = m
        needsInputMonitoring = !(keyMonitor?.start() ?? false)
        AppLog.write("key monitor: source \(String(describing: keyMonitor?.source)) \(keyMonitor?.lastFailure ?? "")")
        keyMonitorFailure = keyMonitor?.lastFailure
        keySourceNote = keyMonitor?.source == .eventTap
            ? "Using macOS key events (another app such as Karabiner has the keyboard), so other keyboards trigger ripples too."
            : nil
    }

    /// Re-checks the permission (after the user enabled it in System Settings).
    func retryKeyMonitor() {
        if softEffect?.isReactive == true { startKeyMonitor() }
    }

    func openInputMonitoringSettings() {
        KeyPressMonitor.requestAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Per-key painter

    func paint(_ keyID: Int, _ color: RGB) {
        if softEffect != nil { setSoftEffect(nil) }
        guard keyColors[keyID] != color else { return }
        keyColors[keyID] = color
        colorsChanged()
    }

    func setAll(_ colors: [Int: RGB]) {
        if softEffect != nil { setSoftEffect(nil) }
        keyColors = colors
        colorsChanged()
    }

    func fill(_ color: RGB) {
        setAll(Dictionary(uniqueKeysWithValues: KeyLayout.keys.filter { !$0.cells.isEmpty }.map { ($0.id, color) }))
    }

    func saveLayout(named name: String) {
        savedLayouts[name] = keyColors
        persistLayouts()
    }

    func deleteLayout(named name: String) {
        savedLayouts[name] = nil
        persistLayouts()
    }

    /// Switches the backlight to per-key mode (if needed) and streams the current colors.
    func applyFrame() {
        if softEffect != nil { setSoftEffect(nil) }
        requestFrameSend()
    }

    private func colorsChanged() {
        defaults.set(Self.encode(keyColors), forKey: Keys.colors)
        if livePreview { debounce("frame", delay: 0.15) { [weak self] in self?.requestFrameSend() } }
    }

    /// A full frame takes about a second over Bluetooth. While one is in flight, further
    /// changes only mark the frame dirty; the latest colors go out when it finishes.
    private func requestFrameSend() {
        guard status == .connected || status == .connecting else { return }
        if sendingFrame { frameDirty = true; return }
        sendingFrame = true
        frameDirty = false
        let frame = KeyLayout.frame(from: keyColors)
        let needsMode = regions[.backlight]?.state.effect != LightingEffect.streamingID
        let profile = self.profile
        if needsMode { paintDiffer.reset() }
        let snapshot = paintDiffer
        if needsMode, var m = regions[.backlight] {
            m.state.effect = LightingEffect.streamingID
            m.state.colors = []
            regions[.backlight] = m
        }
        Task {
            do {
                // Only the rows that changed since the last send (a big win over Bluetooth).
                let sent = try await worker.run { kb -> [Packet] in
                    if needsMode {
                        try kb.setEffect(EffectState(effect: LightingEffect.streamingID), region: LEDRegion.backlight.rawValue, profile: profile)
                    }
                    let packets = snapshot.plan(frame, reportID: kb.hid.reportID, target: kb.target,
                                                allowFill: kb.supportsFillPacket)
                    try kb.sendPackets(packets)
                    return packets
                }
                paintDiffer.applied(sent, frame: frame)
            } catch { report(error) }
            sendingFrame = false
            if frameDirty { requestFrameSend() }
        }
    }

    // MARK: - Settings

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch { report(error) }
            objectWillChange.send()
        }
    }

    // MARK: - Helpers

    private func debounce(_ key: String, delay: TimeInterval, _ action: @escaping @MainActor () async -> Void) {
        debouncers[key]?.cancel()
        debouncers[key] = Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if Task.isCancelled { return }
            }
            await action()
        }
    }

    private func report(_ error: Error) {
        lastError = error.localizedDescription
        AppLog.write("error: \(error.localizedDescription)")
        // A vanished device, a dead handle or a keyboard that stopped answering (it slept or moved to
        // another mode behind the receiver): reconnect instead of staying stuck.
        switch error {
        case BAKeyError.noDevice, BAKeyError.ioFailed, BAKeyError.timeout, BAKeyError.noKeyboardBehindReceiver:
            scheduleReconnect()
        default:
            break
        }
    }

    private func persistLayouts() {
        defaults.set(savedLayouts.mapValues(Self.encode), forKey: Keys.layouts)
    }

    private static func encode(_ colors: [Int: RGB]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: colors.map { (String($0.key), $0.value.hex) })
    }

    private static func decode(_ raw: [String: String]?) -> [Int: RGB]? {
        guard let raw else { return nil }
        var out: [Int: RGB] = [:]
        for (k, v) in raw { if let id = Int(k), let c = RGB(hex: v) { out[id] = c } }
        return out
    }
}
