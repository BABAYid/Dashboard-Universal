#!/usr/bin/env bash
# ============================================================================
#  Сценарий нагрузки на столе (mock-данные, без платы).
#
#  Что делает, пока приборка работает:
#    · каждые ~20 с — событие джойстика (смена экранов/навигация/маршрут),
#      через DASHBOARD_INPUT_DEMO (настоящий путь: кадр 0x530 → разбор);
#    · каждые 15 с — «шторм» WebSocket: 5 параллельных подключений с hello
#      и отключением;
#    · раз в 60 с — смена маршрута (route_handoff) и route_clear;
#    · каждые 3 минуты — потеря GPS на 30 с (гасим gpsd-эмулятор), затем
#      возврат;
#    · каждые 60 с — строка метрик в logs/metrics.csv (tools/metrics.sh).
#
#  Запуск:
#      ./tools/load_test.sh 120        # 120 минут
#      LOAD_WS=10 ./tools/load_test.sh 5
#  (CAN bus-off и перезапуск ESP32 проверяются только на железе.)
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs

MINUTES="${1:-60}"
DURATION=$((MINUTES * 60))
WS_CLIENTS="${LOAD_WS:-5}"

port_open() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }

# --- подготовка: серверы тайлов и маршрутов ---
STARTED=()
cleanup() { for p in "${STARTED[@]:-}"; do kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT

if ! port_open 8090; then
    nohup ./tools/tile-server.py maps/tiles.mbtiles --port 8090 \
          >> logs/tile-server.log 2>&1 & STARTED+=($!)
fi
if ! port_open 8989; then
    nohup build/toolchain/jdk21/bin/java -jar build/toolchain/graphhopper-web.jar \
          server build/gh/config.yml >> logs/graphhopper.log 2>&1 & STARTED+=($!)
fi
for _ in $(seq 1 90); do port_open 8990 && break; sleep 1; done

# gpsd-эмулятор: без него GPS «пропадёт» и останется так — зато потеря
# GPS становится настоящим сценарием (гасим/поднимаем его).
GPS_STARTED=0
if ! port_open 2947; then
    nohup python3 tools/gps_test_server.py > logs/gpsd-test.log 2>&1 &
    GPS_PID=$!; GPS_STARTED=1; STARTED+=($GPS_PID)
fi

# --- последовательность джойстика (настоящий путь через 0x530) ---
# 20 с между событиями: смена режимов панели, вход в навигацию, избранное,
# маршрут, перекрестие, выход. Длину подгоняем под общее время прогона.
events=""
seq="right,right,right,nav,next,press,left,press,back,media,right,right,nav,next,next,press,back,radio"
# Длина списка: событие раз в 20 с (в DASHBOARD_INPUT_DEMO число —
# пауза перед следующим событием в 100 мс, поэтому 200 = 20 с).
count=$(( (DURATION / 20) + 2 ))
i=0
IFS=','; set -- $seq; IFS=' '
while [ "$i" -lt "$count" ]; do
    ev="${!(( i % $# + 1 ))}"
    events+="200,${ev},"
    i=$((i + 1))
done
export DASHBOARD_INPUT_DEMO="20,${events%%,}"

# --- фоновые нагрузки ---
metrics_pid=""
./tools/metrics.sh --interval 60 >> logs/metrics-run.log 2>&1 &
metrics_pid=$!

# Шторм WS: параллельные подключения с hello и отключением.
storm() {
    for _ in $(seq 1 "$WS_CLIENTS"); do
        python3 - "$@" <<'PY' 2>/dev/null || true
import json, sys, time
sys.path.insert(0, 'build/pylibs')
import websocket
try:
    ws = websocket.create_connection("ws://127.0.0.1:8080/ws", timeout=4)
    ws.send(json.dumps({"type": "hello", "role": "media", "version": "1.0", "api": 1}))
    time.sleep(0.3)
    ws.send(json.dumps({"type": "route_handoff", "lat": 55.770, "lon": 37.640,
                        "name": "load"}))
    time.sleep(0.3)
    ws.close()
except Exception:
    pass
PY
    done
}

# Смена маршрута каждые 60 с.
route_churn() {
    python3 tools/send_route_handoff.py --lat 55.770 --lon 37.640 --name "load" >/dev/null 2>&1 || true
    sleep 30
    python3 tools/send_route_handoff.py --clear >/dev/null 2>&1 || true
}

# Потеря GPS: гасим эмулятор на 30 с, затем поднимаем снова.
gps_flap() {
    [ "$GPS_STARTED" -eq 1 ] || return 0
    kill "$GPS_PID" 2>/dev/null || true
    sleep 30
    nohup python3 tools/gps_test_server.py > logs/gpsd-test.log 2>&1 &
    GPS_PID=$!
}

echo "Сценарий: ${MINUTES} мин, приборка в демо-режиме, WS-клиентов: $WS_CLIENTS"
echo "Метрики: logs/metrics.csv (раз в минуту)"

bg=""
( s=0; while [ $s -lt "$DURATION" ]; do storm; sleep 15; s=$((s+15)); done ) & bg+=" $!"
( s=0; while [ $s -lt "$DURATION" ]; do route_churn; s=$((s+90)); done ) & bg+=" $!"
( s=0; while [ $s -lt "$DURATION" ]; do sleep 180; gps_flap; s=$((s+210)); done ) & bg+=" $!"

# Сама приборка — в фоне, с логированием в файл на диске (для разбора).
DASHBOARD_LOG_FILE="$PWD/logs/app.log" \
DASHBOARD_SHOT="${DASHBOARD_SHOT:-}" \
./run.sh --mock --window --shot /tmp/load.png --shot-delay $((DURATION * 1000 + 10000)) \
    >> logs/load-test.log 2>&1 &
app_pid=$!

sleep "$DURATION"
kill "$app_pid" 2>/dev/null || true
kill "$metrics_pid" 2>/dev/null || true
for p in $bg; do kill "$p" 2>/dev/null || true; done
sleep 2

echo
echo "Готово. Артефакты:"
echo "  logs/metrics.csv   — метрики (строка в минуту)"
echo "  logs/app.log       — структурированный лог приборки"
echo "  logs/load-test.log — вывод прибора"
