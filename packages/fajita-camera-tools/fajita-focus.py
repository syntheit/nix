"""fajita-focus — manual + contrast-autofocus for the OnePlus 6T rear camera.

The lc898217xc VCM exposes V4L2_CID_FOCUS_ABSOLUTE (0..2047) on a v4l2
subdev, but libcamera 0.7.0's simple pipeline never drives it (that lands
in CAMERA_PLAN.md phase 3). This tool pokes the control directly while
capturing frames through libcamera's soft ISP (`cam` CLI) and hill-climbs
a Laplacian-variance sharpness metric. Scan constants come from the
fajita-webcam project's AF, proven on this exact hardware: coarse ~227-step
sweep, fine +/-128 @ 32, ultra +/-32 @ 8, 80 ms settle per move.

POWER CONSTRAINT (discovered on-device, 2026-07-16): this kernel powers the
camera block — including the CCI i2c bus the VCM hangs off — ONLY while a
camera pipeline is streaming ("power pipeline only when streaming",
sdm845-mainline). A standalone focus write dies with errno 110 / dmesg
"i2c-qcom-cci: master 1 queue 0 timeout". So every focus write here happens
MID-STREAM: measurements spawn `cam` and set focus while it captures, and
--hold re-asserts every 500 ms, silently riding through the powered-down
gaps (writes succeed again the moment Snapshot's stream powers the bus).

Workflow for a real photo today: close Snapshot -> `fajita-focus auto
--hold` over ssh -> open Snapshot -> shoot -> Ctrl-C. (The camera pipeline
is single-owner: `cam` cannot capture while pipewire streams.)

CRASHDUMP WARNING (observed 2026-07-16): rapid repeated pipeline
start/stops (~50 power-domain cycles over 30 min of per-measurement
pulses) crashed the SoC into Qualcomm CrashDump mode. sweep/auto therefore
run ONE continuous stream per session (Streamer) and step focus
mid-stream — which is also ~7x faster per measurement. Avoid designs that
cycle the pipeline per measurement.
"""
import argparse
import fcntl
import glob
import os
import re
import shutil
import struct
import statistics
import subprocess
import sys
import tempfile
import time

import numpy as np

FOCUS_CID = 0x009A090A       # V4L2_CID_FOCUS_ABSOLUTE (survey: phase-0)
VIDIOC_S_CTRL = 0xC008561C   # _IOWR('V', 28, struct v4l2_control)
FOCUS_MAX = 2047
SETTLE_S = 0.08              # fajita-webcam: 80 ms per move
# Camera INDICES ARE NOT STABLE across boots (enumeration order flips).
# Select by DT path: the rear imx376 sits on cci i2c-bus@1.
REAR_ID_SUBSTR = "i2c-bus@1/camera@10"
ROI = 640                    # center crop for the sharpness metric — 256 was
#                              too tight at full res (2584x1940): it can land
#                              on a featureless patch and flatten the curve


def resolve_camera(camera):
    if camera != "rear":
        sys.exit("error: only the rear camera has a VCM")
    out = subprocess.run(["cam", "--list"], capture_output=True,
                         text=True).stdout
    for line in out.splitlines():
        if REAR_ID_SUBSTR in line:
            m = re.search(r"\((/base[^)]+)\)", line)
            if m:
                return m.group(1)
    sys.exit("error: rear camera not found in `cam --list`")


def find_vcm():
    for name in glob.glob("/sys/class/video4linux/v4l-subdev*/name"):
        with open(name) as fh:
            if "lc898217xc" in fh.read():
                return "/dev/" + os.path.basename(os.path.dirname(name))
    sys.exit("error: no lc898217xc VCM subdev found (rear camera module?)")


