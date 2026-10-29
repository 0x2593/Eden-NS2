# pcsample.py DELAY COUNT : run DELAY seconds, then interrupt COUNT times (0.3 s apart) and tally
# the stopped thread, pc and lr from each stop reply.
import os, sys, time, collections
_source = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "rsp.py"), encoding="utf-8").read()
exec(_source.split("\ndelay = ")[0])
rsp = Rsp(6543)
print("attach:", rsp.cmd("?"), flush=True)
time.sleep(2)
rsp.send("c")
time.sleep(float(sys.argv[1]))
tally = collections.Counter()
for i in range(int(sys.argv[2])):
    rsp.s.sendall(b"\x03")
    stop = rsp.recv(120)
    fields = dict(part.split(":", 1) for part in stop[3:].split(";") if ":" in part)
    raw = lambda key: int.from_bytes(bytes.fromhex(fields[key][:16]), "little") if key in fields else 0
    tally[(fields.get("thread", "?"), raw("20"), raw("1e"))] += 1
    rsp.send("c")
    time.sleep(0.3)
for (thread, pc, lr), n in tally.most_common(25):
    print(f"{n:3} thread={thread} pc={pc:#x} lr={lr:#x}", flush=True)
rsp.s.sendall(b"\x03"); rsp.recv(60); rsp.send("D")
