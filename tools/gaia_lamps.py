#!/usr/bin/env python3
"""Готовит цветные лампы скина Gaia: поворотники (зелёные) и дальний свет (синий).

В макете Gaia иконки свои и монохромные, но заказчик попросил взять
указатели поворота и значок дальнего света из прошлых скинов и дать им
цвет. Поэтому здесь:

  1) белые стрелки классического скина (images/left_turn.png и
     images/right_turn.png — те же файлы, что у Genesis) копируются в
     images/gaia и красятся в зелёный;
  2) значок дальнего света классики (images/hi_beam.png) копируется туда же
     и красится в синий.

Почему покраска заранее, а не цветом в QML: цвет в QML задаётся только
шейдерным эффектом (MultiEffect.colorization), а на программном рендерере
(llvmpipe, аварийный режим без GPU) он не работает — лампа пропадает
совсем. Так же сделано в tools/tint_genesis_icons.py.

    python3 tools/gaia_lamps.py

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

# Цвета. В палитре макета Gaia их нет (макет монохромный), поэтому взяты
# «зелёный» и «синий» из палитры Genesis — чтобы лампы выглядели одинаково
# во всех скинах.
GREEN = "#57D68A"
BLUE = "#63C8FF"

# исходник -> (копия без цвета, цветная копия, цвет)
LAMPS = {
    "left_turn.png":  ("turn_left.png",      "turn_left_green.png",   GREEN),
    "right_turn.png": ("turn_right.png",     "turn_right_green.png",  GREEN),
    "hi_beam.png":    ("hi_beam.png",        "hi_beam_blue.png",      BLUE),
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
    for src_name, (plain_name, color_name, color) in LAMPS.items():
        src = os.path.join(SRC_DIR, src_name)
        if not os.path.exists(src):
            print(f"  !! нет файла {src_name}")
            continue
        shutil.copyfile(src, os.path.join(OUT_DIR, plain_name))
        size = tint(src, os.path.join(OUT_DIR, color_name), color)
        print(f"  {src_name} -> {plain_name} + {color_name}  {size[0]}x{size[1]}  {color}")


if __name__ == "__main__":
    main()
