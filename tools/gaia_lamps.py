#!/usr/bin/env python3
"""Готовит цветные лампы скина Gaia.

Поворотники (зелёные) и дальний свет (синий) делаются из белых иконок
классического скина заливкой цвета. Лампы-предупреждения (check engine,
ABS, масло, АКБ, ручник) берутся из скина Genesis — там они уже покрашены
в палитру приборки (янтарный/красный) и выгружены в 256×224, поэтому просто
копируются под именами Gaia.

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

# Исходник классики -> (копия без цвета, цветная копия, цвет)
LAMPS = {
    "left_turn.png":  ("turn_left.png",      "turn_left_green.png",   GREEN),
    "right_turn.png": ("turn_right.png",     "turn_right_green.png",  GREEN),
    "hi_beam.png":    ("hi_beam.png",        "hi_beam_blue.png",      BLUE),
}

# Предупреждающие лампы: берём готовые цветные иконки Genesis (256×224,
# палитра lampWarn/lampAlarm) и кладём под именем Gaia — перекрашивать не
# нужно, цвет в них уже тот, что в GenesisSkin.qml.
GENESIS_DIR = os.path.join(SRC_DIR, "genesis")
WARN_FROM_GENESIS = {
    "warn_check_engine_amber.png": "lamp_engine.png",
    "warn_abs_amber.png":          "lamp_abs.png",
    "warn_oil_pressure_red.png":   "lamp_oil.png",
    "warn_battery_red.png":        "lamp_batt.png",
    "warn_hand_brake_red.png":     "lamp_brake.png",
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

    for src_name, dst_name in WARN_FROM_GENESIS.items():
        src = os.path.join(GENESIS_DIR, src_name)
        if not os.path.exists(src):
            print(f"  !! нет файла genesis/{src_name}")
            continue
        # Иконки Genesis выгружены в 256×224 с большими прозрачными полями:
        # без обрезки по контенту значок в посадочном месте Gaia (46×31)
        # получается крошечным.
        im = Image.open(src).convert("RGBA")
        box = im.getbbox()
        if box:
            im = im.crop(box)
        im.save(os.path.join(OUT_DIR, dst_name))
        print(f"  genesis/{src_name} -> {dst_name}  {im.size} (обрезано по контенту)")


if __name__ == "__main__":
    main()
