#!/usr/bin/env python3
"""Wardrobe cut-out worker: claims `wardrobe.cutout` jobs from construct and measures each garment photo.

Per photo (flat on a white sheet or any neutral, evenly lit surface such as gray floor tiles; daylight): background
removal with rembg; white balance by chromaticity only, from the removed background: per-channel gains make it neutral
and keep its luminance, so the photo's exposure stands (a gray tile stays gray and a dark tee stays dark; a white sheet
stays as bright as the camera made it). Grout lines and shadows are left out of the reference by a luminance band; a
background with a real colour (C* over 15 at mid-gray) is balanced less, and from C* 30 not at all, so a coloured backdrop
does not tint the garment. Then k-means (k = 3) in CIELAB (D65) over the garment pixels, clusters over 15 % kept as
L*, a*, b*, hex and share. The cut-out PNG is uploaded as a blob; the colours are the job's result.
Test the colour maths offline (synthetic garments on sheet and tiles): python3 test_balance.py [--rembg]

Runs on vista (raven is a phone), as a pull worker over the tailnet:
    construct worker-token vista > ~/.config/construct/worker-token     # on raven, once
    CONSTRUCT_URL=http://raven:4322 CONSTRUCT_WORKER_TOKEN_FILE=~/.config/construct/worker-token \
        nix shell --impure -f env.nix -c wardrobe-cutout
Try one photo without a server:
    nix shell --impure -f env.nix -c wardrobe-cutout --file shirt.jpg --out shirt.png
env.nix pins the u2net model by hash and points REMBG_HOME at it. Env: CONSTRUCT_WORKER_HOST (default vista).
"""
import argparse
import io
import json
import os
import sys
import time
import urllib.error
import urllib.request

import numpy as np
from PIL import Image, ImageOps

KIND = "wardrobe.cutout"
POLL_S = 15
MAX_SIDE = 1600  # measured at this size: plenty for colour, fast on a CPU
CUT_SIDE = 768  # the cut-out the pages show
CAST_FULL, CAST_NONE = 15, 30  # background C*ab (at L* 50): a cast is removed in full up to here, not at all from here
MAX_GAIN = 1.6  # per-channel white-balance gains stay within [1/1.6, 1.6]
MIN_SHARE = 0.15
D65 = np.array([0.95047, 1.0, 1.08883])
RGB2XYZ = np.array([[0.4124564, 0.3575761, 0.1804375], [0.2126729, 0.7151522, 0.0721750], [0.0193339, 0.1191920, 0.9503041]])


def linear(srgb):
    return np.where(srgb <= 0.04045, srgb / 12.92, ((srgb + 0.055) / 1.055) ** 2.4)


def gamma(lin):
    return np.where(lin <= 0.0031308, 12.92 * lin, 1.055 * np.power(np.clip(lin, 0, 1), 1 / 2.4) - 0.055)


def lab(lin):
    """Linear sRGB (n, 3) → CIELAB (n, 3), D65, the same formulas as color.ts."""
    xyz = lin @ RGB2XYZ.T / D65
    f = np.where(xyz > 216 / 24389, np.cbrt(xyz), (24389 / 27 * xyz + 16) / 116)
    return np.stack([116 * f[:, 1] - 16, 500 * (f[:, 0] - f[:, 1]), 200 * (f[:, 1] - f[:, 2])], axis=1)


def kmeans(x, k=3, iters=30, seed=0):
    """Plain k-means with k-means++ seeding; deterministic for a given input."""
    rng = np.random.default_rng(seed)
    centers = [x[rng.integers(len(x))]]
    for _ in range(1, k):
        d = np.min(((x[:, None, :] - np.array(centers)[None]) ** 2).sum(-1), axis=1)
        centers.append(x[rng.choice(len(x), p=d / d.sum())] if d.sum() > 0 else x[rng.integers(len(x))])
    c = np.array(centers)
    for _ in range(iters):
        label = np.argmin(((x[:, None, :] - c[None]) ** 2).sum(-1), axis=1)
        new = np.array([x[label == j].mean(0) if np.any(label == j) else c[j] for j in range(k)])
        if np.allclose(new, c, atol=1e-3):
            break
        c = new
    return c, np.bincount(label, minlength=k)


def hexof(l):
    rgb = gamma(np.clip(np.linalg.solve(RGB2XYZ, finv(l) * D65), 0, 1))
    return "#" + "".join(f"{round(v * 255):02x}" for v in rgb)


def finv(l):
    L, a, b = l
    fy = (L + 16) / 116
    f = np.array([fy + a / 500, fy, fy - b / 200])
    return np.where(f**3 > 216 / 24389, f**3, (116 * f - 16) / (24389 / 27))


def background(lin, sheet):
    """The background's colour (linear RGB): the median of the sheet pixels inside a luminance band around their median,
    so grout lines, shadows at the garment's edge and glare do not count. Brightest 1 % when little background is left."""
    if sheet.sum() < 500:
        return np.percentile(lin.reshape(-1, 3), 99, axis=0)
    px = lin[sheet]
    y = px @ RGB2XYZ[1]
    m = np.median(y)
    band = px[(y > 0.6 * m) & (y < 1.6 * m)]
    return np.median(band if len(band) >= 500 else px, axis=0)


def balance(lin, sheet):
    """White balance by chromaticity only: gains that make the background neutral at its own luminance. Returns the
    balanced image (linear RGB) and the gains."""
    white = np.maximum(background(lin, sheet), 1e-4)
    y = white @ RGB2XYZ[1]
    cast = np.hypot(*lab((white * 0.18 / y)[None])[0, 1:])  # the background's chroma, seen at mid-gray
    strength = np.clip((CAST_NONE - cast) / (CAST_NONE - CAST_FULL), 0, 1)
    gains = np.clip((white.mean() / white) ** strength, 1 / MAX_GAIN, MAX_GAIN)
    gains *= y / ((white * gains) @ RGB2XYZ[1])  # the background keeps its luminance
    return np.clip(lin * gains, 0, 1), gains


