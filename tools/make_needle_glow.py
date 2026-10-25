#!/usr/bin/env python3
"""Генерирует images/needle_glow.png — размытый след стрелки для шлейфа.

Растеризует SVG-арт стрелки (ImageMagick), превращает в белый силуэт,
размывает и кладёт на холст 990x990 с запасом, чтобы размытие не обрезалось.
Стрелка в QML масштабируется на 990/720 — холст и арт согласованы.

usage: tools/make_needle_glow.py [--color #FFFFFF] [--blur 14] [notes...]
"""
import subprocess
import sys
import os

from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "Dashboard", "images", "needls_spd.svg")
OUT = os.path.join(ROOT, "Dashboard", "images", "needle_glow.png")
TMP = "/tmp/needle_art.png"
CANVAS = 990
ART_SIZE = 720


def main():
    color = (255, 255, 255)
    blur = 14
    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--color":
            h = args[i + 1].lstrip("#")
            color = tuple(int(h[j:j + 2], 16) for j in (0, 2, 4))
            i += 2
        elif args[i] == "--blur":
            blur = float(args[i + 1])
            i += 2
        else:
            i += 1

    subprocess.run(["convert", "-background", "none", ART,
                    "-resize", f"{ART_SIZE}x{ART_SIZE}", TMP], check=True)

    art = Image.open(TMP).convert("RGBA")
    alpha = art.getchannel("A")
    lo, hi = alpha.getextrema()
    if hi and hi < 255:
        alpha = alpha.point(lambda v: min(255, round(v * 255.0 / hi)))
    glow = Image.new("RGBA", art.size, color + (0,))
    glow.putalpha(alpha)
    glow = glow.filter(ImageFilter.GaussianBlur(blur))

    # Тонкая линия после размытия почти гаснет — нормализуем пиковую
    # альфу, чтобы след читался, а яркость потом регулировалась opacity.
    alpha = glow.getchannel("A")
    amax = alpha.getextrema()[1] or 1
    alpha = alpha.point(lambda v: min(255, round(v * 255.0 / amax)))
    glow.putalpha(alpha)

    canvas = Image.new("RGBA", (CANVAS, CANVAS), color + (0,))
    off = (CANVAS - ART_SIZE) // 2
    canvas.alpha_composite(glow, (off, off))
    canvas.save(OUT)
    print("saved", OUT, "blur", blur, "color", color)


if __name__ == "__main__":
    main()
