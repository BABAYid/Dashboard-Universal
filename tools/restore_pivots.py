#!/usr/bin/env python3
"""Возврат точек вращения (петель) дверям, капоту, задней двери и колёсам.

В модели от дизайнера (main_3.3.glb) трансформации «запечены» в вершины:
у узлов нет ни translation, ни rotation, поэтому геометрия двери лежит в
мировых координатах, а сама точка вращения узла — в центре модели. Если такую
дверь повернуть, она улетит через всю машину.

Что делает скрипт: для каждой подвижной части считает петлю по её габаритам,
сдвигает вершины так, чтобы петля стала началом координат детали, и прописывает
узлу translation = петля. После этого поворот узла (как в QML) идёт вокруг
петли — двери открываются наружу, капот поднимается передней кромкой, задняя
дверь — нижней, колёса крутятся вокруг своей оси.

Петли (координаты модели, метры: X — ширина, Y — высота, Z — длина, нос в +Z):
    двери            верхняя точка передней кромки (Z_max)
    капот            задняя кромка (Z_min) — у лобового стекла
    задняя дверь     верхняя кромка (Y_max, Z_max)
    колёса           центр габарита

Пример:
    python3 tools/restore_pivots.py --in build/tmp/car_3.glb --out Dashboard/assets/ipsum_fin.glb
"""

from __future__ import annotations

import argparse
import json
import struct
import sys

GLB_MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942
COMPONENT = {5126: ("f", 4), 5125: ("I", 4), 5123: ("H", 2), 5121: ("B", 1)}

# узел → правило петли
PIVOTS = {
    1: "top",        # door back (задняя дверь)
    2: "front",      # door front left
    3: "front",      # door front right
    4: "front",      # door left back
    5: "front",      # door right back
    6: "rear",       # капот (крышка капота открывается от лобового стекла)
    13: "center",    # колёса
    14: "center",
    15: "center",
    16: "center",
}


def read_glb(path: str):
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


def accessor_slice(gltf: dict, index: int) -> tuple[int, int, int, str]:
    """Возвращает (начало, количество, число компонент, формат) для аксессора."""
    acc = gltf["accessors"][index]
    view = gltf["bufferViews"][acc["bufferView"]]
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    fmt, _size = COMPONENT[acc["componentType"]]
    ncomp = {"SCALAR": 1, "VEC3": 3, "VEC2": 2}[acc["type"]]
    return start, acc["count"], ncomp, fmt


def first_successor_summary(name: str) -> str:
    return name


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--in", dest="src", required=True)
    parser.add_argument("--out", dest="dst", required=True)
    args = parser.parse_args()

    gltf, binary = read_glb(args.src)
    nodes = gltf["nodes"]

    for node_index, rule in PIVOTS.items():
        node = nodes[node_index]
        mesh_index = node.get("mesh")
        if mesh_index is None:
            continue
        mesh = gltf["meshes"][mesh_index]
        position_accessors = []
        for primitive in mesh["primitives"]:
            acc_index = primitive["attributes"]["POSITION"]
            if acc_index not in position_accessors:
                position_accessors.append(acc_index)

        # габариты детали
        lo = [1e9, 1e9, 1e9]
        hi = [-1e9, -1e9, -1e9]
        for acc_index in position_accessors:
            start, count, _ncomp, fmt = accessor_slice(gltf, acc_index)
            values = struct.unpack_from("<" + fmt * (3 * count), binary, start)
            for i in range(count):
                for k in range(3):
                    value = values[i * 3 + k]
                    lo[k] = min(lo[k], value)
                    hi[k] = max(hi[k], value)

        cx, cy, cz = [(lo[k] + hi[k]) / 2.0 for k in range(3)]
        if rule == "front":
            pivot = [cx, cy, hi[2]]          # передняя кромка двери
        elif rule == "rear":
            pivot = [cx, cy, lo[2]]          # задняя кромка капота
        elif rule == "top":
            pivot = [cx, hi[1], hi[2]]       # верх задней двери
        else:
            pivot = [cx, cy, cz]             # центр (колёса)

        # сдвигаем вершины: петля становится нулём координат детали
        for acc_index in position_accessors:
            start, count, _ncomp, fmt = accessor_slice(gltf, acc_index)
            values = list(struct.unpack_from("<" + fmt * (3 * count), binary, start))
            for i in range(count):
                values[i * 3 + 0] -= pivot[0]
                values[i * 3 + 1] -= pivot[1]
                values[i * 3 + 2] -= pivot[2]
            struct.pack_into("<" + fmt * (3 * count), binary, start, *values)
            acc = gltf["accessors"][acc_index]
            acc["min"] = [round(lo[k] - pivot[k], 6) for k in range(3)]
            acc["max"] = [round(hi[k] - pivot[k], 6) for k in range(3)]

        node["translation"] = [round(v, 6) for v in pivot]
        print(f"  узел {node_index:2} {node.get('name', ''):22} петля "
              f"X {pivot[0]:.2f} Y {pivot[1]:.2f} Z {pivot[2]:.2f} ({rule})")

    write_glb(args.dst, gltf, binary)
    print(f"Записано: {args.dst}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
