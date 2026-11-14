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
import os
import re
import sqlite3
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
                                    "locality", "district"):
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

    # Для зданий нужны координаты их точек: pyosmium соберёт их в
    # дисковый index (в памяти держать 100+ млн точек нельзя).
    locations = osmium.NodeLocationsForWays(osmium.index.create_map("flex_mem"))
    handler.apply_file(pbf_path, locations=locations)

    # Пакетная вставка и построение FTS-индекса.
    db.executemany("insert into addr values (?,?,?,?,?,?)", handler.rows)
    db.execute("insert into addr_fts(addr_fts) values ('rebuild')")
    db.commit()
    total = db.execute("select count(*) from addr").fetchone()[0]
    db.close()
    size = os.path.getsize(out_path) / (1024 * 1024)
    print(f"адреса: {total} записей (домов {handler.houses}, "
          f"улиц {handler.streets}), {size:.0f} МБ → {out_path}")


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

    args = ap.parse_args()
    if args.cmd == "build":
        build(args.pbf, args.out)
    else:
        for name, street, num, kind, lat, lon in search(args.db, args.text):
            print(f"[{kind}] {name}  ({lat:.5f}, {lon:.5f})")


if __name__ == "__main__":
    main()
