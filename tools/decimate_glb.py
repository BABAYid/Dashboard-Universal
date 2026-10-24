#!/usr/bin/env python3
"""Прореживание glTF-модели: кластеризация вершин по целочисленной сетке.

Зачем: модель `audi3D.glb` весит 75 МБ и содержит ~1 030 000 треугольников.
На Mali-G610 (RK3588) в окне 492×404 это не тянет, да и грузится секундами.
Скрипт прореживает геометрию до заданного порядка и собирает новый GLB:
материалы, текстуры и иерархия узлов сохраняются, геометрия заменяется
прореженной.

Почему кластеризация (vertex clustering), а не настоящее упрощение: она
линейна, работает за секунды на миллионе треугольников и даёт характерный
«low-poly» вид — ровно то, что нужно для маленького окна 3D в приборке.
Если понадобится качество лучше — модель лучше выгрузить из Blender
модификатором Decimate, код приборки от этого не меняется.

Использование:

    python3 tools/decimate_glb.py audi3D.glb Dashboard/assets/car.glb --tris 30000

Скрипт печатает, сколько треугольников было и стало, и сколько весит результат.
"""

import argparse
import copy
import json
import struct
import sys

import numpy as np

GLB_MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942

COMPONENT = {5121: np.uint8, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
COMPONENT_GL = {np.uint8: 5121, np.uint16: 5123, np.uint32: 5125, np.float32: 5126}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def read_glb(path):
    with open(path, "rb") as f:
        magic, version, total = struct.unpack("<III", f.read(12))
        if magic != GLB_MAGIC or version != 2:
            raise SystemExit("это не GLB 2.0")
        gltf, binary = None, b""
        while f.tell() < total:
            length, ctype = struct.unpack("<II", f.read(8))
            data = f.read(length)
            if ctype == CHUNK_JSON:
                gltf = json.loads(data)
            elif ctype == CHUNK_BIN:
                binary = data
    if gltf is None:
        raise SystemExit("в файле нет JSON-чанка")
    return gltf, binary


def accessor_array(gltf, binary, index):
    """Читает accessor в numpy-массив (с учётом byteStride)."""
    acc = gltf["accessors"][index]
    view = gltf["bufferViews"][acc["bufferView"]]
    dtype = COMPONENT[acc["componentType"]]
    ncomp = NCOMP[acc["type"]]
    item = np.dtype(dtype).itemsize
    count = acc["count"]
    stride = view.get("byteStride", ncomp * item)
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    if stride == ncomp * item:
        raw = np.frombuffer(binary, dtype=dtype, count=count * ncomp, offset=start)
        arr = raw.reshape(count, ncomp) if ncomp > 1 else raw
    else:   # чередующиеся данные
        raw = np.frombuffer(binary, dtype=np.uint8, count=(count - 1) * stride + ncomp * item, offset=start)
        rows = np.lib.stride_tricks.as_strided(
            raw, shape=(count, ncomp * item), strides=(stride, 1))
        arr = rows.copy().view(dtype).reshape(count, ncomp) if ncomp > 1 else rows.copy().view(dtype).ravel()
    return np.array(arr, dtype=np.float64 if dtype is np.float32 else dtype)


def primitive_triangles(indices, mode):
    """Индексы примитива → массив треугольников (N, 3).

    В модели все примитивы лежат полосами (mode 5), поэтому без этого
    преобразования «треугольники» считались бы неверно.
    """
    if mode == 4:                        # отдельные треугольники
        return indices.reshape(-1, 3)
    if mode == 5:                        # полоса: намотка чередуется
        a = indices[:-2]
        b = indices[1:-1]
        c = indices[2:]
        even = np.arange(a.size) % 2 == 0
        return np.stack([a, np.where(even, b, c), np.where(even, c, b)], axis=1)
    if mode == 6:                        # веер
        return np.stack([np.full(indices.size - 2, indices[0]),
                         indices[1:-1], indices[2:]], axis=1)
    return None                          # точки и линии не рисуем


def decimate_primitive(pos, nrm, uv, tris, eps):
    """Кластеризация вершин: одна вершина на ячейку сетки."""
    origin = pos.min(axis=0)
    cells = np.floor((pos - origin) / eps).astype(np.int64)
    _, inverse = np.unique(cells, axis=0, return_inverse=True)
    inverse = inverse.ravel()
    count = int(inverse.max()) + 1 if inverse.size else 0
    if count == 0:
        return None

    weights = np.bincount(inverse, minlength=count).astype(np.float64)
    new_pos = np.stack(
        [np.bincount(inverse, weights=pos[:, i], minlength=count) / weights for i in range(3)],
        axis=1)

    new_nrm = None
    if nrm is not None:
        new_nrm = np.stack(
            [np.bincount(inverse, weights=nrm[:, i], minlength=count) / weights for i in range(3)],
            axis=1)
        lengths = np.linalg.norm(new_nrm, axis=1, keepdims=True)
        lengths[lengths == 0] = 1.0
        new_nrm = new_nrm / lengths

    new_uv = None
    if uv is not None:
        new_uv = np.stack(
            [np.bincount(inverse, weights=uv[:, i], minlength=count) / weights for i in range(2)],
            axis=1)

    tris = inverse[tris]
    if tris.size == 0:
        return None
    keep = (tris[:, 0] != tris[:, 1]) & (tris[:, 1] != tris[:, 2]) & (tris[:, 0] != tris[:, 2])
    tris = tris[keep]
    if tris.size == 0:
        return None
    # в glTF пишем float32: float64 посчитан, но в файле не нужен
    return (new_pos.astype(np.float32),
            None if new_nrm is None else new_nrm.astype(np.float32),
            None if new_uv is None else new_uv.astype(np.float32),
            tris)


def total_triangles(gltf):
    total = 0
    for mesh in gltf.get("meshes", []):
        for prim in mesh.get("primitives", []):
            if "indices" not in prim:
                continue
            count = gltf["accessors"][prim["indices"]]["count"]
            mode = prim.get("mode", 4)
            total += count // 3 if mode == 4 else max(0, count - 2)
    return total


def node_transform(node):
    """Матрица узла (translation/rotation/scale или готовая matrix)."""
    if "matrix" in node:
        return np.array(node["matrix"], dtype=float).reshape(4, 4).T
    t = np.eye(4)
    if "translation" in node:
        t[:3, 3] = node["translation"]
    if "rotation" in node:
        x, y, z, w = node["rotation"]
        r = np.array([
            [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
        m = np.eye(4)
        m[:3, :3] = r
        t = t @ m
    if "scale" in node:
        s = np.eye(4)
        s[0, 0], s[1, 1], s[2, 2] = node["scale"]
        t = t @ s
    return t


def bbox_size(gltf):
    """Габарит модели в мировых координатах (с учётом иерархии узлов).

    Локальные габариты мешей для подбора шага не годятся: в этой модели
    геометрия лежит в разных системах координат (меши масштабированы
    по-разному), и локальная сумма даёт «габарит» в сотни единиц.
    """
    lo = np.full(3, np.inf)
    hi = np.full(3, -np.inf)

    def walk(index, matrix):
        nonlocal lo, hi
        node = gltf["nodes"][index]
        matrix = matrix @ node_transform(node)
        if "mesh" in node:
            for prim in gltf["meshes"][node["mesh"]]["primitives"]:
                acc = gltf["accessors"][prim["attributes"]["POSITION"]]
                low, high = np.array(acc["min"]), np.array(acc["max"])
                corners = np.array([[x, y, z, 1.0]
                                    for x in (low[0], high[0])
                                    for y in (low[1], high[1])
                                    for z in (low[2], high[2])])
                world = (matrix @ corners.T).T[:, :3]
                lo = np.minimum(lo, world.min(axis=0))
                hi = np.maximum(hi, world.max(axis=0))
        for child in node.get("children", []):
            walk(child, matrix)

    for root in gltf["scenes"][gltf.get("scene", 0)]["nodes"]:
        walk(root, np.eye(4))
    return hi - lo


def build(gltf, binary, eps):
    """Собирает новый glTF с прореженной геометрией."""
    new_bin = bytearray()
    buffer_views = []
    accessors = []

    def add_view(data):
        while len(new_bin) % 4:
            new_bin.append(0)
        offset = len(new_bin)
        new_bin.extend(data)
        buffer_views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(data)})
        return len(buffer_views) - 1

    def add_accessor(arr, type_name, with_bounds=False):
        view = add_view(np.asarray(arr).tobytes())
        acc = {
            "bufferView": view,
            "componentType": COMPONENT_GL[arr.dtype.type],
            "count": int(arr.shape[0]),
            "type": type_name,
        }
        if with_bounds:
            acc["min"] = [float(v) for v in arr.min(axis=0)]
            acc["max"] = [float(v) for v in arr.max(axis=0)]
        accessors.append(acc)
        return len(accessors) - 1

    # текстуры переносим как есть: они маленькие (сотни КБ) и нужны материалам
    images = gltf.get("images", [])
    for image in images:
        view = gltf["bufferViews"][image["bufferView"]]
        start = view.get("byteOffset", 0)
        data = binary[start:start + view["byteLength"]]
        image["bufferView"] = add_view(bytes(data))

    meshes_out = []
    mesh_map = {}       # старый индекс меша → новый (пустые выбрасываем)
    triangles = 0
    for old_index, mesh in enumerate(gltf.get("meshes", [])):
        primitives_out = []
        for prim in mesh.get("primitives", []):
            attrs = prim["attributes"]
            pos = accessor_array(gltf, binary, attrs["POSITION"]).astype(np.float32)
            nrm = accessor_array(gltf, binary, attrs["NORMAL"]).astype(np.float32) if "NORMAL" in attrs else None
            uv = accessor_array(gltf, binary, attrs["TEXCOORD_0"]).astype(np.float32) if "TEXCOORD_0" in attrs else None
            idx = accessor_array(gltf, binary, prim["indices"]).astype(np.int64) if "indices" in prim else None
            if idx is None:
                idx = np.arange(pos.shape[0], dtype=np.int64)

            tris_in = primitive_triangles(idx, prim.get("mode", 4))
            if tris_in is None:
                continue
            result = decimate_primitive(pos, nrm, uv, tris_in, eps)
            if result is None:
                continue
            new_pos, new_nrm, new_uv, tris = result

            out = {"attributes": {"POSITION": add_accessor(new_pos, "VEC3", with_bounds=True)},
                   "mode": prim.get("mode", 4)}
            if new_nrm is not None:
                out["attributes"]["NORMAL"] = add_accessor(new_nrm.astype(np.float32), "VEC3")
            if new_uv is not None:
                out["attributes"]["TEXCOORD_0"] = add_accessor(new_uv.astype(np.float32), "VEC2")
            if "material" in prim:
                out["material"] = prim["material"]

            flat = tris.reshape(-1)
            if flat.max() < 65536:
                indices = flat.astype(np.uint16)
            else:
                indices = flat.astype(np.uint32)
            out["indices"] = add_accessor(indices, "SCALAR")
            primitives_out.append(out)
            triangles += tris.shape[0]
        if primitives_out:
            mesh_map[old_index] = len(meshes_out)
            meshes_out.append({"name": mesh.get("name", "mesh"), "primitives": primitives_out})

    # Узлы ссылаются на меши по индексу: после выбрасывания пустых индексы
    # сдвигаются, и без пересчёта получается битый файл (импортёр отвечает
    # «Unsupported»). Узлы, чей меш исчез, остаются пустыми.
    for node in gltf.get("nodes", []):
        if "mesh" in node:
            new_index = mesh_map.get(node["mesh"])
            if new_index is None:
                del node["mesh"]
            else:
                node["mesh"] = new_index

    gltf["meshes"] = meshes_out
    gltf["accessors"] = accessors
    gltf["bufferViews"] = buffer_views
    while len(new_bin) % 4:
        new_bin.append(0)
    gltf["buffers"] = [{"byteLength": len(new_bin)}]
    return gltf, bytes(new_bin), triangles


def write_glb(path, gltf, binary):
    json_bytes = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    while len(json_bytes) % 4:
        json_bytes += b" "
    while len(binary) % 4:
        binary += b"\x00"
    total = 12 + 8 + len(json_bytes) + 8 + len(binary)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", GLB_MAGIC, 2, total))
        f.write(struct.pack("<II", len(json_bytes), CHUNK_JSON))
        f.write(json_bytes)
        f.write(struct.pack("<II", len(binary), CHUNK_BIN))
        f.write(binary)


def main():
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument("source")
    args.add_argument("target")
    args.add_argument("--tris", type=int, default=30000, help="целевое число треугольников")
    opts = args.parse_args()

    gltf, binary = read_glb(opts.source)
    before = total_triangles(gltf)
    size = bbox_size(gltf)
    longest = float(np.max(size))
    print(f"исходник: {before:,} треугольников, габарит {np.round(size, 2).tolist()}")

    # подбираем шаг сетки: число треугольников обратно пропорционально шагу²
    # (кластеризация «съедает» площадь), поэтому уточняем в обе стороны
    eps = longest / 64.0
    best = None
    for step in range(10):
        # build() переписывает JSON модели, поэтому каждый проход — на копии
        _, _, tris = build(copy.deepcopy(gltf), binary, eps)
        print(f"  проход {step + 1}: шаг {eps:.4f} → {tris:,} треугольников")
        if best is None or abs(tris - opts.tris) < abs(best[1] - opts.tris):
            best = (eps, tris)
        if 0.7 * opts.tris <= tris <= 1.4 * opts.tris:
            break
        eps *= (tris / opts.tris) ** 0.5

    eps = best[0]
    new_gltf, new_bin, tris = build(copy.deepcopy(gltf), binary, eps)
    write_glb(opts.target, new_gltf, new_bin)

    import os
    print(f"готово: {tris:,} треугольников (было {before:,}), шаг {eps:.4f}, "
          f"файл {os.path.getsize(opts.target) / 1e6:.2f} МБ → {opts.target}")


if __name__ == "__main__":
    sys.exit(main())
