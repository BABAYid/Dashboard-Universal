#!/usr/bin/env bash
# ============================================================================
#  Склейка OSM-выгрузок для GraphHopper (osmium merge).
#
#  Зачем: GraphHopper читает ровно один `datareader.file`, а маршруты нужны
#  в нескольких областях (Центральный ФО + Санкт-Петербург). Округа не
#  пересекаются, и osmium просто складывает элементы.
#
#  Почему osmium, а не pyosmium: PBF требует порядок «все узлы → все пути →
#  все отношения». Склейка «файл за файлом» на pyosmium даёт невалидный файл
#  (GraphHopper: «way elements must be located before relation elements»),
#  а честная трёхпроходная склейка 124 млн узлов на Python шла бы часами.
#  osmium делает это за минуту C++-кодом.
#
#  ВАЖНО: выгрузки не должны пересекаться по территории. У границ округов
#  (Тверь/Новгород, Псков) есть общие узлы пограничных путей — osmium merge
#  на них падает с «Possibly duplicate OSM node ID». Лечится обрезкой области
#  по bbox: `osmium extract -b west,south,east,north` (см. nav-extract.sh).
#
#  Использование:
#      ./tools/nav-union.sh maps/routes.osm.pbf maps/district.osm.pbf maps/spb.osm.pbf
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:?укажите выходной .osm.pbf}"
shift
[ $# -ge 2 ] || { echo "нужно минимум два входных файла: $*" >&2; exit 1; }
for f in "$@"; do
    [ -f "$f" ] || { echo "нет файла $f" >&2; exit 1; }
done

if [ ! -f tools/osmium-env.sh ]; then
    echo "osmium не установлен локально — запускаю tools/osmium-bootstrap.sh"
    ./tools/osmium-bootstrap.sh
fi
# shellcheck disable=SC1091
. tools/osmium-env.sh

echo "Склеиваю: $* → $OUT"
osmium merge --overwrite -o "$OUT" "$@"
echo
ls -lh "$OUT"
