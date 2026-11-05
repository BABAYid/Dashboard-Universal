#!/usr/bin/env python3
"""Раскраска отдельных ЧАСТЕЙ кузова: крыша, решётка, спойлеры.

В модели дизайнера весь кузов — один материал (`base white`), поэтому
«тёмно-коричневые крыша, решётка и спойлеры» требуют не покраски материала,
а выкраивания треугольников из меша кузова в отдельный материал.

Скрипт режет примитив по геометрическому правилу и создаёт для выбранных
треугольников новый материал. Геометрия (вершины) не дублируется: новый
примитив использует тот же POSITION и только свой список индексов.

Правила (координаты модели, метры: X — ширина, Y — высота, Z — длина,
нос в +Z; низ кузова на Y≈2.0, крыша Y≈3.72):

  --roof     основа кузова (узел base): треугольники выше 3.5 м с нормалью
             вверх — горизонтальная панель крыши;
  --grille   капот (узел front door): треугольники в передней части (Z>4.0);
  --spoiler  задняя дверь (узел door back): треугольники в верхней полосе
             (Y>3.05) — кромка, где стоят спойлеры.

Примеры:
    python3 tools/paint_parts.py --list
    python3 tools/paint_parts.py --roof "#3B2A22" --grille "#3B2A22" \\
        --spoiler "#3B2A22" --out Dashboard/assets/ipsum_fin.glb
"""

from __future__ import annotations

import argparse
import json
import struct
import sys

GLB_MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942

BODY_MATERIAL = "base white"
# (узел, индекс примитива с краской кузова)
PART_TARGETS = {
    "roof": (0, 1),      # base → примитив с материалом base white
    # Решётка радиатора — отдельный кластер ЧЁРНОГО ГЛЯНЦА в кузове
    # (X 1.07…1.73, Y 2.67…2.80, Z 4.13…4.26), а не вся передняя кромка:
    # в панели «front door» она не выделена, поэтому раньше в коричневый
    # уезжала половина капота.
    "grille": (0, 0),    # base → примитив black glossy
    "spoiler": (1, 2),   # door back → примитив с материалом base white
}


