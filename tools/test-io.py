#!/usr/bin/env python3
"""End-to-end tests of every Scenic source and destination type.

Each case pushes known content (a solid colour, a sine, a message) through the
real application and checks what comes out with a tool independent of Scenic:
gst-launch-1.0, ffmpeg, shflow, aseqdump, or a Python socket.
See docs/src/development.md.

    test-io.py [-k PATTERN ...] [--roundtrip] [--list] [--keep]

Exit status: 0 if nothing failed, 1 otherwise, 77 if every case was skipped.
"""
import argparse
import json
import os
import queue
import shlex
import shutil
import signal
import socket
import struct
import subprocess
import sys
import threading
import time
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
TMP = Path(os.environ.get("TMPDIR", "/tmp")) / "scenic-io"
# The app's GStreamer: SCENIC_GST_SDK as in tools/env.sh, or the system's.
# "System" GStreamer below is always the one on the PATH, which hosts the
# shmdata elements: SCENIC_SHMDATA_GST names the directory of a shmdata build's
# GStreamer plugin when it is not installed. SCENIC_SHFLOW is sh4lt's shflow.
SDK = Path(os.environ["SCENIC_GST_SDK"]) if os.environ.get("SCENIC_GST_SDK") else None
SHMDATA_GST = os.environ.get("SCENIC_SHMDATA_GST", "")
SHFLOW = Path(os.environ.get("SCENIC_SHFLOW") or shutil.which("shflow") or "/nonexistent/shflow")
SIGNALLER = "ws://127.0.0.1:8453"
W, H = 64, 36   # size frames are verified at

# --- environments ------------------------------------------------------------
def sdk_env():
    e = dict(os.environ)
    if SDK is None:
        return sys_env()
    lib = SDK / ("lib/%s-linux-gnu" % os.uname().machine)
    if not lib.is_dir():
        lib = SDK / "lib"
    e.update(LD_LIBRARY_PATH=str(lib),
             GST_PLUGIN_SYSTEM_PATH_1_0=str(lib / "gstreamer-1.0"),
             GST_PLUGIN_SCANNER=str(SDK / "libexec/gstreamer-1.0/gst-plugin-scanner"),
             GST_REGISTRY_1_0=str(Path(os.environ.get("TMPDIR", "/tmp"))
                                  / "scenic-gst-sdk-registry.bin"))
    return e


def sys_env():
    e = {k: v for k, v in os.environ.items()
         if k not in ("LD_LIBRARY_PATH", "GST_PLUGIN_SYSTEM_PATH_1_0",
                      "GST_PLUGIN_SCANNER", "GST_REGISTRY_1_0")}
    if SHMDATA_GST:
        e["GST_PLUGIN_PATH"] = SHMDATA_GST
    e["GST_REGISTRY_1_0"] = str(Path(os.environ.get("TMPDIR", "/tmp"))
                                / "scenic-io-sys-registry.bin")
    return e


def gst_launch(system):
    return str(SDK / "bin/gst-launch-1.0") if SDK and not system else "gst-launch-1.0"


# --- outcomes ------------------------------------------------------------------
class Fail(Exception):
    pass


class Skip(Exception):
    pass


def check(cond, msg):
    if not cond:
        raise Fail(msg)


# --- prerequisites -------------------------------------------------------------
_have = {}


def have(what):
    """Whether the machine offers `what`; memoised. Raises nothing."""
    if what not in _have:
        _have[what] = _probe(what)
    return _have[what]


def _run_ok(argv, env=None, timeout=10):
    try:
        return subprocess.run(argv, env=env, stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL, timeout=timeout).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def _probe(what):
    kind, _, arg = what.partition(":")
    if kind == "display":
        return bool(os.environ.get("DISPLAY")) and _run_ok(["xset", "q"])
    if kind == "sdk":        # an element of the SDK's GStreamer
        inspect = str(SDK / "bin/gst-inspect-1.0") if SDK else "gst-inspect-1.0"
        return _run_ok([inspect, "--exists", arg], env=sdk_env())
    if kind == "sys":        # an element of the system GStreamer
        return _run_ok(["gst-inspect-1.0", "--exists", arg], env=sys_env())
    if kind == "tool":
        return shutil.which(arg) is not None
    if kind == "shflow":
        return SHFLOW.exists()
    if kind == "v4l2loopback":
        return loopback_device() is not None
    if kind == "pipewire":
        return _run_ok(["pw-cli", "info", "0"])
    if kind == "midithrough":
        try:
            return "Midi Through" in subprocess.run(
                ["aconnect", "-l"], capture_output=True, text=True).stdout
        except OSError:
            return False
    if kind == "python":
        try:
            __import__(arg)
            return True
        except ImportError:
            return False
    if kind == "env":
        return bool(os.environ.get(arg))
    if kind == "os":
        return sys.platform.startswith(arg)
    raise ValueError(what)


def loopback_device():
    """The v4l2loopback device labelled scenic-test, if any."""
    for d in Path("/sys/class/video4linux").glob("video*"):
        try:
            if (d / "name").read_text().strip() == "scenic-test":
                return "/dev/" + d.name
        except OSError:
            pass
    return None


# --- OSC / SLIP ----------------------------------------------------------------
def _pad(b):
    return b + b"\0" * (4 - len(b) % 4)


def osc_encode(address, *args):
    tags, data = ",", b""
    for a in args:
        if isinstance(a, int):
            tags, data = tags + "i", data + struct.pack(">i", a)
        elif isinstance(a, float):
            tags, data = tags + "f", data + struct.pack(">f", a)
        else:
            tags, data = tags + "s", data + _pad(str(a).encode())
    return _pad(address.encode()) + _pad(tags.encode()) + data


def osc_decode(packet):
    def string(b, i):
        end = b.index(b"\0", i)
        return b[i:end].decode(), (end + 4) & ~3
    address, i = string(packet, 0)
    tags, i = string(packet, i)
    args = []
    for t in tags[1:]:
        if t == "i":
            args.append(struct.unpack(">i", packet[i:i + 4])[0]); i += 4
        elif t == "f":
            args.append(struct.unpack(">f", packet[i:i + 4])[0]); i += 4
        elif t == "s":
            s, i = string(packet, i); args.append(s)
    return address, args


END, ESC, ESC_END, ESC_ESC = 0xC0, 0xDB, 0xDC, 0xDD


def slip_encode(b):
    out = bytearray([END])
    for x in b:
        out += {END: bytes([ESC, ESC_END]), ESC: bytes([ESC, ESC_ESC])}.get(x, bytes([x]))
    out.append(END)
    return bytes(out)


def slip_decode(stream):
    frames, cur, esc = [], bytearray(), False
    for x in stream:
        if esc:
            cur.append(END if x == ESC_END else ESC)
            esc = False
        elif x == ESC:
            esc = True
        elif x == END:
            if cur:
                frames.append(bytes(cur))
            cur = bytearray()
        else:
            cur.append(x)
    return frames


# --- signal checks ---------------------------------------------------------------
def frames_of(path):
    data = Path(path).read_bytes() if Path(path).exists() else b""
    n = len(data) // (W * H * 3)
    return np.frombuffer(data[:n * W * H * 3], np.uint8).reshape(n, H, W, 3)


