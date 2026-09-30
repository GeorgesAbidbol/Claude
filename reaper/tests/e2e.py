"""Runs fake_host with the built extension and checks the OSC it sends."""
import socket, struct, subprocess, sys, time

def parse(pkt):
    def s(i):
        j = pkt.index(b"\0", i)
        return pkt[i:j].decode(), (j + 4) & ~3
    addr, i = s(0)
    tags, i = s(i)
    args = []
    for t in tags[1:]:
        if t == "s":
            v, i = s(i)
        elif t == "i":
            v = struct.unpack(">i", pkt[i:i + 4])[0]; i += 4
        elif t == "f":
            v = round(struct.unpack(">f", pkt[i:i + 4])[0], 4); i += 4
        args.append(v)
    return addr, args

host, ext = sys.argv[1], sys.argv[2]
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(("127.0.0.1", 0))
sock.settimeout(0.05)
port = sock.getsockname()[1]
proc = subprocess.Popen([host, ext, str(port)], stdout=subprocess.PIPE, text=True)
got = []
t0 = None
while proc.poll() is None or True:
    try:
        data = sock.recv(2048)
        now = time.monotonic()
        if t0 is None:
            t0 = now
        got.append((round(now - t0, 3), parse(data)))
    except socket.timeout:
        if proc.poll() is not None:
            break
print(proc.stdout.read())
for g in got:
    print(g)

msgs = [m for _, m in got]
expected = [
    # first pass 0.0 -> 1.2
    ("/cmd", ["Goto Sequence 1 Cue 1"]),        # marker intro 0.25
    ("/cmd", ["Go+ Sequence 12"]),              # kick 0.5
    ("/13.13.1.6.5", ["Flash", 1]),             # snare on 0.75
    ("/13.13.1.6.5", ["Flash", 0]),             # snare off 0.875
    ("/cmd", ["Go+ Sequence 12"]),              # kick 1.0
    # seek to 0.9 -> 3.2
    ("/cmd", ["Go+ Sequence 12"]),              # kick 1.0 again
    ("/cmd", ["Goto Sequence 1 Cue 2"]),        # marker refrain 1.5
    ("/cmd", ["Go+ Sequence 12"]),              # looped kick 2.0
    ("/cmd", ["Go+ Sequence 12"]),              # looped kick 2.5
    # label action
    ("/cmd", ['Label Sequence 1 Cue 1 "intro"']),
    ("/cmd", ["Label Sequence 1 Cue 2 \"refrain '1'\""]),
]
ok = msgs == [(a, b) for a, b in expected]
# Timing inside the first pass: kick at 0.5 s should arrive ~0.25 s after the intro marker.
dt = got[1][0] - got[0][0] if len(got) > 1 else -1
timing_ok = abs(dt - 0.25) < 0.02
print("order/content:", "OK" if ok else "MISMATCH")
print("timing kick-marker: %.3f s (expected 0.250)" % dt, "OK" if timing_ok else "BAD")
sys.exit(0 if ok and timing_ok and proc.returncode == 0 else 1)
