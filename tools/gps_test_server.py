#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
#  Тестовый gpsd для приборки: отдаёт тот же JSON-протокол по TCP, что и
#  настоящий gpsd (порт 2947). Нужен, пока USB-приёмник не приехал: GpsBackend
#  в приборке подключается к нему без каких-либо изменений.
#
#  Запуск:
#      python3 tools/gps_test_server.py            # 127.0.0.1:2947
#      python3 tools/gps_test_server.py --port 2948
#
#  Что отдаёт (10 Гц TPV + 1 Гц SKY), как настоящий gpsd:
#      {"class":"TPV","device":"/dev/ttyUSB0","mode":3,"time":"...",
#       "lat":55.7558,"lon":37.6173,"track":41.5,"speed":18.0,"eph":3.2}
#      {"class":"SKY","device":"/dev/ttyUSB0","nSat":9,"uSat":7,"hdop":0.8,
#       "satellites":[...]}
#
#  Машина едет по кругу вдоль демо-маршрута приборки (Москва, центр).
# ============================================================================
import argparse
import json
import math
import socketserver
import sys
import threading
import time
from datetime import datetime, timezone

# Демо-трек из Dashboard/Main.qml — чтобы на столе карта вела себя так же,
# как в демо-режиме приборки.
TRACK = [
    (55.7558, 37.6173), (55.7570, 37.6185), (55.7583, 37.6198),
    (55.7596, 37.6212), (55.7608, 37.6228), (55.7619, 37.6245),
    (55.7628, 37.6263), (55.7636, 37.6281), (55.7643, 37.6300),
    (55.7649, 37.6319),
]

SPEED_MS = 18.0        # 65 км/ч — как routeSpeed в демо-приборке
TPV_HZ = 10            # u-blox M10 умеет 10 Гц

LAT_M = 111320.0


def distance_m(lat1, lon1, lat2, lon2):
    r = 6371000.0
    rad = math.pi / 180.0
    dlat = (lat2 - lat1) * rad
    dlon = (lon2 - lon1) * rad
    a = math.sin(dlat / 2) ** 2 + math.cos(lat1 * rad) * math.cos(lat2 * rad) * math.sin(dlon / 2) ** 2
    return 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def bearing(lat1, lon1, lat2, lon2):
    rad = math.pi / 180.0
    dlon = (lon2 - lon1) * rad
    y = math.sin(dlon) * math.cos(lat2 * rad)
    x = math.cos(lat1 * rad) * math.sin(lat2 * rad) - math.sin(lat1 * rad) * math.cos(lat2 * rad) * math.cos(dlon)
    return (math.degrees(math.atan2(y, x)) + 360.0) % 360.0


class Track:
    """Положение на замкнутом треке по пройденному расстоянию."""

    def __init__(self, points):
        self.points = points
        self.segs = []
        total = 0.0
        for i in range(1, len(points)):
            d = distance_m(points[i - 1][0], points[i - 1][1],
                           points[i][0], points[i][1])
            self.segs.append(d)
            total += d
        # замыкаем круг
        d = distance_m(points[-1][0], points[-1][1], points[0][0], points[0][1])
        self.segs.append(d)
        self.total = total + d
        self.dist = 0.0

    def advance(self, dt):
        self.dist = (self.dist + SPEED_MS * dt) % self.total
        acc = 0.0
        n = len(self.points)
        for k, seg in enumerate(self.segs):
            if acc + seg >= self.dist:
                f = (self.dist - acc) / seg if seg > 0 else 0.0
                a = self.points[k]
                b = self.points[(k + 1) % n]
                lat = a[0] + (b[0] - a[0]) * f
                lon = a[1] + (b[1] - a[1]) * f
                return lat, lon, bearing(a[0], a[1], b[0], b[1])
            acc += seg
        lat, lon = self.points[0]
        return lat, lon, bearing(self.points[0][0], self.points[0][1],
                                 self.points[1][0], self.points[1][1])


LOCK = threading.Lock()
STATE = {"track": Track(TRACK), "speed": SPEED_MS, "mode": 3}


class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        sock = self.request
        sock.settimeout(5.0)
        # Включаем поток данных сразу: настоящий gpsd ждёт "?WATCH", но
        # для теста достаточно и этого — GpsBackend сам пришлёт WATCH.
        interval = 1.0 / TPV_HZ
        next_sky = 0.0
        last = time.monotonic()
        try:
            while True:
                now = time.monotonic()
                dt = now - last
                last = now
                with LOCK:
                    track = STATE["track"]
                    lat, lon, course = track.advance(dt)
                tpv = {
                    "class": "TPV",
                    "device": "/dev/ttyUSB0",
                    "mode": STATE["mode"],
                    "time": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z",
                    "lat": round(lat, 7),
                    "lon": round(lon, 7),
                    "track": round(course, 2),
                    "speed": round(STATE["speed"], 3),
                    "eph": 3.2, "epv": 5.4,
                }
                self._send(json.dumps(tpv))
                if now >= next_sky:
                    next_sky = now + 1.0
                    sky = {
                        "class": "SKY",
                        "device": "/dev/ttyUSB0",
                        "nSat": 9, "uSat": 7, "hdop": 0.8,
                        "satellites": [
                            {"PRN": i, "el": 45 - i, "az": 30 * i, "used": i % 2 == 0}
                            for i in range(1, 10)
                        ],
                    }
                    self._send(json.dumps(sky))
                time.sleep(interval)
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass

    def _send(self, text):
        self.request.sendall((text + "\n").encode("utf-8"))


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    ap = argparse.ArgumentParser(description="Тестовый gpsd для приборки (JSON по TCP)")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=2947)
    args = ap.parse_args()

    srv = Server((args.host, args.port), Handler)
    print(f"Тестовый gpsd: {args.host}:{args.port} "
          f"(10 Гц TPV, {SPEED_MS:.0f} м/с, демо-трек Москвы)")
    print("Остановить: Ctrl+C")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nОстановлен")
        srv.server_close()


if __name__ == "__main__":
    sys.exit(main())