def check_colour(frames, rgb, tol=24, region=(0.35, 0.65, 0.35, 0.65), min_frames=3):
    check(len(frames) >= min_frames, "only %d frame(s) arrived" % len(frames))
    y0, y1, x0, x1 = region
    f = frames[-1][int(H * y0):int(H * y1), int(W * x0):int(W * x1)]
    got = f.reshape(-1, 3).mean(axis=0)
    check(all(abs(got[i] - rgb[i]) <= tol for i in range(3)),
          "colour [%d,%d,%d], expected %s" % (got[0], got[1], got[2], list(rgb)))
    return "%d frames, colour [%d,%d,%d]" % (len(frames), got[0], got[1], got[2])


def samples_of(path):
    return np.fromfile(path, np.int16).astype(np.float64) if Path(path).exists() else np.zeros(0)


def dominant(s, rate=48000):
    n = min(len(s), 1 << 15)
    seg = s[-n:] * np.hanning(n)
    spec = np.abs(np.fft.rfft(seg))
    freqs = np.fft.rfftfreq(n, 1.0 / rate)
    return freqs[1 + np.argmax(spec[1:])], spec, freqs


def check_tone(s, hz):
    check(len(s) > 4800, "only %d sample(s) arrived" % len(s))
    rms = np.sqrt((s[-24000:] ** 2).mean())
    check(rms > 100, "silent (rms %.0f)" % rms)
    dom, _, _ = dominant(s)
    check(abs(dom - hz) / hz < 0.03, "dominant %.0f Hz, expected %d Hz" % (dom, hz))
    return "%.0f Hz, rms %.0f" % (dom, rms)


def check_ltc(s):
    """Biphase-mark code: zero crossings are one half-bit or one bit apart,
    so the intervals between them take exactly two values, one twice the
    other."""
    check(len(s) > 4800, "only %d sample(s) arrived" % len(s))
    x = s[-48000:] - s[-48000:].mean()
    check(np.sqrt((x ** 2).mean()) > 100, "silent")
    d = np.diff(np.where(np.diff(np.sign(x)) != 0)[0])
    half = np.median(d[d <= (d.min() + d.max()) / 2])
    fit = np.mean((np.abs(d - half) <= half * 0.25) | (np.abs(d - 2 * half) <= half * 0.4))
    check(fit > 0.95, "%.0f%% of the zero crossings fit a biphase code" % (fit * 100))
    return "biphase, %.0f bit/s" % (48000 / (2 * half))


# --- one case's processes ------------------------------------------------------------
class Ctx:
    roundtrip = False
    keep = False

    def __init__(self, name):
        self.name = name
        self.dir = TMP / name.replace("/", "-")
        shutil.rmtree(self.dir, ignore_errors=True)
        self.dir.mkdir(parents=True)
        self.procs = []
        self.app = None

    def path(self, name):
        return str(self.dir / name)

    def spawn(self, argv, name, env=None):
        log = open(self.path(name + ".log"), "w")
        p = subprocess.Popen(argv, env=env, stdout=log, stderr=subprocess.STDOUT,
                             stdin=subprocess.DEVNULL, start_new_session=True)
        self.procs.append(p)
        return p

    def gst(self, pipeline, name, system=False):
        """A background gst-launch-1.0 (a producer, or a live consumer)."""
        return self.spawn([gst_launch(system), "-e"] + shlex.split(pipeline), name,
                          sys_env() if system else sdk_env())

    def capture(self, source, name, seconds=4, system=False, audio=False):
        """Run `source` into a raw file for a few seconds, then stop it with EOS."""
        out = self.path(name + (".s16" if audio else ".rgb"))
        tail = ("audioconvert ! audioresample ! audio/x-raw,format=S16LE,channels=1,rate=48000"
                if audio else
                "videoconvert ! videoscale ! video/x-raw,format=RGB,width=%d,height=%d" % (W, H))
        p = self.gst("%s ! %s ! filesink location=%s" % (source, tail, out), name, system)
        stop(p, seconds)
        return samples_of(out) if audio else frames_of(out)

    def cleanup(self):
        if self.app:
            self.app.kill()
        for p in self.procs:
            stop(p, 0)

    # the application ------------------------------------------------------------
    def run(self, spec, verify, offscreen=False, after=None):
        """Launch Scenic on `spec`, verify once READY (and again after a session
        reload with --roundtrip), release it, and check that it ended well."""
        self.app = App(self, spec, offscreen)
        self.app.wait("READY")
        result = [verify()]
        if (Ctx.roundtrip or spec.get("roundtrip")) and not spec.get("remove"):
            self.app.release()
            self.app.wait("RELOADED")
            try:
                result.append("after reload: " + verify())
            except Fail as e:
                raise Fail("after reload: %s" % e)
        self.app.release()
        self.app.finish()
        if after:
            result.append(after())
        return "; ".join(r for r in result if r)


def stop(p, after):
    """Let a process run `after` seconds more, then interrupt it (EOS for
    gst-launch -e) and, failing that, kill it."""
    try:
        p.wait(after)
        return
    except subprocess.TimeoutExpired:
        pass
    for sig, wait in ((signal.SIGINT, 5), (signal.SIGKILL, 5)):
        try:
            os.killpg(p.pid, sig)
            p.wait(wait)
            return
        except (subprocess.TimeoutExpired, ProcessLookupError):
            pass


class App:
    def __init__(self, ctx, spec, offscreen):
        self.ctx = ctx
        self.release_file = ctx.path("release")
        spec = dict({"roundtrip": Ctx.roundtrip}, **spec,
                    release=self.release_file, signaller=SIGNALLER)
        Path(ctx.path("spec.json")).write_text(json.dumps(spec, indent=1))
        env = dict(os.environ,
                   SCENIC_SCENARIO=str(ROOT / "tools/scenarios/io.qml"),
                   SCENIC_IO_SPEC=ctx.path("spec.json"),
                   SCENIC_NODE_PATH=str(ROOT / "tools/fixtures"),
                   SCENIC_NO_THUMBS="1")
        if offscreen:
            # headless runs render nothing: keep them on the null graphics backend
            env.pop("DISPLAY", None)
        try:
            (Path.home() / ".config/ossia/failsafe.bit").unlink()
        except OSError:
            pass
        argv = [str(ROOT / "run.sh")] + (["-platform", "offscreen"] if offscreen else [])
        self.since = int(time.time())
        self.log = open(ctx.path("scenic.log"), "w")
        self.p = subprocess.Popen(argv, env=env, cwd=ROOT, stdout=subprocess.PIPE,
                                  stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                                  text=True, errors="replace", start_new_session=True)
        self.lines = queue.Queue()
        self.failures = []
        threading.Thread(target=self._read, daemon=True).start()

    @property
    def pid(self):
        return self.p.pid   # run.sh execs the score binary

    def _read(self):
        for line in self.p.stdout:
            self.log.write(line)
            self.log.flush()
            if "[io] FAIL:" in line:
                self.failures.append(line.split("[io] FAIL:", 1)[1].strip())
            if "[io]" in line:
                self.lines.put(line)
        self.lines.put(None)

    def wait(self, marker, timeout=60):
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                line = self.lines.get(timeout=0.5)
            except queue.Empty:
                continue
            if line is None:
                raise Fail("Scenic exited before %s: %s" % (marker, "; ".join(self.failures)
                                                           or "see scenic.log"))
            if self.failures:
                raise Fail("scenario: " + "; ".join(self.failures))
            if "[io] " + marker in line:
                time.sleep(2)   # let the media start flowing
                return
        raise Fail("Scenic never reported %s" % marker)

    def release(self):
        Path(self.release_file).write_text("")

    def finish(self, timeout=40):
        try:
            code = self.p.wait(timeout)
        except subprocess.TimeoutExpired:
            self.kill()
            raise Fail("Scenic did not exit")
        check(not self.failures, "scenario: " + "; ".join(self.failures))
        if code != 0:
            r = subprocess.run(
                ["sh", "-c", '. "$0/lib-exit.sh"; classify_exit "$1" "$2" scenic "$3"',
                 str(ROOT / "tools"), str(code), str(self.since), self.ctx.path("scenic.log")],
                capture_output=True, text=True, env=dict(os.environ, HERE=str(ROOT / "tools")))
            check(r.returncode == 0, "exit status %d: %s" % (code, r.stdout.strip()))

    def kill(self):
        if self.p.poll() is None:
            stop(self.p, 0)


