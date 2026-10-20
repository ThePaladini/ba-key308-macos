"""Generates a KeyLayout table from Dareu's public web-driver profile.

    curl -sO https://dr.dareu.com/products/0101/0101.json
    python3 tools/gen_layout_dareu_json.py 0101.json ek75Keys

Key positions, labels and default HID usages come from the profile. The LED cells are NOT in the
profile. The mapping below assumes the ANSI TK51G (Dareu EK75 / Husky Nomadic) uses the same LED
grid as the ABNT2 BA-KEY308, which was calibrated on real hardware (docs/KEY-MATRIX.md). Wide ANSI
keys (Left Shift, Right Shift, Enter) get every cell they cover, so they light up whichever cell
holds the LED. Treat it as uncalibrated until someone with an EK75 checks it.
"""
import json, re, sys

src, name = sys.argv[1], sys.argv[2]
d = json.loads(re.sub(r',\s*([}\]])', r'\1', open(src, encoding="utf-8-sig").read()))
keys = [k for k in d["Keys"] if k["KeyID"] not in (171, 172)]   # knob rotation has no key cap

def row(r, ids):
    return {kid: [(r, c)] for c, kid in enumerate(ids) if kid}

CELLS = {}
CELLS |= row(0, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13])
CELLS |= row(1, [17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 31, 34])
CELLS |= row(2, [39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53])
CELLS |= row(3, [60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 0, 0, 55])
CELLS[73] = [(3, 12), (3, 13)]                                    # ANSI Enter
CELLS |= {kid: [(4, c)] for c, kid in zip(range(2, 12), range(80, 90))}
CELLS[78] = [(4, 0), (4, 1)]                                      # wide Left Shift
CELLS[91] = [(4, 12), (4, 13)]                                    # wide Right Shift
CELLS[92] = [(4, 14)]
CELLS |= row(5, [97, 98, 99])
CELLS[102] = [(5, c) for c in range(3, 9)]                       # Space
CELLS |= {106: [(5, 9)], 107: [(5, 10)], 109: [(5, 11)], 110: [(5, 12)], 111: [(5, 13)], 112: [(5, 14)]}

LABELS = {"Backspace": "⌫", "Page Up": "PgUp", "Delete": "Del", "Caps Lock": "Caps", "Page Down": "PgDn",
          "L-Shift": "Shift", "R-Shift": "Shift", "Up": "↑", "Down": "↓", "Left": "←", "Right": "→",
          "L-Ctrl": "Ctrl", "R-Ctrl": "Ctrl", "L-Win": "Win", "L-Alt": "Alt", "R-Alt": "Alt"}
MODS = {1: 0xE0, 2: 0xE1, 4: 0xE2, 8: 0xE3, 16: 0xE4, 32: 0xE5, 64: 0xE6, 128: 0xE7}

def usage(k):
    if k.get("default-function-Id") != 6:
        return 0
    data = k.get("default-function-data") or [0, 0]
    return data[1] or MODS.get(data[0], 0)

ox = min(k["margin-left"] for k in keys)
oy = min(k["margin-top"] for k in keys)
print(f"    static let {name}: [KeyDef] = [")
for k in keys:
    label = LABELS.get(k["KeyString"], k["KeyString"]).replace("\\", "\\\\").replace('"', '\\"')
    cells = ", ".join(f"MatrixCell(row: {r}, col: {c})" for r, c in CELLS.get(k["KeyID"], []))
    print(f'        KeyDef(id: {k["KeyID"]}, label: "{label}", hidUsage: {usage(k)}, '
          f'rect: CGRect(x: {k["margin-left"] - ox}, y: {k["margin-top"] - oy}, width: {k["Width"]}, height: {k["Height"]}), '
          f'cells: [{cells}]),')
print("    ]")
used = [c for v in CELLS.values() for c in v]
assert len(used) == len(set(used)), "a cell is assigned twice"
missing = {k["KeyID"] for k in keys} - set(CELLS) - {170}
assert not missing, f"keys without cells: {missing}"
