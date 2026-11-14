#!/usr/bin/env python3
"""Рисует стрелку и шлейф для шкал топлива и температуры (скин Genesis).

Зачем свои картинки: у шкал нет отдельной стрелки в комплекте дизайнера —
в макете там просто светлая полоса. Рисуем стрелку-клин с градиентом и шлейф
за ней; шейдерные эффекты в проекте не используются (на программном рендерере
они не работают), поэтому обе картинки — просто PNG с альфой.

    python3 tools/genesis_band_needle.py

Результат в Dashboard/images/genesis:
    band_needle.png   90×20  — стрелка, остриё вправо, градиент вдоль клина
    band_trail.png   120×30  — шлейф, плотный справа (у стрелки), тает влево

Остриё смотрит вправо: в QML стрелка поворачивается на угол касательной полосы.
"""

import os
import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
IMG = os.path.join(HERE, "..", "Dashboard", "images", "genesis")

NEEDLE_W, NEEDLE_H = 90, 20
TRAIL_W, TRAIL_H = 120, 30

HEAD = (232, 244, 240)      # #E8F4F0 — остриё
BODY = (188, 234, 241)      # #BCEAF1 — тело стрелки и шлейф


def gradient_along(width, head, body):
    """Цвет по длине: от body к head."""
    t = np.linspace(0, 1, width)[None, :, None]
    head_a = np.array(head, dtype=float)[None, None, :]
    body_a = np.array(body, dtype=float)[None, None, :]
    return body_a + (head_a - body_a) * t


def needle():
    w, h = NEEDLE_W, NEEDLE_H
    alpha = np.zeros((h, w), dtype=float)
    cx = h / 2.0
    for x in range(w):
        u = x / (w - 1)                      # 0 — хвост, 1 — остриё
        # клин: у хвоста тонкий, к острию сходится в точку
        half = (1.0 - u) ** 0.85 * (cx - 1.5)
        half = max(half, 0.6)
        for y in range(h):
            d = abs(y + 0.5 - cx)
            if d <= half:
                alpha[y, x] = 1.0
    # мягкие края
    a_img = Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))
    alpha = np.asarray(a_img).astype(float) / 255.0

    rgb = gradient_along(w, HEAD, BODY).repeat(h, axis=0)
    out = np.zeros((h, w, 4))
    out[:, :, :3] = rgb
    out[:, :, 3] = alpha * 255

    # свечение вокруг острия
    glow = Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(3.2))
    g = np.asarray(glow).astype(float) / 255.0 * 0.55
    out[:, :, 3] = np.clip(out[:, :, 3] + g * 255, 0, 255)
    return Image.fromarray(out.astype(np.uint8))


def trail():
    w, h = TRAIL_W, TRAIL_H
    alpha = np.zeros((h, w), dtype=float)
    cx = h / 2.0
    for x in range(w):
        u = x / (w - 1)                      # 0 — дальний конец, 1 — у стрелки
        fade = u ** 2.2                      # тает к дальнему концу
        half = (0.35 + 0.65 * u) * (cx - 2.0)
        for y in range(h):
            d = abs(y + 0.5 - cx)
            if d <= half:
                alpha[y, x] = fade * (1.0 - (d / max(half, 0.6)) ** 2)
    a_img = Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(3.0))
    alpha = np.asarray(a_img).astype(float) / 255.0

    rgb = gradient_along(w, HEAD, BODY).repeat(h, axis=0)
    out = np.zeros((h, w, 4))
    out[:, :, :3] = rgb
    out[:, :, 3] = np.clip(alpha * 210, 0, 255)
    return Image.fromarray(out.astype(np.uint8))


def main():
    n = needle()
    t = trail()
    n.save(os.path.join(IMG, "band_needle.png"))
    t.save(os.path.join(IMG, "band_trail.png"))
    print(f"band_needle.png {n.size}")
    print(f"band_trail.png  {t.size}")


if __name__ == "__main__":
    main()
