# Changelog

## 1.2.0 — 2026-10-25

**New**
- **Sleep time.** Choose how long the keyboard waits, idle, before it sleeps (lights off, wireless link
  dropped): 1, 3, 5, 10, 20, 30 or 40 minutes, or never, in the menu or with `bakey sleep`. It is stored on
  the keyboard. The factory value is 3 minutes. The Windows app has the same setting but shows it only on the
  2.4G receiver. "Never" uses more battery.
- **Raindrop inverted (Mac, on key press).** The opposite of the key-press Raindrop: the keyboard stays
  lit (white by default, or any color from the mixer), and the key you press goes dark with a ring of shadow
  spreading out. Made for white keycaps.
- **Diagnostic log** at `~/Library/Logs/BA-KEY Menu.log`: connections, errors and Mac-effect stats.
  It's useful when reporting a problem and never records key presses.
- **Color mixer in the menu.** The 🎛 button next to the swatches opens a hue bar, an intensity bar
  (white → full color), a hex field and recent colors, right inside the panel. It replaces the system color
  panel, which closed the menu. Any of the 16.7 million colors the keyboard supports.
- **Bluetooth batteries.** A new menu section shows the battery of every connected Bluetooth device
  (mice, headphones, AirPods with each earbud and the case, controllers), any brand. Pin a device to show
  its level next to the menu bar icon; mice are pinned automatically. Reads what macOS already collects
  (`system_profiler`), with no extra permission. See [docs/BATTERIES.md](docs/BATTERIES.md).

**Fixed**
- **Side light turned back on after the keyboard woke up (2.4G receiver).** The keyboard relights it
  even when it's set to Off, still reports Off, and ignores a repeat of the same setting. The app now asks
  the receiver every 3 s whether the keyboard is awake and, when it wakes (or the app connects), sends the
  side light again in a way the keyboard applies. Bluetooth wasn't affected.
- **No more "Keyboard did not answer" errors while the keyboard sleeps behind the receiver:** the battery
  isn't read then.
- **2.4G receiver kept disconnecting with Mac effects.** A single "fill" packet (one color for the whole
  keyboard, a Bluetooth speed-up) makes the receiver reset. Raindrop (Mac) and Breathing (Mac) sent it
  whenever the keyboard was one color, so the receiver reset every few seconds. Fill packets are now used
  only over Bluetooth. The 2.4G receiver is now tested (docs/PROTOCOL.md §2.6).
- **Reconnects on its own** after a failed connection or when commands time out. Previously, switching
  the keyboard from Bluetooth to 2.4G could leave the app stuck until it was restarted.
- **Bluetooth still dropped on some keyboards when changing colors.** A second BA-KEY308 needed more
  room than v1.1.1 gave: color changes are now at least 2.5 s apart, other lighting changes wait 1 s after
  a color change, and colors are sent 1 s after you stop adjusting. Verified with 73 back-to-back writes,
  0 drops (docs/BLUETOOTH.md).


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
