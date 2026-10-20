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

    var body: some View {
        // Keyboard (this app's own reading), then any pinned Bluetooth devices, e.g. the mouse.
        var label = Text(Image(systemName: store.status == .connected ? "keyboard.fill" : "keyboard"))
        if store.showBatteryInMenuBar, let level = store.battery?.level {
            label = label + Text(" \(level)%")
        }
        for d in batteries.pinnedDevices where store.showBatteryInMenuBar {
            guard let p = d.primary else { continue }
            label = label + Text("  ") + Text(Image(systemName: d.symbol)) + Text(" \(p)%")
        }
        return label
    }
}
