# BA-KEY308 configuration protocol

This is the protocol the official Windows app ("Ba-KEY308 Installer V1.0.0.1, 2025-12-30") uses to
configure the keyboard. It was reconstructed by decompiling that app (see
[REVERSE-ENGINEERING.md](REVERSE-ENGINEERING.md)) and then **verified against a real keyboard from macOS**
over Bluetooth LE on 2026-10-19.

Each item below carries one of these markers:

- ✅ **Verified**: sent to the real keyboard from macOS, and the response or visible result matched.
- 📖 **From source**: read from the decompiled Windows app, but not tested yet.
- ⚠️ **Dangerous**: never sent. Documented only so nobody sends it by accident. See [SAFETY.md](SAFETY.md).

---

## 1. Identification

| | VID | PID | Notes |
|---|---|---|---|
| Keyboard (USB cable or Bluetooth LE) | `0x260D` | `0x0130` | ✅ Seen over BLE as "BA-KEY308" |
| 2.4 GHz receiver | `0x260D` | `0x0042` | 📖 "Ba-KEY308 2.4G Receiver" |
| Dareu EK75 / Husky Nomadic (ANSI TK51G) | `0x260D` | `0x0101`, `0x0045` | Same `FwType 0` protocol per Dareu's catalog and two Linux projects; recognized by the app since v1.1.0, untested |

✅ Over the USB cable the keyboard enumerates as **"USB_Keyboard"** (same VID/PID, 12 Mb/s full speed).
In wired mode the Bluetooth connection drops, so only one of the two is visible at a time.
| Bootloader (DFU) | `0x260D` | `0xFFFA` or `0x0055` | 📖 Only appears after a DFU command |

`0x260D` is the vendor ID of **Dareu**. The BA-KEY308 is Dareu's "TK51G" platform, model code
`TK51G_0130`, sold under the Brazilian Basike brand. Other Dareu-based keyboards very likely use the same protocol
with a different PID and key map.

## 2. Transport

All configuration goes through **HID Feature reports** (SET_REPORT / GET_REPORT on the control channel).
The app does not use interrupt input/output reports for configuration.

### 2.1 Which interface and report ID

| Transport | Collection | Report ID | Report size |
|---|---|---|---|
| Bluetooth LE | Consumer (`0x0C`/`0x01`), vendor usage `0xFF00`/`0x02` | **7** ✅ | 64 data bytes |
| USB cable | Consumer (`0x0C`/`0x01`) | **0** (no report IDs) ✅ | 64 data bytes |
| 2.4G receiver | Consumer (`0x0C`/`0x01`) | 0 📖 | 64 data bytes |

The Windows app hard-codes report ID 0 because it only supports USB and the receiver. **Over
Bluetooth the descriptor puts the same 64-byte feature report under report ID 7.** The Mac app does not
hard-code either value. It parses the HID report descriptor and uses the ID of the first Feature report
that is 64 bytes long (`ReportDescriptor.swift`).

This is the relevant part of the real BLE report descriptor:

```
05 0C        Usage Page (Consumer)
09 01        Usage (Consumer Control)
A1 01        Collection (Application)
85 07          Report ID (7)
06 00 FF       Usage Page (Vendor 0xFF00)
09 02          Usage (0x02)
15 00          Logical Minimum (0)
26 FF 00       Logical Maximum (255)
75 08          Report Size (8)
95 40          Report Count (64)
B1 01          Feature (Constant)       ← the configuration channel
C0           End Collection
```

### 2.2 Opening the device on macOS

The device must be opened **non-exclusively**: `IOHIDDeviceOpen(dev, kIOHIDOptionsTypeNone)`. In
hidapi terms, call `hid_darwin_set_open_exclusive(0)` first. An exclusive open of a keyboard fails with
"open failed", and it would also take the keyboard away from macOS if it succeeded. A non-exclusive open
works without any Input Monitoring permission, because we never read keystrokes.

### 2.3 Packet layout

Every request and response is 65 bytes: one report-ID byte plus 64 bytes of data.

