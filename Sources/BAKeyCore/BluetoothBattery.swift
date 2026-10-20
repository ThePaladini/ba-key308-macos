import Foundation

/// Battery levels of any connected Bluetooth device (mice, keyboards, headphones, controllers).
///
/// Source: `system_profiler SPBluetoothDataType -json`. macOS reads the standard Bluetooth Battery
/// Service (and Apple's own protocol for AirPods) and reports it as `device_batteryLevelMain`, or
/// `…Left` / `…Right` / `…Case`. This needs no Bluetooth permission, takes ~0.1 s, and works for any
/// brand, as long as the device reports battery over Bluetooth. 2.4 GHz receivers have no standard,
/// so they don't show up. See docs/BATTERIES.md.
public struct BluetoothBatteryDevice: Identifiable, Equatable, Sendable {
    public struct Level: Equatable, Sendable { public let label: String; public let percent: Int }

    /// Bluetooth address when available (stable), otherwise the name.
    public let id: String
    public let name: String
    /// macOS "minor type": Mouse, Keyboard, Headphones, Gamepad, ...
    public let kind: String?
    public let levels: [Level]
    /// Bluetooth vendor ID when macOS reports one (e.g. 0x260D for the Dareu-platform keyboards).
    public let vendorID: Int?

    /// A keyboard this app already controls (its battery is read directly, over USB too).
    public var isDareuKeyboard: Bool { vendorID == BAKey.vendorID }

    /// The level shown in compact places: the main battery, else the lower earbud, else the case.
    public var primary: Int? {
        levels.first { $0.label.isEmpty }?.percent
            ?? levels.filter { $0.label != "Case" }.map(\.percent).min()
            ?? levels.first?.percent
    }

    public var isMouse: Bool { kind?.localizedCaseInsensitiveContains("mouse") == true || name.localizedCaseInsensitiveContains("mouse") }

    public var symbol: String {
        let k = (kind ?? "").lowercased()
        let n = name.lowercased()
        if isMouse { return "computermouse" }
        if k.contains("keyboard") { return "keyboard" }
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if k.contains("headphone") || k.contains("headset") { return "headphones" }
        if k.contains("game") || k.contains("joystick") { return "gamecontroller" }
        if n.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
        return "dot.radiowaves.left.and.right"
    }

    /// Parses `system_profiler SPBluetoothDataType -json` output; connected devices only.
    public static func parse(_ data: Data) -> [BluetoothBatteryDevice] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        var out: [BluetoothBatteryDevice] = []
        for controller in controllers {
            for entry in controller["device_connected"] as? [[String: Any]] ?? [] {
                for (name, value) in entry {
                    guard let info = value as? [String: Any] else { continue }
                    var levels: [Level] = []
                    for (key, label) in [("device_batteryLevelMain", ""), ("device_batteryLevel", ""),
                                         ("device_batteryLevelLeft", "L"), ("device_batteryLevelRight", "R"),
                                         ("device_batteryLevelCase", "Case")] {
                        if let s = info[key] as? String, let p = Int(s.filter(\.isNumber)) {
                            if !(label.isEmpty && levels.contains { $0.label.isEmpty }) { levels.append(Level(label: label, percent: p)) }
                        }
                    }
                    guard !levels.isEmpty else { continue }
                    let vid = (info["device_vendorID"] as? String).flatMap { Int($0.replacingOccurrences(of: "0x", with: ""), radix: 16) }
                    out.append(BluetoothBatteryDevice(id: info["device_address"] as? String ?? name, name: name,
                                                      kind: info["device_minorType"] as? String, levels: levels, vendorID: vid))
                }
            }
        }
        return out.sorted { ($0.isMouse ? 0 : 1, $0.name) < ($1.isMouse ? 0 : 1, $1.name) }
    }
}