# --- specs ------------------------------------------------------------------------
PORTS = iter(range(15600, 16600))


def argb(rgb):
    return "0xFF%02X%02X%02X" % rgb


def solid(rgb, caps="video/x-raw,width=320,height=180,framerate=30/1"):
    return ("videotestsrc is-live=true pattern=solid-color foreground-color=%s ! %s"
            % (argb(rgb), caps))


def video_tap(port):
    """A gstvideoout serving raw frames, caps in-band (GDP), over TCP."""
    return {"as": "tap", "kind": "gstvideoout", "params": {
        "pipeline": "appsrc name=video ! videoconvert ! videoscale"
                    " ! video/x-raw,format=RGB,width=160,height=90 ! gdppay"
                    " ! tcpserversink host=127.0.0.1 port=%d sync=false" % port,
        "width": 320, "height": 180}}


def video_tap_src(port):
    return "tcpclientsrc host=127.0.0.1 port=%d ! gdpdepay" % port


def audio_tap(port):
    return {"as": "tap", "kind": "gstaudioout", "params": {
        "tail": "audioconvert ! audioresample"
                " ! audio/x-raw,format=S16BE,rate=48000,channels=1 ! rtpL16pay"
                " ! udpsink host=127.0.0.1 port=%d sync=false" % port,
        "channels": 2}}


def audio_tap_src(port):
    return ('udpsrc port=%d caps="application/x-rtp,media=audio,clock-rate=48000,'
            'encoding-name=L16,encoding-params=1,channels=1,payload=96"'
            ' ! rtpjitterbuffer latency=100 ! rtpL16depay' % port)


def data_tap(port, codec="osc"):
    return {"as": "tap", "kind": "udpout",
            "params": {"host": "127.0.0.1", "port": port, "codec": codec}}


def data_feed(port, codec="osc"):
    return {"as": "feed", "kind": "udpin",
            "params": {"bind": "127.0.0.1", "port": port, "codec": codec}}


def solid_node(rgb):
    return {"as": "src", "kind": "solidcolor", "params": {"color": argb(rgb)}}


def sine_node(hz):
    return {"as": "src", "kind": "sine", "params": {"freq": str(hz)}}


def io(src, dst):
    return {"connect": [["src" if src is None else src, dst]]}


# --- UDP helpers --------------------------------------------------------------------
class UdpListener:
    def __init__(self, port):
        self.s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.s.bind(("127.0.0.1", port))
        self.s.settimeout(0.2)

    def packets(self, seconds, until=None):
        got, deadline = [], time.time() + seconds
        while time.time() < deadline:
            try:
                got.append(self.s.recv(65536))
            except socket.timeout:
                continue
            if until and until(got[-1]):
                break
        return got


def send_until(send, listener, match, seconds=6):
    """Send repeatedly until `listener` receives a packet satisfying `match`."""
    deadline = time.time() + seconds
    while time.time() < deadline:
        send()
        for pkt in listener.packets(0.5):
            if match(pkt):
                return pkt
    raise Fail("nothing matching arrived")


def udp_send(port, payload):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.sendto(payload, ("127.0.0.1", port))
    s.close()


def is_osc(address, value):
    def m(pkt):
        try:
            a, args = osc_decode(pkt)
            return a == address and args and abs(float(args[0]) - value) < 1e-3
        except (ValueError, struct.error, IndexError):
            return False
    return m


# --- WebRTC helpers ------------------------------------------------------------------
def signaller(c):
    c.spawn([str(SDK / "bin/gst-webrtc-signalling-server") if SDK else "gst-webrtc-signalling-server", "--host", "127.0.0.1",
             "--port", SIGNALLER.rsplit(":", 1)[1]], "signaller", sdk_env())
    time.sleep(1)


def producer_id(name, timeout=15, exclude=()):
    import asyncio
    import websockets

    async def look():
        async with websockets.connect(SIGNALLER) as ws:
            await ws.recv()   # welcome
            await ws.send(json.dumps({"type": "setPeerStatus", "roles": ["listener"],
                                      "meta": {"peer_name": "test-io"}}))
            deadline = time.time() + timeout
            while time.time() < deadline:
                await ws.send(json.dumps({"type": "list"}))
                try:
                    msg = json.loads(await asyncio.wait_for(ws.recv(), 2))
                except asyncio.TimeoutError:
                    continue
                for p in msg.get("producers", []):
                    if (p.get("meta") or {}).get("name") == name and p["id"] not in exclude:
                        return p["id"]
                await asyncio.sleep(1)
        return None
    pid = asyncio.run(look())
    check(pid, "producer %r never appeared on the signalling server" % name)
    return pid


def webrtc_producer(c, name, media):
    meta = 'meta="meta,name=(string)%s,peer_name=(string)test-io,media_type=(string)%s"' % (
        name, "video" if isinstance(media, tuple) else "audio")
    if isinstance(media, tuple):
        src = solid(media) + " ! videoconvert"
    else:
        src = "audiotestsrc is-live=true freq=%d ! audioconvert" % media
    c.gst("%s ! webrtcsink signaller::uri=%s %s" % (src, SIGNALLER, meta), "producer")


def webrtc_consumer_src(pid):
    return "webrtcsrc signaller::uri=%s signaller::producer-peer-id=%s" % (SIGNALLER, pid)


# --- PipeWire helpers ------------------------------------------------------------------
def pw_link(src, dst, timeout=10):
    """Link the output ports of PipeWire node `src` to the input ports of
    `dst`, in order. score's audio engine is a filter node, which the session
    manager does not link on its own."""
    def ports(flag, node):
        out = subprocess.run(["pw-link", flag], capture_output=True, text=True).stdout
        return sorted(l.strip() for l in out.splitlines() if l.strip().startswith(node + ":"))
    deadline = time.time() + timeout
    while time.time() < deadline:
        outs, ins = ports("-o", src), ports("-i", dst)
        if outs and ins:
            for o, i in zip(outs, ins):
                subprocess.run(["pw-link", o, i], capture_output=True)
            return True
        time.sleep(0.5)
    return False


# --- the cases -----------------------------------------------------------------------
CASES = []


def case(name, needs=()):
    def reg(fn):
        CASES.append((name, tuple(needs), fn))
        return fn
    return reg


GPU = ("display",)

# video inputs ------------------------------------------------------------------------


@case("video-in/videotest", GPU)
def _(c):
    t = next(PORTS)
    # the fourth of the seven SMPTE bars, green, is at the centre; the expected
    # value is what GStreamer itself renders for it
    region = (0.1, 0.4, 0.46, 0.54)
    ref = c.path("ref.rgb")
    subprocess.run([gst_launch(False), "-q"] + shlex.split(
        "videotestsrc num-buffers=1 pattern=smpte ! videoconvert ! videoscale"
        " ! video/x-raw,format=RGB,width=%d,height=%d ! filesink location=%s" % (W, H, ref)),
        env=sdk_env(), check=True, timeout=30)
    f = frames_of(ref)[0][int(H * region[0]):int(H * region[1]),
                          int(W * region[2]):int(W * region[3])]
    rgb = tuple(int(v) for v in f.reshape(-1, 3).mean(axis=0))
    return c.run({"nodes": [{"as": "src", "kind": "videotest"}, video_tap(t)],
                  **io(None, "tap")},
                 lambda: check_colour(c.capture(video_tap_src(t), "tap"), rgb,
                                      tol=12, region=region))


