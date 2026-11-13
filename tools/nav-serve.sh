#!/usr/bin/env bash
# Запустить локальный сервер карты и открыть её в браузере.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -s maps/tiles.mbtiles ]; then
  echo "Тайлов нет: сначала запустите ./tools/nav-build-tiles.sh" >&2
  exit 1
fi

echo "Карта: http://127.0.0.1:8090/map.html"
echo "Остановить: Ctrl+C"
( sleep 2; xdg-open "http://127.0.0.1:8090/map.html" >/dev/null 2>&1 || true ) &
exec ./tools/tile-server.py maps/tiles.mbtiles --port 8090
