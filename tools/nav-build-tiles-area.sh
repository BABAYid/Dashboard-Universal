#!/usr/bin/env bash
# ============================================================================
#  Векторные тайлы для одной области (Planetiler → MBTiles).
#
#  Карта приборки собирается по областям: у каждой свой файл, а сервер тайлов
#  (`tools/tile-server.py`) умеет отдавать несколько сразу — тайл берётся из
#  первой базы, где он есть. Так расширять покрытие можно по одной области,
#  не пересобирая всё.
#
#  Использование:
#      ./tools/nav-build-tiles-area.sh mosobl maps/mosobl.osm.pbf 34.8,54.1,40.4,57.1
#      ./tools/nav-build-tiles-area.sh spb    maps/spb.osm.pbf    28.0,58.4,31.8,61.0
#
#  Результат: maps/tiles-<имя>.mbtiles. Запускать ОДИН раз: два planetiler
#  одновременно драться за build/tmp и за память.
#
#  Переменные: MINZOOM/MAXZOOM (по умолчанию 8/15), HEAP (по умолчанию 3g).
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="${1:?имя области, например mosobl или spb}"
PBF="${2:?путь к .osm.pbf}"
BOUNDS="${3:?bbox запад,юг,восток,север}"
MINZOOM="${MINZOOM:-8}"
MAXZOOM="${MAXZOOM:-15}"
HEAP="${HEAP:-3g}"
OUT="maps/tiles-${NAME}.mbtiles"

[ -f "$PBF" ] || { echo "нет $PBF" >&2; exit 1; }
[ -x build/toolchain/jdk21/bin/java ] || { echo "нет JDK 21 в build/toolchain" >&2; exit 1; }
[ -f build/toolchain/planetiler.jar ] || { echo "нет planetiler.jar" >&2; exit 1; }

pkill -f planetiler.jar 2>/dev/null && sleep 2 || true
rm -f "$OUT"
mkdir -p build/tmp

echo "Тайлы «${NAME}»: ${PBF} → ${OUT}"
echo "bbox ${BOUNDS}, зумы ${MINZOOM}–${MAXZOOM}, память ${HEAP}. Это десятки минут."
build/toolchain/jdk21/bin/java -Xmx"${HEAP}" -jar build/toolchain/planetiler.jar \
  --osm-path="$PBF" --output="$OUT" \
  --bounds="$BOUNDS" --minzoom="$MINZOOM" --maxzoom="$MAXZOOM" \
  --force --tmpdir=build/tmp --download_dir=build/toolchain/sources 2>&1 \
  | grep --line-buffered -E "INF \[(osm_pass|archive|sort|water|natural|lake|boundaries)|FINISHED|ERROR|error"

echo
echo "Готово: $OUT"
ls -lh "$OUT"
