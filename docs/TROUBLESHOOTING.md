# Troubleshooting

### The menu says "Not connected"
- Check that the keyboard is connected: Bluetooth settings should show **BA-KEY308 – Connected**, or it
  should be plugged in by cable or through the 2.4G receiver.
- Press a key. In Bluetooth mode the keyboard sleeps and drops the connection; the app reconnects as
  soon as it comes back.
- Click **Try again**.
- From a terminal, `bakey info` gives the actual error.

### "Could not open the keyboard (IOReturn 0xE00002E2)"
Another program has the keyboard open **exclusively** (seized). Quit any other keyboard tool and try
again. Karabiner-Elements only seizes the keyboards you enable in its *Devices* tab, so you may need
to disable the BA-KEY308 there.

### "HID SetReport failed … data was not found (0xE00002F0)"
The report ID is wrong for the current transport. The app reads it from the HID descriptor; if this
appears anyway, please note which connection mode you use (BT / cable / 2.4G), run
`bakey -v info`, and see PROTOCOL.md §2.1.

### "Keyboard did not answer"
- Over the 2.4G receiver: the keyboard behind it may be asleep. Press a key.
- Over Bluetooth: macOS sometimes needs a moment after the keyboard wakes. Click Refresh.

### Per-key colors don't show
- **The backlight may be asleep.** It switches off after the idle time (3 minutes by default). Press any
  key; the colors come back.
- The backlight must be in **Per-key (custom)** mode. The painter window offers a button for this.
- Brightness may be at 0.

### Per-key colors disappeared after turning the keyboard off and on
That's expected: the firmware keeps them in RAM. With **Restore on reconnect** enabled, the app
re-sends them as soon as the keyboard reconnects to this Mac.

### Changing a color or speed seems to do nothing
- Some effects ignore custom colors and always use their own palette. Some have no speed setting.
- Speed 0 is ignored by the firmware; the app always sends 1–3.

### The Windows app and the Mac app disagree
Lighting settings are stored on the keyboard, so both apps read the same values. Per-key colors exist
only in the Mac app (the Windows app has no painter for this model).

### "Launch at login" does nothing
`SMAppService` needs the app to run from a stable location. Install it first:
`scripts/build-app.sh --install` puts it in /Applications. Then toggle the option again.

### Seeing the raw traffic
```bash
bakey -v info                  # every packet sent/received
bakey get 0 0x80               # raw GET: firmware version
bakey get 3 0x81 1             # LED attributes of region 1 (payload bytes go after cmd)
```

### "Raindrop (Mac, on key press)" says it needs Input Monitoring, but it's already enabled
The enabled entry belongs to an older build (see SOFT-EFFECTS.md → Signing). Run
`tccutil reset ListenEvent local.bakeymenu`, reopen the app and grant the permission again. Build with
the "BA-KEY Menu Dev" certificate (`scripts/make-dev-cert.sh`) so it doesn't happen again.

### "Permission OK, but opening the keyboard failed (IOReturn 0xE00002C5)"
Another app has the keyboard exclusively, usually Karabiner-Elements. The app then falls back to
macOS key events automatically. To get keyboard-exact ripples instead, disable the BA-KEY308 under
Karabiner-Elements → Devices.

### Empty space at the bottom of the menu panel
SwiftUI's `MenuBarExtra` (window style) grows with its content but doesn't shrink back. Since
v1.0.0+ the panel measures its content and resizes itself (`WindowHeightFitter` in
`MenuContentView.swift`). If a gap still appears, close and reopen the menu.

### `bakey` says "Keyboard did not answer" while the app is running
The keyboard has a single command "mailbox". If the menu bar app is talking to it at the same moment
(right after it launches or reconnects, or while a Mac effect is running), a CLI command can collide
and time out. Wait a few seconds and retry, or quit the app while using the CLI for longer sessions.

### The keyboard disconnects (Bluetooth) right after changing colors
Fixed in v1.1.1. The firmware freezes when it receives several color changes in quick succession
(e.g. dragging the color picker), and the Bluetooth link times out. The app now spaces color changes at
least 1.2 s apart, so the last color you pick may take about a second to apply. Details in
[BLUETOOTH.md](BLUETOOTH.md#disconnect-investigation-2026-10-20-rapid-color-changes-freeze-the-firmware).

### Over 2.4G, the side light turns back on after the keyboard wakes
Fixed in 1.2.0. The keyboard relights the side light when it wakes behind the receiver, even when it's set to
Off. The app now notices the wake (within ~3 s) and sends the side light setting again. Over Bluetooth this
never happened.

### The 2.4G receiver keeps disconnecting while a Mac effect runs
Fixed in 1.2.0: the app no longer sends the "fill" packet through the receiver, which made it reset.
If anything similar happens, `~/Library/Logs/BA-KEY Menu.log` shows each connect, error and
"HID devices changed" event with timestamps. Please attach it to a bug report.
