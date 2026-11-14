#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
#  Поиск адреса по OSM: SQLite FTS5 (полнотекстовый индекс, без сервера).
#
#  Построение (один раз, ~10-20 минут на district.osm.pbf):
#      python3 tools/nav-search.py build maps/district.osm.pbf maps/addresses.sqlite
#
#  Поиск (проверка):
#      python3 tools/nav-search.py search maps/addresses.sqlite "улица Ленина 5"
#
#  Что кладём в базу:
#    · дома (addr:housenumber на точках и зданиях) — "улица Ленина, 5";
#    · названия улиц (highway с name, без дублей);
#    · города/сёла/районы (place с name);
#    · парки (leisure=park с name).
#
#  База лежит в maps/ (в git не попадает, как и тайлы). Сервер тайлов
#  (tools/tile-server.py) отдаёт её по /search?q=..., приборка спрашивает
#  оттуда при вводе адреса с телефона.
# ============================================================================
import argparse
import math
import os
import re
import sqlite3
import struct
import sys

# pyosmium ставится в проект без root: pip install --target build/pylibs osmium
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))), "build", "pylibs"))

import osmium


def open_db(path, create=False):
    db = sqlite3.connect(path)
    if create:
        db.executescript(
            """
            DROP TABLE IF EXISTS addr;
            DROP TABLE IF EXISTS addr_fts;
            CREATE TABLE addr (
                name TEXT, street TEXT, housenumber TEXT,
                kind TEXT, lat REAL, lon REAL
            );
            CREATE VIRTUAL TABLE addr_fts USING fts5(
                name, street, housenumber,
                content='addr', content_rowid='rowid'
            );
            """
        )
    return db


class Builder(osmium.SimpleHandler):
    def __init__(self, db):
        super().__init__()
        self.db = db
        self.rows = []
        self.seen = set()     # дедуп для улиц/мест/парков
        self.houses = 0
        self.streets = 0

    def _add(self, name, street, housenumber, kind, lat, lon):
        self.rows.append((name, street or "", housenumber or "", kind, lat, lon))

    def _addr(self, tags, lat, lon):
        if "addr:housenumber" not in tags:
            return
        street = tags.get("addr:street") or tags.get("addr:place") or ""
        num = tags.get("addr:housenumber")
        if not street:
            return
        self.houses += 1
        self._add(f"{street}, {num}", street, num, "house", lat, lon)

    def node(self, n):
        t = n.tags
        self._addr(t, n.location.lat, n.location.lon)
        if "name" in t:
            place = t.get("place")
            if place in ("city", "town", "village", "hamlet", "suburb",
                         "quarter", "neighbourhood", "locality", "district"):
                key = ("place", t["name"])
                if key not in self.seen:
                    self.seen.add(key)
                    self._add(t["name"], "", "", "place",
                              n.location.lat, n.location.lon)

    def _centroid(self, w):
        lats = [n.location.lat for n in w.nodes if n.location.valid()]
        lons = [n.location.lon for n in w.nodes if n.location.valid()]
        if not lats:
            return None
        return sum(lats) / len(lats), sum(lons) / len(lons)

    def area(self, a):
        t = a.tags
        name = t.get("name")
        if not name:
            return
        kind = None
        place = t.get("place")
        if place in ("city", "town", "village", "hamlet", "suburb",
                     "quarter", "neighbourhood", "locality", "district",
                     "square"):
            kind = "place"
        elif t.get("leisure") in ("park", "garden"):
            kind = "park"
        elif t.get("tourism") == "attraction":
            kind = "attraction"
        if kind is None:
            return
        key = (kind, name)
        if key in self.seen:
            return
        lats, lons = [], []
        for ring in a.outer_rings():
            for n in ring:
                lats.append(n.lat)
                lons.append(n.lon)
        if not lats:
            return
        self.seen.add(key)
        self._add(name, name if kind == "street" else "", "", kind,
                  sum(lats) / len(lats), sum(lons) / len(lons))

    def way(self, w):
        t = w.tags
        c = self._centroid(w)
        if c is None:
            return
        lat, lon = c
        self._addr(t, lat, lon)
        name = t.get("name")
        if name:
            kind = None
            if "highway" in t and t["highway"] in (
                    "motorway", "trunk", "primary", "secondary", "tertiary",
                    "residential", "service", "unclassified", "pedestrian",
                    "living_street", "footway", "track"):
                kind = "street"
            elif t.get("leisure") == "park":
                kind = "park"
            elif t.get("place") in ("city", "town", "village", "hamlet",
                                    "suburb", "quarter", "neighbourhood",
                                    "locality", "district", "square"):
                kind = "place"
            if kind and ("street" in (kind,) or kind in ("park", "place")):
                key = (kind, name)
                if key not in self.seen:
                    self.seen.add(key)
                    if kind == "street":
                        self.streets += 1
                    self._add(name, name if kind == "street" else "",
                              "", kind, lat, lon)


