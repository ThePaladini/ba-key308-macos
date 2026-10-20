import BAKeyCore
import SwiftUI

@main
struct BAKeyMenuApp: App {
    @StateObject private var store = KeyboardStore()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(store)
        } label: {
            MenuBarLabel(store: store)
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

    var body: some View {
        if store.showBatteryInMenuBar, let level = store.battery?.level {
            Text(Image(systemName: "keyboard")) + Text(" \(level)%")
        } else {
            Image(systemName: store.status == .connected ? "keyboard.fill" : "keyboard")
        }
    }
}
