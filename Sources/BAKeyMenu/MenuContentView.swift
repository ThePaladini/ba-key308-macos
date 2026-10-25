import BAKeyCore
import SwiftUI

/// The panel that opens from the menu bar icon.
struct MenuContentView: View {
    @EnvironmentObject var store: KeyboardStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HeaderView()

            if store.status == .connected {
                Divider()
                RegionControls(region: .backlight)
                Button {
                    openWindow(id: "painter")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("Paint individual keys…", systemImage: "paintbrush.pointed")
                }

                Divider()
                RegionControls(region: .sidelight)

                if store.profiles.count > 1 {
                    Divider()
                    Picker("Profile", selection: Binding(get: { store.profile }, set: { store.setProfile($0) })) {
                        ForEach(store.profiles, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            } else {
                ConnectionHelp()
            }

            Divider()
            BluetoothBatteriesSection()

            if let error = store.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            FooterView()
        }
        .padding(14)
        .frame(width: 330)
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { g in
            Color.clear.preference(key: ContentHeightKey.self, value: g.size.height)
        })
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
        .background(WindowHeightFitter(height: contentHeight))
    }

    @State private var contentHeight: CGFloat = 0
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Works around a SwiftUI bug: a `MenuBarExtra` with `.window` style grows when its content gets
/// taller but never shrinks back, leaving an empty band at the bottom (e.g. after switching from a
/// Mac effect to a keyboard effect). This resizes the panel to the measured content height,
/// keeping its top edge under the menu bar.
private struct WindowHeightFitter: NSViewRepresentable {
    let height: CGFloat

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let target = height
        DispatchQueue.main.async {
            guard target > 0, let window = view.window else { return }
            let contentRect = window.contentRect(forFrameRect: window.frame)
            guard abs(contentRect.height - target) > 0.5 else { return }
            var frame = window.frameRect(forContentRect: NSRect(x: contentRect.minX, y: contentRect.maxY - target,
                                                                width: contentRect.width, height: target))
            frame.origin.y = window.frame.maxY - frame.height
            window.setFrame(frame, display: true, animate: false)
        }
    }
}

private struct HeaderView: View {
    @EnvironmentObject var store: KeyboardStore

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "keyboard")
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.info?.name ?? "BA-KEY308").font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let b = store.battery {
                Label("\(b.level)%", systemImage: batteryIcon(b))
                    .font(.callout)
                    .help(b.status.map { "\($0)".capitalized } ?? "")
            }
        }
    }

    private var subtitle: String {
        switch store.status {
        case .searching: return "Not connected"
        case .connecting: return "Connecting…"
        case .failed(let msg): return msg
        case .connected:
            guard let i = store.info else { return "Connected" }
            return "\(i.transport) · firmware \(i.firmware)"
        }
    }

    private func batteryIcon(_ b: BatteryState) -> String {
        if b.status == .charging { return "battery.100.bolt" }
        switch b.level {
        case 76...: return "battery.100"
        case 51...: return "battery.75"
        case 26...: return "battery.50"
        case 11...: return "battery.25"
        default: return "battery.0"
        }
    }
}

private struct ConnectionHelp: View {
    @EnvironmentObject var store: KeyboardStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if store.status == .connecting {
                ProgressView().controlSize(.small)
            }
            Text("Connect the keyboard over Bluetooth, the USB cable or the 2.4G receiver. Press a key if it is asleep.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try again") { store.scheduleReconnect() }
        }
    }
}

/// Effect, color, speed, direction and brightness for one lighting region.
struct RegionControls: View {
    let region: LEDRegion
    @EnvironmentObject var store: KeyboardStore

    /// Picker tags: firmware effect IDs (0...255) and `SoftEffect` raw values (200+, shifted to 1000+ to avoid clashes).
    private static let softTagOffset = 1000

