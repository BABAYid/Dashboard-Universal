#!/usr/bin/env python3
"""Находит, где в макете стоит каждый экспортированный из Figma ассет.

Зачем: дизайнер выгрузил иконки отдельными PNG (Gaia/*.png), но не сказал,
в каком месте панели какая. Автоподбор по корреляции маски иконки с
яркостью макета @2x даёт точные координаты — их и берём в QML, чтобы
раскладка совпала с макетом без «на глаз».

    python3 tools/gaia_match.py            # все иконки
    python3 tools/gaia_match.py 2.png D.png

Зависимости: numpy, Pillow. Быстро: корреляция через FFT.
"""

import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GAIA = os.path.join(ROOT, "Gaia")
DESIGN = os.path.join(GAIA, "Приборная панель · Вариант 2 · 1920 × 722@2x.png")


def load_design():
    im = Image.open(DESIGN).convert("L")
    a = np.asarray(im).astype(np.float32)
    return a


def match(design, icon_path, scale=1.0):
    im = Image.open(icon_path).convert("RGBA")
    w, h = im.size
    if scale != 1.0:
        im = im.resize((max(2, int(w * scale)), max(2, int(h * scale))), Image.LANCZOS)
    a = np.asarray(im).astype(np.float32)
    mask = (a[:, :, 3] > 40).astype(np.float32)
    lum = a[:, :, :3].mean(axis=2)
    # шаблон: яркость только там, где есть пиксели
    templ = lum * mask
    th, tw = templ.shape
    dh, dw = design.shape
    if th > dh or tw > dw:
        return None
    # нормированная корреляция через FFT
    num = np.fft.irfft2(np.fft.rfft2(design) * np.conj(np.fft.rfft2(templ, design.shape)), design.shape)
    msum = np.fft.irfft2(np.fft.rfft2(np.ones_like(design)) * np.conj(np.fft.rfft2(mask, design.shape)), design.shape)
    # нормируем на площадь: средняя яркость под маской
    valid = msum > 1e-3
    score = np.full(design.shape, -1e9, dtype=np.float32)
    score[valid] = num[valid] / msum[valid]
    # ищем максимум в области, где шаблон помещается
    sub = score[:dh - th + 1, :dw - tw + 1]
    idx = int(np.argmax(sub))
    y, x = divmod(idx, sub.shape[1])
    return x, y, float(sub[y, x])


def main():
    design = load_design()
    names = sys.argv[1:] or sorted(
        f for f in os.listdir(GAIA) if f.lower().endswith(".png") and "1920" not in f)
    print(f"макет @2x {design.shape[1]}x{design.shape[0]}")
    print(f"{'файл':42s} {'@2x x,y':>14s} {'1x x,y':>12s} {'score':>7s}")
    for n in names:
        p = os.path.join(GAIA, n)
        if not os.path.exists(p):
            continue
        best = None
        for sc in (1.0, 0.5, 0.75, 1.5):
            r = match(design, p, sc)
            if r is None:
                continue
            x, y, s = r
            if best is None or s > best[3]:
                best = (x, y, sc, s)
        if best is None:
            print(f"{n:42s} {'—':>14s}")
            continue
        x, y, sc, s = best
        print(f"{n:42s} {f'{x},{y}':>14s} {f'{x/2:.0f},{y/2:.0f}':>12s} {s:7.1f}")


if __name__ == "__main__":
    main()