| Offset | Request | Response |
|---|---|---|
| `[0]` | Report ID (7 over BLE, 0 over USB) | Same |
| `[1]` | **Target**: high nibble, 0 = this device; `n` = keyboard in receiver slot `n` | **Status**: low nibble (table below) |
| `[2]` | Payload length (see note) | Payload length |
| `[3]` | Command class | Echo of the class |
| `[4]` | Command ID. **Bit 7 set = GET**, clear = SET | Echo of the command |
| `[5]` | Profile ID (1–6), or 0 | Profile ID |
| `[6]` | Reserved, 0 | 0 |
| `[7…64]` | Payload | Data |

- Multi-byte integers are **big-endian**.
- **No checksum, no encryption, no session key.** The app ships `Encrypt`/`Decrypt` functions in a
  native DLL, but nothing calls them.
- The length byte `[2]` is set the way the app sets it. For GETs the firmware does not seem to check it
  (✅ GETs with `[2]=0` worked).

**Status values** (`[1] & 0x0F`):

| Value | Meaning | What the app does |
|---|---|---|
| 0 | Empty (no answer yet) | Poll again after 10 ms |
| 1 | Busy | Poll again after 10 ms, up to 300 ms |
| **2** | **Ready / OK** | Accept, but only if `[3]` and `[4]` echo the request |
| 3, 6 | Error | Retry for about 60 ms |
| 5 | Not supported | Give up |

### 2.4 Handshake

```
host → SET_FEATURE(request)
host → GET_FEATURE  → status 0/1 → wait 10 ms, GET again …
                   → status 2 and [3],[4] echo the request → done, data at [7…]
```

Total timeout is 2 s. Commands must be strictly serialized, because there is only one feature report
"mailbox". Over Bluetooth one SET+GET round trip takes about 100–300 ms ✅.

**Set-only commands** (no GET polling) are used only for per-key frames (class 3, command `0x04`).

### 2.5 Multi-packet reads

Lists and names longer than one packet use this scheme:

1. GET with `[2]=1` → the response has `[7]` = total length (the first bytes of data may already be
   at `[9…]`).
2. For each chunk: GET with `[7]=total`, `[8]=offset`, `[2]=n+2` → `n ≤ 48` bytes at `[9…]`.

✅ Verified for the profile list and the LED region list.

### 2.6 Through the 2.4G receiver ✅ (tested 2026-10-24)

1. Open the receiver (PID `0x0042`).
2. GET class 0, command `0xA0` (wireless status) → `[7]` = N, then N groups of
   `{status, PID high, PID low}` starting at `[8]`.
3. For the first slot `i` with status ≠ 0 and PID `0x0130`, set the target nibble: `[1] = (i+1) << 4`.
4. Every other command is identical.

Verified on the real receiver (PID `0x0042`, 12 Mb/s USB):

- **Interface:** Consumer `0x0C`/`0x01`, 64-byte feature report, no report ID (descriptor
  `050c0901a1010600ff09021500250175089540b101c0`). The receiver also exposes keyboard, mouse, consumer
  and digitizer interfaces.
- **The keyboard sits in slot 1:** requests use `[1] = 0x10` and replies carry `0x12` (slot 1 + READY).
- **Speed is about the same as USB:** a GET round trip takes ~14 ms and a frame packet ~1 ms. Stress
  results: 2091 effect writes, 2171 brightness writes, 5169 full frames and 2648 frames of per-row packets,
  with 0 failures.
- ⚠️ **A fill packet (`[8]=0x03`) resets the receiver.** It drops off USB about 3 s later and
  re-enumerates. The app only uses fill packets over Bluetooth (`KeyboardClient.supportsFillPacket`).
  Before this was known, every Mac effect with an all-one-color frame (Raindrop when idle, Breathing)
  made the receiver reset in a loop, every ~3.4 s.
- **Sleep and wake are invisible to macOS.** The receiver stays on USB, so no HID event arrives when the
  keyboard behind it sleeps or wakes. Its slot status in `0xA0` reads 0 while the keyboard sleeps and ≠ 0 when
  it's awake; the receiver answers this while the keyboard sleeps and the query doesn't wake it (2026-10-25).
  The app polls it every 3 s (`KeyboardClient.keyboardAwakeBehindReceiver`).
