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
LOCK = threading.Lock()
HERE = os.path.dirname(os.path.abspath(__file__))
MAP_DIR = os.path.join(HERE, "..", "Dashboard", "map")


def open_db(path):
    global DB
    DB = sqlite3.connect(path, check_same_thread=False)
    meta = dict(DB.execute("select name, value from metadata").fetchall())
    print(f"MBTiles: {meta.get('name','?')} | формат {meta.get('format','?')} | "
          f"bounds {meta.get('bounds','?')} | зумы {meta.get('minzoom','?')}–{meta.get('maxzoom','?')}")


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
    srv = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"сервер тайлов: http://127.0.0.1:{args.port}/map.html")
    srv.serve_forever()


if __name__ == "__main__":
    main()
