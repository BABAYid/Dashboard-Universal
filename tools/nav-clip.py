#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
#  Обрезка выгрузки OSM по прямоугольнику (замена `osmium extract`).
#
#  osmium-tool в системе может отсутствовать, поэтому режем на pyosmium
#  (ставится в проект без root: pip install --target build/pylibs osmium).
#
#  Использование:
#      PYTHONPATH=build/pylibs python3 tools/nav-clip.py \
#          maps/nw-fed.osm.pbf maps/spb.osm.pbf --bbox 28.0,58.4,31.8,61.0
#
#  История правок (стоила двух неудачных прогонов 16–17.11.2026 — читать, если
#  будете править):
#   1. Первая версия складывала найденные пути/отношения в список и писала их
#      после прохода. Так нельзя: pyosmium отдаёт в обработчик *временные*
#      объекты, и сохранённая ссылка «схлопывается» — на выходе получались
#      миллионы узлов и НОЛЬ путей (так вышла обрезка Питера).
#   2. Вторая версия держала id узлов в множестве Python: на 15 млн узлов это
#      больше гигабайта, и процесс молча убивало по памяти (SIGKILL без
#      сообщений). Теперь id лежат в numpy-массивах (8 байт на элемент),
#      проверка — бинарным поиском.
#   3. Обрезать «по узлам в bbox» неправильно: у пути, заходящего за границу,
#      пропали бы вынесенные за bbox узлы — геометрия рвётся. Поэтому пути
#      выбираются те, у которых ХОТЬ ОДИН узел в bbox, и в выход попадают ВСЕ
#      узлы этих путей, плюс отдельные узлы с тегами внутри bbox (адреса, POI).
#
#  Память не зависит от размера выгрузки: в памяти только id, данные элементов
#  пишутся потоком.
# ============================================================================
import os
import sys

try:
    import numpy as np
    import osmium
except ImportError:
    sys.exit("нужны pyosmium и numpy: pip install --target build/pylibs osmium\n"
             "затем запускать с PYTHONPATH=build/pylibs")


class _Ids:
    """Набор id в numpy-массиве: 8 байт на элемент, поиск — бинарный."""

    def __init__(self):
        self._list = []
        self._sorted = np.empty(0, dtype=np.int64)

    def add(self, value):
        self._list.append(value)

    def finish(self):
        self._sorted = np.array(sorted(set(self._list)), dtype=np.int64)
        self._list = []
        return int(self._sorted.size)

    def __contains__(self, value):
        if self._sorted.size == 0:
            return False
        pos = int(np.searchsorted(self._sorted, value))
        return pos < self._sorted.size and int(self._sorted[pos]) == value

    def __len__(self):
        return int(self._sorted.size)


def main():
    args = sys.argv[1:]
    if len(args) < 2:
        sys.exit("использование: nav-clip.py <in.osm.pbf> <out.osm.pbf> --bbox w,s,e,n")
    src, dst = args[0], args[1]
    bbox = None
    if "--bbox" in args:
        i = args.index("--bbox")
        bbox = [float(v) for v in args[i + 1].split(",")]
    if bbox is None or len(bbox) != 4:
        sys.exit("нужен --bbox запад,юг,восток,север (lon,lat — как в OSM)")
    west, south, east, north = bbox
    inside = lambda lon, lat: west <= lon <= east and south <= lat <= north

    print(f"bbox: {west}..{east} E, {south}..{north} N", flush=True)

    kept_ways = _Ids()
    needed_nodes = _Ids()

    # --- проход 1: пути, задевающие bbox, и все их узлы ----------------------
    class WayIdsPass(osmium.SimpleHandler):
        def way(self, w):
            touches = False
            for nd in w.nodes:
                loc = nd.location
                if loc.valid() and inside(loc.lon, loc.lat):
                    touches = True
                    break
            if not touches:
                return
            kept_ways.add(w.id)
            for nd in w.nodes:
                needed_nodes.add(nd.ref)

    WayIdsPass().apply_file(src, locations=True)
    print(f"путей в bbox: {kept_ways.finish()}, их узлов: {needed_nodes.finish()}", flush=True)

    if os.path.exists(dst):
        os.remove(dst)
    writer = osmium.SimpleWriter(dst)

    # --- проход 2: узлы (все узлы нужных путей + отдельные объекты в bbox) ---
    class NodePass(osmium.SimpleHandler):
        written = 0

        def node(self, n):
            keep = n.id in needed_nodes
            if not keep and n.tags and n.location.valid():
                keep = inside(n.location.lon, n.location.lat)
            if keep:
                writer.add_node(n)
                NodePass.written += 1

    NodePass().apply_file(src)
    print(f"узлов записано: {NodePass.written}", flush=True)

    # --- проход 3: сами пути -------------------------------------------------
    class WayWritePass(osmium.SimpleHandler):
        written = 0

        def way(self, w):
            if w.id in kept_ways:
                writer.add_way(w)
                WayWritePass.written += 1

    WayWritePass().apply_file(src)
    print(f"путей записано: {WayWritePass.written}", flush=True)

    # --- проход 4: id отношений, ссылающихся на отобранное -------------------
    kept_rels = _Ids()

    class RelIdsPass(osmium.SimpleHandler):
        def relation(self, r):
            for m in r.members:
                if (m.type == "w" and m.ref in kept_ways) or (m.type == "n" and m.ref in needed_nodes):
                    kept_rels.add(r.id)
                    return

    RelIdsPass().apply_file(src)
    print(f"отношений: {kept_rels.finish()}", flush=True)

    # --- проход 5: сами отношения -------------------------------------------
    class RelWritePass(osmium.SimpleHandler):
        def relation(self, r):
            if r.id in kept_rels:
                writer.add_relation(r)

    if len(kept_rels):
        RelWritePass().apply_file(src)

    writer.close()
    print(f"готово: {dst}", flush=True)


if __name__ == "__main__":
    main()
