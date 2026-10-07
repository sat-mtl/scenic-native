#!/usr/bin/env python3
# Validation helpers for the routing integration tests.
#
#   check-frame.py video <file.jpg> <R> <G> <B> [tol]
#       Decode the last JPEG frame in the (appended) file, average a center
#       region, and compare to the expected RGB within tol (default 24).
#
#   check-frame.py audio <file.raw> [expected_hz]
#       Read raw S16LE stereo @48k, assert non-silence, and (if given) that the
#       dominant frequency is within 5% of expected_hz.
import sys
import numpy as np


def last_jpeg(path):
    data = open(path, "rb").read()
    start = data.rfind(b"\xff\xd8")           # last SOI marker
    if start < 0:
        raise ValueError("no JPEG frame in %s (%d bytes)" % (path, len(data)))
    from io import BytesIO
    from PIL import Image
    return np.asarray(Image.open(BytesIO(data[start:])).convert("RGB"))


def check_video(path, exp, tol):
    im = last_jpeg(path)
    h, w, _ = im.shape
    region = im[int(h * 0.4):int(h * 0.6), int(w * 0.4):int(w * 0.6)]
    got = region.reshape(-1, 3).mean(axis=0)
    ok = all(abs(int(got[i]) - exp[i]) <= tol for i in range(3))
    print("  %s: got=[%d,%d,%d] expect=%s %s"
          % (path.split("/")[-1], got[0], got[1], got[2], exp,
             "OK" if ok else "MISMATCH"))
    return ok


def check_audio(path, exp_hz):
    raw = np.fromfile(path, dtype=np.int16)
    if raw.size == 0:
        print("  %s: EMPTY" % path); return False
    mono = raw.reshape(-1, 2)[:, 0].astype(np.float64)
    rms = np.sqrt((mono ** 2).mean())
    if rms < 100:
        print("  %s: silent (rms=%.0f)" % (path, rms)); return False
    # dominant frequency
    n = 1 << 15
    seg = mono[:n] if mono.size >= n else np.pad(mono, (0, n - mono.size))
    spec = np.abs(np.fft.rfft(seg * np.hanning(len(seg))))
    freqs = np.fft.rfftfreq(n, 1.0 / 48000)
    dom = freqs[1 + np.argmax(spec[1:])]
    ok = not exp_hz or abs(dom - exp_hz) / exp_hz < 0.05
    msg = "rms=%.0f dom=%.0fHz" % (rms, dom)
    if exp_hz:
        msg += " expect=%dHz" % exp_hz
    print("  %s: %s %s" % (path.split("/")[-1], msg, "OK" if ok else "MISMATCH"))
    return ok


if __name__ == "__main__":
    mode = sys.argv[1]
    try:
        if mode == "video":
            exp = [int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])]
            tol = int(sys.argv[6]) if len(sys.argv) > 6 else 24
            sys.exit(0 if check_video(sys.argv[2], exp, tol) else 1)
        elif mode == "audio":
            hz = int(sys.argv[3]) if len(sys.argv) > 3 else 0
            sys.exit(0 if check_audio(sys.argv[2], hz) else 1)
    except Exception as e:
        print("  %s: ERROR %s" % (sys.argv[2], e)); sys.exit(1)
    sys.exit(2)
