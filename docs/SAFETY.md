# Safety

The keyboard's protocol includes commands that can **brick it**. They erase flash, enter the bootloader,
or rewrite the USB IDs. There is no checksum or authentication, so any program that can open the device
can send them. This project is designed so that it cannot send them, even by mistake.

## What could go wrong

| Class / command | What it does | Why it's dangerous |
|---|---|---|
| Class **9** (all) | Firmware update: attribute, prepare, file, CRC, exit, entry | Leaves the keyboard in the bootloader (PID `0xFFFA`/`0x0055`) with no Mac tool to flash it back |
| Class **12**, cmd `0x02`, `[7]=1` | **Flash erase** at a 32-bit address | Can wipe the firmware |
| Class **12**, cmd `0x02`, `[7]=2` | Flash program | Writes arbitrary flash |
| Class **10**, cmd `0x00` | Set test VID/PID | The keyboard re-enumerates under different IDs; the app won't find it |
| Class **10**, `0x01`–`0x03`, `0x40`, `0x41` | Manufacturer/product strings, USB reset, factory defaults, production timestamp | Factory/identity data |
| Class 0, SET `0x03` with mode 2 | Device mode = DFU | Same as class 9 |
| Class 0, SET `0x02`, `0x05`, `0x07`, `0x08`, `0x11`, `0x12` | Serial number, edition, name, reset, receiver identity | Rewrites identity |
| Class 5, SET `0x05` | Reset profile to factory defaults | Loses your settings |

### Bugs in the Windows app worth knowing about

- **`SetPerformaceStatus`** builds class 12, cmd 2, `[7]=status`. With status 1 that is a **flash erase at
  address 0**. This keyboard's code path never calls it, but anyone porting the code wholesale could.
- `SetRfPair` never sets byte `[4]`, so it actually sends class 0, cmd `0x00` (the intended command is `0x23`).
- `GetWirelessRSSI` sends `0x93` instead of `0xA1`.
- `SetLedCal` sends cmd 3 (brightness) instead of 5.
- On connect, the Windows app **writes a made-up serial number** if the stored one isn't alphanumeric.
  This project does not do that.

## How this project prevents it

1. **Unrepresentable classes.** `CommandClass` (in `Protocol.swift`) has only the cases 0, 1, 3, 5, 6 and 7.
   Classes 9, 10 and 12 cannot be expressed in Swift code that uses the client, and the CLI's `get`
   command rejects them.
2. **SET allowlist.** `KeyboardClient.transact` refuses any SET that is not on this list:

   | Class | Cmd | Purpose |
   |---|---|---|
   | 3 | `0x02` | lighting effect |
   | 3 | `0x03` | brightness |
   | 3 | `0x04` | per-key frame |
   | 5 | `0x03` | active profile |

   Everything else must be a GET (bit 7 set), which only reads.
3. **Unit tests** (`SafetyTests`) fail if either guard is loosened by accident.
4. **The CLI's raw `get` command** only accepts commands with bit 7 set.

To add a feature that needs another SET (key remapping, macros, sleep time), add it to `allowedSets`
deliberately, with a comment, after checking its byte layout in [PROTOCOL.md](PROTOCOL.md).

## What has actually been written to the keyboard

During development on 2026-10-19, only these SET commands were sent:

- class 3 `0x02` (effect): static red, Raindrop, effect 18. Raindrop was always restored afterwards.
- class 3 `0x04` (frames): test patterns.

One side effect: the backlight speed field changed from 0 to 2. The firmware ignores a Raindrop write
with speed 0, and Raindrop has no speed control in the UI, so it looks the same.

## If something does go wrong

- The keyboard has an on-board factory reset. The Windows manual lists an Fn combination for it
  (often Fn + Esc held for a few seconds on Dareu keyboards; check your manual).
- If it ever shows up as PID `0xFFFA` or `0x0055`, it is in the bootloader. Connect it to a Windows PC
  and run the official app, which can update/restore the firmware.