def build(pbf_path, out_path):
    if not os.path.exists(pbf_path):
        sys.exit(f"нет файла {pbf_path}")
    tmpdir = os.path.join(os.path.dirname(os.path.dirname(
        os.path.abspath(__file__))), "build", "tmp")
    os.makedirs(tmpdir, exist_ok=True)

    db = open_db(out_path, create=True)
    handler = Builder(db)

    # locations=True заодно собирает площади из мультиполигонов (area()):
    # Красная площадь и т. п. в OSM — relations, без этого они не найдутся.
    handler.apply_file(pbf_path, locations=True)

    # Пакетная вставка и построение FTS-индекса.
    db.executemany("insert into addr values (?,?,?,?,?,?)", handler.rows)
    db.execute("insert into addr_fts(addr_fts) values ('rebuild')")
    db.commit()
    total = db.execute("select count(*) from addr").fetchone()[0]
    db.close()
    size = os.path.getsize(out_path) / (1024 * 1024)
    print(f"адреса: {total} записей (домов {handler.houses}, "
          f"улиц {handler.streets}), {size:.0f} МБ → {out_path}")


def _tile_xy(lat, lon, z):
    n = 2 ** z
    return int((lon + 180) / 360 * n), int((1 - math.log(
        math.tan(math.radians(lat)) + 1 / math.cos(math.radians(lat)))
        / math.pi) / 2 * n)


def _varint(b, i):
    r = 0
    s = 0
    while True:
        c = b[i]
        i += 1
        r |= (c & 0x7f) << s
        if not c & 0x80:
            return r, i
        s += 7


def _fields(b):
    i = 0
    out = []
    while i < len(b):
        k, i = _varint(b, i)
        f, wt = k >> 3, k & 7
        if wt == 0:
            v, i = _varint(b, i)
        elif wt == 2:
            ln, i = _varint(b, i)
            v = b[i:i + ln]
            i += ln
        elif wt == 5:
            v = b[i:i + 4]
            i += 4
        else:
            v = b[i:i + 8]
            i += 8
        out.append((f, v, wt))
    return out


def _val(v):
    if not isinstance(v, (bytes, bytearray)):
        return v
    for k, val_, _ in _fields(v):
        try:
            if k == 1:
                return val_.decode("utf-8")
            if k == 2:
                return struct.unpack("<f", val_)[0]
            if k == 3:
                return struct.unpack("<d", val_)[0]
            if k == 7:
                return bool(val_)
            if k in (4, 5, 6):
                return val_ if isinstance(val_, int) else int.from_bytes(val_, "little")
        except Exception:
            return None
    return None


