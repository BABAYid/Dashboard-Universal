#!/usr/bin/env python3
"""Псевдо-рендер картинки в ASCII: посмотреть макет без глаз.

    python3 tools/gaia_ascii.py <png> [ширина]

Печатает карту яркости: ' ' — фон, '.'..'#' — от тёмного к яркому.
Тонкие шкалы в тёмном фоне видны как редкие точки, текст — как плотные
пятна, поэтому картинку стоит смотреть и в «инвертированном» режиме (--inv),
где буквами отмечены светлые места.

Зависимости: numpy + Pillow.
"""
import sys
import numpy as np
from PIL import Image

path = sys.argv[1]
W = int(sys.argv[2]) if len(sys.argv) > 2 and not sys.argv[2].startswith("--") else 200
inv = "--inv" in sys.argv

im = Image.open(path).convert("L")
w, h = im.size
H = max(4, int(W * h / w / 2.1))
small = np.asarray(im.resize((W, H), Image.BOX)).astype(float)
lo, hi = small.min(), small.max()
norm = (small - lo) / max(1e-6, (hi - lo))
if inv:
    norm = 1.0 - norm
ramp = " .:-=+*#%@"
print(f"{path}: {w}x{h} -> {W}x{H}")
for row in norm:
    print("".join(ramp[min(len(ramp) - 1, int(v * (len(ramp) - 1) + 0.5))] for v in row))