- ⚠️ **After waking over 2.4G, the side light comes back on even when it's set to Off,** and it still
  reports Off. Bluetooth isn't affected. A write identical to the stored state is ignored (Off again does
  nothing); a write that differs is applied (Off with speed 3 turned it off). Fix in the app: on every wake
  and connect through the receiver, send the side light twice, first with a different speed byte, then the
  real state (2026-10-25, reproduced with a 1-min sleep time, verified by eye). **Timing matters:** the
  keyboard relights the side light a moment *after* it reconnects, so a write sent 0.27 s after the wake was
  overwritten; the app sends it 1.5 s and 5 s after the wake, which held over the following wakes.

---

## 3. Command reference

### Class 0: Device

| Cmd | Dir | Request | Response | Status |
|---|---|---|---|---|
| `0x80` | GET | `[2]=2` | `[7..9]` firmware major.minor.patch | ✅ → `0.0.3` |
| `0x81` | GET | `[2]=2` | `[7..9]` hardware version | ✅ → `1.0.0` |
| `0x82` | GET | `[2]=16` | `[7..22]` serial number (ASCII) | 📖 |
| `0x83` | GET | | `[7]` device mode | 📖 |
| `0x84` | GET | `[5]` profile | `[7]` USB speed, `[8]` polling-rate code | 📖 |
| `0x85` | GET | `[2]=3` | `[7]` edition, `[8]` SKU, `[9]` vendor | ✅ → all 0 |
| `0x86` | GET | | `[7..12]` MID | 📖 |
| `0x87` | GET | multi-packet | device name | 📖 |
| `0x90` | GET | | receiver firmware version | 📖 |
| `0xA0` | GET | | wireless slots: `[7]` N, then N × {status, PID} (§2.6); status 0 = keyboard asleep or absent | ✅ |
| `0xA2` | GET | | RF protocol version | 📖 |
| `0xA7` | GET | | `[7]` device color | 📖 |
| `0x02` | SET | | serial number | ⚠️ identity |
| `0x03` | SET | `[7]` mode | 0 Normal, 1 Driver, **2 DFU**, 3 Test, 4 Sleep, 5 Off, 6 RF pair | ⚠️ |
| `0x04` | SET | `[5]`, `[7]` speed, `[8]` rate | polling rate | 📖 |
| `0x05`, `0x07`, `0x08`, `0x11`, `0x12` | SET | | edition, name, reset, receiver identity | ⚠️ |

### Class 1: Keys

| Cmd | Dir | Request | Response | Status |
|---|---|---|---|---|
| `0x80` | GET | multi-packet | list of key IDs | 📖 |
| `0x81` | GET | `[7]` key | `[8]` type, `[9]` purpose, `[10]` programmable | 📖 |
| `0x82`/`0x02` | GET/SET | | `[7]` make ms, `[8]` break ms, `[9]`/`[10]` masks (debounce) | 📖 |
| `0x83`/`0x03` | GET/SET | `[5]` profile, `[7]` key, `[8]` layer (0 normal, 1 Fn), `[9]` function, `[10..14]` data | key assignment (remap) | 📖 |
| `0x85`/`0x05` | GET/SET | `[7]` | Fn lock | 📖 |
| `0x86` | GET | `[2]=2` | `[7]` Win lock, `[8]` Mac mode | ✅ → `0 0` |

**Key assignment function IDs** (`[9]`), with their data bytes `d0…d4` at `[10..14]`:

| ID | Function | Data |
|---|---|---|
| 6 | Key or key combo | `d0` modifiers (1 LCtrl, 2 LShift, 4 LAlt, 8 LGui, 0x10 RCtrl, 0x20 RShift, 0x40 RAlt, 0x80 RGui), `d1` HID usage, `d2` optional second usage |
| 8 | Media | `d0..1` consumer usage (e.g. `00 E9` Vol+, `01 92` Calculator) |
| 10 | Vendor | `d0=0x40` = Fn |
| 11 | Turbo | `d0` modifiers, `d1` usage, `d2..3` period ms |
| 12–15 | Macro | `d0` macro ID. 12 = N times (`d1..2` count), 13 = toggle, 14 = until released, 15 = while held |
| 25 | Switch profile | `d0` profile ID |
| 41 / 42 | BT pair / 2.4G pair | `d0` BT slot 0–2 |
| 44 | Reset settings | |
| 45 | Win/Mac switch | |
| 46 | Show battery | |
| 47 | Win lock | |
| 48, 53, 54, 55 | Lighting speed / mode / brightness / color | |

