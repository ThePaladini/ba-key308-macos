import BAKeyCore
import SwiftUI

@main
struct BAKeyMenuApp: App {
    @StateObject private var store = KeyboardStore()
    @StateObject private var batteries = BatteryMonitor()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(store)
                .environmentObject(batteries)
        } label: {
            MenuBarLabel(store: store, batteries: batteries)
        }
        .menuBarExtraStyle(.window)

        Window("Key Painter", id: "painter") {
            KeyPainterView()
                .environmentObject(store)
        }
        .windowResizability(.contentSize)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var store: KeyboardStore
    @ObservedObject var batteries: BatteryMonitor

    private var keyboardSymbol: String { store.status == .connected ? "keyboard.fill" : "keyboard" }

    /// "100%", then "  🖱 62%" for each pinned Bluetooth device. Empty when battery levels are off.
    private var levels: Text? {
        guard store.showBatteryInMenuBar else { return nil }
        var parts: [Text] = []
        if let level = store.battery?.level { parts.append(Text(" \(level)%")) }
        for d in batteries.pinnedDevices {
            guard let p = d.primary else { continue }
            parts.append(Text("  ") + Text(Image(systemName: d.symbol)) + Text(" \(p)%"))
        }
        return parts.isEmpty ? nil : parts.dropFirst().reduce(parts[0], +)
    }

    var body: some View {
        if let levels {
            // Icon and numbers as one Text, so the menu bar lays them out as a single item.
            Text(Image(systemName: keyboardSymbol)) + levels
        } else {
            // A Text holding only an image renders tiny or invisible in the menu bar; use a plain Image.
            Image(systemName: keyboardSymbol)
        }
    }
}
