# Bluetooth batteries (mouse, headphones, any device)

Since v1.2.0 the menu has a **Bluetooth batteries** section. The menu bar shows `⌨ 100%  🖱 62%` (keyboard, then pinned devices); "Battery levels in menu bar" turns all of them on or off. It lists every connected Bluetooth device
that reports its battery, and each one has a **pin** to show its level next to the menu bar icon. A
mouse is pinned automatically the first time it appears.

## Where the numbers come from

macOS already collects battery levels from Bluetooth devices: from the standard **Battery Service**
(GATT `0x180F`) on Bluetooth LE mice and keyboards, and from Apple's own protocol for AirPods. It
reports them through `system_profiler`:

```bash
system_profiler SPBluetoothDataType -json
```

```json
"BA-KEY308": { "device_batteryLevelMain": "100%", "device_minorType": "Keyboard", "device_vendorID": "0x260D", … }
"AirPods Pro": { "device_batteryLevelLeft": "80%", "device_batteryLevelRight": "75%", "device_batteryLevelCase": "40%", … }
```

The app runs it every 60 s and whenever the menu opens. It takes about 0.1 s and **needs no permission**.
The parser (`BluetoothBatteryDevice.parse` in BAKeyCore) only looks at connected devices and their
`device_batteryLevel*` fields.

Alternatives considered:

- **IORegistry (`ioreg -k BatteryPercent`)**: holds Apple devices only. Third-party Bluetooth
  devices aren't there.
- **CoreBluetooth, reading `0x180F` directly**: real-time, but it needs the Bluetooth permission and
  only covers BLE devices. Not worth it, since macOS already polls them.

## Limits

- **The device has to report battery over Bluetooth.** Most rechargeable BLE mice do. If yours doesn't
  appear, macOS doesn't know its level either: System Settings → Bluetooth won't show it.
- **2.4 GHz receivers aren't covered.** There's no standard; each vendor uses its own protocol.
- **The Dareu keyboard** (VID `0x260D`) is left out of the list, because the app reads its battery
  itself, over USB too.
- Levels update about once a minute. Devices themselves often report in 5–10% steps.
