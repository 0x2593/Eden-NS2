# Lists a dumped native (SM70+) shader: offset, opcode (12-bit), NAK op name, and the 4 words.
import json, struct, sys
names = {int(k, 16): v for k, v in json.load(open(__file__.replace("shlist.py", "sm70_opcodes.json"))).items()}
data = open(sys.argv[1], "rb").read()
header = int(sys.argv[2], 16) if len(sys.argv) > 2 else 0x50
for offset in range(header, len(data) - 15, 16):
    words = struct.unpack_from("<4I", data, offset)
    op = words[0] & 0xfff
    label = "/".join(names.get(op & 0x1ff, ["?"]))
    print(f"{offset - header:#06x}: {op:#05x} {label:<14} {words[0]:08x} {words[1]:08x} {words[2]:08x} {words[3]:08x}")
    if op == 0x94d and words[1] == 0 and words[2] == 0:  # EXIT
        break
