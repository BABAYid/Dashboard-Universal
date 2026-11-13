#!/usr/bin/env bash
# Собрать тайлы для офлайн-карты (Москва + окрестности, z9-13).
# Запускать ОДИН раз: процессы planetiler не должны работать одновременно.
set -euo pipefail
cd "$(dirname "$0")/.."

pkill -f planetiler.jar 2>/dev/null && sleep 2 || true
rm -f maps/tiles.mbtiles

echo "Собираю тайлы. Это займёт 10-20 минут, окно не закрывать."
echo
build/toolchain/jdk21/bin/java -Xmx3g -jar build/toolchain/planetiler.jar \
  --osm-path=maps/district.osm.pbf --output=maps/tiles.mbtiles \
  --bounds=37.30,55.55,37.95,55.95 --minzoom=9 --maxzoom=13 \
  --force --tmpdir=build/tmp --download_dir=build/toolchain/sources 2>&1 \
  | grep --line-buffered -E "INF \[(osm_pass|archive|sort|water|natural|lake|boundaries)|FINISHED|ERROR|error"

echo
echo "Готово. Размер файла:"
ls -lh maps/tiles.mbtiles