@case("video-in/gstvideoin", GPU)
def _(c):
    p, t, rgb = next(PORTS), next(PORTS), (0, 200, 60)
    c.gst(solid(rgb) + " ! videoconvert ! video/x-raw,format=I420 ! jpegenc ! rtpjpegpay"
          " ! udpsink host=127.0.0.1 port=%d" % p,
          "producer")
    pipeline = ('udpsrc port=%d caps="application/x-rtp,media=video,clock-rate=90000,'
                'encoding-name=JPEG,payload=26" ! rtpjpegdepay ! jpegdec ! videoconvert'
                ' ! video/x-raw,format=RGBA ! appsink name=video' % p)
    return c.run({"nodes": [{"as": "src", "kind": "gstvideoin", "params": {
                      "pipeline": pipeline, "width": 320, "height": 180}}, video_tap(t)],
                  **io(None, "tap")},
                 lambda: check_colour(c.capture(video_tap_src(t), "tap"), rgb, tol=30))


@case("video-in/ffmpegin", GPU + ("sdk:x264enc",))
def _(c):
    p, t, rgb = next(PORTS), next(PORTS), (220, 40, 40)
    c.gst(solid(rgb) + " ! videoconvert ! x264enc tune=zerolatency key-int-max=15"
          " ! mpegtsmux ! udpsink host=127.0.0.1 port=%d" % p, "producer")
    return c.run({"nodes": [{"as": "src", "kind": "ffmpegin", "params": {
                      "path": "udp://127.0.0.1:%d" % p, "options": ""}}, video_tap(t)],
                  **io(None, "tap")},
                 lambda: check_colour(c.capture(video_tap_src(t), "tap"), rgb, tol=40))


@case("video-in/filevideo", GPU + ("sdk:x264enc",))
def _(c):
    t, rgb, clip = next(PORTS), (40, 40, 220), c.path("clip.mkv")
    subprocess.run([gst_launch(False), "-q"] + shlex.split(
        "videotestsrc num-buffers=300 pattern=solid-color foreground-color=%s"
        " ! video/x-raw,width=320,height=180,framerate=30/1 ! videoconvert ! x264enc"
        " ! matroskamux ! filesink location=%s" % (argb(rgb), clip)),
        env=sdk_env(), check=True, timeout=60)
    return c.run({"nodes": [{"as": "src", "kind": "filevideo", "params": {"path": clip}},
                            video_tap(t)], **io(None, "tap")},
                 lambda: check_colour(c.capture(video_tap_src(t), "tap"), rgb, tol=40))


@case("video-in/camera", GPU + ("v4l2loopback",))
def _(c):
    t, rgb = next(PORTS), (200, 120, 0)
    c.gst(solid(rgb, "video/x-raw,format=YUY2,width=640,height=480,framerate=30/1")
          + " ! v4l2sink device=%s" % loopback_device(), "producer")
    time.sleep(1)
    return c.run({"nodes": [{"as": "src", "kind": "camera", "pick": "scenic-test"},
                            video_tap(t)], **io(None, "tap")},
                 lambda: check_colour(c.capture(video_tap_src(t), "tap"), rgb, tol=30))


@case("video-in/ndiin", GPU + ("sdk:ndisink",))
def _(c):
    t, rgb = next(PORTS), (0, 160, 200)
    c.gst(solid(rgb, "video/x-raw,format=UYVY,width=320,height=180,framerate=30/1")
          + " ! ndisink ndi-name=scenic-io-ndiin", "producer")
    time.sleep(2)
    return c.run({"nodes": [{"as": "src", "kind": "ndiin", "pick": "scenic-io-ndiin"},
                            video_tap(t)], **io(None, "tap")},
                 lambda: check_colour(c.capture(video_tap_src(t), "tap"), rgb, tol=30))


@case("video-in/shmdatain", GPU + ("sys:shmdatasink",))
def _(c):
    t, rgb, sock = next(PORTS), (160, 0, 160), c.path("shm-in")
    c.gst(solid(rgb, "video/x-raw,format=RGBA,width=320,height=180,framerate=30/1")
          + " ! shmdatasink socket-path=%s" % sock, "producer", system=True)
    time.sleep(1)
    return c.run({"nodes": [{"as": "src", "kind": "shmdatain", "params": {"path": sock}},
                            video_tap(t)], **io(None, "tap")},
                 lambda: check_colour(c.capture(video_tap_src(t), "tap"), rgb))


@case("video-in/sh4ltin", GPU)
def _(c):
    # no sh4lt writer exists outside score: Scenic's own sh4ltout feeds it
    t, rgb = next(PORTS), (120, 200, 0)
    return c.run({"nodes": [solid_node(rgb),
                            {"as": "out", "kind": "sh4ltout", "params": {"path": "scenic-io-loop"}},
                            {"as": "in", "kind": "sh4ltin", "params": {"path": "scenic-io-loop"}},
                            video_tap(t)],
                  "connect": [["src", "out"], ["in", "tap"]]},
                 lambda: check_colour(c.capture(video_tap_src(t), "tap"), rgb))


@case("video-in/pipewirein", GPU + ("pipewire", "sys:pipewiresink"))
def _(c):
    t, rgb = next(PORTS), (255, 90, 160)
    c.gst(solid(rgb, "video/x-raw,format=RGBA,width=320,height=180,framerate=30/1")
          + ' ! pipewiresink mode=provide stream-properties="props,media.class=Video/Source,'
            'node.name=scenic-io-pwin,node.description=scenic-io-pwin"',
          "producer", system=True)
    time.sleep(1)
    return c.run({"nodes": [{"as": "src", "kind": "pipewirein", "pick": "scenic-io-pwin"},
                            video_tap(t)], **io(None, "tap")},
                 lambda: check_colour(c.capture(video_tap_src(t), "tap"), rgb))


def capture_window(c, rgb):
    """A window of colour `rgb` on the display: (id, x, y, width, height)."""
    prod = c.gst(solid(rgb, "video/x-raw,width=320,height=240,framerate=30/1")
                 + " ! videoconvert ! ximagesink", "producer", system=True)
    for _ in range(40):
        ids = subprocess.run(["xdotool", "search", "--onlyvisible", "--pid", str(prod.pid)],
                             capture_output=True, text=True).stdout.split()
        if ids:
            wid = ids[-1]
            # clear of Scenic's own window, which opens at the top left
            subprocess.run(["xdotool", "windowmove", "--sync", wid, "1580", "820"])
            subprocess.run(["xdotool", "windowraise", wid])
            geo = subprocess.run(["xdotool", "getwindowgeometry", "--shell", wid],
                                 capture_output=True, text=True).stdout
            g = dict(l.split("=") for l in geo.split())
            return wid, int(g["X"]), int(g["Y"]), int(g["WIDTH"]), int(g["HEIGHT"])
        time.sleep(0.25)
    raise Fail("the producer window never appeared")


