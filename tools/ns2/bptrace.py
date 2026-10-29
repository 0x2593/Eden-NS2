# Traces every hit of a breakpoint: prints thread, x30, xN and three qwords at xN+OFFs, stepping over
# the breakpoint each time. Stops at the first non-breakpoint stop (e.g. a crash) or after MAX hits.
#   bptrace.py ADDR REG OFF1,OFF2,OFF3 MAX
import os, sys
_source = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "rsp.py"), encoding="utf-8").read()
exec(_source.split("\ndelay = ")[0])

addrs = [int(a, 16) for a in sys.argv[1].split(",")]
regs_wanted = [int(r) for r in sys.argv[2].split(",")]
reg = regs_wanted[0]
offsets = [int(o, 16) for o in sys.argv[3].split(",")]
limit = int(sys.argv[4])
rsp = Rsp(6543)
rsp.cmd("?")
for a in addrs:
    rsp.cmd(f"Z0,{a:x},4")
for hit in range(limit):
    rsp.send("c")
    stop = rsp.recv(900)
    thread = stop.split("thread:")[1].split(";")[0] if "thread:" in stop else "?"
    fields = dict(part.split(":", 1) for part in stop[3:].split(";") if ":" in part)
    # Stop-reply register values are raw hex; le64() would mistake a leading 'E' for an error.
    raw = lambda key: int.from_bytes(bytes.fromhex(fields[key][:16]), "little") if key in fields else 0
    pc = raw("20")
    lr = raw("1e")
    if pc not in addrs:
        print(f"other stop: {stop}", flush=True)
        break
    rsp.cmd(f"Hg{thread}")
    base = None
    for attempt in range(3):
        base = le64(rsp.cmd(f"p{reg:x}"))
        if base is not None:
            break
    if base is None:
        print(f"hit {hit}: could not read x{reg}", flush=True)
        base = 0
    values = []
    for off in offsets:
        data = rsp.cmd(f"m{base + off:x},8")
        values.append(int.from_bytes(bytes.fromhex(data), "little") if not data.startswith("E") else -1)
    others = []
    for r in regs_wanted[1:]:
        value = le64(rsp.cmd(f"p{r:x}"))
        others.append(f"x{r}={value:#x}" if value is not None else f"x{r}=?")
    print(f"hit {hit} pc={pc:#x} thread={thread} lr={lr:#x} x{reg}={base:#x} " + " ".join(others) + " " + " ".join(f"{v:#x}" for v in values), flush=True)
    # Step over the breakpoint: remove, single-step, reinsert.
    rsp.cmd(f"z0,{pc:x},4")
    rsp.send(f"vCont;s:{thread}")
    rsp.recv(60)
    rsp.cmd(f"Z0,{pc:x},4")
rsp.s.close()
