#!/usr/bin/env python3
"""Рисует стрелку для шкал топлива и температуры (скин Genesis).

Стрелка — это только её видимый кончик: та часть, что торчит из-под
циферблата на шкалу топлива/температуры. Основание (от оси диска до кольца
шкалы) не рисуется вовсе — так стрелка «уходит под прибор», как на настоящей
панели. Толщина постоянная, 5 px по всей длине; меняется только цвет от
основания к кончику (лёгкий градиент), чтобы кончик читался.
Градиент вдоль стрелки запечён в PNG: шейдерных эффектов в проекте нет —
на программном рендерере они не работают.

Шлейф отдельной картинкой не нужен: в QML за стрелкой идут её же «призраки»
с запаздыванием по углу (см. GenesisSkin.qml, компонент DialNeedle).

    python3 tools/genesis_band_needle.py

Результат: Dashboard/images/genesis/band_needle.png — 120×5 (кончик стрелки).
"""

import os
import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
IMG = os.path.join(HERE, "..", "Dashboard", "images", "genesis")

W, H = 120, 5

TIP = (232, 244, 240)       # #E8F4F0 — остриё
BASE = (150, 190, 200)      # приглушённое основание
GLOW = (188, 234, 241)      # #BCEAF1 — свечение вокруг


def main():
    # ровная полоса 5 px по всей длине, скруглённые концы на 1 px
    alpha = np.ones((H, W), dtype=float)
    alpha[:, :1] = 0.45
    alpha[:, -1:] = 0.55

    a_img = Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.7))
    alpha = np.asarray(a_img).astype(float) / 255.0

    # цвет вдоль стрелки: основание приглушённое, к острию — светлое
    t = np.linspace(0, 1, W)[None, :, None]
    base = np.array(BASE, float)[None, None, :]
    tip = np.array(TIP, float)[None, None, :]
    rgb = (base + (tip - base) * (t ** 0.7)).repeat(H, axis=0)

    out = np.zeros((H, W, 4))
    out[:, :, :3] = rgb
    out[:, :, 3] = alpha * 255

    final = Image.fromarray(out.astype(np.uint8))
    path = os.path.join(IMG, "band_needle.png")
    final.save(path)
    print(f"band_needle.png {final.size} (ось вращения — левый центр)")


if __name__ == "__main__":
    main()
