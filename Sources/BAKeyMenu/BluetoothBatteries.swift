import BAKeyCore
import Foundation
import SwiftUI

@MainActor
final class BatteryMonitor: ObservableObject {
    @Published private(set) var devices: [BluetoothBatteryDevice] = []
    /// Device IDs whose level is shown next to the menu bar icon.
    @Published private(set) var pinned: Set<String>
    private var known: Set<String>
    private var timer: Timer?
    private let defaults = UserDefaults.standard

    init() {
        pinned = Set(defaults.stringArray(forKey: "batteryPinned") ?? [])
        known = Set(defaults.stringArray(forKey: "batteryKnown") ?? [])
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        Task.detached(priority: .utility) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            p.arguments = ["SPBluetoothDataType", "-json"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let parsed = BluetoothBatteryDevice.parse(data)
            await MainActor.run { self.update(parsed) }
        }
    }

    private func update(_ list: [BluetoothBatteryDevice]) {
        // Pin mice automatically the first time they appear; that is what this feature is for.
        for d in list where !known.contains(d.id) {
            known.insert(d.id)
            if d.isMouse { pinned.insert(d.id) }
        }
        defaults.set(Array(known), forKey: "batteryKnown")
        defaults.set(Array(pinned), forKey: "batteryPinned")
        if list != devices { devices = list }
    }

    func togglePin(_ d: BluetoothBatteryDevice) {
        if pinned.contains(d.id) { pinned.remove(d.id) } else { pinned.insert(d.id) }
        defaults.set(Array(pinned), forKey: "batteryPinned")
    }

    /// Devices other than the Dareu keyboard (whose battery the app reads itself).
    var others: [BluetoothBatteryDevice] { devices.filter { !$0.isDareuKeyboard } }

    /// Connected devices to show in the menu bar.
    var pinnedDevices: [BluetoothBatteryDevice] { others.filter { pinned.contains($0.id) } }
}

/// Menu section listing every Bluetooth device's battery, with a pin to show it in the menu bar.
struct BluetoothBatteriesSection: View {
    @EnvironmentObject var batteries: BatteryMonitor
    var body: some View {
        let list = batteries.others
        VStack(alignment: .leading, spacing: 6) {
            Text("Bluetooth batteries").font(.subheadline.weight(.semibold))
            if list.isEmpty {
                Text("No other connected Bluetooth device is reporting its battery.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(list) { d in
                HStack(spacing: 8) {
                    Image(systemName: d.symbol).frame(width: 18)
                    Text(d.name).lineLimit(1)
                    Spacer()
                    Text(d.levels.map { $0.label.isEmpty ? "\($0.percent)%" : "\($0.label) \($0.percent)%" }.joined(separator: "  "))
                        .monospacedDigit()
                        .foregroundStyle((d.primary ?? 100) <= 15 ? Color.red : Color.primary)
                    Button { batteries.togglePin(d) } label: {
                        Image(systemName: batteries.pinned.contains(d.id) ? "pin.fill" : "pin")
                    }
                    .buttonStyle(.plain)
                    .help("Show in the menu bar")
                }
                .font(.callout)
            }
        }
        .onAppear { batteries.refresh() }
    }
}
