#!/usr/bin/env python3
"""Находит на макете все «буквы/цифры» и читает их OCR-ом.

Зачем: в SVG дизайнера нет ни одного <text> — вся типографика переведена в
кривые. Поэтому что написано на шкалах и где стоят подписи, надёжнее всего
снять с растрового рендера макета: находим яркие связные компоненты,
склеиваем в слова и отдаём в tesseract.

    python3 tools/gaia_text.py                     # весь макет
    python3 tools/gaia_text.py --thr 170           # маска «самое яркое»
    python3 tools/gaia_text.py --box 280,50,900,540  # только область

tesseract берётся из локально распакованных пакетов (.dsh-ocr/tess), если он
там есть; иначе — из PATH. Зависимости: numpy, Pillow.
"""

import os
import subprocess
import sys
from collections import deque

import numpy as np
from PIL import Image, ImageOps

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DEFAULT_PNG = os.path.join(ROOT, "Gaia", "Приборная панель · Вариант 2 · 1920 × 722.png")
TESS_LOCAL = os.path.join(ROOT, ".dsh-ocr", "tess")
TESS_DATA = os.path.join(TESS_LOCAL, "usr", "share", "tesseract-ocr", "5", "tessdata")


def tesseract_cmd():
    exe = os.path.join(TESS_LOCAL, "usr", "bin", "tesseract")
    if os.path.exists(exe):
        return exe
    return "tesseract"


def ocr_image(img, psm="7", lang="rus+eng", cmd=None):
    tmp = os.path.join(ROOT, ".dsh-ocr", "gaia", "ocr_block.png")
    os.makedirs(os.path.dirname(tmp), exist_ok=True)
    img.save(tmp)
    env = dict(os.environ)
    env["LD_LIBRARY_PATH"] = os.path.join(TESS_LOCAL, "usr", "lib", "x86_64-linux-gnu")
    if os.path.isdir(TESS_DATA):
        env["TESSDATA_PREFIX"] = TESS_DATA
    r = subprocess.run([cmd or tesseract_cmd(), tmp, "stdout", "-l", lang, "--psm", psm],
                       capture_output=True, text=True, env=env)
    return r.stdout.strip()


def components(mask):
    """Связные компоненты 4-связностью (без scipy)."""
    h, w = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    out = []
    ys, xs = np.nonzero(mask)
    for y, x in zip(ys.tolist(), xs.tolist()):
        if seen[y, x]:
            continue
        q = deque([(y, x)])
        seen[y, x] = True
        x0 = x1 = x
        y0 = y1 = y
        n = 0
        while q:
            cy, cx = q.popleft()
            n += 1
            if cx < x0: x0 = cx
            if cx > x1: x1 = cx
            if cy < y0: y0 = cy
            if cy > y1: y1 = cy
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = cy + dy, cx + dx
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    q.append((ny, nx))
        out.append((x0, y0, x1, y1, n))
    return out


def group_words(comps, gap_x=7, gap_y=3):
    """Склеиваем компоненты в слова: близко по x и на одной строке."""
    words = []
    for c in sorted(comps, key=lambda c: (c[1], c[0])):
        placed = False
        for w in words:
            if (c[1] <= w[3] + gap_y and c[3] >= w[1] - gap_y
                    and c[0] <= w[2] + gap_x and c[2] >= w[0] - gap_x):
                w[0] = min(w[0], c[0]); w[1] = min(w[1], c[1])
                w[2] = max(w[2], c[2]); w[3] = max(w[3], c[3])
                w[4].append(c)
                placed = True
                break
        if not placed:
            words.append([c[0], c[1], c[2], c[3], [c]])
    return words


def main():
    args = sys.argv[1:]
    png = DEFAULT_PNG
    thr = 165
    box = None
    i = 0
    while i < len(args):
        if args[i] == "--thr":
            thr = float(args[i + 1]); i += 2
        elif args[i] == "--box":
            box = tuple(int(v) for v in args[i + 1].split(",")); i += 2
        else:
            png = args[i]; i += 1

    im = Image.open(png).convert("L")
    a = np.asarray(im).astype(float)
    ox, oy = 0, 0
    if box:
        x0, y0, x1, y1 = box
        a = a[y0:y1, x0:x1]
        ox, oy = x0, y0

    mask = a > thr
    comps = [c for c in components(mask) if c[4] >= 12]
    words = group_words(comps)
    print(f"{os.path.basename(png)}: порог {thr}, компонент {len(comps)}, слов {len(words)}")
    print(f"{'x':>5} {'y':>5} {'w':>4} {'h':>4}  text")
    for w in sorted(words, key=lambda w: (w[1] // 40, w[0])):
        x0, y0, x1, y1 = w[0], w[1], w[2], w[3]
        pad = 4
        crop = a[max(0, y0 - pad):y1 + pad, max(0, x0 - pad):x1 + pad]
        if crop.size == 0 or crop.shape[0] < 6 or crop.shape[1] < 6:
            continue
        m = (crop > thr).astype(np.uint8) * 255
        img = Image.fromarray(255 - m)
        scale = max(2, int(120 / max(1, crop.shape[0])))
        img = img.resize((crop.shape[1] * scale, crop.shape[0] * scale), Image.LANCZOS)
        txt = ocr_image(img)
        print(f"{x0+ox:5d} {y0+oy:5d} {x1-x0:4d} {y1-y0:4d}  {txt!r}")


if __name__ == "__main__":
    main()
