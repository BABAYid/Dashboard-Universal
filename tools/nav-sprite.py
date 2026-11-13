#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
#  Спрайт POI-иконок для MapLibre (формат maptiler sprite.json/sprite.png).
#
#  MapLibre не умеет рисовать иконки без спрайта: icon-image в стиле должен
#  ссылаться на картинку из атласа. Шрифты из системы (DejaVu) покрывают
#  часть символов (☕ ⚕ ₽ ★ ✉), остальные пиктограммы рисуются фигурами.
#
#  Запуск:
#      python3 tools/nav-sprite.py Dashboard/map
#
#  Делает 4 файла: sprite.json/png (1x, иконки 32px) и
#  sprite@2x.json/png (2x, иконки 64px) — MapLibre выберет нужный.
# ============================================================================
import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
S = 64              # 2x иконка
GRID = 6            # колонок в атласе
ICON = S            # размер ячейки

# Цвета из палитры приборки (дороги/мажоры повторяют стиль).
ICONS = {
    "food":      ("#FF9F43", "glyph", "\u2615"),   # ☕
    "fuel":      ("#4FC3F7", "pump",  None),
    "shop":      ("#CE93D8", "bag",   None),
    "medical":   ("#EF5350", "glyph", "\u2695"),   # ⚕
    "transport": ("#4DD0E1", "bus",   None),
    "parking":   ("#81C784", "text",  "P"),
    "bank":      ("#90A4AE", "glyph", "\u20BD"),   # ₽
    "lodging":   ("#7986CB", "bed",   None),
    "attraction": ("#FFD54F", "glyph", "\u2605"),  # ★
    "toilets":   ("#B0BEC5", "text",  "WC"),
    "post":      ("#8D6E63", "glyph", "\u2709"),   # ✉
    "other":     ("#607D8B", "dot",   None),
}


def font(size):
    return ImageFont.truetype(FONT, size)


def badge(size):
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    m = size // 2 - 1
    d.ellipse((1, 1, size - 2, size - 2), fill=(0, 0, 0, 0))
    return im, d, m


def draw_icon(name, size=S):
    color, kind, ch = ICONS[name]
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    m = size // 2 - 1
    d.ellipse((1, 1, size - 2, size - 2), fill=color, outline="#0B141C")

    cx, cy = size // 2, size // 2
    if kind == "glyph":
        f = font(int(size * 0.42))
        bbox = d.textbbox((0, 0), ch, font=f)
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        d.text((cx - tw / 2 - bbox[0], cy - th / 2 - bbox[1]), ch, font=f, fill="white")
    elif kind == "text":
        f = font(int(size * (0.36 if len(ch) > 1 else 0.46)))
        bbox = d.textbbox((0, 0), ch, font=f)
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        d.text((cx - tw / 2 - bbox[0], cy - th / 2 - bbox[1]), ch, font=f, fill="white")
    elif kind == "pump":
        # бензоколонка: корпус, пистолет-шланг
        d.rectangle((cx - 9, cy - 11, cx + 9, cy + 12), fill="white")
        d.rectangle((cx - 5, cy - 7, cx + 3, cy - 1), fill=color)     # окошко
        d.rectangle((cx + 10, cy - 6, cx + 13, cy + 12), fill="white")  # шланг
        d.ellipse((cx + 8, cy - 9, cx + 15, cy - 3), fill="white")      # сопло
    elif kind == "bag":
        # сумка покупок: прямоугольник + ручка
        d.rounded_rectangle((cx - 11, cy - 6, cx + 11, cy + 12), radius=3, fill="white")
        d.arc((cx - 6, cy - 14, cx + 6, cy - 2), 180, 360, fill="white", width=3)
    elif kind == "bus":
        # автобус: корпус + два колеса
        d.rounded_rectangle((cx - 13, cy - 10, cx + 13, cy + 6), radius=4, fill="white")
        d.rectangle((cx - 13, cy + 6, cx + 13, cy + 10), fill="white")
        d.ellipse((cx - 8, cy + 4, cx - 2, cy + 10), fill=color)
        d.ellipse((cx + 2, cy + 4, cx + 8, cy + 10), fill=color)
    elif kind == "bed":
        # кровать: матрас + подушка
        d.rectangle((cx - 12, cy - 2, cx + 12, cy + 6), fill="white")
        d.rectangle((cx - 12, cy - 8, cx + 12, cy - 2), fill="white")
        d.rectangle((cx - 10, cy - 7, cx - 5, cy - 3), fill=color)
    elif kind == "dot":
        d.ellipse((cx - 5, cy - 5, cx + 5, cy + 5), fill="white")
    return im


def build(out_dir):
    names = list(ICONS)
    cols = GRID
    rows = math.ceil(len(names) / cols)

    atlas = Image.new("RGBA", (cols * ICON, rows * ICON), (0, 0, 0, 0))
    meta = {}
    for i, name in enumerate(names):
        x, y = (i % cols) * ICON, (i // cols) * ICON
        atlas.paste(draw_icon(name), (x, y))
        meta[name] = {"x": x, "y": y, "width": ICON, "height": ICON, "pixelRatio": 2}

    os.makedirs(out_dir, exist_ok=True)
    atlas.save(os.path.join(out_dir, "sprite@2x.png"))
    with open(os.path.join(out_dir, "sprite@2x.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f)

    half = atlas.resize((atlas.width // 2, atlas.height // 2), Image.LANCZOS)
    half.save(os.path.join(out_dir, "sprite.png"))
    meta1 = {}
    for name, v in meta.items():
        meta1[name] = {"x": v["x"] // 2, "y": v["y"] // 2,
                       "width": ICON // 2, "height": ICON // 2, "pixelRatio": 1}
    with open(os.path.join(out_dir, "sprite.json"), "w", encoding="utf-8") as f:
        json.dump(meta1, f)
    print(f"спрайт: {len(names)} иконок → {out_dir}/sprite.json, sprite.png, "
          f"sprite@2x.json, sprite@2x.png")


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "Dashboard/map"
    build(out)
