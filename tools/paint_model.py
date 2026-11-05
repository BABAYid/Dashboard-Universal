#!/usr/bin/env python3
"""Раскраска модели машины: меняет базовые цвета материалов в GLB.

Модель дизайнера (`Dashboard/assets/ipsum_fin.glb`) собрана из девяти
материалов. Кузов — материал `base white`: он один, отдельного «крыши» нет,
поэтому покраска делается по материалам, а не по геометрии.

Материалы в файле (индекс — порядок в glTF):
    0 black glossy  — чёрный глянец (молдинги, окантовки)
    1 base white    — КУЗОВ (краска)
    2 inside black  — салон
    3 red           — задние фонари
    4 black glass   — стёкла
    5 orange        — поворотники
    6 orange glass  — стекло фар
    7 metallic      — хром/металл
    8 wheel         — шины

Примеры:
    # покрасить кузов и посмотреть, что получилось
    python3 tools/paint_model.py --body "#1E2A44" --out /tmp/ipsum_blue.glb

    # покрасить кузов и диски, положить на место оригинала
    python3 tools/paint_model.py --body "#1E2A44" --wheel "#2A2E33" \\
        --out Dashboard/assets/ipsum_fin.glb

    # только узнать, какие материалы есть и их цвета
    python3 tools/paint_model.py --list
"""

from __future__ import annotations

import argparse
import json
import struct
import sys

GLB_MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942

# Имя материала в файле → понятное описание (для --list и подсказок).
MATERIAL_HINTS = {
    "base white": "кузов (краска)",
    "black glossy": "чёрный глянец (молдинги)",
    "inside black": "салон",
    "red": "задние фонари",
    "black glass": "стёкла",
    "orange": "поворотники",
    "orange glass": "стекло фар",
    "metallic": "хром/металл",
    "wheel": "шины",
}


