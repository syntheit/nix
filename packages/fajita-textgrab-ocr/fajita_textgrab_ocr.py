"""fajita-textgrab-ocr — OCR helper for the long-press text-grab feature.

Contract:
    Reads a single PNG image on stdin (raw bytes), runs tesseract OCR over an
    optionally-upscaled copy, and emits JSON on stdout describing every
    recognized word and line with their bounding boxes in ORIGINAL image
    pixel space.

    Output shape (always valid JSON, always on stdout):
        {
          "words": [
            {"text": str, "x": int, "y": int, "w": int, "h": int,
             "line": int, "conf": float},
            ...
          ],
          "lines": [
            {"text": str, "x": int, "y": int, "w": int, "h": int},
            ...
          ]
        }

    This is a FAIL-CLOSED, always-valid-JSON contract: on empty stdin, a
    tesseract failure, or ANY unexpected exception, the program prints
    {"words":[],"lines":[]} to stdout and exits 0. The calling shell relies on
    always receiving parseable JSON and never a crash.

    Coordinates are reported in the ORIGINAL (pre-upscale) image space: OCR
    runs on the upscaled image for accuracy, then every box is divided back
    down by the upscale factor and clamped to the original image bounds.

    Line grouping follows normcap's detection/ocr/models.py approach: words
    sharing a (block_num, par_num, line_num) tuple belong to the same line;
    a line's text is its words joined with a single space and its box is the
    union bounding rect of its words' boxes.
"""

import argparse
import io
import json
import os
import subprocess
import sys


def build_parser():
    parser = argparse.ArgumentParser(
        description="PNG on stdin -> word/line boxes JSON via tesseract OCR."
    )
    parser.add_argument(
        "--lang",
        default="eng+spa",
        help="Language(s) passed to tesseract -l (default: eng+spa).",
    )
    parser.add_argument(
        "--upscale",
        default=2,
        type=float,
        help="Upscale factor applied before OCR (default: 2).",
    )
    parser.add_argument(
        "--engine",
        default="tesseract",
        help=(
            "OCR engine. Only 'tesseract' is implemented; 'ocrs' falls back "
            "to tesseract with a warning. Reserved for the on-device caller."
        ),
    )
    parser.add_argument(
        "--psm",
        default=6,
        type=int,
        help="Tesseract page segmentation mode (default: 6).",
    )
    parser.add_argument(
        "--min-conf",
        default=40.0,
        type=float,
        help="Drop words with conf below this (0-100, default: 40.0).",
    )
    return parser


def empty_output():
    print(json.dumps({"words": [], "lines": []}, ensure_ascii=False))


def run_tesseract(png_bytes, lang, psm):
    binary = os.environ.get("FAJITA_TESSERACT", "tesseract")
    cmd = [
        binary,
        "stdin",
        "stdout",
        "--psm",
        str(psm),
        "-l",
        lang,
        "tsv",
    ]
    proc = subprocess.run(
        cmd,
        input=png_bytes,
        capture_output=True,
        check=False,
    )
    if proc.returncode != 0:
        return None
    return proc.stdout.decode("utf-8", errors="replace")


def parse_tsv(tsv, upscale, min_conf, orig_w, orig_h):
    words = []
    # line-identity tuple -> stable integer index
    line_index = {}
    lines = {}  # index -> {"texts": [...], "x0","y0","x1","y1"}

    rows = tsv.splitlines()
    if rows:
        rows = rows[1:]  # drop header

    for raw_row in rows:
        cols = raw_row.split("\t")
        if len(cols) < 12:
            continue
        try:
            level = int(cols[0])
        except ValueError:
            continue
        if level != 5:
            continue

        try:
            block_num = int(cols[2])
            par_num = int(cols[3])
            line_num = int(cols[4])
            left = int(cols[6])
            top = int(cols[7])
            width = int(cols[8])
            height = int(cols[9])
        except ValueError:
            continue

        try:
            conf = float(cols[10])
        except ValueError:
            continue

        text = "\t".join(cols[11:])
        if conf < 0 or conf < min_conf:
            continue
        if not text.strip():
            continue

        x = round(left / upscale)
        y = round(top / upscale)
        w = round(width / upscale)
        h = round(height / upscale)

        if x < 0:
            x = 0
        if y < 0:
            y = 0
        if w < 0:
            w = 0
        if h < 0:
            h = 0
        if x + w > orig_w:
            w = orig_w - x
        if y + h > orig_h:
            h = orig_h - y
        if w < 0:
            w = 0
        if h < 0:
            h = 0

        key = (block_num, par_num, line_num)
        if key not in line_index:
            line_index[key] = len(line_index)
        idx = line_index[key]

        words.append({
            "text": text,
            "x": x,
            "y": y,
            "w": w,
            "h": h,
            "line": idx,
            "conf": round(conf, 2),
        })

        entry = lines.get(idx)
        if entry is None:
            lines[idx] = {
                "texts": [text],
                "x0": x,
                "y0": y,
                "x1": x + w,
                "y1": y + h,
            }
        else:
            entry["texts"].append(text)
            if x < entry["x0"]:
                entry["x0"] = x
            if y < entry["y0"]:
                entry["y0"] = y
            if x + w > entry["x1"]:
                entry["x1"] = x + w
            if y + h > entry["y1"]:
                entry["y1"] = y + h

    line_list = []
    for idx in sorted(lines.keys()):
        entry = lines[idx]
        line_list.append({
            "text": " ".join(entry["texts"]),
            "x": entry["x0"],
            "y": entry["y0"],
            "w": entry["x1"] - entry["x0"],
            "h": entry["y1"] - entry["y0"],
        })

    return words, line_list


def main():
    try:
        args = build_parser().parse_args()

        if args.engine == "ocrs":
            print(
                "fajita-textgrab-ocr: engine 'ocrs' not implemented, "
                "falling back to tesseract",
                file=sys.stderr,
            )

        png_bytes = sys.stdin.buffer.read()
        if not png_bytes:
            empty_output()
            return

        from PIL import Image

        img = Image.open(io.BytesIO(png_bytes)).convert("RGB")
        orig_w, orig_h = img.size

        upscale = args.upscale
        if upscale != 1:
            img = img.resize(
                (round(orig_w * upscale), round(orig_h * upscale)),
                Image.LANCZOS,
            )

        buf = io.BytesIO()
        img.save(buf, format="PNG")
        upscaled_png = buf.getvalue()

        tsv = run_tesseract(upscaled_png, args.lang, args.psm)
        if tsv is None:
            empty_output()
            return

        words, lines = parse_tsv(
            tsv, upscale, args.min_conf, orig_w, orig_h
        )
        print(json.dumps(
            {"words": words, "lines": lines}, ensure_ascii=False
        ))
    except Exception as exc:  # noqa: BLE001 — fail-closed contract
        empty_output()
        print(exc, file=sys.stderr)
        sys.exit(0)


if __name__ == "__main__":
    main()
