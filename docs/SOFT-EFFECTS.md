# Mac effects (host-rendered animations)

The firmware's 19 effects have fixed parameters. **Mac effects** are drawn by the app and streamed to
the keys through per-key mode (effect 18). Their speed, colors and look are entirely up to us.

## Why they exist: Raindrop speed

We wanted a *slower* native Raindrop. Everything we tried on the real keyboard (2026-10-19/20):

| Attempt | Result |
|---|---|
| Speed 1, 2, 3 (the official app's range) | All look the same |
| Speed 0 (the factory value) | Accepted and stored (an earlier "rejected" result was wrong); looks the same |
| Speed 8, 128 | Look the same |
| Speed 255 | Noticeably **faster** |
| Flag byte = 1 | No visible change |
| The keyboard's own **Fn + ← / Fn + →** | Steps the stored speed between 1 and 3, never lower (Fn + ← went 1 → 3, Fn + → went 3 → 1) |

So **this firmware has no slower Raindrop.** The speed byte barely affects it.

### The best answer: Area Reactive (firmware)

The firmware's other key-press effects do honor speed. **Area Reactive (24) at speed 1** turned out
"close to" the slow raindrop that was wanted, and it runs on the keyboard itself: smooth over
Bluetooth, no app needed. Reactive (4) and Line Reactive (25) are similar alternatives. Try speed 1–3,
with a color or the rainbow palette.

The Mac-rendered Raindrop below is still useful when you want full control (it is smooth over USB).

## Bonus: faster firmware effects

Because the speed byte goes up to 255, the menu's **Speed** slider for keyboard effects now covers the
full 1–255 range on a logarithmic scale. It is shown for every effect except Off, Static and per-key.
Values above 3 are faster than the official app allows. This works over Bluetooth too, because the
keyboard does the animating.

## Effects

| Effect | What it does | Speed 1.0× means |
|---|---|---|
| **Raindrop (Mac, on key press)** | Reactive, like the firmware Raindrop. The pressed key flashes, then a ring spreads outward (300 units/s ≈ 7.5 keys/s) and fades over 1.4 s. Random color per press, or one color | The ring speed and fade above |
| **Raindrop inverted (Mac, on key press)** | The keyboard stays lit in the chosen color (white by default, made for white keycaps). The pressed key goes dark, and a ring of shadow spreads and fades while the light comes back | Same ring speed and fade as the normal Raindrop |
| Rain (Mac, random) | Random keys light up and fade out (15% fade-in, 85% fade-out, 1.6 s life). Random colors or one color | About 5 new drops per second |
| Wave (Mac) | Rainbow wave flowing across the keyboard, or a brightness wave in one color | One wavelength per 2.5 s |
| Breathing (Mac) | Whole keyboard breathes; in rainbow mode the hue drifts slowly | One breath per 4 s |

The speed slider is logarithmic, from 0.1× to 3×. The default is 0.5×. Brightness uses the keyboard's
own brightness setting.

## Reactive effects and the Input Monitoring permission

The firmware Raindrop reacts to key presses, so the Mac version has to see them too.
`KeyPressMonitor` (BAKeyCore) has two sources:

| Source | How | Pros / cons |
|---|---|---|
| **Raw HID** (preferred) | `IOHIDManager` on the BA-KEY308 only (VID/PID match), reading HID usages (page 7) | Exact; the MacBook keyboard is ignored. **Fails with `0xE00002C5` (exclusive access) when another app has seized the keyboard**, e.g. Karabiner-Elements with the BA-KEY308 enabled in its *Devices* tab |
| **macOS key events** (fallback) | Listen-only `CGEventTap` for keyDown / flagsChanged; virtual key codes mapped back to HID usages (`usageForKeyCode`, including the ABNT2 keys) | Works alongside Karabiner, because it sees Karabiner's output. It can't tell keyboards apart, so the built-in keyboard triggers ripples too |

The menu says which source is active. `SoftRenderer.keyForUsage` maps the usage to a key and the renderer
starts a ripple there. Nothing is logged or stored. A unit test checks that every lit key is reachable
through the fallback mapping.

Both sources need the **Input Monitoring** permission:

1. Select *Raindrop (Mac, on key press)*. macOS shows a prompt, or the menu shows an orange box with
   the exact reason.
2. System Settings → Privacy & Security → Input Monitoring → enable **BA-KEY Menu**.
3. Quit and reopen the app if macOS asks. Otherwise click **Check again**.

### Signing, and why the permission kept "disappearing"

macOS ties privacy permissions to the app's *designated requirement*. With **ad-hoc signing** that is
the code hash, which changes on every build. Settings still shows "BA-KEY Menu ✓", but the entry
belongs to an old build, and `IOHIDCheckAccess` returns *denied*. The fix:

- `scripts/make-dev-cert.sh` creates a self-signed code-signing identity, **"BA-KEY Menu Dev"**, in
  the login keychain. It was created on this Mac on 2026-10-20.
- `scripts/build-app.sh` signs with it when present. The requirement becomes
  `identifier "local.bakeymenu" and certificate leaf = H"…"`, which is stable across rebuilds.
- After switching signing methods, reset the stale entry once with
  `tccutil reset ListenEvent local.bakeymenu` and grant again.

To remove the certificate, open Keychain Access and delete "BA-KEY Menu Dev". The build falls back to ad-hoc signing.

**Latency**: the next frame goes out at most 33 ms after a press over USB, so it feels instant. Over
Bluetooth a frame takes about 0.9 s, so the ripple shows up late and choppy. Reactive effects need the
cable (or possibly the 2.4G receiver).

**Idle**: between presses the engine sends one blank frame and then stops sending until the next
press, so a quiet keyboard costs nothing.

## How it works

```
KeyboardStore.startEngine()
  └─ set backlight effect 18 (once)
  └─ loop:
       frame = SoftRenderer.frame(dt, speed, color)   // 6×15 RGB, computed on the main actor
       await HIDWorker.run { sendFrame(frame) }       // 6 packets
       sleep to cap at 30 fps
```

- **The loop self-paces.** It sends the next frame only after the previous one finished, so it runs
  as fast as the link allows: about 30 fps over USB (capped; the firmware renders at 33 fps) and about
  1 fps over Bluetooth. The menu shows the fps actually achieved.
- `dt` is real elapsed time, capped at 1 s, so animations keep the same pace on a slow link. On a
  slow link they are just choppier.
- Other HID commands (battery polling, brightness) interleave between frames on the same serial queue.
- The engine stops when you pick a keyboard effect, paint keys, apply a layout, or the keyboard
  disconnects. It restarts on reconnect if the backlight is still in effect 18 and a Mac effect was
  selected. The selection, speed and color are saved in UserDefaults.

## Limits

- **They only run while the app is running and the Mac is awake.** Firmware effects work anywhere.
- Over Bluetooth each packet costs ~154 ms. The engine sends only changed rows (or one fill packet), so
  you get ~6 updates per second, and a key press shows up after ~0.15 s. See [BLUETOOTH.md](BLUETOOTH.md).
- Driving the LEDs continuously keeps the keyboard busy. Over a wireless link that costs battery.

## Adding an effect

1. Add a case to `SoftEffect` (raw value 200+) with a name.
2. Add its drawing to `SoftRenderer.frame`. You get `time` (scaled by speed), `step`, and `KeyLayout`
   (per-key rects for spatial effects). Return a frame with `KeyLayout.frame(from:)`.
3. It appears automatically under **Mac effects** in the menu.
