import json, sys
keys = json.load(open(sys.argv[1]))
# Firmware LED matrix, calibrated on the real keyboard (2026-10-19). 0 = no LED.
M = [
    [1,2,3,4,5,6,7,8,9,10,11,12,13,0,0],
    [17,18,19,20,21,22,23,24,25,26,27,28,29,31,34],
    [39,40,41,42,43,44,45,46,47,48,49,50,51,73,53],
    [60,61,62,63,64,65,66,67,68,69,70,71,0,52,55],
    [78,100,80,81,82,83,84,85,86,87,88,89,135,91,92],
    [97,98,99,102,102,102,102,102,102,106,107,109,110,111,112],
]
labels = {1:"Esc",17:"'",28:"-",29:"=",31:"⌫",34:"PgUp",39:"Tab",50:"´",51:"[",52:"]",53:"Del",
          60:"Caps",70:"Ç",71:"~",73:"Enter",55:"PgDn",78:"Shift",100:"\\",87:",",88:".",89:";",
          135:"/",91:"Shift",92:"↑",97:"Ctrl",98:"Win",99:"Alt",102:"Space",106:"AltGr",107:"Fn",
          109:"Ctrl",110:"←",111:"↓",112:"→",170:"Mute"}
cells = {}
for r,row in enumerate(M):
    for c,k in enumerate(row):
        if k: cells.setdefault(k, []).append((r,c))
ox, oy = 77.0, 21.0
out = []
for k in keys:
    if len(k["pts"]) < 2 or k["pts"][1] == (0.0,0.0) or k["pts"][1] == [0.0,0.0]: continue
    (x1,y1),(x2,y2) = k["pts"][:2]
    if x2 == 0: continue
    lab = labels.get(k["id"], k["name"])
    cl = ", ".join(f"MatrixCell(row: {r}, col: {c})" for r,c in cells.get(k["id"], []))
    lab = lab.replace("\\","\\\\").replace('"','\\"')
    out.append(f'        KeyDef(id: {k["id"]}, label: "{lab}", hidUsage: {k["hid"]}, '
               f'rect: CGRect(x: {x1-ox:g}, y: {y1-oy:g}, width: {x2-x1:g}, height: {y2-y1:g}), cells: [{cl}]),')
missing = set(cells) - {k["id"] for k in keys}
assert not missing, missing
print("\n".join(out))
