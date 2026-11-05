#!/usr/bin/env python3
"""Статистика по базе камер (Smart Driver) — что вообще есть в выгрузке.

Нужна для дизайна предупреждений: какие типы объектов бывают, какие в них
ограничения скорости, на каком расстоянии их предупреждать и какие модели
комплексов встречаются.

Понимает обе выгрузки OpenSpeedcam:
  • PocketGIS: IDX,X,Y,TYPE,SPEED,DIRTYPE,DIRECTION,DISTANCE,ANGLE // id|тип|модель
  • iGO:       X,Y,TYPE,SPEED[,DIRTYPE,DIRECTION]

Запуск:
    python3 tools/speedcam_stats.py PocketGis.txt
    python3 tools/speedcam_stats.py Dashboard/assets/speedcam/speedcam.txt --top 10

Печатает markdown в stdout — удобно перенаправить в docs/speedcam_stats.md.
"""

from __future__ import annotations

import argparse
import collections
import sys

# Названия типов из выгрузки OpenSpeedcam (на случай, если в файле нет
# комментария с названием — компактный iGO-формат его не содержит).
TYPE_NAMES = {
    1: "Статическая камера",
    3: "Контроль проезда на красный",
    5: "Мобильная засада",
    11: "Контроль движения по полосе",
    20: "Стационарный пост ДПС",
    21: "Железнодорожный переезд",
    22: "Пешеходный переход",
    100: "Начало населённого пункта",
    101: "Ограничение скорости",
    102: "Искусственная неровность",
    103: "Плохая дорога",
    104: "Опасный поворот",
    105: "Опасный перекрёсток",
    106: "Другая опасность",
    107: "Обгон запрещён",
}

# Типы, которые контролируют скорость (остальные — предупреждения об опасности).
CAMERA_TYPES = {1, 3, 5, 11, 20}


def parse_line(raw: bytes):
    """Возвращает (type, speed, dirtype, distance, type_name, model) или None."""
    line = raw.strip()
    if not line or line.startswith(b"IDX") or line.startswith(b"#"):
        return None
    body, _, comment = line.partition(b"//")
    fields = [f.strip() for f in body.strip().replace(b";", b",").split(b",")]
    if len(fields) < 4:
        return None

    name = model = None
    if comment:
        parts = [p.strip().decode("cp1251", "replace") for p in comment.split(b"|")]
        if len(parts) >= 2 and parts[1]:
            name = parts[1]
        if len(parts) >= 3 and parts[2]:
            model = parts[2]

    try:
        if len(fields) >= 6 and fields[0].lstrip(b"+-").isdigit() and b"." in fields[1]:
            # PocketGIS: ID, X(долгота), Y(широта), TYPE, SPEED, ...
            type_code = int(fields[3])
            speed = int(fields[4])
            dirtype = int(fields[5]) if fields[5] else 0
            distance = int(fields[7]) if len(fields) > 7 and fields[7] else 0
        else:
            # iGO: X(долгота), Y(широта), TYPE, SPEED, ...
            type_code = int(fields[2]) if fields[2] else 1
            speed = int(fields[3])
            dirtype = int(fields[4]) if len(fields) > 4 and fields[4] else 0
            distance = 0
    except ValueError:
        return None
    return type_code, speed, dirtype, distance, name, model


def collect(path: str):
    counts = collections.Counter()
    names: dict[int, str] = {}
    speeds = collections.defaultdict(collections.Counter)
    dists = collections.defaultdict(collections.Counter)
    dirtypes = collections.Counter()
    models = collections.Counter()
    all_speeds = collections.Counter()

    with open(path, "rb") as handle:
        for raw in handle:
            parsed = parse_line(raw)
            if parsed is None:
                continue
            type_code, speed, dirtype, distance, name, model = parsed
            counts[type_code] += 1
            all_speeds[speed] += 1
            speeds[type_code][speed] += 1
            dists[type_code][distance] += 1
            dirtypes[dirtype] += 1
            if name and type_code not in names:
                names[type_code] = name
            if model:
                models[model] += 1
    return counts, names, speeds, dists, dirtypes, models, all_speeds


def fmt(number: int) -> str:
    """Число с пробелами между разрядами: 207 701."""
    return f"{number:,}".replace(",", " ")


def human_share(part: int, total: int) -> str:
    return f"{100.0 * part / total:.1f}%" if total else "—"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", nargs="?", default="PocketGis.txt",
                        help="файл базы (PocketGis.txt или speedcam.txt)")
    parser.add_argument("--top", type=int, default=6,
                        help="сколько значений скорости/дистанции показывать на тип")
    args = parser.parse_args()

    try:
        counts, names, speeds, dists, dirtypes, models, all_speeds = collect(args.path)
    except OSError as error:
        print(f"Не удалось прочитать {args.path}: {error}", file=sys.stderr)
        return 1

    total = sum(counts.values())
    if total == 0:
        print(f"В файле {args.path} не нашлось ни одной точки базы.", file=sys.stderr)
        return 1

    cameras = sum(count for code, count in counts.items() if code in CAMERA_TYPES)
    dangers = total - cameras

    print(f"# Что есть в базе камер ({args.path})\n")
    print(f"Всего точек: **{fmt(total)}**\n")
    print(f"- камеры (контроль скорости, красный свет, полоса, ДПС, засада): "
          f"**{fmt(cameras)}** ({human_share(cameras, total)})")
    print(f"- предупреждения об опасностях (переходы, неровности, повороты…): "
          f"**{fmt(dangers)}** ({human_share(dangers, total)})\n")

    print("## Типы объектов\n")
    print("| TYPE | Что это | Точек | Доля | Ограничения (сколько точек) | Предупреждать за |")
    print("|-----:|---------|------:|-----:|------------------------------|------------------|")
    for code, count in counts.most_common():
        name = names.get(code) or TYPE_NAMES.get(code, f"Тип {code}")
        speed_list = ", ".join(f"{value} км/ч ×{fmt(number)}" for value, number
                               in speeds[code].most_common(args.top))
        dist_list = ", ".join(f"{value} м ×{fmt(number)}" for value, number
                              in dists[code].most_common(3))
        print(f"| {code} | {name} | {fmt(count)} | {human_share(count, total)} | {speed_list} | {dist_list} |")

    print("\n## Ограничения скорости по всей базе\n")
    print("| Ограничение | Точек | Доля |")
    print("|------------:|------:|-----:|")
    for speed, count in sorted(all_speeds.items()):
        mark = "" if speed else " *(нет ограничения)*"
        print(f"| {speed} км/ч{mark} | {fmt(count)} | {human_share(count, total)} |")

    print("\n## Направленность (DIRTYPE)\n")
    print("| DIRTYPE | Смысл | Точек |")
    print("|--------:|-------|------:|")
    labels = {0: "без направления", 1: "направленная (в одну сторону)", 2: "прочее/оба направления"}
    for dirtype, count in sorted(dirtypes.items()):
        print(f"| {dirtype} | {labels.get(dirtype, '—')} | {fmt(count)} |")

    if models:
        print("\n## Модели комплексов (топ-15)\n")
        print("| Модель | Точек |")
        print("|--------|------:|")
        for model, count in models.most_common(15):
            print(f"| {model or '—'} | {fmt(count)} |")

    print("\n---\n")
    print("Сводка получена скриптом `tools/speedcam_stats.py`;")
    print("формат базы и коды типов — в `docs/speedcam.md`.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
