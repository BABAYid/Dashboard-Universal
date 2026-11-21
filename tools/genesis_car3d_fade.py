#!/usr/bin/env python3
"""Затухание краёв 3D-вида для скина Genesis — по настоящему фону панели.

Задача: у 3D-вида видна граница прямоугольника. Полностью убрать её без
шейдеров нельзя (маска в QML — это MultiEffect, а он шейдерный). Поэтому края
вида растворяются картинкой, а её цвет берётся не «на глаз», а из снимка
панели: в кадре без 3D (режим 4 на столе, где сцена не рисуется) область вида —
это чистый фон скина, включая свечение.

    # снимок панели с ПУСТЫМ местом под 3D (режим с машиной, но без GPU)
    DASHBOARD_SHOT=/tmp/bg.png DASHBOARD_SHOT_DELAY=15000 \
    DASHBOARD_SKIN=genesis DASHBOARD_DEMO_MODE=4 ./build/appDashboard --mock
    python3 tools/genesis_car3d_fade.py /tmp/bg.png

Результат — Dashboard/images/genesis/car3d_fade.png: в центре прозрачная,
к краям заливается ровно тем фоном, который там у панели. Прямоугольник
перестаёт читаться, потому что на краях картинка совпадает с фоном пиксель в
пиксель.

Прямоугольник вида должен совпадать с Main.qml (X0/Y0/W/H ниже).
"""

import os
import sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Dashboard", "images", "genesis", "car3d_fade.png")

# Геометрия вида в скине Genesis (Main.qml, carView: x/y/width/height)
X0, Y0, W, H = 752, 251, 420, 213
FADE = 46          # ширина затухания по краю, px


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    shot = np.asarray(Image.open(sys.argv[1]).convert("RGB")).astype(np.uint8)
    bg = shot[Y0:Y0 + H, X0:X0 + W]
    if bg.shape[:2] != (H, W):
        print(f"снимок меньше нужного: {bg.shape}, ожидалось {(H, W)}")
        return 1

    alpha = np.zeros((H, W), dtype=float)
    for y in range(H):
        for x in range(W):
            d = min(x, W - 1 - x, y, H - 1 - y)
            if d < FADE:
                alpha[y, x] = (1.0 - d / FADE) ** 1.5

    img = np.zeros((H, W, 4), dtype=np.uint8)
    img[:, :, :3] = bg
    img[:, :, 3] = (np.clip(alpha, 0, 1) * 255).astype(np.uint8)
    Image.fromarray(img).save(OUT)

    center = bg[H // 2, W // 2]
    print(f"готово: {os.path.relpath(OUT, os.path.dirname(HERE))} {W}×{H}, "
          f"затухание {FADE} px")
    print(f"  цвет фона в центре вида: #{center[0]:02X}{center[1]:02X}{center[2]:02X} "
          f"(его же надо ставить в backgroundColor сцены)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