class Vcm:
    """Holds the subdev open for the whole session."""

    def __init__(self):
        self.dev = find_vcm()
        self.fd = os.open(self.dev, os.O_RDWR)
        self.pos = None

    def set(self, pos, retries=8):
        """Write focus. Only succeeds while a camera stream powers the CCI
        bus — retries span pipeline startup (~1-2 s worst case)."""
        pos = max(0, min(FOCUS_MAX, int(pos)))
        buf = struct.pack("Ii", FOCUS_CID, pos)
        for attempt in range(retries):
            try:
                fcntl.ioctl(self.fd, VIDIOC_S_CTRL, buf)
                self.pos = pos
                time.sleep(SETTLE_S)
                return pos
            except OSError:
                if attempt == retries - 1:
                    raise SystemExit(
                        "error: focus write timed out — no active camera "
                        "stream powering the CCI bus (see tool docstring)")
                time.sleep(0.25)

    def hold(self):
        print(f"holding focus at {self.pos} — Ctrl-C to release", flush=True)
        try:
            while True:
                try:
                    self.set(self.pos, retries=1)
                except SystemExit:
                    pass  # bus unpowered between streams — retry next tick
                time.sleep(0.5)
        except KeyboardInterrupt:
            print("released")


def read_ppm(path):
    with open(path, "rb") as fh:
        if fh.readline().strip() != b"P6":
            sys.exit(f"error: {path} is not a binary PPM")
        vals = []
        while len(vals) < 3:
            line = fh.readline()
            if line.startswith(b"#"):
                continue
            vals += line.split()
        w, h, _maxv = (int(v) for v in vals[:3])
        raw = fh.read(w * h * 3)
    return np.frombuffer(raw, dtype=np.uint8).reshape(h, w, 3)