def hex_to_rgb(value: str) -> list[float]:
    text = value.strip().lstrip("#")
    if len(text) == 3:
        text = "".join(ch * 2 for ch in text)
    if len(text) != 6:
        raise argparse.ArgumentTypeError(f"ожидался цвет вида #RRGGBB, получено {value!r}")
    return [int(text[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]


def read_glb(path: str) -> tuple[dict, bytes, int]:
    with open(path, "rb") as handle:
        data = handle.read()
    magic, version, length = struct.unpack_from("<III", data, 0)
    if magic != GLB_MAGIC:
        raise SystemExit(f"{path}: это не GLB")
    offset = 12
    gltf: dict | None = None
    binary = b""
    while offset < length:
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        chunk = data[offset + 8: offset + 8 + chunk_length]
        if chunk_type == CHUNK_JSON:
            gltf = json.loads(chunk.decode("utf-8"))
        elif chunk_type == CHUNK_BIN:
            binary = chunk
        offset += 8 + chunk_length + ((4 - chunk_length % 4) % 4 if chunk_length % 4 else 0)
    if gltf is None:
        raise SystemExit(f"{path}: нет JSON-чанка")
    return gltf, binary, version


def write_glb(path: str, gltf: dict, binary: bytes) -> None:
    js = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    js += b" " * ((4 - len(js) % 4) % 4)
    bin_pad = b"\x00" * ((4 - len(binary) % 4) % 4)
    total = 12 + 8 + len(js) + (8 + len(binary) + len(bin_pad) if binary else 0)
    with open(path, "wb") as handle:
        handle.write(struct.pack("<III", GLB_MAGIC, 2, total))
        handle.write(struct.pack("<II", len(js), CHUNK_JSON))
        handle.write(js)
        if binary:
            handle.write(struct.pack("<II", len(binary) + len(bin_pad), CHUNK_BIN))
            handle.write(binary)
            handle.write(bin_pad)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--in", dest="src", default="Dashboard/assets/ipsum_fin.glb",
                        help="исходная модель (по умолчанию Dashboard/assets/ipsum_fin.glb)")
    parser.add_argument("--out", dest="dst", default=None,
                        help="куда писать (по умолчанию — рядом, *_painted.glb)")
    parser.add_argument("--list", action="store_true", help="только показать материалы и выйти")

    # Цвета по материалам: параметр называется по материалу.
    parser.add_argument("--body", type=hex_to_rgb, help="кузов (base white)")
    parser.add_argument("--black-glossy", type=hex_to_rgb, help="чёрный глянец")
    parser.add_argument("--inside", type=hex_to_rgb, help="салон")
    parser.add_argument("--glass", type=hex_to_rgb, help="стёкла (тонировка)")
    parser.add_argument("--glass-alpha", type=float, default=None,
                        help="прозрачность стёкол 0…1 (0.5 — полупрозрачные)")
    parser.add_argument("--glass-rough", type=float, default=None,
                        help="шероховатость стёкол (0.05 — глянец)")
    parser.add_argument("--metallic", type=hex_to_rgb, help="хром/металл")
    parser.add_argument("--wheel", type=hex_to_rgb, help="шины")
    # Диски в модели идут материалом metallic (он же хром в фарах).
    parser.add_argument("--rim", type=hex_to_rgb, help="колёсные диски (metallic)")
    parser.add_argument("--rim-metal", type=float, help="металличность дисков 0…1")
    parser.add_argument("--rim-rough", type=float, help="шероховатость дисков 0…1")
    parser.add_argument("--taillight", type=hex_to_rgb, help="задние фонари")
    parser.add_argument("--turn-signal", type=hex_to_rgb, help="поворотники")
    # Для перламутра и «полуматового» лака нужны ещё металличность и
    # шероховатость: у модели по умолчанию metal=0.8/rough=0.2 — это
    # зеркальный металлик, а не полумат.
    parser.add_argument("--body-metal", type=float, help="металличность кузова 0…1")
    parser.add_argument("--body-rough", type=float, help="шероховатость кузова 0…1")
    args = parser.parse_args()

    gltf, binary, _version = read_glb(args.src)
    materials = gltf.get("materials", [])
    if not materials:
        raise SystemExit(f"{args.src}: в модели нет материалов")

    by_index = {0: "black glossy", 1: "base white", 2: "inside black", 3: "red",
                4: "black glass", 5: "orange", 6: "orange glass", 7: "metallic",
                8: "wheel"}

    if args.list:
        print(f"Модель: {args.src}")
        for index, material in enumerate(materials):
            pbr = material.get("pbrMetallicRoughness", {})
            color = pbr.get("baseColorFactor", [1, 1, 1, 1])
            hex_color = "#%02X%02X%02X" % tuple(int(round(c * 255)) for c in color[:3])
            name = material.get("name") or by_index.get(index, "?")
            print(f"  {index}: {name:14} {hex_color}  — {MATERIAL_HINTS.get(name, '')}")
        return 0

    changes = {
        "base white": args.body,
        # ключ «metallic» один: и --rim, и старый --metallic красят один и тот
        # же материал (раньше здесь было два одинаковых ключа, и второй
        # затирал первый — цвет дисков молча не применялся)
        "metallic": args.rim if args.rim is not None else args.metallic,
        "black glossy": args.black_glossy,
        "inside black": args.inside,
        "black glass": args.glass,
        "wheel": args.wheel,
        "red": args.taillight,
        "orange": args.turn_signal,
    }
    changes = {k: v for k, v in changes.items() if v is not None}
    if not changes:
        parser.print_help()
        print("\nНе задан ни один цвет — менять нечего.", file=sys.stderr)
        return 2

    for index, material in enumerate(materials):
        name = material.get("name") or by_index.get(index, "")
        if name not in changes:
            continue
        pbr = material.setdefault("pbrMetallicRoughness", {})
        old = pbr.get("baseColorFactor", [1, 1, 1, 1])
        alpha = old[3] if len(old) > 3 else 1.0
        rgb = changes[name]
        pbr["baseColorFactor"] = [rgb[0], rgb[1], rgb[2], alpha]
        print(f"  {name}: #%02X%02X%02X → #%02X%02X%02X" % (
            int(round(old[0] * 255)), int(round(old[1] * 255)), int(round(old[2] * 255)),
            int(round(rgb[0] * 255)), int(round(rgb[1] * 255)), int(round(rgb[2] * 255))))

    # Диски: металличность/шероховатость отдельно от цвета.
    if args.rim_metal is not None or args.rim_rough is not None:
        for index, material in enumerate(materials):
            if (material.get("name") or by_index.get(index, "")) != "metallic":
                continue
            pbr = material.setdefault("pbrMetallicRoughness", {})
            if args.rim_metal is not None:
                pbr["metallicFactor"] = args.rim_metal
                print(f"  metallic: metal → {args.rim_metal}")
            if args.rim_rough is not None:
                pbr["roughnessFactor"] = args.rim_rough
                print(f"  metallic: rough → {args.rim_rough}")

    # Металличность/шероховатость — только для кузова (перламутр под лаком).
    if args.body_metal is not None or args.body_rough is not None:
        for index, material in enumerate(materials):
            if (material.get("name") or by_index.get(index, "")) != "base white":
                continue
            pbr = material.setdefault("pbrMetallicRoughness", {})
            if args.body_metal is not None:
                print(f"  base white: metallic {pbr.get('metallicFactor', 1.0)} → {args.body_metal}")
                pbr["metallicFactor"] = args.body_metal
            if args.body_rough is not None:
                print(f"  base white: roughness {pbr.get('roughnessFactor', 0.5)} → {args.body_rough}")
                pbr["roughnessFactor"] = args.body_rough

    # Стекло: цвет + прозрачность. В glTF прозрачность задаётся альфой
    # baseColorFactor и режимом alphaMode=BLEND, иначе материал рисуется
    # непрозрачным и стекло выглядит серой пластмассой.
    for index, material in enumerate(materials):
        if (material.get("name") or by_index.get(index, "")) != "black glass":
            continue
        if args.glass is None and args.glass_alpha is None and args.glass_rough is None:
            break
        pbr = material.setdefault("pbrMetallicRoughness", {})
        color = pbr.get("baseColorFactor", [1, 1, 1, 1])
        rgb = args.glass if args.glass is not None else color[:3]
        alpha = args.glass_alpha if args.glass_alpha is not None else (color[3] if len(color) > 3 else 1.0)
        pbr["baseColorFactor"] = [rgb[0], rgb[1], rgb[2], alpha]
        pbr["metallicFactor"] = 0.0
        if args.glass_rough is not None:
            pbr["roughnessFactor"] = args.glass_rough
        material["alphaMode"] = "BLEND"
        material["doubleSided"] = True
        print(f"  black glass: #%02X%02X%02X, alpha {alpha}, alphaMode BLEND" % (
            int(round(rgb[0] * 255)), int(round(rgb[1] * 255)), int(round(rgb[2] * 255))))

    out = args.dst or args.src.replace(".glb", "_painted.glb")
    write_glb(out, gltf, binary)
    print(f"Записано: {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
