# tools

Scripts from the reverse-engineering session (see ../docs/REVERSE-ENGINEERING.md).

| Script | Purpose |
|---|---|
| `extract_keys.py <TK51G_0130.cs> <keys.json>` | Pulls key IDs, HID usages, labels and rectangles out of the decompiled product class |
| `gen_layout.py <keys.json>` | Combines them with the calibrated LED matrix (edit `M` inside) and prints the `KeyDef` lines for `Sources/BAKeyCore/KeyLayout.swift` |
| `bakey_probe.py` | The original Python + hidapi (ctypes, Homebrew `libhidapi`) driver used for the first experiments |

`TK51G_0130.cs` comes from decompiling `Products/TK51G_0130.dll` with `ilspycmd -p`.
The vendor's code is not included in this repository.
