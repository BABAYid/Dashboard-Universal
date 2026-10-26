#!/usr/bin/env python3
"""Тестовый издатель «что играет» для проверки приборки без Android-блока.

Приборка (MediaBackend) раз в секунду спрашивает
    GET http://<адрес>:8080/api/media
и получает маленький JSON. Этот скрипт отдаёт его и меняет треки по кругу,
чтобы виджет в центральной панели было видно вживую.

Запуск:
    python3 tools/media_test_server.py            # порт 8080
    python3 tools/media_test_server.py 9090       # другой порт

Проверить руками:
    curl http://127.0.0.1:8080/api/media

На приборке адрес задаётся в QSettings (ключ media/url), либо по умолчанию
слушается 127.0.0.1:8080.
"""

import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# Список воспроизведения: разные источники, чтобы проверить все три вида
# подписи (FM / Bluetooth / USB) и состояние паузы.
PLAYLIST = [
    {"source": "fm",  "station": "Русское Радио", "title": "Кавер-версия",
     "artist": "The Hatters", "duration": 210},
    {"source": "bt",  "station": "", "title": "Highway to Hell",
     "artist": "AC/DC", "duration": 208},
    {"source": "usb", "station": "", "title": "Группа крови",
     "artist": "Кино", "duration": 260},
]

# Сколько секунд держать один трек до перехода к следующему.
TRACK_SECONDS = 45
START = time.time()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):                       # noqa: N802 (имя задано базовым классом)
        if self.path.split("?")[0] != "/api/media":
            self.send_error(404, "unknown path")
            return

        elapsed = time.time() - START
        index = int(elapsed / TRACK_SECONDS) % len(PLAYLIST)
        track = PLAYLIST[index]
        position = int(elapsed) % TRACK_SECONDS

        # На третьем треке показываем паузу — проверяем, что виджет это видит.
        playing = track["source"] != "usb"

        payload = {
            "source": track["source"],
            "station": track["station"],
            "title": track["title"],
            "artist": track["artist"],
            "playing": playing,
            "position": position,
            "duration": track["duration"],
            "art": "",
        }
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")

        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):       # тише: раз в секунду — это много
        pass


def main() -> int:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"Медиа-издатель: http://127.0.0.1:{port}/api/media "
          f"(трек меняется каждые {TRACK_SECONDS} с)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nостановлено")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
