#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
#  Локальный сервер тайлов из MBTiles (для офлайн-карты приборки).
#
#  Отдаёт то, что ожидает MapLibre:
#      GET /tiles/{z}/{x}/{y}      -> векторный тайл (protobuf, gzip)
#      GET /style.json             -> стиль карты
#      GET /map.html               -> страница карты (кладёт MapView.qml)
#
#  Запуск:
#      ./tools/tile-server.py maps/tiles.mbtiles --port 8090
#
#  Почему на Python: для прототипа хватает стандартной библиотеки (sqlite3),
#  и это можно проверить прямо сейчас, не трогая сборку Qt. Когда карта
#  заработает, тот же маршрут перенесём в QHttpServer на C++.
# ============================================================================
import argparse
import gzip
import json
import os
import sqlite3
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TILE_LOG = {"served": 0, "empty": 0}
DB = None
ADDR = None          # база адресов (SQLite FTS), может отсутствовать
LOCK = threading.Lock()
HERE = os.path.dirname(os.path.abspath(__file__))
MAP_DIR = os.path.join(HERE, "..", "Dashboard", "map")


def open_db(path):
    global DB
    DB = sqlite3.connect(path, check_same_thread=False)
    meta = dict(DB.execute("select name, value from metadata").fetchall())
    print(f"MBTiles: {meta.get('name','?')} | формат {meta.get('format','?')} | "
          f"bounds {meta.get('bounds','?')} | зумы {meta.get('minzoom','?')}–{meta.get('maxzoom','?')}")


def open_addr_db(path):
    """Открыть базу адресов (FTS5) рядом с тайлами, если она собрана."""
    global ADDR
    if not os.path.exists(path):
        print(f"нет базы адресов {path} — поиск отключён "
              f"(соберите tools/nav-search.py build)")
        return
    ADDR = sqlite3.connect(path, check_same_thread=False)
    n = ADDR.execute("select count(*) from addr").fetchone()[0]
    print(f"База адресов: {n} записей")


def search_address(q, limit=5, lat=None, lon=None):
    if ADDR is None or not q:
        return []
    import re
    toks = re.findall(r"[^\W_]+", q.lower(), re.UNICODE)
    if not toks:
        return []
    match = " ".join('\"%s\"*' % t for t in toks)
    # Если известна позиция машины — ближайшие совпадения важнее: иначе
    # «Красная площадь» найдётся в другом городе раньше, чем в Москве.
    if lat is not None and lon is not None:
        rows = ADDR.execute(
            "select a.name, a.street, a.housenumber, a.kind, a.lat, a.lon "
            "from addr a where a.rowid in "
            "(select rowid from addr_fts where addr_fts match ?) "
            "order by (a.lat - ?)*(a.lat - ?) + (a.lon - ?)*(a.lon - ?) "
            "limit ?",
            (match, lat, lat, lon, lon, limit)).fetchall()
    else:
        rows = ADDR.execute(
            "select a.name, a.street, a.housenumber, a.kind, a.lat, a.lon "
            "from addr a where a.rowid in "
            "(select rowid from addr_fts where addr_fts match ?) "
            "order by rank limit ?",
            (match, limit)).fetchall()
    return [{"name": r[0], "street": r[1], "housenumber": r[2],
             "kind": r[3], "lat": r[4], "lon": r[5]} for r in rows]


def tile(z, x, y):
    with LOCK:
        row = DB.execute("select tile_data from tiles where zoom_level=? and tile_column=? and tile_row=?",
                         (z, x, (1 << z) - 1 - y)).fetchone()
    return row[0] if row else None


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, body, ctype):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "max-age=3600")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path.startswith("/tiles/"):
            try:
                z, x, y = [int(v) for v in path[len("/tiles/"):].split("/")[:3]]
            except ValueError:
                return self._send(400, b"bad tile", "text/plain")
            data = tile(z, x, y)
            if data is None:
                TILE_LOG["empty"] += 1
                if TILE_LOG["empty"] == 1:
                    print(f"нет тайла {z}/{x}/{y} (первые запросы: {TILE_LOG})")
                return self._send(204, b"", "application/x-protobuf")
            # В MBTiles тайлы обычно лежат уже сжатыми gzip. MapLibre ждёт
            # либо чистый protobuf, либо сжатый с заголовком Content-Encoding.
            # Заголовок мы не ставили, и карта молча не рисовалась — поэтому
            # распаковываем и отдаём чистый protobuf.
            if data[:2] == b"\x1f\x8b":
                try:
                    data = gzip.decompress(data)
                except OSError:
                    pass
            return self._send(200, data, "application/x-protobuf")

        # Шрифты для подписей улиц: MapLibre просит /fonts/<fontstack>/<range>.pbf
        if path.startswith("/fonts/"):
            parts = path[len("/fonts/"):].split("/")
            if len(parts) == 2 and parts[0] and parts[1].endswith(".pbf"):
                name = os.path.basename(parts[1])
                full = os.path.join(MAP_DIR, "fonts", parts[0], name)
                if os.path.isfile(full):
                    with open(full, "rb") as f:
                        return self._send(200, f.read(), "application/x-protobuf")
            return self._send(404, b"no glyphs", "text/plain")

        if path.startswith("/search"):
            from urllib.parse import parse_qs, urlparse
            qs = parse_qs(urlparse(self.path).query)
            text = (qs.get("q") or [""])[0]
            try:
                limit = max(1, min(20, int((qs.get("limit") or ["5"])[0])))
            except ValueError:
                limit = 5
            def fnum(name):
                try:
                    return float((qs.get(name) or [""])[0])
                except ValueError:
                    return None
            result = search_address(text, limit, fnum("lat"), fnum("lon"))
            body = json.dumps({"query": text, "results": result}).encode("utf-8")
            return self._send(200, body, "application/json")

        if path in ("/style.json", "/style"):
            with open(os.path.join(MAP_DIR, "style.json"), "rb") as f:
                return self._send(200, f.read(), "application/json")

        if path in ("/map.html", "/", "/index.html"):
            with open(os.path.join(MAP_DIR, "index.html"), "rb") as f:
                return self._send(200, f.read(), "text/html; charset=utf-8")

        # статика карты: maplibre-gl.js/.css и всё, что лежит рядом с map.html
        name = os.path.basename(path)
        full = os.path.join(MAP_DIR, name)
        if name and os.path.isfile(full):
            ctype = {
                ".js": "application/javascript; charset=utf-8",
                ".css": "text/css; charset=utf-8",
                ".json": "application/json",
                ".html": "text/html; charset=utf-8",
            }.get(os.path.splitext(name)[1], "application/octet-stream")
            with open(full, "rb") as f:
                return self._send(200, f.read(), ctype)

        self._send(404, b"not found", "text/plain")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mbtiles")
    ap.add_argument("--port", type=int, default=8090)
    args = ap.parse_args()
    if not os.path.exists(args.mbtiles):
        sys.exit(f"нет файла {args.mbtiles} — сначала соберите тайлы")
    open_db(args.mbtiles)
    open_addr_db(os.path.join(os.path.dirname(args.mbtiles) or ".", "addresses.sqlite"))
    srv = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"сервер тайлов: http://127.0.0.1:{args.port}/map.html")
    srv.serve_forever()


if __name__ == "__main__":
    main()
