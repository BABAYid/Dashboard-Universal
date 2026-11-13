#!/usr/bin/env bash
# Собрать тайлы для офлайн-карты (Москва + 100 км, z8-15).
# Запускать ОДИН раз: процессы planetiler не должны работать одновременно.
# Выгрузка OSM — maps/district.osm.pbf (обрезка по bbox, см. nav-clip.py).
set -euo pipefail
cd "$(dirname "$0")/.."

pkill -f planetiler.jar 2>/dev/null && sleep 2 || true
rm -f maps/tiles.mbtiles

echo "Собираю тайлы (Москва + 100 км, z8-15). Это займёт 1-2 часа, окно не закрывать."
echo
build/toolchain/jdk21/bin/java -Xmx3g -jar build/toolchain/planetiler.jar \
  --osm-path=maps/district.osm.pbf --output=maps/tiles.mbtiles \
  --bounds=36.016,54.855,39.218,56.657 --minzoom=8 --maxzoom=15 \
  --force --tmpdir=build/tmp --download_dir=build/toolchain/sources 2>&1 \
  | grep --line-buffered -E "INF \[(osm_pass|archive|sort|water|natural|lake|boundaries)|FINISHED|ERROR|error"

echo
echo "Готово. Размер файла:"
ls -lh maps/tiles.mbtiles
