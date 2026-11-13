#!/usr/bin/env python3
"""Красит белые иконки ламп скина Genesis в цвета панели.

Зачем скрипт, если иконки «монохромные белые, а цвет задаётся в QML»:
задать цвет в QML можно только эффектом (MultiEffect.colorization), а он
шейдерный. На программном рендерере (llvmpipe, аварийный режим без GPU)
шейдерные эффекты не работают и лампы не рисуются вовсе. Поэтому цветные
варианты делаются из тех же файлов заранее — рисование остаётся обычной
картинкой, без эффектов, и стоит дешевле на RK3588.

Цвета повторяют константы lampInfo / lampWarn / lampAlarm из
Dashboard/GenesisSkin.qml. Если меняете цвет там — прогоняйте скрипт заново:

    python3 tools/tint_genesis_icons.py

Что делает: берёт альфу исходной белой иконки, заливает её цветом, кладёт
рядом файл с суффиксом цвета и пишет список получившихся файлов.
"""

import os
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
IMG = os.path.join(HERE, "..", "Dashboard", "images", "genesis")

# Те же цвета, что в GenesisSkin.qml (дневной вариант).
COLORS = {
    "cyan": "#BCEAF1",     # lampInfo  — свет, габариты, поворотники
    "amber": "#F2C14E",    # lampWarn  — предупреждение
    "red": "#FF5252",      # lampAlarm — авария
}

# какие иконки в каком цвете нужны скину
NEEDED = {
    "cyan": ["turn_left", "turn_right", "warn_high_beam", "warn_position_lights",
             "warn_fog_front", "warn_snowflake", "warn_fog_rear"],
    "amber": ["warn_check_engine", "warn_abs", "warn_attention_yellow",
              "warn_stability_esc", "warn_tire_pressure"],
    "red": ["warn_oil_pressure", "warn_brake_red", "warn_seat_belt",
            "warn_battery", "warn_car_triangle", "warn_hand_brake"],
}


def hex_to_rgb(value):
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def main():
    made = []
    for tone, names in NEEDED.items():
        rgb = hex_to_rgb(COLORS[tone])
        for name in names:
            src = os.path.join(IMG, name + ".png")
            if not os.path.exists(src):
                print(f"  нет исходника: {name}.png — пропуск")
                continue
            im = Image.open(src).convert("RGBA")
            a = np.asarray(im)
            out = np.zeros_like(a)
            out[:, :, 0], out[:, :, 1], out[:, :, 2] = rgb
            out[:, :, 3] = a[:, :, 3]
            dst = os.path.join(IMG, f"{name}_{tone}.png")
            Image.fromarray(out).save(dst)
            made.append(os.path.basename(dst))
    print(f"готово, файлов: {len(made)}")
    for name in sorted(made):
        print("  " + name)


if __name__ == "__main__":
    main()
