#!/usr/bin/env python3
"""Готовит указатели поворота для скина Gaia.

В макете Gaia стрелки свои (широкие, 105×100), но заказчик попросил взять
стрелки из прошлых скинов и сделать их зелёными. Поэтому здесь:

  1) берём белые стрелки классического скина (images/left_turn.png и
     images/right_turn.png — те же файлы, что у Genesis);
  2) кладём копии в images/gaia под теми же именами;
  3) красим их в зелёный и кладём рядом файлы *_green.png.

Почему покраска заранее, а не цветом в QML: цвет в QML задаётся только
шейдерным эффектом (MultiEffect.colorization), а на программном рендерере
(llvmpipe, аварийный режим без GPU) он не работает — лампа пропадает
совсем. Так же сделано в tools/tint_genesis_icons.py.

    python3 tools/gaia_arrows.py

Зависимости: numpy, Pillow.
"""

import os
import shutil

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC_DIR = os.path.join(ROOT, "Dashboard", "images")
OUT_DIR = os.path.join(ROOT, "Dashboard", "images", "gaia")

# Цвет поворотника. В палитре макета Gaia его нет (макет монохромный),
# поэтому взят «зелёный поворотника» из палитры Genesis — чтобы стрелки
# выглядели одинаково во всех скинах.
GREEN = "#57D68A"

PAIRS = {
    "left_turn.png": ("turn_left.png", "turn_left_green.png"),
    "right_turn.png": ("turn_right.png", "turn_right_green.png"),
}


def tint(src, dst, color):
    im = Image.open(src).convert("RGBA")
    a = np.asarray(im)
    rgb = np.array([int(color[1:3], 16), int(color[3:5], 16), int(color[5:7], 16)], np.uint8)
    out = np.zeros_like(a)
    out[..., 0] = rgb[0]
    out[..., 1] = rgb[1]
    out[..., 2] = rgb[2]
    out[..., 3] = a[..., 3]
    Image.fromarray(out, "RGBA").save(dst)
    return im.size


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for src_name, (plain_name, green_name) in PAIRS.items():
        src = os.path.join(SRC_DIR, src_name)
        if not os.path.exists(src):
            print(f"  !! нет файла {src_name}")
            continue
        shutil.copyfile(src, os.path.join(OUT_DIR, plain_name))
        size = tint(src, os.path.join(OUT_DIR, green_name), GREEN)
        print(f"  {src_name} -> {plain_name} + {green_name}  {size[0]}x{size[1]}  {GREEN}")


if __name__ == "__main__":
    main()