### Class 3: Lighting

Regions on this keyboard ✅:

| Region | Name | LEDs | FPS | Supported effects (firmware order) |
|---|---|---|---|---|
| 1 | Backlight (per-key RGB) | 6 × 15 | 33 | 1, 2, 5, 11, 4, 9, 6, 3, 10, 20, 21, 22, 26, 24, 25, 27, 28, 29, **18** |
| 4 | Side light | 1 × 16 | 33 | 0, 2, 1, 18 |

| Cmd | Dir | Request | Response | Status |
|---|---|---|---|---|
| `0x80` | GET | multi-packet | region IDs | ✅ → `01 04` |
| `0x81` | GET | `[7]` region | `[8]` type, `[9]` fps, `[10]` rows, `[11]` cols, `[12]` N, `[13..]` effect IDs | ✅ |
| `0x82` | GET | `[5]` profile, `[7]` region | `[8]` effect, `[9]` flag, `[10]` speed, `[11]` N colors, `[12..]` RGB×N | ✅ |
| `0x02` | SET | `[5]` profile, `[7]` region, `[8]` effect, `[9]` flag, `[10]` speed, `[11]` N, `[12..]` RGB×N; `[2]=5+3N` | | ✅ |
| `0x83` | GET | `[5]` profile, `[7]` region; `[2]=2` | `[8]` brightness 0–255. **Read with `[5]=0`** (see below) | ✅ |
| `0x03` | SET | `[5]` profile, `[7]` region, `[8]` level; `[2]=2` | | ✅ |
| `0x04` | SET-only | per-key frame, see §4 | none | ✅ |
| `0x88` / `0x08` | GET/SET | custom LED storage (effects 13–17) | | 📖 (not supported by this firmware) |

**Effect fields:**

- **flag**: direction for Wave (5). 0 = left→right, 1 = right→left.
- **speed**: 1–3 in the Windows UI and on the keyboard's Fn + ← / → keys. The firmware stores any
  byte 0–255 ✅. The factory Raindrop uses 0. (An early test where a speed-0 write "didn't apply" was
  probably a different problem; a later clean write of 0 worked.) The app still sends ≥ 1 for safety.
- **colors**: 0–5 RGB triplets. **0 colors = the firmware's own palette** (rainbow); this is how Wave
  and Raindrop ship. Static needs 1 color.
- **brightness**: 0–255. The keyboard's own Fn steps are 0, 70, 120, 190, 255.
  ✅ **Quirk: a brightness GET with `[5]=1` returns the value from before the last write.** After
  SET 190 and then SET 255, a read with profile 0 returned 255 and a read with profile 1 returned 190.
  The firmware probably persists to flash lazily. Read with profile 0 to get the live value. Effect
  reads (`0x82`) return the same data for profile 0 and 1.
- ✅ **For Raindrop the speed byte barely matters.** 0, 1, 2, 3 and 128 look identical, and only 255 is
  clearly faster, so there is no slower Raindrop. Area Reactive (24) at speed 1 is a good slow
  alternative. See [SOFT-EFFECTS.md](SOFT-EFFECTS.md).

