#!/usr/bin/env bash
# ============================================================================
#  run.sh — запуск приборки из терминала, с короткими флагами.
#
#  Просто и без сюрпризов: собирает (если нужно) и запускает ./build/appDashboard,
#  подставляя нужные переменные окружения. Все ключи — ниже в --help.
#
#  Примеры:
#    ./run.sh                       # реальный CAN с can0, полный экран
#    ./run.sh --window              # оконный режим (для отладки на столе)
#    ./run.sh --mock                # демо: данные выдумываются, CAN не нужен
#    ./run.sh --mock --city 56.8052,60.6512   # демо-маршрут в своём городе
#    ./run.sh --mock --demo-camera 60         # сразу показать камеру впереди
#    ./run.sh --can can1 --window   # другой интерфейс
#    ./run.sh --shot /tmp/dash.png  # снимок экрана и выход (без монитора)
#
#  Переменные окружения, которые понимает сама приборка, тоже можно задавать
#  напрямую — скрипт их не перетирает, а только дополняет:
#    DASHBOARD_SHOT, DASHBOARD_SHOT_DELAY, DASHBOARD_DEMO_CAMERA,
#    DASHBOARD_DEMO_CAMERA_TYPE, DASHBOARD_MOCK_LAT, DASHBOARD_MOCK_LON,
#    DASHBOARD_SPEEDCAM, QT_LOGGING_RULES
# ============================================================================
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BIN="$ROOT/build/appDashboard"

ARGS=()
BUILD=0
FULLSCREEN=1

usage() {
    cat <<'EOF'
Запуск приборки из терминала.

  ./run.sh [ключи]

Ключи:
  --mock                 демо-режим: данные генерируются, CAN не нужен
  --can IFACE            интерфейс SocketCAN (по умолчанию can0)
  --window               оконный режим (по умолчанию полный экран)
  --fullscreen           полный экран (по умолчанию и так он)
  --no-3d                без 3D-заставки при старте (слабое железо)
  --build                пересобрать перед запуском
  --shot PATH            снять окно в файл и выйти (нужен --mock или CAN)
  --shot-delay MS        задержка снимка (по умолчанию 3000)
  --demo-camera [КМЧ]    включить демо-камеру в 420 м впереди (по умолчанию 60)
  --demo-type КОД        тип демо-точки: 1 камера, 102 неровность, 22 переход…
  --city LAT,LON         перенести демо-маршрут в свой город
  --speedcam PATH        файл базы камер (по умолчанию ищется автоматически)
  -h, --help             эта справка

Примеры:
  ./run.sh                                  # в машине: CAN can0, полный экран
  ./run.sh --window --mock                  # на столе: окно и демо-данные
  ./run.sh --mock --city 55.7520,37.6175    # Москва
  ./run.sh --mock --demo-camera 20 --demo-type 102
  ./run.sh --shot /tmp/dash.png --mock      # снимок для проверки без монитора
EOF
}

# Значение ключа вида «--flag ЗНАЧЕНИЕ» с проверкой, что оно есть.
need_value() {
    if [ $# -lt 2 ] || [ -z "${2:-}" ]; then
        echo "Ключ $1 требует значение (см. --help)" >&2
        exit 2
    fi
}

while [ $# -gt 0 ]; do
    case "$1" in
        --mock)        ARGS+=(--mock); shift ;;
        --can)         need_value "$@"; ARGS+=(--can "$2"); shift 2 ;;
        --window)      FULLSCREEN=0; shift ;;
        --fullscreen)  FULLSCREEN=1; shift ;;
        --no-3d)       ARGS+=(--no-3d); shift ;;
        --build)       BUILD=1; shift ;;
        --shot)        need_value "$@"; export DASHBOARD_SHOT="$2"; shift 2 ;;
        --shot-delay)  need_value "$@"; export DASHBOARD_SHOT_DELAY="$2"; shift 2 ;;
        --demo-camera)
            # значение необязательное: следующее слово — число, иначе 60
            if [ $# -ge 2 ] && [[ "${2:-}" =~ ^[0-9]+$ ]]; then
                export DASHBOARD_DEMO_CAMERA="$2"; shift 2
            else
                export DASHBOARD_DEMO_CAMERA=60; shift
            fi ;;
        --demo-type)   need_value "$@"; export DASHBOARD_DEMO_CAMERA_TYPE="$2"; shift 2 ;;
        --city)
            need_value "$@"
            lat="${2%%,*}"; lon="${2##*,}"
            if [ -z "$lat" ] || [ -z "$lon" ] || [ "$lat" = "$lon" ]; then
                echo "Ключ --city ждёт «ШИРОТА,ДОЛГОТА», например 55.7520,37.6175" >&2
                exit 2
            fi
            export DASHBOARD_MOCK_LAT="$lat" DASHBOARD_MOCK_LON="$lon"; shift 2 ;;
        --speedcam)    need_value "$@"; export DASHBOARD_SPEEDCAM="$2"; shift 2 ;;
        -h|--help)     usage; exit 0 ;;
        *) echo "Неизвестный ключ: $1 (см. --help)" >&2; exit 2 ;;
    esac
done

if [ ! -x "$BIN" ] || [ "$BUILD" -eq 1 ]; then
    echo "Сборка приборки…"
    cmake -S "$ROOT/Dashboard" -B "$ROOT/build" -DCMAKE_BUILD_TYPE=Release >/dev/null
    cmake --build "$ROOT/build" -j"$(nproc)"
fi

[ -x "$BIN" ] || { echo "Не собралось: нет $BIN" >&2; exit 1; }

if [ "$FULLSCREEN" -eq 1 ]; then
    ARGS+=(--fullscreen)
fi

# Короткая шпаргалка в консоль: что сейчас запускаем.
echo "Запуск: $BIN ${ARGS[*]:-}"
[ -n "${DASHBOARD_SHOT:-}" ] && echo "  снимок: ${DASHBOARD_SHOT} через ${DASHBOARD_SHOT_DELAY:-3000} мс"
[ -n "${DASHBOARD_DEMO_CAMERA:-}" ] && echo "  демо-камера: ${DASHBOARD_DEMO_CAMERA} км/ч, тип ${DASHBOARD_DEMO_CAMERA_TYPE:-1}"
[ -n "${DASHBOARD_MOCK_LAT:-}" ] && echo "  демо-город: ${DASHBOARD_MOCK_LAT}, ${DASHBOARD_MOCK_LON:-}"
[ -n "${DASHBOARD_SPEEDCAM:-}" ] && echo "  база камер: ${DASHBOARD_SPEEDCAM}"

exec "$BIN" "${ARGS[@]}"