@case("video-in/windowcapture-window", GPU + ("tool:xdotool", "sys:ximagesink"))
def _(c):
    t, rgb = next(PORTS), (250, 250, 0)
    wid = capture_window(c, rgb)[0]
    subprocess.run(["xdotool", "set_window", "--name", "scenic-io-capture", wid])
    return c.run({"nodes": [{"as": "src", "kind": "windowcapture", "params": {
                      "mode": 0, "title": "scenic-io-capture", "screen": "",
                      "rpos": [0, 0], "rsize": [640, 480]}}, video_tap(t)],
                  **io(None, "tap")},
                 lambda: check_colour(c.capture(video_tap_src(t), "tap"), rgb))


@case("video-in/windowcapture-region", GPU + ("tool:xdotool", "sys:ximagesink"))
def _(c):
    t, rgb = next(PORTS), (0, 250, 250)
    _, x, y, w, h = capture_window(c, rgb)
    # the middle of the window, clear of any decoration
    return c.run({"nodes": [{"as": "src", "kind": "windowcapture", "params": {
                      "mode": 3, "title": "", "screen": "",
                      "rpos": [x + w // 4, y + h // 4], "rsize": [w // 2, h // 2]}},
                            video_tap(t)], **io(None, "tap")},
                 lambda: check_colour(c.capture(video_tap_src(t), "tap"), rgb))


@case("video-in/webrtcsub_video", GPU + ("sdk:webrtcsink", "python:websockets"))
def _(c):
    t, rgb = next(PORTS), (90, 0, 220)
    signaller(c)
    webrtc_producer(c, "scenic-io-v", rgb)
    return c.run({"nodes": [{"as": "src", "kind": "webrtcsub_video", "webrtc": "scenic-io-v"},
                            video_tap(t)], **io(None, "tap")},
                 lambda: check_colour(c.capture(video_tap_src(t), "tap", seconds=6), rgb,
                                      tol=40))


@case("video-in/gphoto2", GPU + ("env:SCENIC_IO_GPHOTO2",))
def _(c):
    t = next(PORTS)

    def live():
        frames = c.capture(video_tap_src(t), "tap")
        check(len(frames) >= 3, "only %d frame(s) arrived" % len(frames))
        check(frames[-1].mean() > 8, "the frames are black")
        return "%d frames" % len(frames)
    return c.run({"nodes": [{"as": "src", "kind": "gphoto2",
                             "pick": os.environ.get("SCENIC_IO_GPHOTO2", "")},
                            video_tap(t)], **io(None, "tap")}, live)


@case("video-in/spoutin", ("os:win",))
def _(c):
    raise Skip("not implemented off Windows")


@case("video-in/syphonin", ("os:darwin",))
def _(c):
    raise Skip("not implemented off macOS")


# audio inputs ------------------------------------------------------------------------

@case("audio-in/audiotest")
def _(c):
    t = next(PORTS)
    return c.run({"nodes": [{"as": "src", "kind": "audiotest"}, audio_tap(t)],
                  **io(None, "tap")},
                 lambda: check_tone(c.capture(audio_tap_src(t), "tap", audio=True), 440),
                 offscreen=True)


@case("audio-in/gstaudioin")
def _(c):
    p, t = next(PORTS), next(PORTS)
    c.gst("audiotestsrc is-live=true freq=660 ! audioconvert"
          " ! audio/x-raw,format=S16BE,rate=48000,channels=1 ! rtpL16pay"
          " ! udpsink host=127.0.0.1 port=%d" % p, "producer")
    pipeline = (audio_tap_src(p) + " ! audioconvert ! audioresample"
                " ! audio/x-raw,format=F32LE,rate=48000,channels=2 ! appsink name=audio")
    return c.run({"nodes": [{"as": "src", "kind": "gstaudioin",
                             "params": {"pipeline": pipeline}}, audio_tap(t)],
                  **io(None, "tap")},
                 lambda: check_tone(c.capture(audio_tap_src(t), "tap", audio=True), 660),
                 offscreen=True)


@case("audio-in/fileaudio")
def _(c):
    t, wav = next(PORTS), c.path("tone.wav")
    subprocess.run([gst_launch(False), "-q"] + shlex.split(
        "audiotestsrc num-buffers=1500 freq=523 ! audioconvert ! wavenc"
        " ! filesink location=%s" % wav), env=sdk_env(), check=True, timeout=60)
    return c.run({"nodes": [{"as": "src", "kind": "fileaudio", "params": {"path": wav}},
                            audio_tap(t)], **io(None, "tap")},
                 lambda: check_tone(c.capture(audio_tap_src(t), "tap", audio=True), 523),
                 offscreen=True)


@case("audio-in/ltcgen")
def _(c):
    t = next(PORTS)
    return c.run({"nodes": [{"as": "src", "kind": "ltcgen"}, audio_tap(t)],
                  **io(None, "tap")},
                 lambda: check_ltc(c.capture(audio_tap_src(t), "tap", audio=True)),
                 offscreen=True)


@case("audio-in/audioin", ("pipewire", "sys:pipewiresink", "tool:pw-link"))
def _(c):
    t = next(PORTS)

    def verify():
        c.gst("audiotestsrc is-live=true freq=880 volume=0.5 ! audioconvert"
              " ! audio/x-raw,channels=2 ! pipewiresink"
              ' stream-properties="props,node.name=scenic-io-play,node.autoconnect=false"',
              "producer", system=True)
        if not pw_link("scenic-io-play", "ossia score"):
            raise Skip("no PipeWire node 'ossia score' (another audio backend?)")
        time.sleep(2)
        return check_tone(c.capture(audio_tap_src(t), "tap", audio=True), 880)
    return c.run({"nodes": [{"as": "src", "kind": "audioin"}, audio_tap(t)],
                  **io(None, "tap")}, verify, offscreen=True)


@case("audio-in/webrtcsub_audio", ("sdk:webrtcsink", "python:websockets"))
def _(c):
    t = next(PORTS)
    signaller(c)
    webrtc_producer(c, "scenic-io-a", 330)
    return c.run({"nodes": [{"as": "src", "kind": "webrtcsub_audio", "webrtc": "scenic-io-a"},
                            audio_tap(t)], **io(None, "tap")},
                 lambda: check_tone(c.capture(audio_tap_src(t), "tap", seconds=6,
                                              audio=True), 330),
                 offscreen=True)


# video outputs ---------------------------------------------------------------------

@case("video-out/gstvideoout", GPU)
def _(c):
    t, rgb = next(PORTS), (30, 220, 220)
    return c.run({"nodes": [solid_node(rgb), video_tap(t)], **io(None, "tap")},
                 lambda: check_colour(c.capture(video_tap_src(t), "tap"), rgb))


@case("video-out/window", GPU + ("tool:xdotool", "tool:xwininfo", "sys:ximagesrc"))
def _(c):
    rgb = (240, 60, 0)

    def verify():
        wid = None
        r = subprocess.run(["xdotool", "search", "--pid", str(c.app.pid)],
                           capture_output=True, text=True)
        for w in r.stdout.split():
            info = subprocess.run(["xwininfo", "-id", w], capture_output=True, text=True).stdout
            if "Width: 320" in info and "Height: 180" in info and "IsViewable" in info:
                wid = w
        check(wid, "no 320x180 monitor window")
        return check_colour(c.capture("ximagesrc xid=%s use-damage=false" % wid,
                                      "window", system=True), rgb, tol=30)
    return c.run({"nodes": [solid_node(rgb),
                            {"as": "out", "kind": "window",
                             "deviceParams": {"/size": [320, 180], "/position": [40, 40]}}],
                  **io(None, "out")}, verify)


@case("video-out/ndiout", GPU + ("sdk:ndisrc",))
def _(c):
    rgb = (0, 90, 255)

    def verify():
        names = ["%s (scenic-io-ndiout)" % h
                 for h in (socket.gethostname().upper(), socket.gethostname())]
        last = None
        # NDI discovery is by mDNS and sometimes takes longer than a capture
        for n in names * 2:
            try:
                return check_colour(c.capture(
                    'ndisrc ndi-name="%s" ! ndisrcdemux name=d d.video ! queue' % n,
                    "ndi", seconds=6), rgb, tol=30)
            except Fail as e:
                last = e
        raise last
    return c.run({"nodes": [solid_node(rgb),
                            {"as": "out", "kind": "ndiout", "params": {"path": "scenic-io-ndiout"}}],
                  **io(None, "out")}, verify)


@case("video-out/shmdataout", GPU + ("sys:shmdatasrc",))
def _(c):
    rgb, sock = (255, 0, 120), c.path("shm-out")
    return c.run({"nodes": [solid_node(rgb),
                            {"as": "out", "kind": "shmdataout", "params": {"path": sock}}],
                  **io(None, "out")},
                 lambda: check_colour(c.capture("shmdatasrc socket-path=%s" % sock, "shm",
                                                system=True), rgb))


@case("video-out/sh4ltout", GPU + ("shflow",))
def _(c):
    rgb = (0, 120, 60)

    def verify():
        p = subprocess.Popen([str(SHFLOW), "-m", "8", "-f", "ui8", "-i", " ", "scenic-io-sh4lt"],
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                             start_new_session=True)
        time.sleep(3)
        os.killpg(p.pid, signal.SIGINT)
        out = p.communicate(timeout=5)[0]
        Path(c.path("shflow.log")).write_text(out)
        # frame lines read "<n>  size: <bytes>  data: r g b a r g b a ..."
        rows = [l.split("data:", 1)[1].split() for l in out.splitlines() if "data:" in l]
        check(rows, "shflow printed no frame values")
        vals = [int(v) for v in rows[-1] if v.isdigit()]
        got = tuple(vals[0:3])
        check(all(abs(got[i] - rgb[i]) <= 12 for i in range(3)),
              "first pixel %s, expected %s" % (got, rgb))
        return "%d frames, first pixel %s" % (len(rows), got)
    return c.run({"nodes": [solid_node(rgb),
                            {"as": "out", "kind": "sh4ltout", "params": {"path": "scenic-io-sh4lt"}}],
                  **io(None, "out")}, verify)


@case("video-out/pipewireout", GPU + ("pipewire", "sys:pipewiresrc"))
def _(c):
    rgb = (200, 0, 0)
    return c.run({"nodes": [solid_node(rgb),
                            {"as": "out", "kind": "pipewireout", "params": {"path": "scenic-io-pwout"}}],
                  **io(None, "out")},
                 lambda: check_colour(c.capture("pipewiresrc target-object=scenic-io-pwout",
                                                "pw", system=True), rgb))


@case("video-out/record", GPU)
def _(c):
    rgb, path = (90, 200, 90), c.path("recording.mp4")
    spec = {"nodes": [solid_node(rgb),
                      {"as": "out", "kind": "record", "params": {"path": path}}],
            "remove": ["out"], **io(None, "out")}

    def after():
        return "file: " + check_colour(decode_file(c, path, "rec"), rgb, tol=40)
    return c.run(spec, lambda: "", after=after)


@case("video-out/gst-record-across-rebuild", GPU)
def _(c):
    # A GStreamer recording must survive the graph rebuild that adding another
    # output causes: the file holds what was recorded before it, too.
    rgb, path = (90, 90, 200), c.path("rec.mjpeg")
    spec = {"nodes": [solid_node(rgb),
                      {"as": "rec", "kind": "gstvideoout", "params": {
                          "pipeline": "appsrc name=video ! videoconvert"
                                      " ! video/x-raw,format=I420 ! jpegenc"
                                      " ! multipartmux ! filesink location=" + path,
                          "width": 320, "height": 180}},
                      {"as": "other", "kind": "gstvideoout", "after_ms": 6000,
                       "params": {"pipeline": "appsrc name=video ! fakesink",
                                  "width": 320, "height": 180}}],
            "connect": [["src", "rec"]], "remove": ["rec"]}
    def verify():
        time.sleep(3)
        return ""

    def after():
        frames = Path(path).read_bytes().count(b"\xff\xd8\xff") if Path(path).exists() else 0
        # about 6 s before the rebuild and 3 s after it, at 30 fps
        check(frames >= 180, "%d frames recorded: what came before the rebuild is lost"
              % frames)
        return "%d frames across the rebuild" % frames
    return c.run(spec, verify, after=after)


@case("video-out/rtmp", GPU + ("tool:ffmpeg",))
def _(c):
    rgb, port = (255, 200, 0), next(PORTS)
    out = c.path("rtmp.rgb")
    ff = c.spawn(["ffmpeg", "-loglevel", "error", "-listen", "1", "-i",
                  "rtmp://127.0.0.1:%d/live/io" % port, "-frames:v", "60",
                  "-vf", "scale=%d:%d" % (W, H), "-pix_fmt", "rgb24", "-f", "rawvideo",
                  "-y", out], "ffmpeg")
    time.sleep(1)

    def verify():
        stop(ff, 15)
        return check_colour(frames_of(out), rgb, tol=40)
    return c.run({"nodes": [solid_node(rgb),
                            {"as": "out", "kind": "rtmp", "params": {
                                "url": "rtmp://127.0.0.1:%d/live" % port, "key": "io"}}],
                  **io(None, "out")}, verify)


@case("video-out/srt", GPU + ("tool:sh",))
def _(c):
    # The node listens, and blocks while it waits for a peer: the verifier has
    # to be calling already, so it retries until the listener is up.
    rgb, port = (0, 255, 160), next(PORTS)
    out = c.path("srt.rgb")
    caller = ("%s -e srtsrc uri=srt://127.0.0.1:%d?mode=caller ! tsdemux ! h264parse"
              " ! avdec_h264 ! videoconvert ! videoscale"
              " ! video/x-raw,format=RGB,width=%d,height=%d ! filesink location=%s"
              % (gst_launch(False), port, W, H, out))
    loop = c.spawn(["sh", "-c", 'until [ -s "$0" ]; do %s; sleep 0.5; done' % caller, out],
                   "srt", sdk_env())

    def verify():
        time.sleep(4)
        stop(loop, 0)
        return check_colour(frames_of(out), rgb, tol=40)
    return c.run({"nodes": [solid_node(rgb),
                            {"as": "out", "kind": "srt", "params": {
                                "uri": "srt://:%d?mode=listener&listen_timeout=20000000" % port}}],
                  **io(None, "out")}, verify)


def decode_file(c, path, name):
    """Decode a recorded file to frames at the verification size."""
    out = c.path(name + ".rgb")
    subprocess.run([gst_launch(False), "-q"] + shlex.split(
        "filesrc location=%s ! decodebin ! videoconvert ! videoscale"
        " ! video/x-raw,format=RGB,width=%d,height=%d ! filesink location=%s"
        % (path, W, H, out)), env=sdk_env(), timeout=60)
    return frames_of(out)


@case("video-out/ffmpegout", GPU)
def _(c):
    rgb, port = (160, 90, 255), next(PORTS)
    rx = UdpListener(port)

    def verify():
        # recorded, then decoded from its start: a demuxer joining a live
        # MPEG-TS mid-stream is unreliable, independently of the output
        ts = c.path("udp.ts")
        with open(ts, "wb") as f:
            for pkt in rx.packets(4):
                f.write(pkt)
        return check_colour(decode_file(c, ts, "udp"), rgb, tol=40)
    return c.run({"nodes": [solid_node(rgb),
                            {"as": "out", "kind": "ffmpegout", "params": {
                                "path": "udp://127.0.0.1:%d?pkt_size=1316" % port,
                                "muxer": "mpegts", "encoder": "libx264",
                                "options": "preset=ultrafast, tune=zerolatency, g=15"}}],
                  **io(None, "out")}, verify)


@case("video-out/webrtcpub_video", GPU + ("sdk:webrtcsrc", "python:websockets"))
def _(c):
    rgb = (255, 128, 0)
    signaller(c)
    seen = set()

    def verify():
        # after a reload, the new publication, not the one that went away
        pid = producer_id("scenic-io-pubv", exclude=seen)
        seen.add(pid)
        return check_colour(c.capture(webrtc_consumer_src(pid), "consumer", seconds=8),
                            rgb, tol=40)
    return c.run({"nodes": [solid_node(rgb),
                            {"as": "out", "kind": "webrtcpub_video", "params": {
                                "uri": SIGNALLER, "name": "scenic-io-pubv", "peer": "scenic"}}],
                  **io(None, "out")}, verify)


@case("video-out/spoutout", ("os:win",))
def _(c):
    raise Skip("not implemented off Windows")


@case("video-out/syphonout", ("os:darwin",))
def _(c):
    raise Skip("not implemented off macOS")


# audio outputs ---------------------------------------------------------------------

@case("audio-out/gstaudioout")
def _(c):
    t = next(PORTS)
    return c.run({"nodes": [sine_node(550), audio_tap(t)], **io(None, "tap")},
                 lambda: check_tone(c.capture(audio_tap_src(t), "tap", audio=True), 550),
                 offscreen=True)


@case("audio-out/audioout", ("pipewire", "sys:pipewiresrc", "tool:pw-link"))
def _(c):
    def verify():
        rec = c.path("pw.s16")
        p = c.gst('pipewiresrc autoconnect=false stream-properties="props,node.name=scenic-io-rec"'
                  " ! audio/x-raw,channels=2 ! audioconvert ! audioresample"
                  " ! audio/x-raw,format=S16LE,channels=1,rate=48000"
                  " ! filesink location=%s" % rec, "pw", system=True)
        if not pw_link("ossia score", "scenic-io-rec"):
            raise Skip("no PipeWire node 'ossia score' (another audio backend?)")
        stop(p, 4)
        return check_tone(samples_of(rec), 610)
    return c.run({"nodes": [sine_node(610), {"as": "out", "kind": "audioout"}],
                  **io(None, "out")}, verify, offscreen=True)


@case("audio-out/webrtcpub_audio", ("sdk:webrtcsrc", "python:websockets"))
def _(c):
    signaller(c)
    seen = set()

    def verify():
        # after a reload, the new publication, not the one that went away
        pid = producer_id("scenic-io-puba", exclude=seen)
        seen.add(pid)
        return check_tone(c.capture(webrtc_consumer_src(pid), "consumer", seconds=8,
                                    audio=True), 470)
    return c.run({"nodes": [sine_node(470),
                            {"as": "out", "kind": "webrtcpub_audio", "params": {
                                "uri": SIGNALLER, "name": "scenic-io-puba", "peer": "scenic"}}],
                  **io(None, "out")}, verify, offscreen=True)


# data bridges ------------------------------------------------------------------------

def data_case(c, nodes, connect, verify):
    return c.run({"nodes": nodes, "connect": connect}, verify,
                 offscreen=True)


@case("data/udp")
def _(c):
    i, o = next(PORTS), next(PORTS)
    rx = UdpListener(o)
    return data_case(c, [data_feed(i), data_tap(o)], [["feed", "tap"]], lambda: (
        send_until(lambda: udp_send(i, osc_encode("/io/udp", 0.25)), rx,
                   is_osc("/io/udp", 0.25)) and "OSC in, OSC out"))


@case("data/udp-raw")
def _(c):
    i, o = next(PORTS), next(PORTS)
    rx = UdpListener(o)
    payload = b"scenic\x00\x01\xff"
    return data_case(c, [data_feed(i, "raw"), data_tap(o, "raw")], [["feed", "tap"]],
                     lambda: send_until(lambda: udp_send(i, payload), rx,
                                        lambda p: p == payload) and "bytes unchanged")


@case("data/tcpin")
def _(c):
    i, o = next(PORTS), next(PORTS)
    rx = UdpListener(o)

    def verify():
        s = socket.create_connection(("127.0.0.1", i), timeout=5)
        try:
            send_until(lambda: s.sendall(slip_encode(osc_encode("/io/tcp", 7))), rx,
                       is_osc("/io/tcp", 7))
        finally:
            s.close()
        return "SLIP OSC in"
    return data_case(c, [{"as": "src", "kind": "tcpin", "params": {
                              "bind": "127.0.0.1", "port": i, "codec": "osc"}}, data_tap(o)],
                     [["src", "tap"]], verify)


@case("data/tcpout")
def _(c):
    i, o = next(PORTS), next(PORTS)
    server = socket.socket()
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", o))
    server.listen(1)
    server.settimeout(15)

    def verify():
        conn, _ = server.accept()
        conn.settimeout(0.5)
        data, deadline = b"", time.time() + 8
        while time.time() < deadline:
            udp_send(i, osc_encode("/io/tcpout", 3))
            try:
                data += conn.recv(4096)
            except socket.timeout:
                pass
            if any(osc_decode(f)[0] == "/io/tcpout" for f in slip_decode(data)):
                return "SLIP OSC out"
        raise Fail("received %r" % data[:64])
    try:
        return data_case(c, [data_feed(i), {"as": "dst", "kind": "tcpout", "params": {
                                 "host": "127.0.0.1", "port": o, "codec": "osc"}}],
                         [["feed", "dst"]], verify)
    finally:
        server.close()


@case("data/wsin", ("python:websockets",))
def _(c):
    i, o = next(PORTS), next(PORTS)
    rx = UdpListener(o)
    payload = b"\x01\x02\x03scenic"

    def verify():
        import asyncio
        import websockets

        async def go():
            async with websockets.connect("ws://127.0.0.1:%d" % i) as ws:
                deadline = time.time() + 6
                while time.time() < deadline:
                    await ws.send(payload)
                    if any(p == payload for p in rx.packets(0.5)):
                        return True
            return False
        check(asyncio.run(go()), "nothing arrived")
        return "binary frame in"
    return data_case(c, [{"as": "src", "kind": "wsin", "params": {
                              "bind": "127.0.0.1", "port": i, "codec": "raw"}},
                         data_tap(o, "raw")], [["src", "tap"]], verify)


@case("data/wsout", ("python:websockets",))
def _(c):
    i, o = next(PORTS), next(PORTS)
    got = queue.Queue()

    def serve():
        import asyncio
        import websockets

        async def handler(ws, *_):
            try:
                async for m in ws:
                    got.put(m)
            except websockets.exceptions.ConnectionClosed:
                pass

        async def main():
            async with websockets.serve(handler, "127.0.0.1", o):
                await asyncio.sleep(40)
        asyncio.run(main())
    threading.Thread(target=serve, daemon=True).start()
    time.sleep(0.5)

    def verify():
        deadline = time.time() + 8
        while time.time() < deadline:
            udp_send(i, osc_encode("/io/ws", 5))
            try:
                m = got.get(timeout=0.5)
            except queue.Empty:
                continue
            msg = json.loads(m)
            check(msg == {"address": "/io/ws", "values": [5]}, "received %r" % m)
            return "OSC out as JSON text"
        raise Fail("nothing arrived")
    return data_case(c, [data_feed(i), {"as": "dst", "kind": "wsout", "params": {
                             "host": "127.0.0.1", "port": o}}], [["feed", "dst"]], verify)


def pty_pair(c):
    a, b = c.path("ttyA"), c.path("ttyB")
    c.spawn(["socat", "pty,raw,echo=0,link=" + a, "pty,raw,echo=0,link=" + b], "socat")
    for _ in range(20):
        if os.path.exists(a) and os.path.exists(b):
            return a, b
        time.sleep(0.1)
    raise Fail("socat made no pseudo-terminals")


@case("data/serialin", ("tool:socat",))
def _(c):
    a, b = pty_pair(c)
    o = next(PORTS)
    rx = UdpListener(o)
    payload = b"serial\x10\x20"

    def verify():
        fd = os.open(b, os.O_WRONLY | os.O_NOCTTY)
        try:
            send_until(lambda: os.write(fd, payload), rx, lambda p: payload in p)
        finally:
            os.close(fd)
        return "bytes in"
    return data_case(c, [{"as": "src", "kind": "serialin", "params": {
                              "device": a, "baud": 115200, "codec": "raw"}},
                         data_tap(o, "raw")], [["src", "tap"]], verify)


@case("data/serialout", ("tool:socat",))
def _(c):
    a, b = pty_pair(c)
    i = next(PORTS)
    payload = b"serial-out\x7f"

    def verify():
        fd = os.open(b, os.O_RDONLY | os.O_NOCTTY | os.O_NONBLOCK)
        data, deadline = b"", time.time() + 6
        try:
            while time.time() < deadline and payload not in data:
                udp_send(i, payload)
                time.sleep(0.3)
                try:
                    data += os.read(fd, 4096)
                except BlockingIOError:
                    pass
        finally:
            os.close(fd)
        check(payload in data, "received %r" % data[:64])
        return "bytes out"
    return data_case(c, [data_feed(i, "raw"), {"as": "dst", "kind": "serialout", "params": {
                             "device": a, "baud": 115200, "codec": "raw"}}],
                     [["feed", "dst"]], verify)


def smf_note(path):
    """A one-note Standard MIDI File: channel 1, note 60, velocity 100."""
    track = bytes([0x00, 0x90, 60, 100, 0x60, 0x80, 60, 0, 0x00, 0xFF, 0x2F, 0x00])
    Path(path).write_bytes(b"MThd" + struct.pack(">IHHH", 6, 0, 1, 96)
                           + b"MTrk" + struct.pack(">I", len(track)) + track)


@case("data/midiin", ("midithrough", "tool:aplaymidi"))
def _(c):
    o, mid = next(PORTS), c.path("note.mid")
    smf_note(mid)
    rx = UdpListener(o)

    def verify():
        send_until(lambda: subprocess.run(["aplaymidi", "-p", "Midi Through", mid],
                                          capture_output=True),
                   rx, is_osc("/midi/1/note/60", 100))
        return "note on as /midi/1/note/60"
    return data_case(c, [{"as": "src", "kind": "midiin", "params": {
                              "device": "~Midi Through", "codec": "midi"}}, data_tap(o)],
                     [["src", "tap"]], verify)


@case("data/midiout", ("midithrough", "tool:aseqdump"))
def _(c):
    i = next(PORTS)
    dump = c.spawn(["aseqdump", "-p", "Midi Through"], "aseqdump")

    def verify():
        deadline = time.time() + 6
        while time.time() < deadline:
            udp_send(i, osc_encode("/midi/1/cc/7", 99))
            time.sleep(0.4)
            log = Path(c.path("aseqdump.log")).read_text()
            if any("Control change" in l and " 7" in l and "99" in l for l in log.splitlines()):
                return "/midi/1/cc/7 99 as a control change"
        raise Fail("aseqdump saw no control change 7 = 99")
    try:
        return data_case(c, [data_feed(i), {"as": "dst", "kind": "midiout", "params": {
                                 "device": "~Midi Through", "codec": "midi"}}],
                         [["feed", "dst"]], verify)
    finally:
        stop(dump, 0)


# sessions ----------------------------------------------------------------------

@case("session/load-over-open", GPU)
def _(c):
    # Load a session over the open one, as the Load menu does: its nodes get
    # the same ids, and so the same ports and sockets, as the ones going away.
    t, rgb = next(PORTS), (30, 220, 220)
    return c.run({"nodes": [solid_node(rgb), video_tap(t)], **io(None, "tap"),
                  "roundtrip": True, "load_over_open": True},
                 lambda: check_colour(c.capture(video_tap_src(t), "tap"), rgb))


# --- runner ------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-k", action="append", default=[], help="run cases whose name contains this")
    ap.add_argument("--roundtrip", action="store_true",
                    help="also verify after saving and reloading the session")
    ap.add_argument("--list", action="store_true", help="list the cases and exit")
    ap.add_argument("--keep", action="store_true", help="keep the logs of passing cases")
    ap.add_argument("--display", help="an X display to use instead of a private Xvfb")
    args = ap.parse_args()
    Ctx.roundtrip, Ctx.keep = args.roundtrip, args.keep

    cases = [c for c in CASES if not args.k or any(k in c[0] for k in args.k)]
    if args.list:
        for name, needs, _ in cases:
            print("%-28s %s" % (name, ", ".join(needs) or "-"))
        return 0

    # The cases that render run on a private X server: nothing else draws on
    # it, so windows are where they were put and can be captured.
    xvfb = None
    args.display = args.display or os.environ.get("SCENIC_TEST_DISPLAY")
    if args.display:
        os.environ["DISPLAY"] = args.display
    elif shutil.which("Xvfb"):
        r, w = os.pipe()
        xvfb = subprocess.Popen(["Xvfb", "-displayfd", str(w), "-screen", "0", "1920x1080x24",
                                 "-nolisten", "tcp"], pass_fds=(w,),
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        os.close(w)
        os.environ["DISPLAY"] = ":" + os.read(r, 16).decode().strip()
        os.close(r)
    else:
        os.environ.pop("DISPLAY", None)

    TMP.mkdir(parents=True, exist_ok=True)
    counts = {"PASS": 0, "FAIL": 0, "SKIP": 0}
    for name, needs, fn in cases:
        missing = [n for n in needs if not have(n)]
        if missing:
            print("SKIP %-28s missing %s" % (name, ", ".join(missing)), flush=True)
            counts["SKIP"] += 1
            continue
        c = Ctx(name)
        t0 = time.time()
        try:
            detail = fn(c)
            status = "PASS"
        except Skip as e:
            status, detail = "SKIP", str(e)
        except Fail as e:
            status, detail = "FAIL", "%s (logs: %s)" % (e, c.dir)
        except Exception as e:   # a bug in the case itself is a failure too
            status, detail = "FAIL", "%s: %s (logs: %s)" % (type(e).__name__, e, c.dir)
        finally:
            c.cleanup()
        counts[status] += 1
        print("%s %-28s %s  [%.0fs]" % (status, name, detail or "", time.time() - t0),
              flush=True)
        if status == "PASS" and not Ctx.keep:
            shutil.rmtree(c.dir, ignore_errors=True)
        time.sleep(1)
    if xvfb:
        xvfb.terminate()
    print("----\nPASS=%(PASS)d FAIL=%(FAIL)d SKIP=%(SKIP)d" % counts)
    if counts["FAIL"]:
        return 1
    return 77 if counts["PASS"] == 0 else 0


if __name__ == "__main__":
    sys.exit(main())
