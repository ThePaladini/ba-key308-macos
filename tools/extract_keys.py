import re, sys, json
src = open(sys.argv[1], encoding="utf-8").read()
block = src[src.index("_keyUnitArray"):src.index("_hidKeyMap")]
pat = re.compile(r'new KeyUnit\(\(byte\)(\d+), \(byte\)(\d+), "([^"]*)",(?: "[^"]*",)? \(Point\[\]\)\(object\)new Point\[\d+\]\s*\{(.*?)\}\)', re.S)
keys = []
for m in pat.finditer(block):
    pts = [tuple(map(float, p)) for p in re.findall(r'new Point\(([-\d.]+), ([-\d.]+)\)', m.group(4))]
    keys.append(dict(id=int(m.group(1)), hid=int(m.group(2)), name=m.group(3), pts=pts))
json.dump(keys, open(sys.argv[2], "w"))
print(len(keys))
for k in keys: print(k["id"], k["hid"], k["name"], k["pts"])
