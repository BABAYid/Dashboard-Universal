#!/usr/bin/env python3
"""Разбор снимков стенда сравнения приборов.

Стенд (Dashboard/Main.qml, временный) — окно 1456 x 2940, четыре пары:

    y=0     OldSpeedometer | Speedometer     проверка (спидометр)
    y=742   OldTachometer  | Tachometer      проверка (тахометр)
    y=1484  Speedometer    | Speedometer     контроль: одинаковые новые
    y=2226  OldSpeedometer | OldSpeedometer  контроль: одинаковые старые

Для каждой пары печатается максимальная разница по каналу, число различающихся
пикселей и рамка различий. Смысл контроля — измерить шум отрисовки: если
одинаковые реализации тоже расходятся на несколько десятков пикселей, то
различия такого же порядка в проверочных парах ничего не доказывают.
"""

import sys

import numpy as np
from PIL import Image

GAUGE = 714
GAP = 28
ROWS = [
    (0, "проверка: спидометр старый/новый"),
    (GAUGE + GAP, "проверка: тахометр  старый/новый"),
    ((GAUGE + GAP) * 2, "контроль: две новые реализации"),
    ((GAUGE + GAP) * 3, "контроль: две старые реализации"),
]


def compare(a, b):
    diff = np.abs(a.astype(np.int16) - b.astype(np.int16)).max(axis=2)
    n = int((diff > 0).sum())
    bbox = None
    if n:
        ys, xs = np.nonzero(diff)
        bbox = (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()))
    return int(diff.max()), n, int((diff > 4).sum()), bbox


def main(path):
    img = np.asarray(Image.open(path).convert("RGB"))
    print(f"{path}: {img.shape[1]}x{img.shape[0]}")
    results = []
    for y0, name in ROWS:
        left = img[y0:y0 + GAUGE, 0:GAUGE]
        right = img[y0:y0 + GAUGE, GAUGE + GAP:GAUGE + GAP + GAUGE]
        maxd, n, n4, bbox = compare(left, right)
        results.append((name, maxd, n, n4))
        print(f"  {name}: max_delta={maxd} px_diff={n} px_diff>4={n4} bbox={bbox}")

    checks = [r for r in results if r[0].startswith("проверка")]
    controls = [r for r in results if r[0].startswith("контроль")]
    worst_check = max(r[2] for r in checks)
    worst_control = max(r[2] for r in controls)
    print(f"  худшая проверочная пара: {worst_check} px, "
          f"худший контроль (шум отрисовки): {worst_control} px")
    ok = worst_check <= worst_control
    print("РЕЗУЛЬТАТ:", "различия в пределах шума отрисовки" if ok
          else "ЕСТЬ РАЗЛИЧИЯ ВЫШЕ ШУМА")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
