# hangdump.py DELAY : let the guest run DELAY seconds, interrupt, then print every guest thread's
# pc/lr/x0-x3 and its frame-pointer backtrace (12 frames).
import os, sys, time
_source = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "rsp.py"), encoding="utf-8").read()
exec(_source.split("\ndelay = ")[0])
rsp = Rsp(6543)
print("attach:", rsp.cmd("?"), flush=True)
time.sleep(2)
rsp.send("c")
time.sleep(5)
rsp.s.settimeout(0.5)
try:
    print("early:", rsp.s.recv(256), flush=True)
except OSError:
    pass
time.sleep(float(sys.argv[1]))
rsp.s.sendall(b"\x03")
print("stop:", rsp.recv(60), flush=True)
def reg(n):
    for _ in range(5):
        r = rsp.cmd(f"p{n:x}")
        if len(r) == 16: return int.from_bytes(bytes.fromhex(r), "little")
    return 0
def q(addr):
    for _ in range(3):
        r = rsp.cmd(f"m{addr:x},8")
        if len(r) == 16: return int.from_bytes(bytes.fromhex(r), "little")
    return 0
threads, reply = [], rsp.cmd("qfThreadInfo")
while reply.startswith("m"):
    threads += reply[1:].split(",")
    reply = rsp.cmd("qsThreadInfo")
for tid in threads:
    rsp.cmd(f"Hg{tid}")
    extra = rsp.cmd(f"qThreadExtraInfo,{tid}")
    try: extra = bytes.fromhex(extra).decode(errors="replace")
    except ValueError: pass
    pc, lr, fp = reg(32), reg(30), reg(29)
    frames = []
    for _ in range(12):
        if not fp or fp & 7: break
        nfp, ret = q(fp), q(fp + 8)
        frames.append(ret); fp = nfp
    print(f"thread {tid} [{extra}] pc={pc:#x} lr={lr:#x} x0={reg(0):#x} x1={reg(1):#x} x2={reg(2):#x} x3={reg(3):#x}\n   bt: " +
          " ".join(f"{f:#x}" for f in frames), flush=True)
    if 0x82e1c300 <= pc < 0x82e1c440:
        regs = {n: reg(n) for n in range(19, 29)}
        print("   NVN sync wait: " + " ".join(f"x{n}={v:#x}" for n, v in regs.items()), flush=True)
        for r in (25, 19, 27):
            print(f"   [x{r}] = " + " ".join(f"{q(regs[r] + o):#x}" for o in range(0, 0x40, 8)), flush=True)
for extra in sys.argv[2:]:
    a = int(extra, 16)
    print(f"[{a:#x}] = " + " ".join(f"{q(a + o):#x}" for o in range(0, 0x30, 8)), flush=True)
rsp.send("D")
rsp.s.close()
