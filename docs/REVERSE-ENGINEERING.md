# How this was reverse-engineered

This is the log of the experiment that produced this project. It took one evening (2026-10-19), with the
keyboard connected to a Mac over Bluetooth the whole time. No Windows machine was involved.

## 1. Unpacking the installer

The only input was `Ba-KEY308 Installer_V1.0.0.1_20251230.exe` (5.3 MB).

```bash
file "Ba-KEY308 Installer_V1.0.0.1_20251230.exe"
# PE32 executable (GUI) Intel 80386, for MS Windows
strings -n 6 installer.exe | grep -i setup
# TSetupHeader, TSetupCompressMethod …  → Inno Setup
brew install innoextract
innoextract -d extracted installer.exe
```

Contents:

| File | Kind | Role |
|---|---|---|
| `Ba-KEY308.exe` (3.5 MB) | .NET (WPF) | UI |
| `DeviceBase.dll` (880 KB) | .NET | **Device protocol for every Dareu product** |
| `Products/TK51G_0130.dll` | .NET | Product definition: name, key table, LED matrix, defaults |
| `DataControl.dll`, `ToolLib.dll`, `UiLib.dll`, `LangLib.dll` | .NET | Helpers, raw input, UI widgets, strings |
| `TgApi.dll` (9 MB) | Native C++ | Auto-launch, pointer precision, app directory, unused encrypt/decrypt |

`file` reported "Mono/.Net assembly" for everything except `TgApi.dll`. That was the key finding: .NET
compiles to IL, which decompiles back to nearly the original C#.

## 2. Decompiling

```bash
dotnet tool install -g ilspycmd --version 9.1.0.7988   # newer versions need .NET 10
for f in *.dll *.exe; do ilspycmd -p -o src/$(basename $f .dll) $f; done
```

That produced about 580 C# files. Grepping for `DllImport` showed how the app reaches the device:

- `hid.dll`: `HidD_SetFeature`, `HidD_GetFeature`, `HidD_GetPreparsedData`, …
- `setupapi.dll`: device enumeration.
- `TgApi.dll` / `DataSource.dll`: no device I/O at all, only host-side extras.

**So the keyboard is configured with standard HID feature reports.** No kernel driver, no proprietary
USB class. macOS can send these from user space.

## 3. Mapping the protocol

The protocol lives in `DeviceBase/UsbHidDevice/TgUsbHidDevice.cs` (about 4,000 lines; every
`Get…`/`Set…` builds a 65-byte buffer) and in `DeviceBase/HidControl/TgHidUsb.cs` (the SET-then-poll-GET
handshake). The product class `TK51G_0130` gave the VID/PID, the key table with on-screen coordinates,
the LED matrix table and the default profile.

The result is [PROTOCOL.md](PROTOCOL.md).

## 4. First contact from macOS

`system_profiler SPBluetoothDataType` showed the keyboard as "BA-KEY308, Vendor ID 0x260D, Product ID
0x0130, BLE". `ioreg` provided its HID report descriptor, which contains a **65-byte feature report
under report ID 7**. Over USB the Windows app uses report ID 0, so the Bluetooth descriptor wraps the
same channel under a different ID.

### Problem 1: "open failed"

Stock hidapi opens macOS devices **exclusively** by default, and macOS refuses to give an exclusive
handle to a keyboard. Calling `hid_darwin_set_open_exclusive(0)` (or, in IOKit,
`IOHIDDeviceOpen(…, kIOHIDOptionsTypeNone)`) fixed it. No Input Monitoring permission was needed.

### Problem 2: wrong report ID

The first probe used report ID 0 and got `IOHIDDeviceSetReport failed: data was not found`. With
report ID 7, every GET answered:

```
FW version   07 02 03 00 80 00 00 00 00 03     → 0.0.3
Battery      07 02 04 07 80 00 00 00 64 64     → 100% (matches macOS)
LED region 1 07 02 05 03 82 01 00 01 06 …      → Raindrop
```

## 5. First write

SET effect = Static red, then read it back, then restore. Red appeared, so writing works.
The restore (Raindrop with speed 0) was **acknowledged but ignored**. The Windows UI substitutes speed 2
when the device reports 0, so we tried speed 2 and it worked. The firmware rejects speed 0 on writes
without reporting an error.

## 6. Per-key lighting

`LED attributes` for region 1 listed effect **18 ("StreamingFrame")** among the supported effects. The
Windows app contains a `SetLedFrame` implementation but **never calls it** for this product. We tried
it anyway: effect 18, then six row packets with everything blue and WASD red. The pattern appeared on
the keyboard and stayed.

Two lessons came out of this step:

- The first attempt "showed nothing" because **the backlight had gone to sleep** (idle-off after 180 s).
  Pressing a key woke it with the frame intact.
- The Windows app's LED matrix table is wrong (see [KEY-MATRIX.md](KEY-MATRIX.md)). We found out by
  lighting test cells in distinct colors and photographing the keyboard twice.

## 7. Finding the limits

- **Raindrop speed.** We sent Raindrop with speed 1 and then speed 3: no visible difference. The
  firmware ignores speed for that effect, which is why the Windows UI hides the slider. Hardware
  effects and their parameters are fixed by the firmware.
- **Brightness reads lag.** A GET with profile 1 returned the value from before the last write, while
  profile 0 returned the live value (see PROTOCOL.md).
- **Link speed.** `bakey bench`: over Bluetooth, about 154 ms per frame packet (~1 fps per full frame).
  Over the **USB cable**, 7.5 ms per frame (~130 fps). `bakey demo` ran a Mac-computed rainbow at
  84 fps over USB and it looked smooth. The keyboard renders at 33 fps, so over USB the Mac can drive
  any animation it wants.
- **The firmware can't be changed in practice.** The installer contains no firmware image, and its DFU
  page is an empty placeholder. Flashing custom firmware with no way to recover the original is the
  most likely way to brick the keyboard.

## 8. Building the app

- `BAKeyCore`: protocol, report-descriptor parser, IOKit transport, key layout. Pure Swift with no
  dependencies.
- `bakey`: CLI used to validate the core against the keyboard.
- `BAKeyMenu`: SwiftUI `MenuBarExtra` plus a painter window.

See [ARCHITECTURE.md](ARCHITECTURE.md).

## Tools used

`innoextract`, `ilspycmd` 9.1, `strings`, `file`, `ioreg`, `system_profiler`, Python 3 + hidapi for the
first probes, then Swift 6.1 / IOKit.

## Reproducing this for another Dareu keyboard

1. Extract and decompile its installer the same way.
2. Find the `Products/*.dll` for your model: it contains PID, key table and matrix.
3. Check `ioreg -r -c IOHIDDevice -l | grep -A40 '"Product" = "<name>"'` for `MaxFeatureReportSize = 65`.
4. Change `BAKey.keyboardPID` and regenerate `KeyLayout.swift`. Calibrate the matrix with test frames.
