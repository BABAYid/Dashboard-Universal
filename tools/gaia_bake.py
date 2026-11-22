#!/usr/bin/env python3
"""Готовит фон скина Gaia из SVG дизайнера и выгружает PNG.

Зачем: в макете поверх статичной графики нарисованы «живые» элементы —
стрелки приборов, буквы передач, указатели поворотов, иконки ламп. Если
рисовать фон прямо из макета, они застынут: стрелка не поедет, лампа не
погаснет. Поэтому из SVG вырезаются ровно те узлы, которые скин рисует
сам, а остальное (колодцы, шкалы, цифры, карточки, декор углов) остаётся
фоном.

    python3 tools/gaia_bake.py                 # фон 1920×720 + @2x
    python3 tools/gaia_bake.py --svg-only      # только вырезать SVG
    python3 tools/gaia_bake.py --check         # сравнить с макетом

Рендер — Chrome headless (Qt Svg в проекте не подключён).
Зависимости: только стандартная библиотека + numpy/Pillow для --check.
"""

import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GAIA = os.path.join(ROOT, "Gaia")
SVG_IN = os.path.join(GAIA, "Приборная панель · Вариант 2 · 1920 × 722.svg")
OUT_DIR = os.path.join(ROOT, "Dashboard", "images", "gaia")
SVG_OUT = os.path.join(OUT_DIR, "gaia_bg.svg")
PNG_1X = os.path.join(OUT_DIR, "gaia_bg.png")
PNG_2X = os.path.join(OUT_DIR, "gaia_bg@2x.png")

NS = "{http://www.w3.org/2000/svg}"
NUM = re.compile(r"-?\d*\.?\d+(?:[eE][-+]?\d+)?")
TOK = re.compile(r"([MmLlHhVvCcSsQqTtAaZz])|(-?\d*\.?\d+(?:[eE][-+]?\d+)?)")

# Зоны, внутри которых лежат «живые» элементы. Удаляем узел, только если его
# габарит целиком внутри зоны: иначе снесём шкалу, которая лишь касается зоны.
# Указатели поворота вырезаются по отдельности: значок в центре сверху
# (5 полос + «мачта») — статичный, он остаётся в фоне.
ZONE_ARROW_L = (824.0, 42.0, 912.0, 114.0)
ZONE_ARROW_R = (1008.0, 42.0, 1096.0, 114.0)
ZONE_GEAR = (938.0, 128.0, 992.0, 532.0)     # буквы P R N D 2 L
ZONE_LAMPS = (300.0, 552.0, 1640.0, 646.0)   # ряд ламп внизу
NEEDLE_X = (575.0, 591.0)                    # колонна стрелки левого колодца
NEEDLE_X2 = (1329.0, 1345.0)
# Ступицы в основаниях стрелок (два концентрических круга + блик + красная
# точка оси). По просьбе заказчика их в скине нет — остаются только стрелки,
# поэтому из фона они тоже вырезаются: иначе вокруг каждой стрелки светился
# бы круг, который не поворачивается вместе ней.
ZONE_HUB_L = (487.0, 271.0, 680.0, 464.0)
ZONE_HUB_R = (1241.0, 270.0, 1434.0, 462.0)


def mat_mul(a, b):
    a0, a1, a2, a3, a4, a5 = a
    b0, b1, b2, b3, b4, b5 = b
    return (a0 * b0 + a2 * b1, a1 * b0 + a3 * b1,
            a0 * b2 + a2 * b3, a1 * b2 + a3 * b3,
            a0 * b4 + a2 * b5 + a4, a1 * b4 + a3 * b5 + a5)


def parse_transform(text):
    m = (1, 0, 0, 1, 0, 0)
    for name, args in re.findall(r"(matrix|translate|scale|rotate)\(([^)]*)\)", text):
        v = [float(x) for x in NUM.findall(args)]
        if name == "matrix":
            mm = tuple(v)
        elif name == "translate":
            mm = (1, 0, 0, 1, v[0], v[1] if len(v) > 1 else 0)
        elif name == "scale":
            mm = (v[0], 0, 0, (v[1] if len(v) > 1 else v[0]), 0, 0)
        else:
            import math
            a = math.radians(v[0])
            if len(v) >= 3:
                ca, sa = math.cos(a), math.sin(a)
                cx, cy = v[1], v[2]
                mm = (ca, sa, -sa, ca, cx - ca * cx + sa * cy, cy - sa * cx - ca * cy)
            else:
                mm = (math.cos(a), math.sin(a), -math.sin(a), math.cos(a), 0, 0)
        m = mat_mul(m, mm)
    return m


