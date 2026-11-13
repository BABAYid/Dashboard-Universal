#!/usr/bin/env bash
# Поднять офлайн-маршрутизатор GraphHopper для приборки.
#
# Карта маршрутов — те же данных OSM, что и тайлы (maps/district.osm.pbf).
# Первый запуск строит граф (~10 минут) и кладёт его в maps/graph-cache,
# дальше старт занимает секунды.
#
# Приборка ходит на http://127.0.0.1:8989/route (см. RouteService.qml),
# так что сервер нужно держать запущенным, пока идёт навигация.
set -euo pipefail
cd "$(dirname "$0")/.."

JAR=build/toolchain/graphhopper-web.jar
JAVA=build/toolchain/jdk21/bin/java
CONFIG=build/gh/config.yml

[ -x "$JAVA" ]   || { echo "нет $JAVA (JDK 21 в build/toolchain)" >&2; exit 1; }
[ -f "$JAR" ]    || { echo "нет $JAR" >&2; exit 1; }
[ -f "$CONFIG" ] || { echo "нет $CONFIG" >&2; exit 1; }
[ -f maps/district.osm.pbf ] || { echo "нет maps/district.osm.pbf (см. tools/nav-fetch.sh)" >&2; exit 1; }

mkdir -p logs
echo "Маршруты: http://127.0.0.1:8989/route"
echo "Лог:      logs/graphhopper.log"
echo "Остановить: Ctrl+C"

exec "$JAVA" -jar "$JAR" server "$CONFIG" >> logs/graphhopper.log 2>&1
