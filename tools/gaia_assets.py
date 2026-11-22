#!/usr/bin/env python3
"""Раскладывает ассеты скина Gaia в Dashboard/images/gaia.

Что делает:
  1) копирует выгруженные дизайнером иконки под понятными именами
     (лампы и указатели поворота) — они белые на прозрачном, поэтому цвет
     задаётся прозрачностью в QML, без перекраски файлов;
  2) вырезает из рендера макета @2x буквы передач P R N D 2 L — в фоне их
     нет (tools/gaia_bake.py их вырезал), а рисовать их надо по одной;
  3) печатает таблицу «что где лежит в макете», которую использует
     GaiaSkin.qml.

    python3 tools/gaia_assets.py

Зависимости: numpy, Pillow.
"""

import os
import shutil

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GAIA = os.path.join(ROOT, "Gaia")
OUT = os.path.join(ROOT, "Dashboard", "images", "gaia")
DESIGN2X = os.path.join(GAIA, "Приборная панель · Вариант 2 · 1920 × 722@2x.png")

# Иконки дизайнера → имена в скине. Размер в макете 1x = размер PNG / 2.
# Иконки ламп здесь больше не раскладываются: все они цветные и готовятся
# в tools/gaia_lamps.py. Скрипт отвечает за фон и буквы передач.
ICONS = {
    # Поворотники в Gaia берутся из прошлых скинов и красятся в зелёный —
    # ими занимается отдельный скрипт tools/gaia_arrows.py.
}

# Цвета передач (просьба заказчика): P — зелёная, R — оранжевая,
# N и D — зелёные, 2 и L — оранжевые. Спрайты белые, поэтому красим копии:
# цвет в QML задаётся только шейдерным эффектом, а на программном
# рендерере он не работает (см. tools/gaia_lamps.py).
GEAR_COLORS = {
    "P": "green", "R": "orange", "N": "green",
    "D": "green", "2": "orange", "L": "orange",
}
GEAR_RGB = {"green": (0x57, 0xD6, 0x8A), "orange": (0xF6, 0x7E, 0x53)}

# Карточки передач в макете 1x: x 936.9…983.4, шаг 68.1. В @2x — вдвое.
GEAR_CARDS = [("P", 136.6), ("R", 204.7), ("N", 272.8),
              ("D", 340.9), ("2", 409.0), ("L", 477.1)]
CARD_X = 936.9
CARD_W = 46.5
CARD_H = 44.0


def copy_icons():
    for src, dst in ICONS.items():
        s = os.path.join(GAIA, src)
        if not os.path.exists(s):
            print(f"  !! нет файла {src}")
            continue
        shutil.copyfile(s, os.path.join(OUT, dst))
        im = Image.open(s)
        print(f"  {src:32s} -> {dst:18s} {im.size[0]}x{im.size[1]}  "
              f"(в макете {im.size[0] / 2:.1f}x{im.size[1] / 2:.1f})")


def extract_gears():
    """Буквы передач — из рендера @2x: белая альфа по яркости глифа."""
    d = np.asarray(Image.open(DESIGN2X).convert("L")).astype(float)
    for letter, y0 in GEAR_CARDS:
        x0 = int(round(CARD_X * 2)) - 4
        x1 = int(round((CARD_X + CARD_W) * 2)) + 4
        ya = int(round(y0 * 2)) - 4
        yb = int(round((y0 + CARD_H) * 2)) + 4
        crop = d[ya:yb, x0:x1]
        mask = crop > 150   # буква светлее плашки карточки
        if not mask.any():
            print(f"  !! нет глифа {letter}")
            continue
        ys, xs = np.nonzero(mask)
        # отступ, чтобы сглаживание не резалось
        gx0, gx1 = max(0, xs.min() - 2), min(crop.shape[1], xs.max() + 3)
        gy0, gy1 = max(0, ys.min() - 2), min(crop.shape[0], ys.max() + 3)
        sub = crop[gy0:gy1, gx0:gx1]
        alpha = np.clip(sub, 0, 255).astype(np.uint8)
        rgba = np.zeros((sub.shape[0], sub.shape[1], 4), np.uint8)
        rgba[..., :3] = 255
        rgba[..., 3] = alpha
        name = f"gear_{letter}.png"
        Image.fromarray(rgba, "RGBA").save(os.path.join(OUT, name))
        colour = GEAR_COLORS.get(letter)
        if colour:
            rgb = GEAR_RGB[colour]
            tinted = rgba.copy()
            tinted[..., 0] = rgb[0]
            tinted[..., 1] = rgb[1]
            tinted[..., 2] = rgb[2]
            Image.fromarray(tinted, "RGBA").save(os.path.join(OUT, f"gear_{letter}_{colour}.png"))
            print(f"  {letter}: {name} + gear_{letter}_{colour}.png "
                  f"{sub.shape[1]}x{sub.shape[0]} (1x {sub.shape[1] / 2:.1f}x{sub.shape[0] / 2:.1f})")
        else:
            print(f"  {letter}: {name} {sub.shape[1]}x{sub.shape[0]} (1x {sub.shape[1] / 2:.1f}x{sub.shape[0] / 2:.1f})")


def main():
    os.makedirs(OUT, exist_ok=True)
    print("иконки ламп и поворотников:")
    copy_icons()
    print("буквы передач:")
    extract_gears()
    print("\nчто где лежит в макете (1x, как в GaiaSkin.qml):")
    print("  левый колодец:  центр (584.7, 295.0), ось стрелки (583.4, 367.2), r шкалы 302.6x231.4")
    print("  правый колодец: центр (1335.3, 295.0), ось стрелки (1337.8, 365.9)")
    print("  шкалы: 0 внизу-слева под 140°, максимум внизу-справа под 410°, ход 270°")
    print("  лампы (центры, y≈600): 362 топливо, 639 двигатель, 741 ABS, 884 ECO,")
    print("                          1084 масло, 1165 двери, 1261 АКБ, 1351 тормоза,")
    print("                          1439 подушка, 1544 ремень")
    print("  поворотники: (873, 79) и (1048, 79), 52x50")


if __name__ == "__main__":
    main()