def apply(m, x, y):
    return (m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5])


def path_points(d):
    pts, cx, cy, sx, sy = [], 0.0, 0.0, 0.0, 0.0
    cmd, buf = None, []

    def flush(cmd, buf):
        nonlocal cx, cy, sx, sy
        if not buf:
            return
        if cmd in "MmLl":
            for k in range(0, len(buf) - 1, 2):
                x, y = buf[k], buf[k + 1]
                if cmd.islower():
                    x, y = x + cx, y + cy
                pts.append((x, y))
                cx, cy = x, y
                if k == 0:
                    sx, sy = x, y
        elif cmd in "Hh":
            for v in buf:
                x = v + cx if cmd == "h" else v
                pts.append((x, cy))
                cx = x
        elif cmd in "Vv":
            for v in buf:
                y = v + cy if cmd == "v" else v
                pts.append((cx, y))
                cy = y
        elif cmd in "CcSsQqTt":
            step = 6 if cmd in "Cc" else 4
            for k in range(0, len(buf) - step + 1, step):
                seg = buf[k:k + step]
                for j in range(0, len(seg), 2):
                    x, y = seg[j], seg[j + 1]
                    if cmd.islower():
                        x, y = x + cx, y + cy
                    pts.append((x, y))
                x, y = seg[-2], seg[-1]
                if cmd.islower():
                    x, y = x + cx, y + cy
                cx, cy = x, y
        elif cmd in "Aa":
            for k in range(0, len(buf) - 6, 7):
                x, y = buf[k + 5], buf[k + 6]
                if cmd.islower():
                    x, y = x + cx, y + cy
                pts.append((x, y))
                cx, cy = x, y
        elif cmd in "Zz":
            cx, cy = sx, sy

    for c, n in TOK.findall(d):
        if c:
            if cmd is not None:
                flush(cmd, buf)
            cmd, buf = c, []
        else:
            buf.append(float(n))
    if cmd is not None:
        flush(cmd, buf)
    return pts


def bbox_of(el, m):
    tag = el.tag.replace(NS, "")
    if tag == "path":
        pts = path_points(el.get("d", ""))
        if not pts:
            return None
        xs = [apply(m, x, y)[0] for x, y in pts]
        ys = [apply(m, x, y)[1] for x, y in pts]
        return (min(xs), min(ys), max(xs), max(ys))
    if tag == "rect":
        x, y = float(el.get("x", 0)), float(el.get("y", 0))
        w, h = float(el.get("width", 0)), float(el.get("height", 0))
        p1, p2 = apply(m, x, y), apply(m, x + w, y + h)
        return (min(p1[0], p2[0]), min(p1[1], p2[1]), max(p1[0], p2[0]), max(p1[1], p2[1]))
    if tag in ("circle", "ellipse"):
        cx, cy = float(el.get("cx", 0)), float(el.get("cy", 0))
        rx = float(el.get("rx", el.get("r", 0)))
        ry = float(el.get("ry", el.get("r", 0)))
        p1, p2 = apply(m, cx - rx, cy - ry), apply(m, cx + rx, cy + ry)
        return (p1[0], p1[1], p2[0], p2[1])
    if tag == "line":
        p1 = apply(m, float(el.get("x1", 0)), float(el.get("y1", 0)))
        p2 = apply(m, float(el.get("x2", 0)), float(el.get("y2", 0)))
        return (min(p1[0], p2[0]), min(p1[1], p2[1]), max(p1[0], p2[0]), max(p1[1], p2[1]))
    return None


HIDE = ("defs", "clipPath", "filter", "linearGradient", "radialGradient",
        "pattern", "mask", "symbol", "style")


def union(a, b):
    if a is None:
        return b
    if b is None:
        return a
    return (min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3]))


