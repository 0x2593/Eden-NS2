# Offline helper over guest memory dumps named main-<hexbase>.bin in worklog/dumps.
#   gdis.py dis ADDR [COUNT]   disassemble COUNT instructions from ADDR
#   gdis.py str ADDR           print the NUL-terminated string at ADDR
#   gdis.py q ADDR [N]         print N little-endian u64 words at ADDR
#   gdis.py xref TARGET        list BL/B instructions that branch to TARGET
import glob, os, struct, sys
import capstone

DUMPS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "dumps")
regions = []
for path in glob.glob(os.path.join(DUMPS, "main-*.bin")):
    base = int(os.path.basename(path)[5:-4], 16)
    regions.append((base, open(path, "rb").read()))

def read(addr, size):
    for base, data in regions:
        if base <= addr and addr + size <= base + len(data):
            return data[addr - base:addr - base + size]
    raise SystemExit(f"{addr:#x} not in any dump")

cmd, addr = sys.argv[1], int(sys.argv[2], 16)
if cmd == "dis":
    count = int(sys.argv[3]) if len(sys.argv) > 3 else 40
    md = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_ARM)
    for insn in md.disasm(read(addr, count * 4), addr):
        print(f"{insn.address:#x}: {insn.mnemonic} {insn.op_str}")
elif cmd == "str":
    data = read(addr, 0x100)
    print(repr(data.split(b"\x00")[0]))
elif cmd == "q":
    n = int(sys.argv[3]) if len(sys.argv) > 3 else 8
    print(" ".join(f"{v:#x}" for v in struct.unpack(f"<{n}Q", read(addr, n * 8))))
elif cmd == "xref":
    for base, data in regions:
        for off in range(0, len(data) - 3, 4):
            word = int.from_bytes(data[off:off + 4], "little")
            if (word >> 26) in (0x25, 0x05):  # BL / B
                imm = word & 0x3ffffff
                if imm & 0x2000000:
                    imm -= 1 << 26
                if base + off + imm * 4 == addr:
                    print(f"{base + off:#x}: {'bl' if word >> 31 else 'b'}")
