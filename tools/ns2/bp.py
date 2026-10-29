# Sets a breakpoint through Eden's gdbstub, runs until it hits, then dumps registers and memory.
#   bp.py ADDR [stack-words] [hits]
import os, sys
# Reuse the client class and helpers from rsp.py without running its main body.
_source = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "rsp.py"), encoding="utf-8").read()
exec(_source.split("\ndelay = ")[0])

addr = int(sys.argv[1], 16)
words = int(sys.argv[2], 16) if len(sys.argv) > 2 else 0x10
hits = int(sys.argv[3]) if len(sys.argv) > 3 else 1
# Extra dumps after each hit: "rN:LEN" dumps LEN bytes at register xN, "aADDR:LEN" at a fixed address,
# "pN:OFF:LEN" dumps LEN bytes at *(xN + OFF).
extra = sys.argv[4:]

def qwords(raw):
    return " ".join(f"{int.from_bytes(raw[i:i + 8], 'little'):x}" for i in range(0, len(raw) - 7, 8))
rsp = Rsp(6543)
print("stop:", rsp.cmd("?"))
print("set bp:", rsp.cmd(f"Z0,{addr:x},4"))
for hit in range(hits):
    rsp.send("c")
    stop = rsp.recv(600)
    print("hit:", stop)
    packet = rsp.cmd("g")
    regs = [le64(packet[i * 16:(i + 1) * 16]) for i in range(33)]
    print("  " + " ".join(f"x{i}={v:#x}" for i, v in enumerate(regs[:31]) if v is not None))
    sp = regs[31]
    data = rsp.cmd(f"m{sp:x},{words * 4:x}")
    if not data.startswith("E"):
        raw = bytes.fromhex(data)
        print("  stack:", " ".join(f"{int.from_bytes(raw[i:i + 4], 'little'):08x}" for i in range(0, len(raw), 4)))
    for spec in extra:
        parts = spec[1:].split(":")
        if spec[0] == "r":
            base, length = regs[int(parts[0])], int(parts[1], 16)
        elif spec[0] == "p":
            pointer = rsp.cmd(f"m{regs[int(parts[0])] + int(parts[1], 16):x},8")
            base, length = int.from_bytes(bytes.fromhex(pointer), "little"), int(parts[2], 16)
        else:
            base, length = int(parts[0], 16), int(parts[1], 16)
        data = rsp.cmd(f"m{base:x},{length:x}") if base else "E00"
        print(f"  {spec} @ {base:#x}:", qwords(bytes.fromhex(data)) if not data.startswith("E") else data)
rsp.cmd(f"z0,{addr:x},4")
rsp.s.close()
