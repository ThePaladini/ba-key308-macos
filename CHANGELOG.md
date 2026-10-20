# Changelog

## 1.2.0 — 2026-10-20

**New**
- **Bluetooth batteries.** A new menu section shows the battery of every connected Bluetooth device
  (mice, headphones, AirPods with each earbud and the case, controllers), any brand. Pin a device to show
  its level next to the menu bar icon; mice are pinned automatically. Reads what macOS already collects
  (`system_profiler`), with no extra permission. See [docs/BATTERIES.md](docs/BATTERIES.md).


## 1.1.1 — 2026-10-20

**Fixed**
- **Bluetooth disconnects when changing colors.** Several color changes in quick succession (dragging
  the color picker, clicking through swatches) froze the keyboard's firmware, and macOS dropped the link
  (supervision timeout). Color-changing writes are now spaced at least 1.2 s apart, and the color picker
  waits 0.5 s before sending. Reproduced and verified with the new `bakey lab-stress` command; see
  [docs/BLUETOOTH.md](docs/BLUETOOTH.md).


## 1.1.0 — 2026-10-20

**More keyboards (experimental)**
- Recognizes the ANSI TK51G keyboards from Dareu's public catalog: **Dareu EK75** (PIDs `0x0101`,
  `0x0045`), also sold as **Husky Nomadic HTG200 / HTG500 / HTG800 V2**. Works directly and through the
  2.4G receiver. Not tested on hardware yet.
- Per-model key layouts: the Key Painter, built-in layouts and the key-press Raindrop follow the
  connected keyboard (ABNT2 BA-KEY308 or ANSI EK75). The EK75 layout comes from Dareu's own profile; its
  LED cells are inferred (docs/KEY-MATRIX.md).
- `bakey info` shows the detected model, and the CLI now detects **any** VID `0x260D` keyboard with the
  configuration channel, so owners of other Dareu models can send a (read-only) compatibility report.
- [docs/DAREU-CATALOG.md](docs/DAREU-CATALOG.md): all 91 keyboards in Dareu's public catalog, with platform and
  firmware type. 19 use the same protocol family (`FwType 0`).
- New GitHub issue form for compatibility reports.

**Other**
- `bakey showcase` adapts to Bluetooth (keyboard-driven scenes, one-packet-per-step animations).
- Demo videos linked from the README.


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
