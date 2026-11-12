#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
#  Обрезка выгрузки OSM по прямоугольнику (замена `osmium extract`).
#
#  Нужна потому, что Geofabrik даёт округ/область, а нам нужен свой bbox
#  (Москва + 100 км). osmium-tool в системе может отсутствовать, поэтому
#  режем на pyosmium — он ставится в проект без root:
#
#      pip install --target build/pylibs osmium
#
#  Использование:
#      python3 tools/nav-clip.py maps/district.osm.pbf maps/nav-box.osm.pbf
#          --bbox 36.016,54.855,39.218,56.657
#
#  Как режем: сначала узлы внутри bbox (их id запоминаем), затем пути, у
#  которых есть хотя бы один такой узел, затем отношения, ссылающиеся на
#  отобранное. Пути, выходящие за край, остаются целиком — это нормально
#  для карт и маршрутов (лучше чуть больше, чем разорванная геометрия).
# ============================================================================
import sys
try:
    import osmium
except ImportError:
    sys.exit("нужен pyosmium: pip install --target build/pylibs osmium\n"
             "затем запускать с PYTHONPATH=build/pylibs")


def main():
    args = sys.argv[1:]
    if len(args) < 2:
        sys.exit("использование: nav-clip.py <in.osm.pbf> <out.osm.pbf> --bbox w,s,e,n")
    src, dst = args[0], args[1]
    bbox = None
    if "--bbox" in args:
        i = args.index("--bbox")
        west, south, east, north = [float(v) for v in args[i+1].split(",")]
        bbox = (west, south, east, north)
    if bbox is None:
        sys.exit("нужен --bbox запад,юг,восток,север")
    west, south, east, north = bbox
    inside = lambda lon, lat: west <= lon <= east and south <= lat <= north

    print(f"bbox: {west}..{east} E, {south}..{north} N")

    node_ids = set()
    ways_kept = set()
    rels_kept = set()

    # --- проход 1: узлы внутри bbox + пути, которые их касаются ---
    class NodePass(osmium.SimpleHandler):
        def __init__(self, writer):
            super().__init__()
            self.writer = writer
        def node(self, n):
            if n.location.valid() and inside(n.location.lon, n.location.lat):
                node_ids.add(n.id)
                self.writer.add_node(n)

    class WayPass(osmium.SimpleHandler):
        def way(self, w):
            if any(nd.ref in node_ids for nd in w.nodes):
                ways_kept.add(w.id)
                way_holder.append(w)

    way_holder = []
    writer = osmium.SimpleWriter(dst)
    NodePass(writer).apply_file(src, locations=False)
    print(f"узлов в bbox: {len(node_ids)}")

    WayPass().apply_file(src)
    print(f"путей: {len(ways_kept)}")
    for w in way_holder:
        writer.add_way(w)
    way_holder.clear()

    # --- проход 2: отношения, ссылающиеся на отобранное ---
    class RelPass(osmium.SimpleHandler):
        def relation(self, r):
            for m in r.members:
                if (m.type == "w" and m.ref in ways_kept) or (m.type == "n" and m.ref in node_ids):
                    rels_kept.add(r.id)
                    r_holder.append(r)
                    return

    r_holder = []
    RelPass().apply_file(src)
    print(f"отношений: {len(rels_kept)}")
    for r in r_holder:
        writer.add_relation(r)
    writer.close()
    print(f"готово: {dst}")


if __name__ == "__main__":
    main()