class Streamer:
    """One long-lived `cam` capture for a whole sweep/auto session.

    Frames land as numbered PPMs in a tmpdir; consumers wait for fresh
    sequence numbers and stale files are deleted continuously (tmpfs-safe).
    The newest file is never read — cam may still be writing it.
    """

    def __init__(self, camera):
        self.d = tempfile.mkdtemp(prefix="fajita-focus-")
        self.proc = subprocess.Popen(
            ["cam", f"--camera={camera}", "--capture=100000",
             f"--file={self.d}/f#.ppm"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )

    def _files(self):
        out = []
        for f in os.listdir(self.d):
            m = re.search(r"(\d+)\.ppm$", f)
            if m:
                out.append((int(m.group(1)), os.path.join(self.d, f)))
        return sorted(out)

    def latest_seq(self):
        fs = self._files()
        return fs[-1][0] if fs else -1

    def frames_after(self, seq, k=3, timeout=15):
        """Return `k` complete frames with sequence > `seq`; prune consumed."""
        t0 = time.monotonic()
        while time.monotonic() - t0 < timeout:
            if self.proc.poll() is not None:
                sys.exit("error: cam stream died (camera busy? "
                         "close Snapshot first)")
            fs = self._files()
            ready = [(s, p) for s, p in fs[:-1] if s > seq]
            if len(ready) >= k:
                imgs = [read_ppm(p) for _, p in ready[:k]]
                consumed = ready[k - 1][0]
                for s, p in fs[:-1]:
                    if s <= consumed:
                        try:
                            os.unlink(p)
                        except FileNotFoundError:
                            pass
                return imgs
            time.sleep(0.03)
        sys.exit("error: stream stalled — no new frames")

    def stop(self):
        self.proc.terminate()
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()
        shutil.rmtree(self.d, ignore_errors=True)


def pulse_stream(camera, during=None, frames=40, keep=3):
    """Stream `frames` frames through the soft ISP; run `during()` ~1 s in
    (while the pipeline powers the CCI bus); return the last `keep` frames —
    they're AGC-settled and post-focus-move. Multiple frames let callers
    median away single-frame AGC flicker."""
    d = tempfile.mkdtemp(prefix="fajita-focus-")
    try:
        proc = subprocess.Popen(
            ["cam", f"--camera={camera}", f"--capture={frames}",
             f"--file={d}/f#.ppm"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        if during is not None:
            time.sleep(1.0)  # pipeline startup before the first write attempt
            during()
        proc.wait(timeout=30)
        files = sorted(glob.glob(f"{d}/*.ppm"))
        if not files:
            sys.exit("error: cam produced no frames (camera busy? "
                     "close Snapshot first)")
        return [read_ppm(f) for f in files[-keep:]]
    finally:
        for f in glob.glob(f"{d}/*"):
            os.unlink(f)
        os.rmdir(d)


def sharpness(img):
    """Normalized Laplacian variance, green channel, center ROI."""
    h, w, _ = img.shape
    y0, x0 = (h - ROI) // 2, (w - ROI) // 2
    g = img[y0:y0 + ROI, x0:x0 + ROI, 1].astype(np.float32)
    lap = (4 * g[1:-1, 1:-1] - g[:-2, 1:-1] - g[2:, 1:-1]
           - g[1:-1, :-2] - g[1:-1, 2:])
    mean = g.mean()
    return float(lap.var()) / (mean * mean + 1e-6)


def measure(streamer, vcm, pos, quiet=False):
    """Step focus mid-stream; skip the in-flight + settle frames; median-3."""
    seq0 = streamer.latest_seq()
    vcm.set(pos)
    imgs = streamer.frames_after(seq0 + 3)
    s = statistics.median(sharpness(i) for i in imgs)
    if not quiet:
        print(f"  pos={pos:4d}  sharpness={s:.6f}", flush=True)
    return s


def check_scene(streamer):
    """Wait for the stream to produce frames + AGC to roughly settle."""
    img = streamer.frames_after(-1, k=25)[-1]  # cold-start AGC needs ~20 frames
    if img.mean() < 3:
        sys.exit("error: scene is black (mean<3) — rear camera face-down?")
    return img


def cmd_set(args, vcm):
    pulse_stream(args.camera, during=lambda: vcm.set(args.position))
    print(f"focus_absolute = {vcm.pos} ({vcm.dev})")
    if args.hold:
        vcm.hold()
    else:
        print("note: the lens relaxes once the camera powers down; "
              "use --hold to re-assert while you shoot in Snapshot")


def cmd_sweep(args, vcm):
    streamer = Streamer(args.camera)
    try:
        check_scene(streamer)
        print("pos,sharpness")
        for pos in range(args.start, args.stop + 1, args.step):
            s = measure(streamer, vcm, pos, quiet=True)
            print(f"{pos},{s:.6f}", flush=True)
    finally:
        streamer.stop()


def cmd_auto(args, vcm):
    streamer = Streamer(args.camera)
    try:
        check_scene(streamer)
        t0 = time.monotonic()

        def best_of(label, positions):
            print(f"{label}:", flush=True)
            scored = [(measure(streamer, vcm, p), p) for p in positions]
            return max(scored)[1]

        best = best_of("coarse", list(range(0, FOCUS_MAX + 1, 227)))
        best = best_of("fine", [p for p in range(best - 128, best + 129, 32)
                                if 0 <= p <= FOCUS_MAX])
        best = best_of("ultra", [p for p in range(best - 32, best + 33, 8)
                                 if 0 <= p <= FOCUS_MAX])
        vcm.set(best)  # stream still up — bus powered
        print(f"converged: focus_absolute={best} "
              f"in {time.monotonic() - t0:.1f}s")
    finally:
        streamer.stop()
    if args.hold:
        vcm.hold()


def main():
    ap = argparse.ArgumentParser(
        description="manual + contrast-autofocus for the fajita rear camera")
    ap.add_argument("--camera", default="rear", choices=["rear", "front"])
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("set", help="set focus position 0..2047")
    p.add_argument("position", type=int)
    p.add_argument("--hold", action="store_true",
                   help="keep process alive re-asserting the position")

    p = sub.add_parser("sweep", help="measure sharpness across the range (CSV)")
    p.add_argument("--start", type=int, default=0)
    p.add_argument("--stop", type=int, default=FOCUS_MAX)
    p.add_argument("--step", type=int, default=128)

    p = sub.add_parser("auto", help="contrast-AF hill climb (close Snapshot!)")
    p.add_argument("--hold", action="store_true",
                   help="hold the converged position for shooting")

    args = ap.parse_args()
    if args.camera == "front":
        sys.exit("error: the front camera (imx371) is fixed-focus — no VCM")

    args.camera = resolve_camera(args.camera)
    vcm = Vcm()
    {"set": cmd_set, "sweep": cmd_sweep, "auto": cmd_auto}[args.cmd](args, vcm)


if __name__ == "__main__":
    main()
