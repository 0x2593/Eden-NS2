# Minimal GDB remote-protocol client for Eden's gdbstub: let the guest run, interrupt it after a
# delay, then dump pc/lr/sp/x0-x2 of every guest thread plus code bytes around each pc.
import socket, sys, time

def checksum(data):
    return sum(data.encode()) & 0xff

class Rsp:
    def __init__(self, port):
        for _ in range(60):
            try:
                self.s = socket.create_connection(("127.0.0.1", port), timeout=30)
                break
            except OSError:
                time.sleep(1)
        else:
            raise SystemExit("could not connect")
        self.buf = b""

    def send(self, data):
        self.s.sendall(f"${data}#{checksum(data):02x}".encode())

    def recv(self, timeout=30):
        self.s.settimeout(timeout)
        while True:
            start = self.buf.find(b"$")
            end = self.buf.find(b"#", start)
            if start >= 0 and end >= 0 and len(self.buf) >= end + 3:
                packet = self.buf[start + 1:end].decode(errors="replace")
                self.buf = self.buf[end + 3:]
                self.s.sendall(b"+")
                return packet
            chunk = self.s.recv(65536)
            if not chunk:
                raise SystemExit("connection closed")
            self.buf += chunk

    def cmd(self, data):
        self.send(data)
        return self.recv()

def le64(hexstr):
    try:
        return int.from_bytes(bytes.fromhex(hexstr[:16]), "little") if hexstr and not hexstr.startswith("E") else None
    except ValueError:
        return None

delay = float(sys.argv[1]) if len(sys.argv) > 1 else 60
rsp = Rsp(6543)
print("stop:", rsp.cmd("?"))
rsp.send("c")
time.sleep(delay)
rsp.s.sendall(b"\x03")
stop = rsp.recv(60)
print("stop:", stop)
stop_thread = stop.split("thread:")[1].split(";")[0] if "thread:" in stop else "1"
threads = []
reply = rsp.cmd("qfThreadInfo")
while reply.startswith("m"):
    threads += reply[1:].split(",")
    reply = rsp.cmd("qsThreadInfo")
print("threads:", threads)
threads_pc = {}
for tid in threads:
    rsp.cmd(f"Hg{tid}")
    regs = {name: le64(rsp.cmd(f"p{num:x}")) for name, num in
            (("pc", 32), ("lr", 30), ("sp", 31), ("x0", 0), ("x1", 1), ("x2", 2), ("x8", 8))}
    extra = rsp.cmd(f"qThreadExtraInfo,{tid}")
    try:
        extra = bytes.fromhex(extra).decode(errors="replace")
    except ValueError:
        pass
    threads_pc[tid] = regs["pc"]
    print(f"thread {tid} [{extra}] " + " ".join(f"{k}={v:#x}" if v is not None else f"{k}=?" for k, v in regs.items()))
    if regs["pc"]:
        code = rsp.cmd(f"m{regs['pc'] - 32:x},64")
        words = [code[i:i + 8] for i in range(0, len(code), 8)]
        print("   code@pc-32:", " ".join(bytes.fromhex(w)[::-1].hex() for w in words if len(w) == 8))

# Detailed view of the thread that was running when interrupted.
try:
    import capstone
    md = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_ARM)
except ImportError:
    md = None

def read(addr, size):
    data = rsp.cmd(f"m{addr:x},{size:x}")
    return None if data.startswith("E") else bytes.fromhex(data)

def disasm(addr, before=0x40, after=0x40, label=""):
    data = read(addr - before, before + after)
    print(f"--- {label} around {addr:#x}")
    if data is None or md is None:
        print("   ", data.hex() if data else "unreadable")
        return
    for insn in md.disasm(data, addr - before):
        mark = "=>" if insn.address == addr else "  "
        print(f" {mark} {insn.address:#x}: {insn.mnemonic} {insn.op_str}")

current = stop_thread
# Prefer a thread executing inside the main module (0x80020000..0x82000000): that is game code.
for tid, pc in threads_pc.items():
    if pc and 0x80020000 <= pc < 0x82000000:
        current = tid
        break
rsp.cmd(f"Hg{current}")
regs = {}
packet = rsp.cmd("g")
for num in range(33):
    chunk = packet[num * 16:(num + 1) * 16]
    regs[num] = le64(chunk) if len(chunk) == 16 else None
print(f"current thread {current}:")
print("  " + " ".join(f"x{n}={v:#x}" if v is not None else f"x{n}=?" for n, v in regs.items() if n < 31))
print(f"  sp={regs[31]} pc={regs[32]:#x}" if regs[32] else "  pc=?")
if regs[32]:
    disasm(regs[32], 0x80, 0x40, "pc")
if regs[30]:
    disasm(regs[30], 0x40, 0x10, "lr")
fp = regs[29]
for depth in range(12):
    if not fp:
        break
    frame = read(fp, 16)
    if not frame:
        break
    fp, ret = int.from_bytes(frame[:8], "little"), int.from_bytes(frame[8:], "little")
    print(f"  frame {depth}: return {ret:#x}")
    if depth < 4:
        disasm(ret, 0x30, 0x8, f"caller {depth}")
# Extra probes from the command line: "u32:ADDR" reads a word, "dis:ADDR" disassembles forward.
for probe in sys.argv[2:]:
    kind, _, rest = probe.partition(":")
    addr, _, length = rest.partition(":")
    length = length.split(":")[0]
    addr = int(addr, 16)
    length = int(length, 16) if length else 0x80
    if kind == "u32":
        data = read(addr, 16)
        print(f"  [{addr:#x}] =", [int.from_bytes(data[i:i + 4], "little") for i in range(0, 16, 4)] if data else "unreadable")
    elif kind == "dump":
        # dump:ADDR:LEN:path, read in 0x800-byte packets
        target = rest.split(":")[2]
        with open(target, "wb") as out:
            for offset in range(0, length, 0x800):
                chunk = read(addr + offset, min(0x800, length - offset))
                out.write(chunk if chunk else bytes(min(0x800, length - offset)))
        print(f"  dumped {length:#x} bytes at {addr:#x} to {target}")
    elif kind == "words":
        data = read(addr, length or 0x100)
        if data:
            for row in range(0, len(data), 32):
                print(f"  {addr + row:#x}:", " ".join(f"{int.from_bytes(data[i:i + 4], 'little'):08x}" for i in range(row, min(row + 32, len(data)), 4)))
    elif kind == "str":
        data = read(addr, length or 0x80)
        print(f"  str@{addr:#x}:", data.split(b"\0")[0].decode(errors="replace") if data else "unreadable")
    elif kind == "regstr":
        # regstr:N  -> string at register xN
        reg = regs.get(addr)
        data = read(reg, 0x80) if reg else None
        print(f"  x{addr} -> {reg:#x}: " + (repr(data.split(b"\0")[0][:120]) if data else "unreadable") if reg else f"  x{addr}: ?")
    elif kind == "regmem":
        reg = regs.get(addr)
        data = read(reg, length or 0x40) if reg else None
        if data:
            print(f"  [x{addr}={reg:#x}]:", " ".join(f"{int.from_bytes(data[i:i+8],'little'):016x}" for i in range(0, len(data), 8)))
        else:
            print(f"  [x{addr}]: unreadable")
    elif kind == "dis":
        disasm(addr, 0, length, "probe")
rsp.s.close()
