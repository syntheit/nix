#!/usr/bin/env python3
"""Offline check of cutout.py's colour maths on synthetic photos: four garments of known colour on a white sheet, on
mid-gray tiles with darker grout, on warm-gray tiles and under a warm light, each rendered through a simple camera
(linear light x exposure, sRGB, 8 bit, JPEG). Prints CIEDE2000 between the main measured cluster and the truth, the
colour name construct gives each (color.ts NAMES, nearest by CIEDE2000), and the old balance (sheet scaled to 0.9) for
comparison. Exits 1 when a checked case is off by ΔE00 >= 10 or changes name.

    python3 test_balance.py            # garment and background masks known (the colour maths alone)
    python3 test_balance.py --rembg    # the whole measure(): rembg finds the garment (needs REMBG_HOME, as the worker)

On vista, with the worker's own Python:  W=$(readlink -f $(which wardrobe-cutout)); eval "$(grep REMBG_HOME $W)";
$(grep -o '/nix/store/[^ ]*/bin/python3' $W) test_balance.py --rembg
"""
import io
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cutout as C  # noqa: E402

GARMENTS = {"burgundy tee": "#5a1a24", "denim jeans": "#4a6a9a", "white tee": "#f0f0ee", "black tee": "#1c1c1e"}
NEUTRAL, WARM = (1.0, 1.0, 1.0), (1.10, 1.0, 0.80)  # light colour per channel (WARM: about 4500 K against daylight)
# name: background reflectance, grout (None: a sheet), light, exposure, checked
SCENES = {
    "white sheet": ("#eeeeee", None, NEUTRAL, 1.0, True),
    "white sheet, warm light": ("#eeeeee", None, WARM, 1.0, True),
    "gray tile": ("#808080", "#4a4a4a", NEUTRAL, 1.0, True),
    "gray tile, warm light": ("#808080", "#4a4a4a", WARM, 1.0, True),
    "warm-gray tile": ("#8a8278", "#504a44", NEUTRAL, 1.0, True),
    "blue sheet (guard)": ("#3a5a9a", None, NEUTRAL, 1.0, True),
    "white sheet, exposed -20%": ("#eeeeee", None, NEUTRAL, 0.8, False),
    "gray tile, exposed +20%": ("#808080", "#4a4a4a", NEUTRAL, 1.2, False),
}
H, W, TILE, GROUT = 1200, 1600, 220, 6


def lin_of(hex_):
    return C.linear(np.array([int(hex_[i : i + 2], 16) for i in (1, 3, 5)]) / 255)


def de2000(p, q):
    """CIEDE2000, the same as color.ts."""
    (L1, a1, b1), (L2, a2, b2) = p, q
    Cb = (math.hypot(a1, b1) + math.hypot(a2, b2)) / 2
    G = 0.5 * (1 - math.sqrt(Cb**7 / (Cb**7 + 25**7)))
    a1p, a2p = (1 + G) * a1, (1 + G) * a2
    c1, c2 = math.hypot(a1p, b1), math.hypot(a2p, b2)
    hp = lambda b, a: 0 if a == 0 and b == 0 else math.degrees(math.atan2(b, a)) % 360  # noqa: E731
    h1, h2 = hp(b1, a1p), hp(b2, a2p)
    dh = 0
    if c1 * c2:
        dh = h2 - h1
        dh = dh - 360 if dh > 180 else dh + 360 if dh < -180 else dh
    dH = 2 * math.sqrt(c1 * c2) * math.sin(math.radians(dh / 2))
    Lb, cb, hb = (L1 + L2) / 2, (c1 + c2) / 2, h1 + h2
    if c1 * c2:
        if abs(h1 - h2) > 180:
            hb += 360 if hb < 360 else -360
        hb /= 2
    T = 1 - 0.17 * math.cos(math.radians(hb - 30)) + 0.24 * math.cos(math.radians(2 * hb)) + 0.32 * math.cos(math.radians(3 * hb + 6)) - 0.2 * math.cos(math.radians(4 * hb - 63))
    dTh = 30 * math.exp(-(((hb - 275) / 25) ** 2))
    Rc = 2 * math.sqrt(cb**7 / (cb**7 + 25**7))
    Sl = 1 + 0.015 * (Lb - 50) ** 2 / math.sqrt(20 + (Lb - 50) ** 2)
    Sc, Sh = 1 + 0.045 * cb, 1 + 0.015 * cb * T
    Rt = -math.sin(math.radians(2 * dTh)) * Rc
    dL, dC = L2 - L1, c2 - c1
    return math.sqrt((dL / Sl) ** 2 + (dC / Sc) ** 2 + (dH / Sh) ** 2 + Rt * (dC / Sc) * (dH / Sh))


