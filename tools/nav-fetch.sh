#!/usr/bin/env bash
# ============================================================================
#  Подготовка данных для офлайн-навигации (шаг 1: выгрузка OSM).
#
#  Что делает: качает выгрузку OpenStreetMap под нужную область в maps/.
#  Ничего не публикует и не меняет в системе — просто файл .osm.pbf.
#
#  Использование:
#      ./tools/nav-fetch.sh moscow      # город Москва (~80 МБ, для прототипа)
#      ./tools/nav-fetch.sh district    # Центральный ФО (~1.5 ГБ, для 100 км)
#
#  Дальше: tools/nav-tiles.sh (tilemaker) и Valhalla — см. docs/nav_offline.md.
# ============================================================================
set -euo pipefail

WHAT="${1:-moscow}"
DIR="$(cd "$(dirname "$0")/.." && pwd)/maps"
mkdir -p "$DIR"

case "$WHAT" in
  moscow)
    URL="https://download.bbbike.org/osm/bbbike/Moscow/Moscow.osm.pbf"
    OUT="$DIR/moscow.osm.pbf"
    ;;
  district)
    # Центральный федеральный округ: покрывает Москву + ~300 км вокруг,
    # из него потом вырезается наш bbox (osmium extract)
    URL="https://download.geofabrik.de/russia/central-fed-district-latest.osm.pbf"
    OUT="$DIR/central-fed-district.osm.pbf"
    ;;
  *)
    echo "Неизвестный набор: $WHAT (moscow|district)" >&2
    exit 1
    ;;
esac

if [ -f "$OUT" ]; then
    echo "Уже есть: $OUT ($(du -h "$OUT" | cut -f1))"
    exit 0
fi

echo "Качаю $URL"
curl -L --fail --progress-bar -o "$OUT.part" "$URL"
mv "$OUT.part" "$OUT"
echo "Готово: $OUT ($(du -h "$OUT" | cut -f1))"

# Наш bbox: Москва + 100 км
cat <<'TXT'

Если нужен ровно наш прямоугольник (54.855..56.657 N, 36.016..39.218 E),
вырежьте его osmium-ом:

    osmium extract -b 36.016,54.855,39.218,56.657 \
        maps/central-fed-district.osm.pbf -o maps/nav-box.osm.pbf

TXT