**Effect IDs** (from the app's `LedEffectIndex`):

| ID | Effect | ID | Effect | ID | Effect |
|---|---|---|---|---|---|
| 0 | Off | 11 | Starlit | 22 | Steady Stream |
| 1 | Static | 12 | Heat-up | 23 | Start-up |
| 2 | Breathing | 13–17 | Custom frame 1–5 | 24 | Area Reactive |
| 3 | Neon | **18** | **Streaming (per-key)** | 25 | Line Reactive |
| 4 | Reactive | 19 | Lap | 26 | Waterfall |
| 5 | Wave | 20 | Rainbow Wheel | 27 | Scanning |
| 6 | Raindrop | 21 | Light Wave | 28 | Heartbeat |
| 7 | Gather | | | 29 | Fluxay |
| 8 | Ripple | | | 30–32 | Heart / Moon / Star Breath |
| 9 | Running Light | | | | |
| 10 | Diffusion | | | | |

The Windows UI enables the speed slider for 2, 3, 4, 5, 9, 10, 11, 19, 20, 21, 22, 24–29. IDs 128 and
up are software effects (audio visualizer and similar) that the app renders itself; they are never
sent to the keyboard.

### Class 5: Profiles

| Cmd | Dir | Request | Response | Status |
|---|---|---|---|---|
| `0x80` | GET | multi-packet | profile IDs | ✅ → `01` (only one profile exists; `[5]` reported 6 = maximum) |
| `0x83` | GET | | `[5]` and `[7]` active profile | ✅ → 1 |
| `0x03` | SET | `[5]` profile | | 📖 |
| `0x01` / `0x02` | SET | `[5]` ID | create / delete | 📖 |
| `0x84` / `0x04` | GET/SET | multi-packet, UTF-16LE | name | 📖 |
| `0x05` | SET | `[5]` ID | **reset profile to defaults** (the app's "Reset" button) | ⚠️ destructive, not used |

### Class 6: Macros (stored on the keyboard) 📖

| Cmd | Dir | Layout |
|---|---|---|
| `0x80` | GET | `[8..11]` max, `[12..15]` free, `[16..19]` recyclable bytes (u32) |
| `0x81` | GET | multi-packet macro ID list |
| `0x02` | SET | create: `[7]` ID, `[8..9]` size |
| `0x03` | SET | delete: `[7]` ID |
| `0x04`/`0x84` | SET/GET | name: `[7]` ID, `[8]` total, `[9]` offset, `[10..]` ≤48 bytes UTF-16LE |
| `0x05`/`0x85` | SET/GET | data: `[7]` ID, `[8..9]` total, `[10..11]` offset, `[12..]` ≤48 bytes |
| `0x86` | GET | `[7]` minimum delay |

Macro event stream: 4/5 key make/break + usage; 8/9 media make/break + u16 usage; 1/15/16 mouse
buttons; 2 wheel; 3 cursor (x, y as int16); 10/11/12 delay in ms (1/2/3 bytes); 13 random delay
(min, max); `0xFE` end. Uploads go create → name → data, with about 100 ms between steps.
Macros are not synced over the wireless receiver.

### Class 7: Power

| Cmd | Dir | Request | Response | Status |
|---|---|---|---|---|
| `0x80` | GET | `[2]=4` | `[7]` status (0 discharging, 1 charging, 2 full), `[8]` level %, `[9]` max, `[10]` critical | ✅ → `00 64 64` = 100% |
| `0x81`/`0x01` | GET/SET | | `[7..8]` seconds until the backlight dims | 📖 |
| `0x82` | GET | `[2]=3`, `[5]` profile | `[7]` enabled, `[8..9]` idle seconds before the keyboard sleeps | ✅ → `01 00 B4` = 180 s (factory) |
| `0x02` | SET | `[2]=3`, `[5]` profile, `[7]` enable (0 = never), `[8..9]` seconds | | ✅ see below |
| `0x83`–`0x85` | | | low-battery indicator, battery max LED level, ADC | 📖 |

**Sleep time** ✅ (2026-10-25, BA-KEY308 on the 2.4G receiver). This is the Windows app's "Sleep time"
(`SetBatteryTimeToSleep`): it offers 1, 3, 5, 10, 20, 30, 40 minutes or never, and shows the setting only for the
wireless product (`TK51G_0130WL.IsSupportSleepTimeChange`); the command is the same on every link. When the time
runs out with no key pressed, the backlight goes off and the keyboard drops the wireless link (the receiver then
reports no keyboard) until a key is pressed. HID requests from the host do not count as activity. Measured: set to
1 min, the keyboard was gone from the receiver between 71 and 81 s later; the factory 3 min is what made it vanish
during long sessions. Writes of 1, 3, 10, 40 min and 0 read back exactly. **After the SET the keyboard ignores
requests for a moment** (probably saving the setting): a GET sent right after never gets an answer, one sent 0.5 s
later does, so `setSleepSeconds` waits 0.6 s. With one profile, GET answers the same
for profile 0 and 1.

### Asynchronous notifications 📖

24-byte input reports with report ID 4 on vendor page `0xFF00`. `[1]` is the event:

| Event | Meaning |
|---|---|
| 2 | Profile changed (`[2]` = ID) |
| 3 | Brightness |
| 4 / 15 | Lighting mode (`[2]` = effect, `[4]` = speed) |
| 7 | Wireless connect/disconnect |
| 12 | Win lock / Mac mode |

The Mac app does not listen for these yet. Reading input reports from a keyboard needs the Input
Monitoring permission.

---

## 4. Per-key lighting (streaming frames) ✅

1. Set the backlight region to effect **18** (class 3, `0x02`, `[8]=18`).
2. Send one packet per matrix row (class 3, `0x04`, **no GET polling**):

```
[7]  region (1)
[8]  flags: 0x01, OR 0x80 on the last packet of the frame
[9]  row (0–5)
[10] first column
[11] last column
[12…] R G B for each column (at most 16 LEDs per packet)
[2]  = 6 + 3 × count
```

A full 6 × 15 frame is 6 packets. Measured with `bakey bench` / `bakey demo` ✅:

| Link | GET round trip | Frame packet | Full frame | Sustained animation |
|---|---|---|---|---|
| Bluetooth LE | 256 ms | 154 ms | ~900 ms (~1 fps) | not practical |
| USB cable (12 Mb/s) | 14 ms | ~1.3 ms | 7.5 ms (~130 fps) | **84 fps measured, looks smooth** |
| 2.4G receiver | not measured | | | |

The firmware renders at 33 fps (LED attribute `[9]=0x21`), so over USB the link is no longer the
bottleneck. Bluetooth is limited by the BLE connection interval: each feature report waits for a
connection event.

**Persistence** ✅: the frame stays on screen indefinitely, and it survives the backlight's idle-off (the
LEDs come back with the same colors on the next key press). It is held in RAM, so it is presumably lost
when the keyboard powers off. The Mac app re-sends it on reconnect ("Restore on reconnect"). Effect 18
itself *is* stored in the profile.

✅ **Partial updates**: a single row packet with flags `0x81` updates only that row; the other rows keep
their colors. ✅ **Fill**: `[8]=0x03`, `[9..11]=R,G,B` paints the whole region in one packet. The Windows
app's `SetLedFrameALL` wrongly puts R in all three bytes. See [BLUETOOTH.md](BLUETOOTH.md).

The LED matrix does **not** match the Windows app's table. The calibrated map is in
[KEY-MATRIX.md](KEY-MATRIX.md).

---

## 5. Captured examples (Bluetooth, report ID 7)

```
GET firmware      → 07 00 02 00 80 00 00 …
                  ← 07 02 03 00 80 00 00 00 00 03            (0.0.3)
GET battery       → 07 00 04 07 80 00 00 …
                  ← 07 02 04 07 80 00 00 00 64 64             (discharging, 100%)
GET effect rgn 1  → 07 00 00 03 82 01 00 01 …
                  ← 07 02 05 03 82 01 00 01 06 00 00 00       (Raindrop, speed 0, 0 colors)
GET effect rgn 4  ← 07 02 08 03 82 01 00 04 02 00 00 01 FF FF FF   (Breathing, white)
SET static red    → 07 00 08 03 02 01 00 01 01 00 00 01 FF 00 00
                  ← 07 02 08 03 02 01 00 01
GET LED attrs 1   ← 07 02 19 03 81 00 00 01 04 21 06 0F 13 01 02 05 0B 04 09 06 03 0A 14 15 16 1A 18 19 1B 1C 1D 12
GET profile list  ← 07 02 01 05 80 06 00 01 00 01
GET sleep         ← 07 02 03 07 82 00 00 01 00 B4             (180 s)
SET sleep 10 min  → 00 10 03 07 02 01 00 01 02 58             (2.4G: report ID 0; 0x0258 = 600 s)
                  ← 00 12 01 07 02 01 00 01
```
