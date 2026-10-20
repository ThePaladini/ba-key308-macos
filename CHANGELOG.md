# Changelog

## 1.0.0 — 2026-10-20

First public release.

**App**
- Menu bar panel: connection, firmware, battery; backlight and side-light effects, color, speed and
  brightness; launch at login; optional battery level in the menu bar.
- Firmware effect speed covers the full 1–255 range (the official app only uses 1–3).
- Key Painter window: per-key colors with an eyedropper, fill, built-in and saved layouts, and
  restore on reconnect.
- Mac effects: Raindrop on key press, random Rain, Wave and Breathing, with speed from 0.1× to 3×.
- Bluetooth optimizations: only changed rows are sent, one-packet fills, compact ripples on slow links.
- Works alongside Karabiner-Elements: key-press effects fall back to macOS key events when the
  keyboard is seized.
- Panel resizes correctly when content shrinks (works around a SwiftUI `MenuBarExtra` bug).
- Universal binary (Apple Silicon + Intel), macOS 13+.

**CLI (`bakey`)**
- `info`, `effects`, `effect`, `effect-raw`, `brightness`, `fill`, `keys`, `layout`, `get`, `listen`,
  `bench`, `demo`, `lab`.

**Docs**
- Full protocol reference, calibrated LED matrix, Bluetooth analysis, safety notes,
  reverse-engineering log.

**Known limitations**
- The 2.4G receiver path is implemented but untested.
- The native Raindrop cannot be slowed down (firmware limit). Use Area Reactive or the Mac Raindrop.
- Not notarized: the first launch needs right-click → Open (see README).
