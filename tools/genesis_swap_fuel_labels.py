#!/usr/bin/env python3
"""Меняет местами подписи «0» и «1» на шкале топлива (скин Genesis).

На арте дизайнера у начала полосы нарисована «0», у конца — «1». Вместе с
переворотом логики стрелки (`fuelReverse: true` в GenesisSkin.qml) это даёт
нужное чтение шкалы: пустой бак — на «0», полный — на «1».

Скрипт берёт исходник дизайнера `Genesis/Gauge/fuel.png`, вырезает оба знака и
вставляет их навстречу друг другу (по центрам), результат пишет в
`Dashboard/images/genesis/scale_fuel.png`. Исходник не меняется, поэтому скрипт
идемпотентен: сколько раз ни запускай — файл получится один и тот же.

Вернуть исходные подписи: скопировать `Genesis/Gauge/fuel.png` поверх
`Dashboard/images/genesis/scale_fuel.png` и выключить `fuelReverse`.

    python3 tools/genesis_swap_fuel_labels.py
"""

import os
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, "Genesis", "Gauge", "fuel.png")
DST = os.path.join(ROOT, "Dashboard", "images", "genesis", "scale_fuel.png")

# Прямоугольники знаков в файле (замер по альфе: у «0» 20×39, у «1» 13×38),
# взяты с полями, чтобы захватить свечение вокруг штрихов.
GLYPH_TOP = (102, 872, 138, 926)       # «0» у начала полосы
GLYPH_BOTTOM = (324, 1222, 356, 1278)  # «1» у конца полосы

ARR = None
ALPHA = None


def content_center(box):
    """Центр непрозрачного содержимого внутри прямоугольника."""
    x0, y0, x1, y1 = box
    sub = ALPHA[y0:y1, x0:x1]
    ys, xs = np.nonzero(sub > 30)
    return (x0 + (xs.min() + xs.max()) / 2, y0 + (ys.min() + ys.max()) / 2)


def cut(box):
    x0, y0, x1, y1 = box
    block = ARR[y0:y1, x0:x1].copy()
    ARR[y0:y1, x0:x1] = 0
    return block


def paste(block, center):
    """Кладёт блок так, чтобы центр его содержимого попал в center."""
    ys, xs = np.nonzero(block[:, :, 3] > 30)
    h, w = block.shape[:2]
    cx = int(round(center[0] - (xs.min() + xs.max()) / 2))
    cy = int(round(center[1] - (ys.min() + ys.max()) / 2))
    region = ARR[cy:cy + h, cx:cx + w]
    alpha = block[:, :, 3:4].astype(float) / 255.0
    region[:, :, :3] = (block[:, :, :3] * alpha
                        + region[:, :, :3] * (1 - alpha)).astype(np.uint8)
    region[:, :, 3:4] = np.maximum(region[:, :, 3:4], block[:, :, 3:4])


def main():
    global ARR, ALPHA
    ARR = np.asarray(Image.open(SRC).convert("RGBA")).copy()
    ALPHA = ARR[:, :, 3]

    center_top = content_center(GLYPH_TOP)
    center_bottom = content_center(GLYPH_BOTTOM)

    block_top = cut(GLYPH_TOP)
    block_bottom = cut(GLYPH_BOTTOM)

    paste(block_bottom, center_top)      # «1» — на место «0»
    paste(block_top, center_bottom)      # «0» — на место «1»

    Image.fromarray(ARR).save(DST)
    print(f"готово: {os.path.relpath(DST, ROOT)}")
    print(f"  «0» был в {tuple(round(v) for v in center_top)}, "
          f"«1» в {tuple(round(v) for v in center_bottom)} — поменяны местами")


if __name__ == "__main__":
    main()
