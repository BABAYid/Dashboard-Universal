#!/usr/bin/env python3
"""Проверяет, что скин Genesis стоит по макету: ищет картинки комплекта
дизайнера на рендере макета и на снимке приложения и сравнивает места.

Зачем: «на глаз» раскладку не сверить — модель не видит картинок, а человек
не заметит сдвиг на 20 px. Шаблонный поиск (нормированная корреляция по
масштабам) находит каждый файл на обоих изображениях и говорит, где он стоит.

Нужны два PNG одинакового размера 1920×720:

    # рендер макета (Chrome умеет рисовать SVG)
    google-chrome --headless=new --no-sandbox --disable-gpu --hide-scrollbars \
        --window-size=1920,720 --screenshot=design.png design.html
    # снимок приложения
    DASHBOARD_SHOT=/tmp/skin.png DASHBOARD_SHOT_DELAY=9000 \
    DASHBOARD_SKIN=genesis ./build/appDashboard --mock

    python3 tools/genesis_place_check.py design.png /tmp/skin.png

Оценка совпадения: 0.9 и выше — файл найден уверенно, 0.6…0.8 — похоже,
ниже 0.5 — не найден (например, элемент не выводится или нарисован кодом).
"""

import os
import sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GEN = os.path.join(ROOT, "Genesis")

# что искать: файл из комплекта дизайнера
ASSETS = [
    "Information/Range.png",
    "Information/Odometer.png",
    "Information/Footer.png",
    "Icon/Fuel.png",
    "Icon/Coolant.png",
    "Icon/Clock.png",
    "Icon/Snow.png",
    "Indicator/Speed limit.png",
    "Indicator/Driving mode.png",
    "Indicator/Gear.png",
]


def load_template(path):
    a = np.asarray(Image.open(path).convert("RGBA")).astype(np.float32)
    mask = (a[:, :, 3] > 60).astype(np.float32)
    ys, xs = np.nonzero(mask)
    return (mask[ys.min():ys.max() + 1, xs.min():xs.max() + 1],
            (int(xs.min()), int(ys.min())), Image.open(path).size)


def locate(image, template, off, full_size, scales):
    """Возвращает (оценка, масштаб, x, y) лучшего совпадения."""
    H, W = image.shape
    ink = np.clip((image - 40.0) / 160.0, 0, 1)
    F = np.fft.rfft2
    best = (0.0, 0.0, 0, 0)
    for scale in scales:
        th = max(10, int(round(template.shape[0] * scale)))
        tw = max(10, int(round(template.shape[1] * scale)))
        if th >= H or tw >= W:
            continue
        t = np.asarray(Image.fromarray((template * 255).astype(np.uint8))
                       .resize((tw, th), Image.LANCZOS)).astype(np.float32) / 255.0
        t = t - t.mean()
        tn = np.sqrt((t * t).sum())
        if tn < 1e-6:
            continue
        corr = np.fft.irfft2(F(ink) * np.conj(F(t, s=(H, W))), s=(H, W))
        ones = np.ones_like(t)
        s1 = np.fft.irfft2(F(ink) * np.conj(F(ones, s=(H, W))), s=(H, W))
        s2 = np.fft.irfft2(F(ink * ink) * np.conj(F(ones, s=(H, W))), s=(H, W))
        var = np.maximum(s2 - s1 * s1 / t.size, 1e-4)
        score = corr / (np.sqrt(var) * tn)
        y, x = np.unravel_index(np.argmax(score), score.shape)
        if score[y, x] > best[0]:
            ox = int(x) - int(round(off[0] * scale))
            oy = int(y) - int(round(off[1] * scale))
            best = (float(score[y, x]), float(scale), ox, oy)
    return best


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    design = np.asarray(Image.open(sys.argv[1]).convert("L")).astype(np.float32)
    skin = np.asarray(Image.open(sys.argv[2]).convert("L")).astype(np.float32)
    if design.shape != skin.shape:
        print(f"размеры разные: {design.shape} и {skin.shape} — нужны оба 1920×720")
        return 1

    print(f"{'файл':24s} {'макет (x,y)':>16s} {'скин (x,y)':>16s} {'сдвиг':>10s} {'оценка':>7s}")
    bad = 0
    for rel in ASSETS:
        path = os.path.join(GEN, rel)
        if not os.path.exists(path):
            print(f"{rel:24s} — нет файла")
            continue
        tpl, off, size = load_template(path)
        scales = np.arange(0.30, 0.62, 0.01)
        sd = locate(design, tpl, off, size, scales)
        ss = locate(skin, tpl, off, size, scales)
        if sd[0] < 0.5:
            print(f"{rel:24s} в макете не найден (оценка {sd[0]:.2f})")
            continue
        dx, dy = ss[2] - sd[2], ss[3] - sd[3]
        mark = "ok" if max(abs(dx), abs(dy)) <= 4 and ss[0] >= 0.5 else "!!"
        if mark == "!!":
            bad += 1
        print(f"{rel:24s} {str((sd[2], sd[3])):>16s} {str((ss[2], ss[3])):>16s} "
              f"{f'{dx:+d},{dy:+d}':>10s} {ss[0]:7.2f}  {mark}")
    print()
    print("ok — стоит там же, где в макете (сдвиг до 4 px); "
          "!! — расхождение или элемент не найден")
    return 0 if bad == 0 else 2


if __name__ == "__main__":
    sys.exit(main())