def scan_tiles(db, mbtiles):
    """Дополнить базу названиями из готовых тайлов.

    Planetiler уже собрал POI/площади/улицы из OSM (включая relations),
    поэтому если в addr что-то не попало из pbf, берём отсюда. Быстро:
    разбор 114 тыс. тайлов — пара минут.
    """
    import gzip
    tdb = sqlite3.connect(mbtiles)
    seen = set()
    added = 0
    rows = []
    layers = {"poi": "poi", "place": "place", "park": "park",
              "transportation_name": "street"}
    for z, x, y, data in tdb.execute(
            "select zoom_level, tile_column, tile_row, tile_data from tiles"):
        if data[:2] == b"\x1f\x8b":
            data = gzip.decompress(data)
        scale = 360.0 / (2 ** z)
        # tile_row в mbtiles — TMS (снизу вверх); для широты нужен XYZ.
        y_xyz = (1 << z) - 1 - y
        try:
            for f, v, _ in _fields(data):
                if f != 3:
                    continue
                name = None
                feats = []
                keys = []
                vals = []
                for ff, vv, _ in _fields(v):
                    if ff == 1:
                        name = vv.decode("utf-8")
                    elif ff == 2:
                        feats.append(vv)
                    elif ff == 3:
                        keys.append(vv.decode("utf-8"))
                    elif ff == 4:
                        vals.append(_val(vv))
                kind = layers.get(name)
                if kind is None:
                    continue
                for fb in feats:
                    tags = []
                    geom = b""
                    for k, val_, _ in _fields(fb):
                        if k == 2:
                            arr = []
                            j = 0
                            while j < len(val_):
                                n, j = _varint(val_, j)
                                arr.append(n)
                            tags.extend(arr)
                        elif k == 4:
                            geom = val_
                    props = {keys[tags[i]]: vals[tags[i + 1]]
                             for i in range(0, len(tags) - 1, 2)}
                    nm = props.get("name") or props.get("name:ru") or ""
                    if not nm:
                        continue
                    # первая точка геометрии (DecodeCommand): MoveTo(1) + x,y zigzag
                    if not geom:
                        continue
                    j = 0
                    cmd, j = _varint(geom, j)
                    if cmd >> 3 != 1:
                        continue
                    cx, j = _varint(geom, j)
                    cy, j = _varint(geom, j)
                    px = (cx >> 1) ^ (-(cx & 1))
                    py = (cy >> 1) ^ (-(cy & 1))
                    lon = (x + px / 4096.0) * scale - 180
                    lat = math.degrees(math.atan(math.sinh(math.pi * (
                        1 - 2 * (y_xyz + py / 4096.0) / (2 ** z)))))
                    key = (nm, round(lat, 4), round(lon, 4), kind)
                    if key in seen:
                        continue
                    seen.add(key)
                    rows.append((nm, nm if kind == "street" else "",
                                 "", kind, lat, lon))
                    added += 1
        except Exception:
            continue
    tdb.close()
    db.executemany("insert into addr values (?,?,?,?,?,?)", rows)
    db.execute("insert into addr_fts(addr_fts) values ('rebuild')")
    db.commit()
    print(f"из тайлов добавлено {added} названий")


def fts_query(text):
    toks = re.findall(r"[^\W_]+", text.lower(), re.UNICODE)
    if not toks:
        return None
    return " ".join(f'"{t}"*' for t in toks)


def search(db_path, text, limit=5):
    db = open_db(db_path)
    match = fts_query(text)
    if not match:
        return []
    rows = db.execute(
        "select a.name, a.street, a.housenumber, a.kind, a.lat, a.lon "
        "from addr a where a.rowid in "
        "(select rowid from addr_fts where addr_fts match ?) limit ?",
        (match, limit)).fetchall()
    db.close()
    return rows


def main():
    ap = argparse.ArgumentParser(description="Поиск адреса (SQLite FTS5)")
    sub = ap.add_subparsers(dest="cmd", required=True)

    b = sub.add_parser("build", help="собрать базу из .osm.pbf")
    b.add_argument("pbf")
    b.add_argument("out")

    s = sub.add_parser("search", help="поиск по базе")
    s.add_argument("db")
    s.add_argument("text")

    t = sub.add_parser("tiles", help="дополнить базу названиями из tiles.mbtiles")
    t.add_argument("db")
    t.add_argument("mbtiles")

    args = ap.parse_args()
    if args.cmd == "build":
        build(args.pbf, args.out)
    elif args.cmd == "tiles":
        scan_tiles(open_db(args.db), args.mbtiles)
    else:
        for name, street, num, kind, lat, lon in search(args.db, args.text):
            print(f"[{kind}] {name}  ({lat:.5f}, {lon:.5f})")


if __name__ == "__main__":
    main()
