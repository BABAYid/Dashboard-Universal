#!/usr/bin/env bash
# ============================================================================
#  Сбор метрик приборки в CSV (для 24-часовых прогонов и отчёта).
#
#  Раз в N секунд (по умолчанию 300) пишет строку:
#    ts, iso, app_uptime_s, rss_kb, cpu_pct, threads, temp_max_c,
#    freq_avg_mhz, can_bus_error, can_err_warning, can_err_passive,
#    can_bus_off, can_frames, ws_clients, can_connected, can_frames_delta
#
#  Запуск:
#      ./tools/metrics.sh                    # каждые 5 минут в logs/metrics.csv
#      ./tools/metrics.sh --interval 60      # каждую минуту
#      ./tools/metrics.sh --once             # одна строка (проверка)
#      ./tools/metrics.sh --pid 1234         # метрики конкретного процесса
#
#  Всё читается из /proc и /sys без root. CAN-счётчики — из /proc/net/can/stats
#  (если интерфейс не поднят — нули, строка всё равно пишется).
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs

OUT=logs/metrics.csv
INTERVAL=300
ONCE=0
PID=""

while [ $# -gt 0 ]; do
    case "$1" in
        --interval) INTERVAL="$2"; shift 2 ;;
        --out)      OUT="$2"; shift 2 ;;
        --pid)      PID="$2"; shift 2 ;;
        --once)     ONCE=1; shift ;;
        *) echo "неизвестный ключ: $1" >&2; exit 2 ;;
    esac
done

# Процесс приборки: по имени, если не задан явно
find_pid() {
    if [ -n "$PID" ]; then echo "$PID"; return; fi
    pgrep -x appDashboard | head -1 || true
}

# Значение из /sys/class/thermal: максимум по зонам
temp_max() {
    local max=""
    for f in /sys/class/thermal/thermal_zone*/temp; do
        [ -r "$f" ] || continue
        local v
        v=$(cat "$f" 2>/dev/null || true)
        [ -n "$v" ] || continue
        if [ -z "$max" ] || [ "$v" -gt "$max" ]; then max="$v"; fi
    done
    if [ -n "$max" ]; then awk -v v="$max" 'BEGIN{printf "%.1f", v/1000}'; else echo ""; fi
}

# Средняя текущая частота CPU (кГц → МГц); если cpufreq нет — пусто
freq_avg() {
    local sum=0 n=0
    for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq; do
        [ -r "$f" ] || continue
        local v
        v=$(cat "$f" 2>/dev/null || true)
        [ -n "$v" ] || continue
        sum=$((sum + v)); n=$((n + 1))
    done
    if [ "$n" -gt 0 ]; then awk -v s="$sum" -v n="$n" 'BEGIN{printf "%.0f", s/n/1000}'; else echo ""; fi
}

# CAN-счётчики ошибок из /proc/net/can/stats: bus_error error_warning
# error_passive bus_off ... (по одной строке на счётчик)
can_stat() {
    local key="$1"
    awk -v k="$key" '$1==k {print $2; found=1} END{if(!found) print ""}' \
        /proc/net/can/stats 2>/dev/null || echo ""
}

# Сколько WebSocket-сессий у приборки: из HTTP health (clients) или ss.
ws_clients() {
    local n
    n=$(curl -s -m 2 http://127.0.0.1:8080/api/v1/health 2>/dev/null \
        | python3 -c "import json,sys;print(json.load(sys.stdin).get('clients',''))" 2>/dev/null || true)
    if [ -n "$n" ]; then echo "$n"; return; fi
    ss -tn state established "( sport = :8080 )" 2>/dev/null | awk 'NR>1' | wc -l
}

# Uptime процесса: uptime системы минус starttime процесса (в тиках / HZ).
# Без systime() — mawk её не знает, а Ubuntu ставит mawk.
app_uptime() {
    local pid="$1"
    local start
    start=$(awk '{print $22}' "/proc/$pid/stat" 2>/dev/null || true)
    [ -n "$start" ] || { echo ""; return; }
    local hz sysup
    hz=$(getconf CLK_TCK 2>/dev/null || echo 100)
    sysup=$(cut -d. -f1 /proc/uptime 2>/dev/null || true)
    [ -n "$sysup" ] || { echo ""; return; }
    echo $((sysup - start / hz))
}

rss_kb() { awk '/VmRSS/ {print $2}' "/proc/$1/status" 2>/dev/null || echo ""; }
threads() { awk '/Threads/ {print $2}' "/proc/$1/status" 2>/dev/null || echo ""; }

# CPU% за интервал: дельта utime+stime / (интервал * HZ)
cpu_pct() {
    local pid="$1" prev="$2"
    local ut st now
    ut=$(awk '{print $14}' "/proc/$pid/stat" 2>/dev/null || true)
    st=$(awk '{print $15}' "/proc/$pid/stat" 2>/dev/null || true)
    [ -n "$ut" ] && [ -n "$st" ] || { echo ""; return; }
    now=$((ut + st))
    awk -v n="$now" -v p="$prev" -v s="$INTERVAL" 'BEGIN{printf "%.1f", (n-p)*100/s}' 2>/dev/null \
        || echo ""
}

header="ts,iso,app_uptime_s,rss_kb,cpu_pct,threads,temp_max_c,freq_avg_mhz,can_bus_error,can_err_warning,can_err_passive,can_bus_off,can_frames,ws_clients,can_connected,can_frames_delta"
if [ ! -s "$OUT" ]; then echo "$header" > "$OUT"; fi

pid=$(find_pid)
prev_cpu=""
prev_frames=""

while true; do
    ts=$(date +%s)
    iso=$(date -Iseconds)
    pid=$(find_pid)
    if [ -z "$pid" ]; then
        # Приборка не запущена: пишем строку с пустыми полями, чтобы был виден простой
        echo "$ts,$iso,,,,,,,,,,,," >> "$OUT"
    else
        rss=$(rss_kb "$pid")
        th=$(threads "$pid")
        up=$(app_uptime "$pid")
        cpu=$(cpu_pct "$pid" "${prev_cpu:-0}")
        prev_cpu=$(awk '{print $14+$15}' "/proc/$pid/stat" 2>/dev/null || echo 0)
        temp=$(temp_max)
        freq=$(freq_avg)
        be=$(can_stat bus_error)
        ew=$(can_stat error_warning)
        ep=$(can_stat error_passive)
        bo=$(can_stat bus_off)
        frames=$(curl -s -m 2 http://127.0.0.1:8080/api/v1/health 2>/dev/null \
            | python3 -c "import json,sys;print(json.load(sys.stdin)['can']['frames'])" 2>/dev/null || true)
        fdelta=""
        if [ -n "$frames" ] && [ -n "$prev_frames" ]; then
            fdelta=$((frames - prev_frames))
        fi
        [ -n "$frames" ] && prev_frames="$frames"
        conn=$(curl -s -m 2 http://127.0.0.1:8080/api/v1/health 2>/dev/null \
            | python3 -c "import json,sys;print(json.load(sys.stdin)['can']['connected'])" 2>/dev/null || true)
        ws=$(ws_clients)
        echo "$ts,$iso,$up,$rss,$cpu,$th,$temp,$freq,$be,$ew,$ep,$bo,$frames,$ws,$conn,$fdelta" >> "$OUT"
    fi
    [ "$ONCE" -eq 1 ] && break
    sleep "$INTERVAL"
done
