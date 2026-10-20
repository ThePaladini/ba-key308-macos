import BAKeyCore
import SwiftUI

/// Window for coloring individual keys. Click or drag across keys to paint them.
struct KeyPainterView: View {
    @EnvironmentObject var store: KeyboardStore
    @State private var brush: Color = .red
    @State private var eyedropper = false
    @State private var newLayoutName = ""
    @State private var showingSave = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            toolbar

            KeyboardCanvas(colors: store.keyColors) { key in
                if eyedropper {
                    if let c = store.keyColors[key.id] { brush = c.color }
                    eyedropper = false
                } else {
                    store.paint(key.id, RGB(brush))
                }
            }
            .frame(width: 720, height: 720 * KeyLayout.size.height / KeyLayout.size.width)

            statusLine
        }
        .padding(18)
        .alert("Save layout", isPresented: $showingSave) {
            TextField("Name", text: $newLayoutName)
            Button("Save") {
                let name = newLayoutName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { store.saveLayout(named: name) }
                newLayoutName = ""
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            ColorPicker("Brush", selection: $brush, supportsOpacity: false)

            HStack(spacing: 4) {
                ForEach(SwatchRow.colors, id: \.self) { c in
                    Button { brush = c.color; eyedropper = false } label: {
                        RoundedRectangle(cornerRadius: 4).fill(c.color).frame(width: 18, height: 18)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.3), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
                Button { brush = .black; eyedropper = false } label: {
                    RoundedRectangle(cornerRadius: 4).fill(Color.black).frame(width: 18, height: 18)
                        .overlay(Image(systemName: "xmark").font(.system(size: 9)).foregroundStyle(.white))
                }
                .buttonStyle(.plain)
                .help("Off")
            }

            Toggle(isOn: $eyedropper) { Image(systemName: "eyedropper") }
                .toggleStyle(.button)
                .help("Pick a color from a key")

            Spacer()

            Button("Fill all") { store.fill(RGB(brush)) }

            Menu("Layouts") {
                Section("Built-in") {
                    ForEach(Presets.builtIn, id: \.0) { name, colors in
                        Button(name) { store.setAll(colors) }
                    }
                }
                if !store.savedLayouts.isEmpty {
                    Section("Saved") {
                        ForEach(store.savedLayouts.keys.sorted(), id: \.self) { name in
                            Button(name) { store.setAll(store.savedLayouts[name] ?? [:]) }
                        }
                    }
                    Menu("Delete saved") {
                        ForEach(store.savedLayouts.keys.sorted(), id: \.self) { name in
                            Button(name, role: .destructive) { store.deleteLayout(named: name) }
                        }
                    }
                }
                Divider()
                Button("Save current…") { showingSave = true }
            }
            .fixedSize()
        }
    }

    private var statusLine: some View {
        HStack(spacing: 12) {
            Toggle("Live", isOn: $store.livePreview)
                .help("Send to the keyboard while painting")
            Toggle("Restore on reconnect", isOn: $store.restoreFrameOnConnect)
                .help("Per-key colors live in the keyboard's RAM; re-send them when it reconnects")

            if !store.livePreview {
                Button("Apply to keyboard") { store.applyFrame() }
                    .keyboardShortcut(.return)
            }

            Spacer()

            if store.sendingFrame {
                ProgressView().controlSize(.small)
                Text("Sending…").foregroundStyle(.secondary)
            } else if store.status != .connected {
                Text("Keyboard not connected").foregroundStyle(.secondary)
            } else if store.regions[.backlight]?.state.effect != LightingEffect.streamingID {
                Button("Switch backlight to per-key mode") { store.applyFrame() }
            } else {
                Label("Per-key mode", systemImage: "checkmark.circle").foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)
        .font(.callout)
    }
}

/// Draws the keyboard from `KeyLayout` and reports which key is under the pointer.
struct KeyboardCanvas: View {
    let colors: [Int: RGB]
    let onPaint: (KeyDef) -> Void
    @State private var lastPainted: Int?

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / KeyLayout.size.width
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(white: 0.12))
                    .frame(width: geo.size.width + 16, height: geo.size.height + 16)
                    .offset(x: -8, y: -8)

                ForEach(KeyLayout.keys) { key in
                    KeyCap(key: key, color: colors[key.id])
                        .frame(width: key.rect.width * scale - 2, height: key.rect.height * scale - 2)
                        .offset(x: key.rect.minX * scale + 1, y: key.rect.minY * scale + 1)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let p = CGPoint(x: value.location.x / scale, y: value.location.y / scale)
                        guard let key = KeyLayout.keys.first(where: { !$0.cells.isEmpty && $0.rect.contains(p) }),
                              key.id != lastPainted else { return }
                        lastPainted = key.id
                        onPaint(key)
                    }
                    .onEnded { _ in lastPainted = nil }
            )
        }
    }
}

private struct KeyCap: View {
    let key: KeyDef
    let color: RGB?

    var body: some View {
        let lit = !key.cells.isEmpty
        let fill = lit ? (color ?? .black) : RGB(60, 60, 60)
        ZStack {
            if lit {
                RoundedRectangle(cornerRadius: 5).fill(fill.color)
                RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.15), lineWidth: 1)
            } else {
                Circle().fill(Color(white: 0.25))
            }
            Text(key.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(fill.isLight ? Color.black : Color.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(2)
        }
        .help(lit ? "\(key.label) · #\((color ?? .black).hex)" : "\(key.label) (no LED)")
    }
}
