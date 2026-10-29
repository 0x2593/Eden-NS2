# Decodes dumped native pushbuffers (native-submit-*.bin) into method writes and prints the ones
# that touch QMD scheduling (0xad address, 0xae-0xb0 PCAS) or mention a given value.
import struct, sys, glob, os

def decode(words):
    i = 0
    while i < len(words):
        header = words[i]
        method, subchannel, count, kind = header & 0x1fff, (header >> 13) & 7, (header >> 16) & 0x1fff, header >> 29
        i += 1
        if kind == 4:  # immediate data
            yield subchannel, method, count
        elif kind in (1, 3, 5):
            for n in range(count):
                if i >= len(words):
                    return
                m = method + (n if kind == 1 else (1 if kind == 5 and n else 0))
                yield subchannel, m, words[i]
                i += 1
        elif kind == 0 and header == 0:
            continue
        else:
            yield subchannel, -1, header

needle = int(sys.argv[2], 16) if len(sys.argv) > 2 else None
for path in sorted(glob.glob(sys.argv[1]), key=os.path.getmtime):
    data = open(path, "rb").read()
    words = struct.unpack(f"<{len(data) // 4}I", data[:len(data) // 4 * 4])
    hits = []
    for sub, method, value in decode(words):
        if method in (0xad, 0xae, 0xaf, 0xb0) or (needle is not None and value == needle):
            hits.append(f"s{sub}:{method:#x}={value:#x}")
    if hits:
        print(os.path.basename(path), " ".join(hits))
