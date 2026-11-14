#!/usr/bin/env python3
"""Убирает «примерочные» числа из картинок дизайнера и сохраняет чистые копии.

В комплекте Genesis числа нарисованы прямо в картинках:
    Range.png      — «369км» рядом со значком бензоколонки
    Odometer.png   — «2648км»
    Footer.png     — «8,8» слева и «8,8 l/100km» справа, плюс подписи 0/10/20

В машине эти числа должны быть живыми, поэтому цифры из картинки стираются:
под ними чистый прозрачный фон (проверено — альфа 0), достаточно обнулить альфу
в прямоугольниках. Подписи «км» и «l/100km», значки и шкала остаются.

    python3 tools/genesis_clean_numbers.py

Результат кладётся рядом: `range_clean.png`, `odometer_clean.png`,
`footer_clean.png`. Исходники дизайнера не меняются.
"""

import os
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
IMG = os.path.join(HERE, "..", "Dashboard", "images", "genesis")

# файл → список прямоугольников (x1, y1, x2, y2) в пикселях файла, где стереть
# Имена — как в проекте (Dashboard/images/genesis), они совпадают с комплектом
# дизайнера побайтно (сверено md5).
ERASE = {
    "range.png": [(82, 10, 216, 86)],            # «369» (подпись «км» справа остаётся)
    "odometer.png": [(0, 10, 172, 86)],          # «2648»
    "footer.png": [(1310, 288, 1432, 368),       # «8,8» справа, перед «l/100km»
                   (158, 290, 258, 368),         # «8,8» слева, рядом со снежинкой
                   (6, 296, 70, 364)],           # сама снежинка: её рисуем кодом,
                                                 # чтобы синеть на морозе
}


def main():
    made = []
    for name, boxes in ERASE.items():
        src = os.path.join(IMG, name)
        if not os.path.exists(src):
            print(f"  нет файла {name} — пропуск")
            continue
        im = Image.open(src).convert("RGBA")
        a = np.asarray(im).copy()
        for x1, y1, x2, y2 in boxes:
            a[y1:y2, x1:x2, 3] = 0
        dst = os.path.join(IMG, name.replace(".png", "_clean.png"))
        Image.fromarray(a).save(dst)
        made.append(os.path.basename(dst))

        # контроль: сколько пикселей осталось в стёртых местах
        left = 0
        for x1, y1, x2, y2 in boxes:
            left += int((a[y1:y2, x1:x2, 3] > 40).sum())
        print(f"  {os.path.basename(dst):22s} стёрто прямоугольников {len(boxes)}, "
              f"осталось пикселей в них: {left}")

    print(f"готово, файлов: {len(made)}")


if __name__ == "__main__":
    main()
