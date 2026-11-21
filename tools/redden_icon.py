#!/usr/bin/env python3
"""Красит иконку в один цвет, сохраняя альфу.

Нужно для ламп, которые в комплекте нарисованы «не тем» цветом: например
значок давления масла был янтарным, а должен быть красным (авария).

    python3 tools/redden_icon.py Dashboard/images/oil_press.png "#E8231F"

Прозрачность не трогается — форма значка та же, меняется только цвет.
Исходник восстанавливается из истории git.
"""

import sys
import numpy as np
from PIL import Image


def hex_to_rgb(value):
    v = value.lstrip("#")
    return tuple(int(v[i:i + 2], 16) for i in (0, 2, 4))


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    path, color = sys.argv[1], sys.argv[2]
    r, g, b = hex_to_rgb(color)
    im = Image.open(path).convert("RGBA")
    a = np.asarray(im).copy()
    before = a[a[:, :, 3] > 40][:, :3].mean(axis=0)
    a[:, :, 0], a[:, :, 1], a[:, :, 2] = r, g, b
    Image.fromarray(a).save(path, optimize=True)
    print(f"{path}: было #{int(before[0]):02X}{int(before[1]):02X}{int(before[2]):02X}"
          f" → стало {color.upper()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
