# Architecture

```
┌──────────────────────────── BAKeyMenu (SwiftUI app) ────────────────────────────┐
│  MenuContentView ─┐                                                            │
│  KeyPainterView  ─┼──► KeyboardStore (@MainActor, ObservableObject)            │
│                   │       • mirrors keyboard state for the UI                  │
│                   │       • debounces UI changes into commands                 │
│                   │       • coalesces per-key frames                           │
│                   │       • persists painter colors/layouts (UserDefaults)     │
│                   │            │ async                                         │
│                   │            ▼                                               │
│                   │       HIDWorker (serial DispatchQueue)                     │
└───────────────────┼────────────┼───────────────────────────────────────────────┘
                    │            ▼
┌──────────────────────────── BAKeyCore (library) ───────────────────────────────┐
│  KeyboardClient   high-level API: info, battery, effect, brightness, frames…   │
│       │           SET-allowlist safety check, SET→GET polling handshake        │
│       ▼                                                                        │
│  HIDDevice        IOKit: non-exclusive open, Set/GetReport(Feature)            │
│  DeviceMonitor    IOHIDManager matching VID 0x260D PID 0x0130 / 0x0042         │
│  ReportDescriptor finds the 64-byte feature report's ID (7 BLE / 0 USB)        │
│  Packet, PacketBuilder   65-byte packet encode/decode, frame packets           │
│  Protocol         constants, CommandClass, LightingEffect, RGB                 │
│  KeyLayout        83 keys: label, HID usage, rect, calibrated LED cells        │
└────────────────────────────────────────────────────────────────────────────────┘
          ▲
          └── bakey (CLI) uses the same library
```

## Package layout

```
BAKeyMenu/
├── Package.swift
├── Sources/
│   ├── BAKeyCore/          protocol + transport (no UI)
│   │   ├── Protocol.swift
│   │   ├── Packet.swift
│   │   ├── ReportDescriptor.swift
│   │   ├── HIDDevice.swift       (HIDDevice, DeviceMonitor)
│   │   ├── KeyboardClient.swift
│   │   ├── FrameDiffer.swift     (send only changed rows / fill packets; Bluetooth speed-up)
│   │   ├── KeyPressMonitor.swift (key presses: raw HID, falls back to CGEventTap)
│   │   └── KeyLayout.swift       (generated from the Windows app, then calibrated)
│   ├── BAKeyMenu/          the menu bar app
│   │   ├── BAKeyMenuApp.swift    (MenuBarExtra + "Key Painter" Window scenes)
│   │   ├── KeyboardStore.swift
│   │   ├── HIDWorker.swift
│   │   ├── MenuContentView.swift
│   │   ├── KeyPainterView.swift
│   │   ├── Presets.swift         (built-in layouts, RGB↔Color)
│   │   └── SoftEffects.swift     (Mac-rendered effects: key-press Raindrop, Rain, Wave, Breathing)
│   └── bakey/              CLI (main.swift) + Lab.swift (Bluetooth experiments)
├── Tests/BAKeyCoreTests/   descriptor, packets, layout, safety
├── Resources/              Info.plist (LSUIElement = menu bar only), AppIcon.icns
├── scripts/build-app.sh    builds, signs (dev cert or ad-hoc), --install to /Applications
├── scripts/make-dev-cert.sh  one-time self-signed signing identity
├── tools/                  layout extraction, icon generator (make-icon.swift), Python probe
└── docs/
```

## Design decisions

### IOKit directly, no hidapi
The first experiments used Python and hidapi. The app talks to IOKit directly, so it has no
dependencies and full control over the open mode, which must be non-exclusive. Each `IOHIDDevice` on
macOS covers all collections of an interface, so unlike on Windows there is no need to pick the
"right" collection path.

### The report ID comes from the descriptor
Over Bluetooth the configuration report is ID 7, over USB it is 0. Rather than branching on transport,
`ReportDescriptor.featureReportID` scans the descriptor for a 64-byte Feature report. The same scan
also filters out the keyboard's other USB interfaces.

### One serial queue for all HID traffic
Transactions are blocking: SET, then GET polling every 10 ms. Over BLE one takes 100–300 ms. They must
not interleave, because the firmware has a single feature-report mailbox. `HIDWorker` runs everything
on one `DispatchQueue` and exposes `async` functions to the `@MainActor` store.

### Optimistic UI with debouncing
`KeyboardStore` updates its published model first (so the UI reacts instantly) and then sends the
command after a short debounce: 250 ms for color and speed, 200 ms for brightness, immediately for
effect changes. Dragging a slider therefore sends one command instead of dozens.

### Frame coalescing
A per-key frame takes about 1 s over BLE and 7.5 ms over USB (6 packets). While one is being sent, further paint strokes
only set `frameDirty`. When the send finishes, the latest colors go out in one more frame. Painting
fast never builds a backlog.

### Per-key colors are owned by the Mac
The firmware has no storage for per-key colors on this model: custom frames 13–17 are not in its effect
list. Effect 18 shows whatever the host last streamed, and it lives in RAM. The app keeps the colors in
`UserDefaults` and re-sends them when the keyboard reconnects (if "Restore on reconnect" is on and the
backlight is in effect 18).

### Hot-plug
`DeviceMonitor` registers IOHIDManager matching/removal callbacks on the main run loop. Bluetooth
connect/disconnect and USB plug/unplug fire them. Events arrive in bursts, one per interface, so the
store waits 0.6 s and then reconnects to the best candidate: the keyboard itself (BLE or USB) before
the 2.4G receiver.

## Data flow example: choosing "Wave"

1. The `Picker` binding calls `store.setEffect(5, for: .backlight)`.
2. The store sets `regions[.backlight].state.effect = 5` and clamps speed 0 to 2, so the UI immediately
   shows the speed and direction controls.
3. `pushEffect` → `HIDWorker.run { $0.setEffect(state, region: 1, profile: 1) }`.
4. `KeyboardClient.transact(.lighting, 0x02, …)` checks the allowlist, then sends
   `07 00 05 03 02 01 00 01 05 00 02 00`.
5. It polls GET until `[1]&0x0F == 2` and `[3..4] == 03 02`.

## Extending

| Feature | Where | Notes |
|---|---|---|
| Key remapping | `KeyboardClient` + allowlist `[1, 0x03]` | Layout in PROTOCOL.md §Class 1 |
| On-board macros | allowlist `[6, 0x02…0x05]` | Upload sequence and event format in PROTOCOL.md §Class 6 |
| Sleep timer | allowlist `[7, 0x02]` | `[7]` enable, `[8..9]` seconds |
| Notifications | Input report ID 4 | Needs Input Monitoring permission |
| Software animations | `sendFrame` in a loop | About 1 fps over BLE, 84+ fps over USB (see `bakey demo`) |
