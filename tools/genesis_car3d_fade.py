#!/usr/bin/env python3
"""Затухание краёв 3D-вида для скина Genesis.

3D-сцена рисуется прямоугольником, и на панели видна его рамка. Полностью
убрать её без шейдеров нельзя (маска в QML — это MultiEffect, а он шейдерный),
поэтому края вида растворяются картинкой: в центре она прозрачная, к краям
заливается цветом панели.

    python3 tools/genesis_car3d_fade.py

Размер должен совпадать с видом в Main.qml (420×213), цвет — с фоном панели
вокруг вида (замер по снимку: #0A1218).
"""

import os
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Dashboard", "images", "genesis", "car3d_fade.png")

W, H = 420, 213          # как x/width вида в Main.qml
FADE = 44                # ширина затухания по краю, px
COLOR = (10, 18, 24)     # #0A1218 — фон панели рядом с видом


def main():
    alpha = np.zeros((H, W), dtype=float)
    for y in range(H):
        for x in range(W):
            d = min(x, W - 1 - x, y, H - 1 - y)
            if d < FADE:
                alpha[y, x] = (1.0 - d / FADE) ** 1.6
    img = np.zeros((H, W, 4), dtype=np.uint8)
    img[:, :, 0], img[:, :, 1], img[:, :, 2] = COLOR
    img[:, :, 3] = (np.clip(alpha, 0, 1) * 255).astype(np.uint8)
    Image.fromarray(img).save(OUT)
    print(f"готово: {os.path.relpath(OUT, os.path.dirname(HERE))} {W}×{H}, "
          f"затухание {FADE} px, цвет #{COLOR[0]:02X}{COLOR[1]:02X}{COLOR[2]:02X}")


if __name__ == "__main__":
    main()