def bbox_tree(el, m):
    t = el.get("transform")
    if t:
        m = mat_mul(m, parse_transform(t))
    tag = el.tag.replace(NS, "")
    if tag in HIDE:
        return None, m
    bb = bbox_of(el, m)
    for ch in list(el):
        cb, _ = bbox_tree(ch, m)
        bb = union(bb, cb)
    return bb, m


def inside(bb, zone, eps=0.5):
    x0, y0, x1, y1 = zone
    return (bb[0] >= x0 - eps and bb[1] >= y0 - eps
            and bb[2] <= x1 + eps and bb[3] <= y1 + eps)


def main():
    what = sys.argv[1] if len(sys.argv) > 1 else "all"
    os.makedirs(OUT_DIR, exist_ok=True)

    tree = ET.parse(SVG_IN)
    root = tree.getroot()
    # содержимое лежит в группе с clip0
    host = root
    for ch in root:
        if "clip0" in (ch.get("clip-path") or ""):
            host = ch
            break

    removed = []
    keep = []
    for ch in list(host):
        bb, _ = bbox_tree(ch, (1, 0, 0, 1, 0, 0))
        if bb is None:
            continue
        tag = ch.tag.replace(NS, "")
        w, h = bb[2] - bb[0], bb[3] - bb[1]
        who = None
        if tag == "rect" and 280 <= h <= 320 and w <= 16:
            who = "стрелка прибора"
        elif tag == "rect" and 6.0 <= w <= 9.0 and 6.0 <= h <= 9.0 and (
                NEEDLE_X[0] - 6 <= bb[0] <= NEEDLE_X[1] + 6
                or NEEDLE_X2[0] - 6 <= bb[0] <= NEEDLE_X2[1] + 6):
            who = "наконечник стрелки"
        elif inside(bb, ZONE_ARROW_L) or inside(bb, ZONE_ARROW_R):
            who = "указатель поворота"
        elif inside(bb, ZONE_HUB_L) or inside(bb, ZONE_HUB_R):
            who = "ступица у основания стрелки"
        elif inside(bb, ZONE_GEAR):
            who = "буква передачи"
        elif inside(bb, ZONE_LAMPS):
            who = "иконка лампы"
        if who:
            removed.append((who, tag, bb))
            host.remove(ch)
        else:
            keep.append((tag, bb))

    print(f"оставлено узлов: {len(keep)}, вырезано: {len(removed)}")
    from collections import Counter
    for who, n in Counter(r[0] for r in removed).most_common():
        print(f"  - {who}: {n}")

    if what in ("all", "svg-only", "--svg-only"):
        tree.write(SVG_OUT, encoding="unicode")
        print("SVG фона:", os.path.relpath(SVG_OUT, ROOT))

    if what == "--check" or what == "all":
        render()


def render():
    chrome = os.path.join(os.sep, "usr", "bin", "google-chrome")
    prof = os.path.join(ROOT, ".dsh-ocr", "gaia", "chrome", "prof")
    for scale, out in ((1, PNG_1X), (2, PNG_2X)):
        cmd = [chrome, "--headless=new", "--disable-gpu", "--no-sandbox",
               "--hide-scrollbars", "--force-device-scale-factor=%d" % scale,
               "--user-data-dir=" + prof, "--window-size=1920,720",
               "--screenshot=" + out, "file://" + SVG_OUT]
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
        ok = os.path.exists(out)
        print(f"рендер @{scale}x: {'ok' if ok else 'FAIL'} -> {os.path.relpath(out, ROOT)}")
        if not ok and r.stderr:
            print(r.stderr[-500:])


def check():
    import numpy as np
    from PIL import Image
    a = np.asarray(Image.open(PNG_1X).convert("L")).astype(float)
    b = np.asarray(Image.open(os.path.join(GAIA, "Приборная панель · Вариант 2 · 1920 × 722.png")).convert("L")).astype(float)
    if a.shape != b.shape:
        print("размеры разные:", a.shape, b.shape)
        return
    d = np.abs(a - b)
    print(f"средняя разница {d.mean():.2f}, доля px > 20: {(d > 20).mean() * 100:.2f}%")
    ys, xs = np.nonzero(d > 20)
    if len(xs):
        print(f"отличия в bbox x {xs.min()}..{xs.max()} y {ys.min()}..{ys.max()}")


if __name__ == "__main__":
    if sys.argv[1:2] == ["--check"]:
        check()
    else:
        main()
