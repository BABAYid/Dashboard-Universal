#!/usr/bin/env bash
# Запустить локальный сервер карты и открыть её в браузере.
set -euo pipefail
cd "$(dirname "$0")/.."

# Карта собирается по областям отдельными файлами (см. nav-build-tiles.sh):
# Московская область и Санкт-Петербург. Сервер тайлов умеет несколько сразу.
TILES=()
for f in maps/tiles-mosobl.mbtiles maps/tiles-spb.mbtiles maps/tiles.mbtiles; do
  [ -s "$f" ] && TILES+=("$f")
done
if [ ${#TILES[@]} -eq 0 ]; then
  echo "Тайлов нет: сначала запустите ./tools/nav-build-tiles.sh" >&2
  exit 1
fi
echo "Тайлы: ${TILES[*]}"

echo "Карта: http://127.0.0.1:8090/map.html"
echo "Остановить: Ctrl+C"
( sleep 2; xdg-open "http://127.0.0.1:8090/map.html" >/dev/null 2>&1 || true ) &
exec ./tools/tile-server.py "${TILES[@]}" --port 8090
