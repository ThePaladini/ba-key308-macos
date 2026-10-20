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