    var body: some View {
        if let m = store.regions[region] {
            let effect = LightingEffect(id: m.state.effect)
            let soft = region == .backlight ? store.softEffect : nil
            VStack(alignment: .leading, spacing: 8) {
                Text(region.name).font(.subheadline.weight(.semibold))

                Picker("Effect", selection: Binding(
                    get: { soft.map { $0.rawValue + Self.softTagOffset } ?? Int(m.state.effect) },
                    set: { tag in
                        if tag >= Self.softTagOffset {
                            store.setSoftEffect(SoftEffect(rawValue: tag - Self.softTagOffset))
                        } else {
                            store.setEffect(UInt8(tag), for: region)
                        }
                    })) {
                    Section("Keyboard effects") {
                        ForEach(m.effects) { Text($0.name).tag(Int($0.id)) }
                    }
                    if region == .backlight {
                        Section("Mac effects (adjustable)") {
                            ForEach(SoftEffect.allCases) { Text($0.name).tag($0.rawValue + Self.softTagOffset) }
                        }
                    }
                }
                .labelsHidden()

                if soft != nil {
                    SoftEffectControls()
                } else {
                    firmwareControls(m, effect)
                }
            }
        }
    }

    @ViewBuilder
    private func firmwareControls(_ m: KeyboardStore.RegionModel, _ effect: LightingEffect) -> some View {
                if effect.acceptsColor {
                    SwatchRow(selected: m.state.colors.first,
                              allowsRainbow: effect.id != 1,
                              onSelect: { store.setColor($0, for: region) })
                }

                if effect.hasSpeed {
                    // Logarithmic over the firmware's full 1...255 range (the Windows app only uses 1...3).
                    LabeledContent("Speed") {
                        Slider(value: Binding(get: { log(Double(max(m.state.speed, 1))) },
                                              set: { store.setSpeed(exp($0), for: region) }),
                               in: 0...log(255.0))
                    }
                    Text(m.state.speed <= 3 ? "Normal (\(max(m.state.speed, 1)))" : "Faster than the official app allows (\(m.state.speed))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if effect.hasDirection {
                    Picker("Direction", selection: Binding(get: { m.state.flag == 1 },
                                                           set: { store.setReversed($0, for: region) })) {
                        Image(systemName: "arrow.right").tag(false)
                        Image(systemName: "arrow.left").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                if effect.id != 0 {
                    LabeledContent {
                        Slider(value: Binding(get: { m.brightness }, set: { store.setBrightness($0, for: region) }),
                               in: 0...100)
                    } label: {
                        Image(systemName: "sun.max")
                    }
                }
    }
}

/// Speed, color and brightness for a Mac-rendered effect.
private struct SoftEffectControls: View {
    @EnvironmentObject var store: KeyboardStore

    var body: some View {
        if store.needsInputMonitoring {
            VStack(alignment: .leading, spacing: 6) {
                Label("Needs the Input Monitoring permission to see key presses.", systemImage: "hand.raised")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Enable “BA-KEY Menu” in System Settings → Privacy & Security → Input Monitoring. macOS may ask you to quit and reopen the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let why = store.keyMonitorFailure {
                    Text(why).font(.caption.monospaced()).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button("Open Settings") { store.openInputMonitoringSettings() }
                    Button("Check again") { store.retryKeyMonitor() }
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.15)))
        }

        if let note = store.keySourceNote, store.softEffect?.isReactive == true {
            Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }

        SwatchRow(selected: store.softColor, allowsRainbow: true, onSelect: { store.setSoftColor($0) })

        LabeledContent("Speed") {
            // Logarithmic: 0.1x ... 3x, 1x in the middle-right.
            Slider(value: Binding(get: { log10(store.softSpeed) }, set: { store.softSpeed = pow(10, $0) }),
                   in: -1...log10(3))
        }
        HStack {
            Text(String(format: "%.2fx", store.softSpeed))
            Spacer()
            Text(store.softFPS > 0 ? String(format: "%.0f updates/s", store.softFPS)
                 : store.softEffect?.isReactive == true ? "waiting for key presses" : "starting…")
        }
        .font(.caption)
        .foregroundStyle(.secondary)

        if let m = store.regions[.backlight] {
            LabeledContent {
                Slider(value: Binding(get: { m.brightness }, set: { store.setBrightness($0, for: .backlight) }), in: 0...100)
            } label: {
                Image(systemName: "sun.max")
            }
        }

        if store.info?.transport.contains("Bluetooth") == true {
            Text("Runs while this app is open. Bluetooth sends about 6 updates per second (one keyboard row each), so animations are choppier than on the USB cable.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Runs while this app is open.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Quick color choices, plus "rainbow" (= firmware palette) and a full color picker.
struct SwatchRow: View {
    let selected: RGB?
    let allowsRainbow: Bool
    let onSelect: (RGB?) -> Void

    static let colors: [RGB] = [
        RGB(255, 0, 0), RGB(255, 100, 0), RGB(255, 220, 0), RGB(0, 255, 0), RGB(0, 255, 200),
        RGB(0, 120, 255), RGB(0, 0, 255), RGB(160, 0, 255), RGB(255, 0, 140), RGB(255, 255, 255),
    ]

    @State private var showMixer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                if allowsRainbow {
                    Button { onSelect(nil) } label: {
                        Circle()
                            .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                            .frame(width: 18, height: 18)
                            .overlay(Circle().stroke(Color.primary, lineWidth: selected == nil ? 2 : 0).padding(-2))
                    }
                    .buttonStyle(.plain)
                    .help("Default colors (rainbow)")
                }
                ForEach(Self.colors, id: \.self) { c in
                    Button { onSelect(c) } label: {
                        Circle()
                            .fill(c.color)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
                            .overlay(Circle().stroke(Color.primary, lineWidth: selected == c ? 2 : 0).padding(-2))
                    }
                    .buttonStyle(.plain)
                    .help("#\(c.hex)")
                }
                Button { showMixer.toggle() } label: {
                    Image(systemName: showMixer ? "chevron.up.circle.fill" : "slider.horizontal.3")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("Mix any color")
            }
            if showMixer {
                ColorMixer(initial: selected, onCommit: { onSelect($0) })
            }
        }
    }
}

private struct FooterView: View {
    @EnvironmentObject var store: KeyboardStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Battery levels in menu bar", isOn: $store.showBatteryInMenuBar)
                .help("Keyboard, plus any Bluetooth device pinned below (e.g. the mouse)")
            Toggle("Launch at login", isOn: Binding(get: { store.launchAtLogin }, set: { store.launchAtLogin = $0 }))
            if let seconds = store.sleepSeconds, store.status == .connected {
                SleepPicker(seconds: seconds) { store.setSleep(minutes: $0) }
            }
            HStack {
                Button("Refresh") { store.refresh() }
                    .disabled(store.status != .connected)
                Spacer()
                Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .toggleStyle(.checkbox)
        .font(.callout)
    }
}

/// Idle time before the keyboard sleeps, with the Windows app's choices. A value set elsewhere (e.g. with
/// `bakey sleep 7`) is shown as an extra item so the picker never misreports it.
private struct SleepPicker: View {
    let seconds: Int
    let onSelect: (Int) -> Void

    private var choices: [Int] {
        var c = KeyboardClient.sleepMinutesChoices
        let current = seconds / 60
        if !c.contains(current) { c.insert(current, at: c.firstIndex { $0 == 0 || $0 > current } ?? c.endIndex) }
        return c
    }

    var body: some View {
        Picker("Keyboard sleeps after", selection: Binding(get: { seconds / 60 }, set: onSelect)) {
            ForEach(choices, id: \.self) { m in
                Text(m == 0 ? "Never" : "\(m) min").tag(m)
            }
        }
        .help("Idle time before the keyboard turns off its lights and, on Bluetooth or the 2.4G receiver, disconnects. Stored on the keyboard. \"Never\" drains the battery faster.")
    }
}
