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
    """Пути-цифры на шкалах в порядке документа.

    В макете цифры залиты #DFE2DD, и идут они ровно в порядке шкалы:
    сначала 0, 20, … 180 левого колодца, потом 0…8 правого. Порядок
    документа — самый надёжный способ не перепутать значения с углами.
    """
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
    left = [b for b in boxes if (b[0] + b[2]) / 2 < 960]
    right = [b for b in boxes if (b[0] + b[2]) / 2 >= 960]
    for name, d, group in (("speed", DIALS["speed"], left), ("rpm", DIALS["rpm"], right)):
        cx, py = d["cx"], d["pivotY"]
        if len(group) != len(d["values"]):
            print(f"  !! {name}: цифр {len(group)}, ожидалось {len(d['values'])}")
            continue
        angles = []
        for bb in group:
            mx, my = (bb[0] + bb[2]) / 2, (bb[1] + bb[3]) / 2
            angles.append(math.degrees(math.atan2(my - py, mx - cx)) % 360)
        print(f"=== {name}: значения {d['values']}")
        print(f"    углы от оси: {[round(a, 1) for a in angles]}")
        # Спрайт стрелки нарисован «вверх» (270° по экранной поляре), поэтому
        # поворот QML = угол - 270. Приводим к диапазону (-180, 180].
        rot = []
        for a in angles:
            r = (a - 270) % 360
            if r > 180:
                r -= 360
            rot.append(round(r, 1))
        print(f"    {name}Angles: {rot}")
        print()


if __name__ == "__main__":
    main()
