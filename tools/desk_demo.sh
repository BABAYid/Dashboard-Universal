#!/usr/bin/env bash
# ============================================================================
#  Проверка на столе: поднимает сервер тайлов (:8090) и GraphHopper (:8989),
#  если их ещё нет, и запускает приборку в демо-режиме.
#
#  Использование:
#      ./tools/desk_demo.sh                 # F6 — навигация с маршрутом до «Дома»
#      DASHBOARD_INPUT_DEMO="100,nav" ./tools/desk_demo.sh
#      ./tools/desk_demo.sh --shot /tmp/x.png --shot-delay 15000
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs

port_open() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }

STARTED=()
cleanup() { for p in "${STARTED[@]:-}"; do kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT

if ! port_open 8090; then
    echo "Стартую сервер тайлов :8090 (лог logs/tile-server.log)"
    nohup ./tools/tile-server.py maps/tiles.mbtiles --port 8090 \
          >> logs/tile-server.log 2>&1 &
    STARTED+=($!)
fi
if ! port_open 8989; then
    echo "Стартую GraphHopper :8989 (лог logs/graphhopper.log)"
    nohup build/toolchain/jdk21/bin/java -jar build/toolchain/graphhopper-web.jar \
          server build/gh/config.yml >> logs/graphhopper.log 2>&1 &
    STARTED+=($!)
fi

wait_port() {
    local port=$1
    for _ in $(seq 1 90); do
        port_open "$port" && return 0
        sleep 1
    done
    return 1
}
wait_port 8090 || { echo "тайлы :8090 не поднялись — см. logs/tile-server.log" >&2; exit 1; }
wait_port 8989 || { echo "GraphHopper :8989 не поднялся — см. logs/graphhopper.log" >&2; exit 1; }
echo "тайлы :8090 ок, маршруты :8989 ок"

exec ./run.sh --mock --window "$@"
