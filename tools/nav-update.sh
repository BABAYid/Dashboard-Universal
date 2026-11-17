#!/usr/bin/env bash
# ============================================================================
#  Обновление карт и маршрутов (раз в N месяцев, на ПК, как в пайплайне).
#
#  1) свежая выгрузка OSM (Geofabrik central-fed-district)
#  2) векторные тайлы z8–15 (Planetiler) → maps/tiles.mbtiles
#  3) граф маршрутов GraphHopper → maps/graph-cache
#  4) база адресов SQLite FTS → maps/addresses.sqlite
#
#  После обновления серверы (tile-server, GraphHopper) надо перезапустить:
#  они держат старые файлы открытыми.
#
#  Полный прогон — 1.5–2 часа, из них основное — выгрузка и сборка тайлов.
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs

echo "1/4 Выгрузка OSM (Geofabrik, ~1.5 ГБ)…"
./tools/nav-fetch.sh district

echo "2/4 Тайлы z8–15 (15–30 минут)…"
./tools/nav-build-tiles.sh

echo "3/4 Граф GraphHopper (5–15 минут)…"
rm -rf maps/graph-cache
build/toolchain/jdk21/bin/java \
    -jar build/toolchain/graphhopper-web.jar import build/gh/config.yml \
    >> logs/graphhopper.log 2>&1

echo "4/4 База адресов (40–50 минут)…"
python3 tools/nav-search.py build maps/district.osm.pbf maps/addresses.sqlite
python3 tools/nav-search.py tiles maps/addresses.sqlite maps/tiles.mbtiles

echo
echo "Готово. Обновлены maps/tiles.mbtiles и maps/addresses.sqlite."
echo "Перезапустите серверы: ./tools/nav-serve.sh и ./tools/nav-route.sh"
ls -lh maps/tiles.mbtiles maps/addresses.sqlite