def colours(balanced, garment):
    """k-means (k = 3) in CIELAB over the garment pixels: clusters over 15 %, largest first."""
    px = lab(balanced[garment])
    if len(px) > 20000:
        px = px[np.random.default_rng(0).choice(len(px), 20000, replace=False)]
    centers, counts = kmeans(px)
    shares = counts / counts.sum()
    return [
        {"L": round(float(c[0]), 2), "a": round(float(c[1]), 2), "b": round(float(c[2]), 2), "hex": hexof(c), "share": round(float(s), 3)}
        for c, s in sorted(zip(centers, shares), key=lambda cs: -cs[1])
        if s > MIN_SHARE
    ]


def measure(data, session):
    """Photo bytes → (cut-out PNG bytes, colour clusters over 15 %)."""
    from rembg import remove

    img = ImageOps.exif_transpose(Image.open(io.BytesIO(data))).convert("RGB")
    img.thumbnail((MAX_SIDE, MAX_SIDE))
    alpha = np.asarray(remove(img, session=session))[..., 3]
    lin = linear(np.asarray(img, dtype=np.float64) / 255)
    garment, sheet = alpha >= 200, alpha <= 20
    if garment.sum() < 500:
        raise ValueError("no garment found in the photo")
    balanced, _ = balance(lin, sheet)
    colors = colours(balanced, garment)
    ys, xs = np.nonzero(alpha > 20)
    pad = int(0.04 * max(alpha.shape))
    box = (max(0, xs.min() - pad), max(0, ys.min() - pad), min(alpha.shape[1], xs.max() + pad + 1), min(alpha.shape[0], ys.max() + pad + 1))
    rgba = np.dstack([np.round(gamma(balanced) * 255), alpha]).astype(np.uint8)
    cut = Image.fromarray(rgba, "RGBA").crop(box)
    cut.thumbnail((CUT_SIDE, CUT_SIDE))
    out = io.BytesIO()
    cut.save(out, "PNG", optimize=True)
    return out.getvalue(), colors


class Api:
    def __init__(self, base, token):
        self.base, self.token = base.rstrip("/"), token

    def call(self, method, path, body=None, raw=None, ctype="application/json"):
        data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
        req = urllib.request.Request(self.base + path, data=data, method=method, headers={"Authorization": f"Bearer {self.token}", "Content-Type": ctype})
        with urllib.request.urlopen(req, timeout=60) as res:
            payload = res.read()
            return json.loads(payload) if res.headers.get_content_type() == "application/json" else payload


def run_job(api, job, session):
    items = job["payload"].get("items", [])
    urls = {b["sha256"]: b["url"] for b in job["blobs"]}
    out = []
    for i, it in enumerate(items):
        sig = api.call("POST", f"/api/jobs/{job['id']}/progress", {"progress": i / max(1, len(items)), "reason": f"cut out {i} of {len(items)}"})
        if sig.get("cancel") or sig.get("hold"):
            print(f"job {job['id']}: {'cancelled' if sig.get('cancel') else 'held'}", flush=True)
            return
        try:
            png, colors = measure(api.call("GET", urls[it["sha256"]]), session)
            blob = api.call("POST", "/api/blobs?ext=png", raw=png, ctype="image/png")
            out.append({"id": it["id"], "cutout": blob["sha256"], "colors": colors})
        except Exception as e:  # one bad photo does not sink the batch
            print(f"job {job['id']} item {it['id']}: {e}", file=sys.stderr, flush=True)
            out.append({"id": it["id"], "error": str(e)[:500]})
    api.call("POST", f"/api/jobs/{job['id']}/result", {"ok": True, "result": {"items": out}})
    print(f"job {job['id']}: {len(out)} photo(s) done", flush=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--file", help="measure one local photo and print the colours (no server)")
    ap.add_argument("--out", help="with --file: write the cut-out PNG here")
    args = ap.parse_args()
    from rembg import new_session

    session = new_session("u2net")
    if args.file:
        png, colors = measure(open(args.file, "rb").read(), session)
        if args.out:
            open(args.out, "wb").write(png)
        print(json.dumps(colors, indent=2))
        return
    token = open(os.path.expanduser(os.environ["CONSTRUCT_WORKER_TOKEN_FILE"])).read().strip()
    api = Api(os.environ.get("CONSTRUCT_URL", "http://raven:4322"), token)
    host = os.environ.get("CONSTRUCT_WORKER_HOST", "vista")
    print(f"wardrobe cut-out worker on {host}, polling {api.base}", flush=True)
    while True:
        try:
            job = api.call("POST", "/api/jobs/worker/claim", {"host": host, "kinds": [KIND], "gpu": {"busy": False}}).get("job")
            if job:
                try:
                    run_job(api, job, session)
                except urllib.error.HTTPError as e:
                    print(f"job {job['id']}: HTTP {e.code} {e.read()[:200]!r}", file=sys.stderr, flush=True)
                except Exception as e:
                    api.call("POST", f"/api/jobs/{job['id']}/result", {"ok": False, "error": str(e)[:500], "retry": True})
                continue
        except (urllib.error.URLError, OSError, ValueError) as e:
            print(f"construct unreachable: {e}", file=sys.stderr, flush=True)
        time.sleep(POLL_S)


if __name__ == "__main__":
    main()