# color.ts NAMES (L*, C*, h)
NAMES = [
    ("white", 95, 2, 90), ("ecru", 90, 9, 85), ("cream", 88, 15, 88), ("stone", 74, 8, 80), ("light grey", 78, 1, 100),
    ("heather grey", 62, 2, 250), ("mid grey", 54, 1, 250), ("charcoal", 32, 2, 260), ("black", 16, 1, 280), ("navy", 24, 16, 272),
    ("light blue", 75, 16, 245), ("sky blue", 68, 28, 240), ("denim blue", 44, 24, 260), ("cobalt", 40, 55, 285), ("slate", 50, 14, 252),
    ("teal", 45, 25, 205), ("forest green", 32, 22, 150), ("olive", 42, 20, 112), ("sage", 65, 14, 128), ("mint", 82, 18, 165),
    ("khaki", 66, 18, 84), ("tan", 62, 25, 70), ("camel", 58, 32, 68), ("brown", 38, 19, 62), ("chocolate", 27, 15, 50),
    ("rust", 44, 38, 48), ("terracotta", 53, 35, 42), ("burgundy", 30, 28, 12), ("red", 45, 55, 30), ("dusty pink", 78, 18, 15),
    ("mustard", 65, 50, 85), ("yellow", 86, 60, 95), ("lavender", 72, 20, 300), ("purple", 35, 35, 310), ("orange", 65, 60, 60),
]
NAMED = [(n, (L, c * math.cos(math.radians(h)), c * math.sin(math.radians(h)))) for n, L, c, h in NAMES]


def name(l):
    return min(NAMED, key=lambda nl: de2000(l, nl[1]))[0]


def shirt_mask(jeans):
    """The garment's silhouette, flat-lay style, centred."""
    m = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(m)
    if jeans:
        d.polygon([(620, 120), (980, 120), (1020, 1080), (850, 1080), (800, 430), (750, 1080), (580, 1080)], fill=255)
    else:
        d.polygon([(560, 160), (700, 120), (800, 170), (900, 120), (1040, 160), (1220, 360), (1110, 450), (1040, 380), (1040, 1060), (560, 1060), (560, 380), (490, 450), (380, 360)], fill=255)
    return np.asarray(m) > 127


def scene(garment_hex, bg_hex, grout_hex, light, exposure, seed=0):
    """Photo bytes (JPEG) and the true masks (garment, background)."""
    rng = np.random.default_rng(seed)
    g = shirt_mask(garment_hex == GARMENTS["denim jeans"])
    yy, xx = np.mgrid[0:H, 0:W]
    refl = np.broadcast_to(lin_of(bg_hex), (H, W, 3)).copy()
    if grout_hex:
        refl[((yy % TILE) < GROUT) | ((xx % TILE) < GROUT)] = lin_of(grout_hex)
        refl *= (1 + 0.04 * rng.standard_normal((H // TILE + 1, W // TILE + 1)))[yy // TILE, xx // TILE][..., None]  # tile to tile
    shadow = np.asarray(Image.fromarray((g * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(14)), dtype=np.float64) / 255
    refl *= 1 - 0.35 * np.roll(shadow, (10, 10), (0, 1))[..., None] * ~g[..., None]  # soft drop shadow
    folds = 1 + 0.08 * np.sin(xx / 47.0) * np.sin(yy / 83.0) + 0.04 * rng.standard_normal((H, W))  # folds and weave
    refl[g] = lin_of(garment_hex) * folds[g][:, None]
    light_ = np.array(light) / (np.array(light) @ C.RGB2XYZ[1])  # the light changes colour, not brightness
    evenness = 1 + 0.05 * (xx / W - 0.5)  # "evenly lit": ±2.5 % across the frame
    lin = refl * light_ * exposure * evenness[..., None]
    img = Image.fromarray(np.round(C.gamma(np.clip(lin, 0, 1)) * 255).astype(np.uint8), "RGB")
    out = io.BytesIO()
    img.save(out, "JPEG", quality=90)
    ring = np.asarray(Image.fromarray((g * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(9))) > 0
    core = np.asarray(Image.fromarray((g * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(9))) > 0
    return out.getvalue(), core, ~ring


def old_measure(lin, garment, sheet):
    white = np.median(lin[sheet], axis=0)
    return C.colours(np.clip(lin * (0.9 / np.maximum(white, 1e-4)), 0, 1), garment)


def main():
    use_rembg = "--rembg" in sys.argv
    session = None
    if use_rembg:
        from rembg import new_session

        session = new_session("u2net")
    fails = []
    print(f"{'scene':27} {'garment':12} {'truth':8} {'name':11} | {'new':8} {'name':11} {'ΔE00':>5} | {'old':8} {'name':12} {'ΔE00':>5}", flush=True)
    for sname, (bg, grout, light, exposure, checked) in SCENES.items():
        for gname, ghex in GARMENTS.items():
            truth = tuple(C.lab(lin_of(ghex)[None])[0])
            data, garment, sheet = scene(ghex, bg, grout, light, exposure)
            lin = C.linear(np.asarray(Image.open(io.BytesIO(data)).convert("RGB"), dtype=np.float64) / 255)
            if use_rembg:
                _, cols = C.measure(data, session)
            else:
                cols = C.colours(C.balance(lin, sheet)[0], garment)
            old = old_measure(lin, garment, sheet)[0]
            main_ = (cols[0]["L"], cols[0]["a"], cols[0]["b"])
            d, dold = de2000(truth, main_), de2000(truth, (old["L"], old["a"], old["b"]))
            ok = d < 10 and name(main_) == name(truth)
            if checked and not ok:
                fails.append(f"{sname} / {gname}")
            verdict = "ok" if ok else "FAIL" if checked else "off (not checked)"
            print(f"{sname:27} {gname:12} {ghex:8} {name(truth):11} | {cols[0]['hex']:8} {name(main_):11} {d:5.1f} | {old['hex']:8} {name((old['L'], old['a'], old['b'])):12} {dold:5.1f}  {verdict}", flush=True)
    print(f"\n{'rembg' if use_rembg else 'known masks'}: " + (f"{len(fails)} failed: {', '.join(fails)}" if fails else "all checked cases ΔE00 < 10, names unchanged"))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
