# Bluetooth performance and workarounds

## Why Bluetooth is slow for lighting

Bluetooth LE saves power by keeping the radio off most of the time. The keyboard and the Mac only
exchange data at scheduled **connection events**, once per *connection interval*. HID feature reports
(our configuration channel) are sent as **ATT Write Requests**, which must be acknowledged before the
next one may go out. So every packet costs at least one round trip of connection events.

Measured on this keyboard (2026-10-19/20, `bakey bench`, `bakey lab`):

| | USB cable | Bluetooth LE |
|---|---|---|
| Command with reply (SET + GET poll) | 14 ms | 256 ms |
| One frame packet (set-only) | ~1.3 ms | **~154 ms** |
| Full 6-row frame | 7.5 ms | ~900 ms |

The ~154 ms figure suggests that the keyboard asks for a long connection interval and/or peripheral
latency to save battery. That is negotiated between the firmware and macOS's Bluetooth daemon, and
apps cannot change it.

Key presses are not affected. They travel keyboard → Mac as **notifications**, which don't need an
acknowledgement, so typing is not slowed down by any of this.

## What we tried

| Idea | Command | Result |
|---|---|---|
| **Warm-up**: does steady traffic make the link renegotiate a faster interval? | `bakey lab sustained` | ❌ Stays at 153–157 ms/packet over 60 packets |
| **Pipelining**: queue many `IOHIDDeviceSetReportWithCallback` calls without waiting | `bakey lab async 30` | ❌ 156–165 ms/packet. macOS serializes them |
| **Partial update**: send one row only | `bakey lab partial` | ✅ That row changes and the others keep their colors. ~145 ms |
| **One-packet fill**: flags `0x03` + RGB at `[9..11]` | `bakey lab fill 00ff00` | ✅ The whole keyboard changes color with one packet. ~153 ms |

The fill packet comes from `SetLedFrameALL` in the Windows app, which has a bug: it writes R into all
three color bytes. R, G, B is what actually works.

## What the app does with this

`FrameDiffer` (BAKeyCore) remembers what the keyboard is showing and, for each new frame:

1. sends nothing if no lit key changed;
2. sends **one fill packet** if every lit key has the same color (Breathing, all off, a full-keyboard
   color change);
3. otherwise sends **only the rows that changed**, most-changed first.

The Mac-effects engine measures the cost per packet. On a slow link (> 30 ms/packet) it sends **one
row per iteration** and then recomputes the frame, so the most important change always goes next. The
painter also sends only changed rows.

### Extra tuning for the key-press Raindrop

The first Bluetooth version of the ripple was barely visible ("not working at all"), especially at
3× speed, because a ripple lived under 0.5 s and its ring crossed all 6 rows. On a slow link the
engine now also:

- draws **compact ripples**: the ring fades out after about 2 keys, so it touches about 3 rows;
- uses a **minimum change per row** (`minScore` 120), so faint fade steps don't use up packets. A row
  that goes completely dark is always sent, so no key stays faintly lit;
- recreates the key listener on every reconnect. Karabiner seizes the USB keyboard but not the
  Bluetooth one, so raw HID works over Bluetooth and the app should use it there.

Tip: on Bluetooth, use a **low speed (0.3–0.7×)**. Each ripple then lasts long enough to get several
updates.

Expected effect on Bluetooth, calculated from the measurements above:

| | Before | After |
|---|---|---|
| Key press → pressed key lights up | ~0.9 s | **~0.15 s** (one packet) |
| Breathing (Mac) | ~1 fps | **~6.5 fps** (fill packets) |
| Ripple animation | 1 full frame per second | ~6.5 row updates per second |
| Painting one key | ~0.9 s | ~0.15 s |

Over USB nothing changes in practice: all changed rows go out every frame, up to 30 fps.

## Ideas not tried yet

- **2.4G receiver.** It uses a proprietary 2.4 GHz link, typically 1 ms polling. It is probably as
  fast as USB, which would make wireless effects smooth.
- **Smaller packets don't help.** The cost is per packet, not per byte.
- **The side light (region 4)** is one row of 16 LEDs, so any side-light frame is a single packet.

## Disconnect investigation (2026-10-20): rapid color changes freeze the firmware

**Symptom (user report):** Bluetooth sometimes disconnects while changing settings in the app. It
was hard to reproduce by hand.

**Method:** `bakey lab-stress <scenario> <seconds> [interval-ms]` sends the same writes the app sends,
back to back. It logs each command's latency and every HID removal. In parallel,
`log stream --predicate 'process == "bluetoothd"'` recorded the link layer. macOS doesn't persist these
logs, but streams them live.

| Scenario (Bluetooth, writes back to back, ~0.45 s each) | Writes | Link drops |
|---|---|---|
| Battery reads | 103 | 0 |
| Brightness 120 ↔ 255 | 101 | 0 |
| Effect Raindrop ↔ Static | 104 | 0 |
| Speed 1 → 255 (Area Reactive) | 101 | 0 |
| Side-light effect Static ↔ Breathing, fixed color | 135 | 0 |
| **Side-light Static, color changes every write** | 12, then dropped | **1** |
| **Backlight Static, color changes every write** | 3, then dropped | **1** |
| Side-light color changes, **1 s apart** | 41 | 0 |

**What bluetoothd logged** at the drop: `tx [S=0:F=66]` (66 packets sent, none acknowledged) for
about 1.5 s, then `Connection timed out … reason 708`, i.e. the BLE supervision timeout. The keyboard
stopped answering on the radio and reconnected by itself about 1 s later. That looks like a firmware
stall or reset. My inference is that each new color makes it re-render and persist, and a rapid series
overwhelms it.

**Fix (v1.1.1):** `KeyboardClient.colorWriteSpacing = 1.2 s`. An effect write whose colors differ from
the previous one for that region waits until 1.2 s have passed. In the app, color changes are also
debounced for 0.5 s, so a color-picker drag sends only where it stops. Per-key frames (effect 18) are
RAM-only and unaffected: 45 back-to-back frames, 0 drops.

### Follow-up (2026-10-24): 1.2 s wasn't enough on a second keyboard

A second BA-KEY308 (white, same firmware 0.0.3) dropped the link while the user tried the new inline
color mixer. Stress tests on that unit:

| Color writes on the backlight | Writes | Link drops |
|---|---|---|
| ~1.6 s apart (the v1.1.1 spacing + write time) | 8, then dropped | 1 |
| ~1.7 s apart | 58 | 0 |
| ~4.2 s apart | 34 | 0 |
| Alternating backlight ↔ side light, ~0.8 s | 92 | 0 |

The cause is the rate of writes to one region, not their total count, and the threshold (~1.6–1.7 s)
varies per unit. v1.1.1 sat right at the edge. Changes:

- `colorWriteSpacing` **2.5 s** (≈ 2.9 s per write), well clear of the threshold.
- `quietAfterColor` **1.0 s**: brightness and non-color effect writes wait 1 s after a color change.
- The app debounces color changes for **1.0 s**, so several mixer drags or swatch clicks become one write.

Verified on the white unit: 42 back-to-back color writes and 31 color-then-brightness pairs, 0 drops.
