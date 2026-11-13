#!/usr/bin/env python3
"""Снимает числа с макета дизайнера и с картинок скина Genesis.

Зачем: размеры приборов нельзя подбирать «на глаз» — из-за этого диски
однажды вылезли за верх экрана. Этот скрипт достаёт геометрию из SVG
дизайнера (габариты групп, центры окружностей, положение стрелок) и меряет
картинки скина (где кончается диск, на каком радиусе кольцо шкалы),
чтобы масштаб в GenesisSkin.qml считался, а не угадывался.

    python3 tools/genesis_geom.py            # всё: макет + картинки
    python3 tools/genesis_geom.py svg        # только разбор макета
    python3 tools/genesis_geom.py png        # только замеры картинок

Макет: Genesis/Genesis · цифровая приборная панель · 1920×720.svg
Картинки: Dashboard/images/genesis/dial_speed.png, needle.png

Зависимости: только стандартная библиотека (для замеров картинок — numpy и
Pillow, они уже нужны другим скриптом в tools/).
"""

import os
import re
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SVG = os.path.join(ROOT, "Genesis", "Genesis · цифровая приборная панель · 1920×720.svg")
IMG = os.path.join(ROOT, "Dashboard", "images", "genesis")

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


def walk(el, m, leaves):
    t = el.get("transform")
    if t:
        m = mat_mul(m, parse_transform(t))
    tag = el.tag.replace(NS, "")
    if tag in HIDE:
        return None
    bb = bbox_of(el, m)
    if bb is not None:
        leaves.append({"tag": tag, "bbox": bb, "fill": el.get("fill"),
                       "stroke": el.get("stroke")})
    for child in list(el):
        bb = union(bb, walk(child, m, leaves))
    return bb


def report_svg():
    tree = ET.parse(SVG)
    root = tree.getroot()
    clip = [ch for ch in root if "clip0_40_1840" in (ch.get("clip-path") or "")]
    target = clip[0] if clip else root
    rows = []
    for idx, ch in enumerate(list(target)):
        leaves = []
        bb = walk(ch, (1, 0, 0, 1, 0, 0), leaves)
        if bb is None:
            continue
        fills = sorted({(l["fill"] or "-")[:20] for l in leaves})
        rows.append((idx, ch.tag.replace(NS, ""), ch.get("filter") or "", bb,
                     len(leaves), fills))
    print(f"=== макет: {os.path.basename(SVG)} — {len(rows)} групп с содержимым")
    print("    группы отсортированы сверху вниз, слева направо\n")
    rows.sort(key=lambda r: (round(r[3][1] / 40), r[3][0]))
    for idx, tag, filt, bb, n, fills in rows:
        print(f"[{idx:3d}] {tag:6s} {filt[5:24]:20s} "
              f"({bb[0]:7.1f},{bb[1]:7.1f})-({bb[2]:7.1f},{bb[3]:7.1f}) "
              f"{bb[2]-bb[0]:6.1f}x{bb[3]-bb[1]:6.1f} n={n:3d} {' '.join(fills)[:40]}")

    print("\n--- что важно для скина ---")
    for idx, tag, filt, bb, n, fills in rows:
        if tag == "circle":
            print(f"    окружность (свечение диска): центр "
                  f"({(bb[0]+bb[2])/2:.1f}, {(bb[1]+bb[3])/2:.1f}), "
                  f"радиус {(bb[2]-bb[0])/2:.1f}")
    for idx, tag, filt, bb, n, fills in rows:
        if tag == "image":
            print(f"    картинка: ({bb[0]:.1f},{bb[1]:.1f}) "
                  f"{bb[2]-bb[0]:.1f}x{bb[3]-bb[1]:.1f} — центр "
                  f"({(bb[0]+bb[2])/2:.1f}, {(bb[1]+bb[3])/2:.1f})")


# ---------------------------------------------------------------- PNG ------
def ring_radius(path, cx, cy, rmax=1200, thr=0.35):
    """Радиус яркого кольца: ищем пик медианной яркости по окружностям."""
    import numpy as np
    from PIL import Image
    a = np.asarray(Image.open(path).convert("L")).astype(float)
    h, w = a.shape
    best = (0, -1.0)
    for r in range(4, min(rmax, min(h, w) // 2)):
        vals = []
        for ang in range(0, 360, 3):
            x = int(cx + r * np.cos(np.radians(ang)))
            y = int(cy + r * np.sin(np.radians(ang)))
            if 0 <= x < w and 0 <= y < h:
                vals.append(a[y, x])
        if not vals:
            continue
        med = float(np.median(vals))
        if med > best[1]:
            best = (r, med)
    return best


def content_bbox(path, thr=8):
    import numpy as np
    from PIL import Image
    im = Image.open(path).convert("RGBA")
    a = np.asarray(im).astype(int)
    mask = (a[:, :, 3] > thr) & (a[:, :, :3].max(axis=2) > thr)
    if not mask.any():
        return None
    ys, xs = np.nonzero(mask)
    return (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()))


def report_png():
    for name in ("dial_speed.png", "dial_tach.png"):
        path = os.path.join(IMG, name)
        if not os.path.exists(path):
            continue
        bb = content_bbox(path)
        import numpy as np
        from PIL import Image
        w, h = Image.open(path).size
        cx, cy = w // 2, h // 2
        r, med = ring_radius(path, cx, cy)
        print(f"{name}: холст {w}x{h}, контент bbox={bb} "
              f"(радиус {(bb[2]-bb[0])//2} от центра — это свечение)")
        print(f"    кольцо шкалы: радиус {r} (медианная яркость {med:.0f})")
        print(f"    масштаб под макет (кольцо 326): {w} × 326 / {r} = {w*326/r:.0f} px")
    path = os.path.join(IMG, "needle.png")
    if os.path.exists(path):
        bb = content_bbox(path, 12)
        import numpy as np
        from PIL import Image
        w, h = Image.open(path).size
        im = Image.open(path).convert("RGBA")
        a = np.asarray(im).astype(int)
        mask = a[:, :, 3] > 12
        ys, xs = np.nonzero(mask)
        widths = {}
        for y in set(ys[::20]):
            row = xs[ys == y]
            widths[y] = int(row.max() - row.min() + 1) if row.size else 0
        print(f"needle.png: холст {w}x{h}, контент bbox={bb}")
        print(f"    ось вращения — центр холста ({w//2}, {h//2}); "
              f"остриё — верх холста, значит холст на экране = 2 × длину стрелки")
        print("    ширина по строкам (y: ширина):",
              ", ".join(f"{y}:{v}" for y, v in sorted(widths.items())[:10]))


if __name__ == "__main__":
    what = sys.argv[1] if len(sys.argv) > 1 else "all"
    if what in ("all", "svg"):
        report_svg()
    if what in ("all", "png"):
        print()
        report_png()
