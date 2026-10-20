# Dareu product catalog (VID 0x260D)

Dareu's browser-based configuration tool, [dr.dareu.com](https://dr.dareu.com/), loads one public profile
per product from `https://dr.dareu.com/products/<PID>/<PID>.json`. This page lists what that catalog
returned for PIDs `0x0000`–`0x02FF` on **2026-10-20**: 91 keyboards and 5 receivers. A handful of
PIDs timed out and may be missing.

Each profile's `Device` block has:

- **`Model`**: the internal platform code, e.g. `TK51G`. The Basike BA-KEY308 is `TK51G_0130` in the
  Windows app.
- **`FwType`**: the firmware/protocol family. **`FwType 0` is the protocol this project implements.**
  Other values use different report IDs/sizes and command sets ([open-ek75](https://github.com/mateusands/open-ek75)
  notes the same). The Windows code has matching device families (`Tg`, `Hy`, `HyOHID`, `Ws`, `Jm`, `Qf`).

**The BA-KEY308's PID (`0x0130`) is not in Dareu's catalog.** It looks like a Basike-specific firmware
build, which fits it being a rebadged design.

## What this means for compatibility

| Group | Expectation |
|---|---|
| **TK51G + FwType 0** (Dareu EK75 `0x0045`, `0x0101`; Husky Nomadic) | Same platform and protocol as the BA-KEY308. **Recognized by the app since v1.1.0** (experimental). |
| **Other platforms + FwType 0** | Same protocol, different board and key layout. Lighting effects, brightness and battery **probably work**; per-key painting needs that model's LED map. Not recognized by the app yet. `bakey info` detects them, so please send a report. |
| **FwType ≠ 0** | Different protocol (many are Hall-effect "HE/RT" boards). **Not supported.** |

## Keyboards with FwType 0 (same protocol as this project)

| PID | Platform (`Model`) | Product | FwType | Battery |
|---|---|---|---|---|
| `0x0030` | TK51A | Z82 | 0 | yes |
| `0x0070` | TK51ARGB | Z82 PRO | 0 | yes |
| `0x0060` | TK51CF | EK87 PRO | 0 | yes |
| `0x0056` | TK51CU | A87 PRO | 0 | yes |
| `0x0091` | TK51CU | EK87 PRO 8K | 0 | no |
| `0x0150` | TK51D | EK81 MAX | 0 | no |
| `0x0045` | TK51G | EK75 | 0 | yes |
| `0x0101` | TK51G | EK75 | 0 | yes |
| `0x0163` | TK51Q | DK108 PRO | 0 | no |
| `0x0074` | TK51QF | EK106 PRO | 0 | no |
| `0x0043` | TK51QU | A104 | 0 | yes |
| `0x0090` | TK51QU | EK106 PRO 8K | 0 | no |
| `0x0206` | TK51QU | A104PRO8K V2 | 0 | yes |
| `0x0051` | TK51V | A98 | 0 | yes |
| `0x0178` | TK51V | FK98 | 0 | yes |
| `0x0167` | TK529 | DK87 PRO | 0 | no |
| `0x0170` | TK52K | EK815 MAX | 0 | no |
| `0x0161` | TK52Q | COOL 98 | 0 | yes |
| `0x0202` | TK53N | FLEX 75 | 0 | no |

## Keyboards with other firmware types (not supported)

| PID | Platform (`Model`) | Product | FwType | Battery |
|---|---|---|---|---|
| `0x0246` | TK50G | 锋刃 75 | 6 | no |
| `0x0140` | TK50TRT | CK98 MAX | 6 | no |
| `0x0208` | TK50TRT | CK98 MAX | 6 | no |
| `0x0159` | TK51C | EK87 RT 8K | 4 | no |
| `0x0180` | TK51C | EK87RT WP | 6 | no |
| `0x0237` | TK51C | EK87RT WP | 6 | no |
| `0x0081` | TK51CU | EK87 RT 8K | 4 | no |
| `0x0105` | TK51CU | EK87RT WP | 6 | no |
| `0x0138` | TK51CU | A87 Master 8K | 2 | no |
| `0x0129` | TK51D | CK75 | 6 | no |
| `0x0162` | TK51D | CK75 08G | 4 | no |
| `0x0193` | TK51D | CK75 | 6 | no |
| `0x0201` | TK51D | CK75 | 6 | no |
| `0x0223` | TK51D | CK75 | 6 | no |
| `0x0230` | TK51D | CK75 | 6 | no |
| `0x0232` | TK51D | CK75 | 6 | no |
| `0x0249` | TK51D | CK75 | 6 | no |
| `0x0107` | TK51G | EK75 | 6 | no |
| `0x0113` | TK51G | VICTOR HE | 6 | no |
| `0x0115` | TK51G | EK75 | 6 | no |
| `0x0124` | TK51G | CK75 PRO | 6 | no |
| `0x0131` | TK51G | EK75 | 6 | no |
| `0x0132` | TK51G | EK75 | 6 | no |
| `0x0152` | TK51G | CK75 PRO | 6 | no |
| `0x0174` | TK51G | CK75 PRO | 6 | no |
| `0x0187` | TK51G | CK75 PRO | 6 | no |
| `0x0188` | TK51G | 猎光75 | 6 | no |
| `0x0192` | TK51G | CK75 PRO | 6 | no |
| `0x0239` | TK51G | 猎光75 | 6 | no |
| `0x0139` | TK51N | CK100 | 6 | no |
| `0x0164` | TK51N | CK100 | 6 | no |
| `0x0205` | TK51N | CK100 | 6 | no |
| `0x0224` | TK51N | CK100 | 6 | no |
| `0x0106` | TK51Q | EK108 RT | 6 | no |
| `0x0137` | TK51Q | A104 Master  8K | 2 | no |
| `0x0160` | TK51Q | EK106 RT 8K | 4 | no |
| `0x0179` | TK51Q | EK108 RT | 6 | no |
| `0x0238` | TK51Q | EK108 RT | 6 | no |
| `0x0252` | TK51Q | CK108 HE | 6 | no |
| `0x0075` | TK51QRT8K | EK106 RT 8K | 4 | no |
| `0x0136` | TK51V | A98 RT | 6 | yes |
| `0x0067` | TK51WU | CK98 PRO RT | 4 | no |
| `0x0092` | TK52K | EK815 PRO | 6 | no |
| `0x0078` | TK52L | A75 PRO | 4 | yes |
| `0x0083` | TK52L | A75 HE | 4 | no |
| `0x0145` | TK52L | A75 HE | 4 | no |
| `0x0166` | TK52Q | CK98 Ultra | 6 | no |
| `0x0191` | TK52Q | COOL 98 | 6 | no |
| `0x0194` | TK52Q | CK98 Ultra | 6 | no |
| `0x0195` | TK52Q | CK98 Ultra | 6 | no |
| `0x0196` | TK52Q | CK98 Ultra | 6 | no |
| `0x0209` | TK52Q | CK98 Ultra | 6 | no |
| `0x0216` | TK52Q | CK98 Ultra | 6 | no |
| `0x0103` | TK52U | CK87 MAX | 6 | no |
| `0x0169` | TK52U | CK87 MAX | 6 | no |
| `0x0241` | TK52U | CK87 MAX | 6 | no |
| `0x0253` | TK52U | CK87 MAX | 6 | no |
| `0x0126` | TK52W | 影刃 | 6 | no |
| `0x0175` | TK53H | A68 | 6 | no |
| `0x0233` | TK53M | Flex 98 | 1 | no |
| `0x0234` | TK53N | FLEX 75 | 6 | no |
| `0x0210` | TK53P | FLEX 87 | 1 | yes |
| `0x0236` | TK53Q | 影刃75 | 6 | no |
| `0x0244` | TK53V | 冰刃75 | 6 | no |
| `0x0117` | TK599 | COOL 60 / EK60 HE | 6 | no |
| `0x0119` | TK599 | COOL 60 / EK60 HE | 6 | no |
| `0x0123` | TK599 | COOL 60 / EK60 HE | 6 | no |
| `0x0127` | TK599 | COOL 60 / EK60 HE | 6 | no |
| `0x0198` | TK599 | COOL 60 / EK60 HE | 6 | no |
| `0x0199` | TK599 | COOL 60 / EK60 HE | 6 | no |
| `0x0214` | TK599 | COOL 60 / EK60 HE | 6 | no |
| `0x0229` | TK599 | COOL 60 / EK60 HE | 6 | no |

## Receivers

| PID | Platform (`Model`) | Product | FwType | Battery |
|---|---|---|---|---|
| `0x0037` | Dongle | USB 2.4G Receiver | 0 | no |
| `0x0042` | Dongle | USB 2.4G Receiver | 0 | no |
| `0x0112` | Dongle | USB 2.4G Receiver | 7 | no |
| `0x0211` | Dongle | USB 2.4G Receiver | 1 | no |
| `0x0146` | TK51Q | USB 2.4G Receiver | 2 | no |

---

Regenerate it by fetching each `products/<PID>/<PID>.json` and reading its `Device` block. Requests
should be sequential or lightly parallel, since it is someone else's server.
