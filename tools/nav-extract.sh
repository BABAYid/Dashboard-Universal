#!/usr/bin/env bash
# ============================================================================
#  Обрезка OSM-выгрузки по прямоугольнику (osmium extract).
#
#  Один проход C++, минута на выгрузку в сотни мегабайт. Узор «обрезка области»
#  нужен и для тайлов (хотя Planetiler умеет `--bounds` сам), и для склейки:
#  у выгрузок соседних округов есть общие узлы пограничных путей, и
#  `osmium merge` на них падает («Possibly duplicate OSM node ID»). Обрезка
#  по bbox убирает пересечение.
#
#  Использование:
#      ./tools/nav-extract.sh maps/nw-fed.osm.pbf maps/spb.osm.pbf 28.0,58.4,31.8,61.0
#
#  Если osmium поставить нельзя — остаётся `tools/nav-clip.py` на pyosmium
#  (медленнее и требовательнее к памяти, но без внешних бинарников).
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="${1:?входной .osm.pbf}"
DST="${2:?выходной .osm.pbf}"
BBOX="${3:?bbox запад,юг,восток,север (lon,lat)}"

[ -f "$SRC" ] || { echo "нет файла $SRC" >&2; exit 1; }

if [ ! -f tools/osmium-env.sh ]; then
    echo "osmium не установлен локально — запускаю tools/osmium-bootstrap.sh"
    ./tools/osmium-bootstrap.sh
fi
# shellcheck disable=SC1091
. tools/osmium-env.sh

echo "Обрезаю $SRC по bbox $BBOX → $DST"
osmium extract -b "$BBOX" "$SRC" -o "$DST" --overwrite
echo
ls -lh "$DST"