def hex_to_rgb(value: str) -> list[float]:
    text = value.strip().lstrip("#")
    if len(text) == 3:
        text = "".join(ch * 2 for ch in text)
    if len(text) != 6:
        raise argparse.ArgumentTypeError(f"ожидался цвет #RRGGBB, получено {value!r}")
    return [int(text[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]


def read_glb(path: str) -> tuple[dict, bytearray]:
    data = open(path, "rb").read()
    magic, _version, length = struct.unpack_from("<III", data, 0)
    if magic != GLB_MAGIC:
        raise SystemExit(f"{path}: это не GLB")
    offset, gltf, binary = 12, None, bytearray()
    while offset < length:
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        chunk = data[offset + 8: offset + 8 + chunk_length]
        if chunk_type == CHUNK_JSON:
            gltf = json.loads(chunk.decode("utf-8"))
        elif chunk_type == CHUNK_BIN:
            binary = bytearray(chunk)
        offset += 8 + chunk_length + ((4 - chunk_length % 4) % 4 if chunk_length % 4 else 0)
    if gltf is None:
        raise SystemExit(f"{path}: нет JSON-чанка")
    return gltf, binary


def write_glb(path: str, gltf: dict, binary: bytearray) -> None:
    gltf.setdefault("buffers", [{}])[0]["byteLength"] = len(binary)
    js = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    js += b" " * ((4 - len(js) % 4) % 4)
    pad = b"\x00" * ((4 - len(binary) % 4) % 4)
    total = 12 + 8 + len(js) + 8 + len(binary) + len(pad)
    with open(path, "wb") as handle:
        handle.write(struct.pack("<III", GLB_MAGIC, 2, total))
        handle.write(struct.pack("<II", len(js), CHUNK_JSON))
        handle.write(js)
        handle.write(struct.pack("<II", len(binary) + len(pad), CHUNK_BIN))
        handle.write(bytes(binary))
        handle.write(pad)


COMPONENT = {5126: ("f", 4), 5125: ("I", 4), 5123: ("H", 2), 5121: ("B", 1)}


def read_accessor(gltf: dict, binary: bytearray, index: int):
    acc = gltf["accessors"][index]
    view = gltf["bufferViews"][acc["bufferView"]]
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    fmt, size = COMPONENT[acc["componentType"]]
    ncomp = {"SCALAR": 1, "VEC3": 3, "VEC2": 2}[acc["type"]]
    count = acc["count"]
    values = struct.unpack_from("<" + fmt * (ncomp * count), binary, start)
    if ncomp == 1:
        return list(values)
    return [values[i * ncomp:(i + 1) * ncomp] for i in range(count)]


def append_indices(gltf: dict, binary: bytearray, indices: list[int]) -> int:
    """Дописывает массив индексов в BIN и возвращает индекс нового accessor."""
    while len(binary) % 4:
        binary.append(0)
    offset = len(binary)
    payload = struct.pack("<" + "I" * len(indices), *indices)
    binary.extend(payload)
    gltf["bufferViews"].append({
        "buffer": 0,
        "byteOffset": offset,
        "byteLength": len(payload),
        "target": 34963,   # ELEMENT_ARRAY_BUFFER
    })
    gltf["accessors"].append({
        "bufferView": len(gltf["bufferViews"]) - 1,
        "componentType": 5125,
        "count": len(indices),
        "type": "SCALAR",
    })
    return len(gltf["accessors"]) - 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--in", dest="src", default="Dashboard/assets/ipsum_fin.glb")
    parser.add_argument("--out", dest="dst", default=None)
    parser.add_argument("--list", action="store_true", help="показать материалы и выйти")
    parser.add_argument("--roof", type=hex_to_rgb, help="крыша")
    parser.add_argument("--grille", type=hex_to_rgb, help="решётка радиатора (капот)")
    parser.add_argument("--spoiler", type=hex_to_rgb, help="спойлеры задней двери")
    parser.add_argument("--metal", type=float, default=0.85, help="металличность новых частей (по умолчанию 0.85)")
    parser.add_argument("--rough", type=float, default=0.30, help="шероховатость новых частей (по умолчанию 0.30)")
    parser.add_argument("--roof-level", type=float, default=3.50, help="порог высоты крыши, м (3.50)")
    parser.add_argument("--grille-z", type=float, default=4.05, help="с какого Z начинается решётка (4.05)")
    parser.add_argument("--grille-x0", type=float, default=1.00, help="левая граница решётки по X (1.00)")
    parser.add_argument("--grille-x1", type=float, default=1.80, help="правая граница решётки по X (1.80)")
    parser.add_argument("--spoiler-level", type=float, default=3.05, help="порог высоты спойлеров, м (3.05)")
    args = parser.parse_args()

    gltf, binary = read_glb(args.src)
    materials = gltf.get("materials", [])
    if args.list:
        print(f"Модель: {args.src}")
        for index, material in enumerate(materials):
            pbr = material.get("pbrMetallicRoughness", {})
            color = pbr.get("baseColorFactor", [1, 1, 1, 1])
            print(f"  {index}: {material.get('name', '?'):14} "
                  f"#%02X%02X%02X" % tuple(int(round(c * 255)) for c in color[:3]))
        for part, (node, prim) in PART_TARGETS.items():
            mesh = gltf["meshes"][gltf["nodes"][node]["mesh"]]
            primitive = mesh["primitives"][prim]
            print(f"  часть «{part}»: узел {node} ({gltf['nodes'][node].get('name')}), "
                  f"примитив {prim}, материал {gltf['materials'][primitive.get('material', 0)].get('name')}, "
                  f"треугольников {gltf['accessors'][primitive['indices']]['count'] // 3}")
        return 0

    wanted = {"roof": args.roof, "grille": args.grille, "spoiler": args.spoiler}
    wanted = {k: v for k, v in wanted.items() if v is not None}
    if not wanted:
        parser.print_help()
        print("\nНе задана ни одна часть — менять нечего.", file=sys.stderr)
        return 2

    for part, color in wanted.items():
        node_index, prim_index = PART_TARGETS[part]
        mesh_index = gltf["nodes"][node_index]["mesh"]
        mesh = gltf["meshes"][mesh_index]
        primitive = mesh["primitives"][prim_index]
        positions = read_accessor(gltf, binary, primitive["attributes"]["POSITION"])
        indices = read_accessor(gltf, binary, primitive["indices"])

        keep, moved = [], []
        for t in range(len(indices) // 3):
            a, b, c = (positions[indices[t * 3]], positions[indices[t * 3 + 1]],
                       positions[indices[t * 3 + 2]])
            cy = (a[1] + b[1] + c[1]) / 3.0
            cz = (a[2] + b[2] + c[2]) / 3.0
            # нормаль (для крыши важно, чтобы панель была горизонтальной)
            ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
            vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
            nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
            length = (nx * nx + ny * ny + nz * nz) ** 0.5 or 1.0
            ny_norm = abs(ny) / length

            take = False
            if part == "roof":
                take = cy > args.roof_level and ny_norm > 0.55
            elif part == "grille":
                # спереди и по центру: у решётки X 1.07…1.73, у всей панели
                # вокруг — от 0.55 до 2.25, поэтому ограничиваем полосу
                cx = (a[0] + b[0] + c[0]) / 3.0
                take = cz > args.grille_z and args.grille_x0 <= cx <= args.grille_x1
            elif part == "spoiler":
                take = cy > args.spoiler_level
            (moved if take else keep).extend(indices[t * 3:t * 3 + 3])

        if not moved:
            print(f"  {part}: ни один треугольник не подошёл (порог?) — пропущено")
            continue

        # новый материал — копия кузова с нужным цветом
        base_material = json.loads(json.dumps(materials[primitive["material"]]))
        base_material["name"] = f"{part}"
        pbr = base_material.setdefault("pbrMetallicRoughness", {})
        pbr["baseColorFactor"] = [color[0], color[1], color[2], 1.0]
        pbr["metallicFactor"] = args.metal
        pbr["roughnessFactor"] = args.rough
        materials.append(base_material)
        new_material_index = len(materials) - 1

        keep_accessor = append_indices(gltf, binary, keep)
        moved_accessor = append_indices(gltf, binary, moved)
        primitive["indices"] = keep_accessor
        new_primitive = dict(primitive)
        new_primitive["indices"] = moved_accessor
        new_primitive["material"] = new_material_index
        mesh["primitives"].append(new_primitive)

        print(f"  {part}: перенесено треугольников {len(moved) // 3} из {len(indices) // 3}, "
              f"цвет #%02X%02X%02X" % tuple(int(round(c * 255)) for c in color))

    gltf["materials"] = materials
    out = args.dst or args.src.replace(".glb", "_parts.glb")
    write_glb(out, gltf, binary)
    print(f"Записано: {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
