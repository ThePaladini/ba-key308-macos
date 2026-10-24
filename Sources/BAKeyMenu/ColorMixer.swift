import AppKit
import BAKeyCore
import SwiftUI

/// Inline color mixer for the menu panel: hue bar, intensity bar (white → full color), hex field and
/// recent colors.
///
/// It replaces the system ColorPicker, whose floating panel steals focus and closes the menu. It only
/// reports a color when you let go of a bar (or press Return in the hex field): rapid color writes
/// freeze the keyboard's firmware over Bluetooth (see KeyboardClient.colorWriteSpacing).
/// Brightness stays on the separate brightness slider, since the LEDs have their own dimming.
struct ColorMixer: View {
    let initial: RGB?
    let onCommit: (RGB) -> Void

    @State private var hue: Double = 0
    @State private var saturation: Double = 1
    @State private var hexText = ""
    @State private var hexInvalid = false
    @AppStorage("recentColors") private var recentRaw = ""

    private static let maxRecent = 8
    private var current: RGB { RGB(hue: hue, saturation: saturation) }
    private var recent: [RGB] { recentRaw.split(separator: ",").compactMap { RGB(hex: String($0)) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GradientSlider(value: $hue,
                           colors: (0...12).map { Color(hue: Double($0) / 12, saturation: 1, brightness: 1) },
                           onChanged: { hexText = current.hex }, onEnded: commit)
                .help("Hue")
            GradientSlider(value: $saturation,
                           colors: [.white, Color(hue: hue, saturation: 1, brightness: 1)],
                           onChanged: { hexText = current.hex }, onEnded: commit)
                .help("Intensity: from white to full color")

            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(current.color)
                    .frame(width: 26, height: 18)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
                Text("#").foregroundStyle(.secondary)
                TextField("RRGGBB", text: $hexText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.callout, design: .monospaced))
                    .frame(width: 78)
                    .foregroundStyle(hexInvalid ? Color.red : Color.primary)
                    .onSubmit(applyHex)
                Spacer()
                ForEach(recent, id: \.self) { c in
                    Button {
                        set(from: c)
                        commit()
                    } label: {
                        Circle().fill(c.color).frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .help("#\(c.hex)")
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
        .onAppear { set(from: initial ?? RGB(0, 120, 255)) }
    }

    private func set(from c: RGB) {
        let hs = c.hueSaturation
        hue = hs.hue
        saturation = hs.saturation
        hexText = c.hex
        hexInvalid = false
    }

    private func applyHex() {
        guard let c = RGB(hex: hexText) else { hexInvalid = true; return }
        set(from: c)
        // Typed colors are sent exactly, not rounded through hue/saturation.
        onCommit(c)
        remember(c)
    }

    private func commit() {
        let c = current
        hexText = c.hex
        onCommit(c)
        remember(c)
    }

    private func remember(_ c: RGB) {
        var list = recent.filter { $0 != c }
        list.insert(c, at: 0)
        recentRaw = list.prefix(Self.maxRecent).map(\.hex).joined(separator: ",")
    }
}

/// A horizontal bar showing a gradient, with a draggable knob for a 0...1 value.
struct GradientSlider: View {
    @Binding var value: Double
    let colors: [Color]
    var onChanged: () -> Void = {}
    var onEnded: () -> Void = {}

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .overlay(Capsule().stroke(Color.primary.opacity(0.2), lineWidth: 0.5))
                Circle()
                    .fill(Color.white)
                    .shadow(radius: 1.5)
                    .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 0.5))
                    .frame(width: 16, height: 16)
                    .offset(x: CGFloat(value) * (w - 16))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        value = min(max(Double((g.location.x - 8) / (w - 16)), 0), 1)
                        onChanged()
                    }
                    .onEnded { _ in onEnded() }
            )
        }
        .frame(height: 16)
    }
}

extension RGB {
    /// Fully bright color from hue and saturation (0...1). Saturation 0 is white.
    init(hue: Double, saturation: Double) {
        let ns = NSColor(hue: hue, saturation: saturation, brightness: 1, alpha: 1).usingColorSpace(.sRGB) ?? .white
        self.init(UInt8((ns.redComponent * 255).rounded()), UInt8((ns.greenComponent * 255).rounded()),
                  UInt8((ns.blueComponent * 255).rounded()))
    }

    var hueSaturation: (hue: Double, saturation: Double) {
        let ns = NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        return (Double(h), Double(s))
    }
}
