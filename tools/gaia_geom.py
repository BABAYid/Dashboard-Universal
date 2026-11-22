#!/usr/bin/env python3
"""Снимает геометрию с макета Gaia (третий скин, «простой, как оригинал»).

Макет: Gaia/Приборная панель · Вариант 2 · 1920 × 722.svg
Дизайн — чистая векторная графика: текста в SVG нет вовсе, поэтому все
числа (скорость, обороты, передачи) рисует QML поверх фона. Скрипт нужен,
чтобы колодцы, центры шкал и просвет под центральную зону брались из
макета, а не подбирались на глаз.

    python3 tools/gaia_geom.py            # всё
    python3 tools/gaia_geom.py svg        # только разбор макета
    python3 tools/gaia_geom.py colors     # палитра макета по площади

Зависимости: только стандартная библиотека.
"""

import os
import re
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SVG = os.path.join(ROOT, "Gaia", "Приборная панель · Вариант 2 · 1920 × 722.svg")

NS = "{http://www.w3.org/2000/svg}"
NUM = re.compile(r"-?\d*\.?\d+(?:[eE][-+]?\d+)?")
TOK = re.compile(r"([MmLlHhVvCcSsQqTtAaZz])|(-?\d*\.?\d+(?:[eE][-+]?\d+)?)")


# ---------------------------------------------------------------- SVG ------
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
            mm = (math.cos(a), math.sin(a), -math.sin(a), math.cos(a), 0, 0)
        m = mat_mul(m, mm)
    return m


def apply(m, x, y):
    return (m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5])


def path_points(d):
    """Точки пути: для габарита достаточно опорных точек кривых."""
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
    if tag in ("rect", "image"):
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
    return None


HIDE = ("defs", "clipPath", "filter", "linearGradient", "radialGradient",
        "pattern", "mask", "symbol", "style")


def union(a, b):
    if a is None:
        return b
    if b is None:
        return a
    return (min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3]))


def walk(el, m, leaves, depth=0, cap=20000):
    t = el.get("transform")
    if t:
        m = mat_mul(m, parse_transform(t))
    tag = el.tag.replace(NS, "")
    if tag in HIDE:
        return None
    bb = bbox_of(el, m)
    if bb is not None:
        leaves.append({"tag": tag, "bbox": bb, "fill": el.get("fill"),
                       "stroke": el.get("stroke"), "depth": depth})
    for child in list(el):
        bb = union(bb, walk(child, m, leaves, depth + 1, cap))
    return bb


def content_groups():
    """Корневая группа с clip0_* — в Gaia фон и весь макет лежат внутри неё."""
    root = ET.parse(SVG).getroot()
    for ch in root:
        if "clip0" in (ch.get("clip-path") or ""):
            return ch
    return root


def report_svg():
    root = content_groups()
    rows = []
    for idx, ch in enumerate(list(root)):
        leaves = []
        bb = walk(ch, (1, 0, 0, 1, 0, 0), leaves)
        if bb is None:
            continue
        fills = sorted({(l["fill"] or "-")[:24] for l in leaves})
        rows.append((idx, ch.tag.replace(NS, ""), bb, len(leaves), fills))

    print(f"=== макет: {os.path.basename(SVG)} — {len(rows)} групп")
    print("    (сверху вниз, слева направо)\n")
    rows.sort(key=lambda r: (round(r[2][1] / 40), r[2][0]))
    for idx, tag, bb, n, fills in rows:
        print(f"[{idx:3d}] {tag:6s} ({bb[0]:7.1f},{bb[1]:7.1f})-({bb[2]:7.1f},{bb[3]:7.1f}) "
              f"{bb[2]-bb[0]:6.1f}x{bb[3]-bb[1]:6.1f} n={n:3d} "
              f"{' '.join(f[:18] for f in fills)[:46]}")

    print("\n--- окружности и кольца (центры шкал) ---")
    for ch in list(root):
        leaves = []
        walk(ch, (1, 0, 0, 1, 0, 0), leaves)
        for l in leaves:
            if l["tag"] in ("circle", "ellipse"):
                b = l["bbox"]
                print(f"    {l['tag']}: центр ({(b[0]+b[2])/2:7.1f}, {(b[1]+b[3])/2:6.1f}) "
                      f"r=({(b[2]-b[0])/2:.1f},{ (b[3]-b[1])/2:.1f}) "
                      f"fill={l['fill']}")

    print("\n--- промеры для раскладки ---")
    allbb = None
    for ch in list(root):
        leaves = []
        bb = walk(ch, (1, 0, 0, 1, 0, 0), leaves)
        allbb = union(allbb, bb)
    if allbb:
        print(f"    весь макет: ({allbb[0]:.0f},{allbb[1]:.0f})-({allbb[2]:.0f},{allbb[3]:.0f})")


def report_colors():
    root = content_groups()
    acc = {}
    for ch in list(root):
        leaves = []
        walk(ch, (1, 0, 0, 1, 0, 0), leaves)
        for l in leaves:
            b = l["bbox"]
            area = max(0.0, (b[2] - b[0])) * max(0.0, (b[3] - b[1]))
            for key in (l["fill"], l["stroke"]):
                if not key or key.startswith("url("):
                    continue
                acc.setdefault(key, [0, 0.0])
                acc[key][0] += 1
                acc[key][1] += area
    print("=== палитра (по площади) ===")
    for k, (n, a) in sorted(acc.items(), key=lambda kv: -kv[1][1])[:24]:
        print(f"    {k:16s} элементов={n:4d} площадь≈{a/1000:10.1f}k px²")


if __name__ == "__main__":
    what = sys.argv[1] if len(sys.argv) > 1 else "all"
    if what in ("all", "svg"):
        report_svg()
    if what in ("all", "colors"):
        print()
        report_colors()
