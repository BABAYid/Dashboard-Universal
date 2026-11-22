#!/usr/bin/env python3
"""Снимает с макета Gaia углы, куда должна смотреть стрелка на каждом делении.

Зачем: шкалы нарисованы на эллипсе, а стрелка ходит по кругу вокруг оси,
которая смещена от центра эллипса вниз (583.4, 367.2 вместо 584.7, 295.0).
Поэтому равномерный поворот «0…270°» не совпадает с цифрами: у нуля
ошибка ~8°, у максимума ~18°. Правильно — привязать поворот стрелки к
углам, под которыми нарисованы сами цифры, и интерполировать между ними.

Скрипт печатает готовые таблицы (значение → угол поворота QML), которые
вставлены в GaiaSkin.qml как speedAngles / rpmAngles.

    python3 tools/gaia_scale.py

Зависимости: только стандартная библиотека.
"""

import math
import os
import re
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gaia_bake as GB  # noqa: E402  (парсер геометрии переиспользуем)

SVG = GB.SVG_IN

# Оси приборов (из макета) и параметры шкал.
DIALS = {
    "speed": dict(cx=583.4, pivotY=367.2, xlo=280, xhi=910, values=[0, 20, 40, 60, 80, 100, 120, 140, 160, 180]),
    "rpm": dict(cx=1337.8, pivotY=365.9, xlo=1020, xhi=1660, values=[0, 1, 2, 3, 4, 5, 6, 7, 8]),
}


def label_paths():
    """Пути-цифры на шкалах: в макете они залиты #DFE2DD."""
    root = ET.parse(SVG).getroot()
    host = root
    for ch in root:
        if "clip0" in (ch.get("clip-path") or ""):
            host = ch
            break
    out = []
    for ch in list(host):
        if ch.tag.replace(GB.NS, "") != "path":
            continue
        if (ch.get("fill") or "") != "#DFE2DD":
            continue
        bb, _ = GB.bbox_tree(ch, (1, 0, 0, 1, 0, 0))
        if bb:
            out.append(bb)
    return out


def main():
    boxes = label_paths()
    for name, d in DIALS.items():
        cx, py = d["cx"], d["pivotY"]
        rows = []
        for bb in boxes:
            mx, my = (bb[0] + bb[2]) / 2, (bb[1] + bb[3]) / 2
            if not (d["xlo"] <= mx <= d["xhi"]):
                continue
            if bb[1] < 40 or bb[3] > 560:
                continue
            ang = math.degrees(math.atan2(my - py, mx - cx)) % 360
            rows.append((ang, mx, my, bb[2] - bb[0], bb[3] - bb[1]))
        rows.sort()
        print(f"=== {name}: найдено {len(rows)} цифр (угол от оси, центр)")
        for ang, mx, my, w, h in rows:
            print(f"  {ang:7.2f}°  центр ({mx:6.1f},{my:6.1f})  {w:.0f}x{h:.0f}")
        if len(rows) != len(d["values"]):
            print(f"  !! ожидалось {len(d['values'])} цифр — проверьте вручную")
            continue
        # Порядок цифр по углу совпадает с порядком значений по шкале.
        vals = d["values"]
        # нормируем: углы могут перейти через 0 — разворачиваем монотонно от первой
        base = rows[0][0]
        angles = [base]
        for ang, *_ in rows[1:]:
            a = ang
            while a < angles[-1] - 1:
                a += 360
            angles.append(a)
        print(f"  углы: {[round(a, 1) for a in angles]}")
        # QML: поворот спрайта (стрелка нарисована вверх = 270°) = угол - 270
        rot = [round((a - 270) % 360, 1) for a in angles]
        rot = [round(x - 360 if x > 180 else x, 1) for x in rot]
        print(f"  {name}Angles: {rot}")
        print()


if __name__ == "__main__":
    main()
