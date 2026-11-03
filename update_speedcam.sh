#!/usr/bin/env bash
# ============================================================================
#  update_speedcam.sh — обновление базы камер (Smart Driver) для приборки.
#
#  Что делает:
#    1) скачивает свежий speedcam.txt (iGO-формат OpenSpeedcam);
#    2) проверяет, что это действительно база камер, а не страница ошибки;
#    3) атомарно подменяет файл в Dashboard/assets/speedcam/ (старый — в .bak);
#    4) пишет в лог дату, источник, число строк, размер и результат.
#
#  ВАЖНО ПРО ИСТОЧНИК.
#  Сайт openspeedcam.net — свободно редактируемая база, а её сервис экспорта
#  закрыт авторизацией: GET https://openspeedcam.net/api/export/history
#  отвечает 401 Unauthorized. Готовые сборки в формате speedcam.txt сам
#  OpenSpeedcam выкладывает только ссылками на сторонние зеркала
#  (страница «Полезное → Готовые сборки»). Поэтому скрипт НЕ полагается на
#  «магический» публичный URL, а умеет три способа получить файл:
#
#    A. Готовый файл с диска (--file /path/speedcam.txt) — скачали вручную
#       или на ПК, скрипт просто ставит его на место. Самый надёжный способ.
#    B. Личная ссылка экспорта с openspeedcam.net (--url ...) — на сайте
#       после входа в «Экспорт» выбираете страну/формат iGO и копируете
#       ссылку на файл. Ссылка (и cookie, если нужна авторизация) хранится
#       в speedcam.conf рядом со скриптом либо в /etc/dashboard-speedcam.conf.
#    C. Любое публичное зеркало с прямым speedcam.txt / speedcam.zip
#       (--url ...), которое вы считаете доверенным.
#
#  Примеры:
#    ./update_speedcam.sh --file ~/Downloads/speedcam.txt
#    ./update_speedcam.sh --url "https://example.org/speedcam.zip"
#    SPEEDCAM_COOKIE="PHPSESSID=..." ./update_speedcam.sh --url "https://openspeedcam.net/api/export/..."
#    ./update_speedcam.sh --check          # только проверить текущий файл
#    ./update_speedcam.sh --dry-run        # скачать и проверить, не заменять
#
#  Коды возврата: 0 — успех (или --check: файл валиден), 1 — ошибка,
#                 2 — не задан источник, 3 — файл не похож на базу камер.
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename -- "$0")"

# --- пути по умолчанию -------------------------------------------------------
# В репозитории база лежит рядом с приложением: Dashboard/assets/speedcam/.
# На устройстве (nanoPC-T6) тот же путь, если приборка запускается из репозитория;
# иначе задайте DEST в speedcam.conf или через --dest.
DEFAULT_DEST="${SCRIPT_DIR}/Dashboard/assets/speedcam/speedcam.txt"
DEFAULT_LOG="${XDG_STATE_HOME:-$HOME/.local/state}/audi-dashboard/speedcam-update.log"

# Конфиг: сначала рядом со скриптом, потом общесистемный. Формат — KEY=VALUE.
CONFIG_CANDIDATES=(
    "${SCRIPT_DIR}/speedcam.conf"
    "/etc/dashboard-speedcam.conf"
)

# Значения по умолчанию (перекрываются конфигом, окружением и аргументами)
URLS=()
COOKIE="${SPEEDCAM_COOKIE:-}"
DEST="${SPEEDCAM_DEST:-$DEFAULT_DEST}"
LOG_FILE="${SPEEDCAM_LOG:-$DEFAULT_LOG}"
MIN_LINES=100          # меньше — считаем, что скачалось что-то не то
MAX_AGE_DAYS=30        # предупреждение «база давно не обновлялась»
TIMEOUT=120
RETRIES=3
UNZIP=1
DRY_RUN=0
QUIET=0
CHECK_ONLY=0
FILE_SRC=""

usage() {
    sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    echo
    echo "Аргументы:"
    echo "  --url URL        источник (можно повторять; .txt, .gz, .zip)"
    echo "  --file PATH      взять уже скачанный файл с диска"
    echo "  --dest PATH      куда положить базу (по умолчанию $DEFAULT_DEST)"
    echo "  --log PATH       файл лога (по умолчанию $DEFAULT_LOG)"
    echo "  --min-lines N    минимум строк с координатами (по умолчанию $MIN_LINES)"
    echo "  --no-unpack      не распаковывать .gz/.zip, требовать чистый .txt"
    echo "  --check          ничего не скачивать: проверить текущий файл и выйти"
    echo "  --dry-run        скачать и проверить, но не заменять файл"
    echo "  --quiet          писать только в лог"
    echo "  -h, --help       эта справка"
}

log()  { printf '%s\n' "$*"; }
info() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }

# --- разбор аргументов -------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --url)        URLS+=("${2:?--url требует значение}"); shift 2 ;;
        --file)       FILE_SRC="${2:?--file требует значение}"; shift 2 ;;
        --dest)       DEST="${2:?--dest требует значение}"; shift 2 ;;
        --log)        LOG_FILE="${2:?--log требует значение}"; shift 2 ;;
        --min-lines)  MIN_LINES="${2:?--min-lines требует значение}"; shift 2 ;;
        --no-unpack)  UNZIP=0; shift ;;
        --check)      CHECK_ONLY=1; shift ;;
        --dry-run)    DRY_RUN=1; shift ;;
        --quiet)      QUIET=1; shift ;;
        -h|--help)    usage; exit 0 ;;
        *) echo "Неизвестный аргумент: $1" >&2; usage >&2; exit 2 ;;
    esac
done

# --- конфиг ------------------------------------------------------------------
for cfg in "${CONFIG_CANDIDATES[@]}"; do
    [ -r "$cfg" ] || continue
    # shellcheck disable=SC1090
    . "$cfg"
    [ -n "${SPEEDCAM_URL:-}" ] && URLS+=("$SPEEDCAM_URL")
    [ -n "${SPEEDCAM_COOKIE:-}" ] && COOKIE="$SPEEDCAM_COOKIE"
    [ -n "${SPEEDCAM_DEST:-}" ] && DEST="$SPEEDCAM_DEST"
    break
done

mkdir -p "$(dirname -- "$LOG_FILE")" 2>/dev/null || true

# Пишем в лог и одновременно в stdout (stdout забирает systemd → journalctl).
run_log() {
    local line="$*"
    [ -w "$LOG_FILE" ] || touch "$LOG_FILE" 2>/dev/null || true
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$line" >>"$LOG_FILE" 2>/dev/null || true
    info "$line"
}

die() {
    local code="$1"; shift
    run_log "ОШИБКА: $*"
    exit "$code"
}

# --- проверка формата --------------------------------------------------------
# Понимаем две выгрузки OpenSpeedcam:
#   iGO:      X,Y,TYPE,SPEED[,DIRTYPE,DIRECTION]
#   PocketGIS: IDX,X,Y,TYPE,SPEED,DIRTYPE,DIRECTION,DISTANCE,ANGLE // ...
# Поэтому первые два числа ищем как «координаты с точкой», допуская колонку ID
# впереди. Файлы PocketGIS в Windows-1251 — grep считает их двоичными, отсюда -a.
count_points() {
    grep -acE '^[[:space:]]*([0-9]+[[:space:]]*[,;][[:space:]]*)?-?[0-9]{1,3}\.[0-9]+[[:space:]]*[,;][[:space:]]*-?[0-9]{1,2}\.[0-9]+[[:space:]]*[,;]' "$1" 2>/dev/null || true
}

# Формат определяем по первой значимой строке: в PocketGIS впереди идёт ID.
detect_format() {
    local f="$1" first
    first=$(grep -am1 -E '^[[:space:]]*[0-9]' "$f" 2>/dev/null || true)
    if printf '%s' "$first" | grep -qE '^[[:space:]]*[0-9]+[[:space:]]*,[[:space:]]*-?[0-9]{1,3}\.[0-9]+[[:space:]]*,[[:space:]]*-?[0-9]{1,2}\.[0-9]+'; then
        printf 'PocketGIS'
    else
        printf 'iGO speedcam.txt'
    fi
}

check_file() {
    local f="$1"
    [ -s "$f" ] || { run_log "Файл пустой: $f"; return 3; }
    local lines points size
    lines=$(wc -l <"$f" | tr -d ' ')
    points=$(count_points "$f")
    size=$(wc -c <"$f" | tr -d ' ')
    run_log "Проверка базы: строк $lines, с координатами $points, размер $size Б, формат $(detect_format "$f")"
    if head -c 400 "$f" | grep -qiE '<!doctype|<html|\{"message"|Unauthorized'; then
        run_log "Это не база камер, а страница/ответ сервера (HTML или JSON)."
        return 3
    fi
    if [ "${points:-0}" -lt "$MIN_LINES" ]; then
        run_log "Строк с координатами ${points} < минимума ${MIN_LINES} — файл не похож на базу камер."
        return 3
    fi
    return 0
}

describe_file() {
    local f="$1"
    local first
    # Комментарий PocketGIS в Windows-1251 — в лог его не тащим, только числа.
    first=$(grep -am1 -E '^[[:space:]]*[0-9]' "$f" | cut -d/ -f1 | head -c 120 || true)
    run_log "Первая точка: ${first:-нет}"
    local mtime
    mtime=$(date -r "$f" '+%Y-%m-%d %H:%M' 2>/dev/null || echo '?')
    run_log "Файл изменён: $mtime"
}

# --- распаковка --------------------------------------------------------------
unpack_if_needed() {
    local src="$1" workdir="$2" out
    case "$src" in
        *.gz)
            [ "$UNZIP" -eq 1 ] || die 1 "Источник сжат (.gz), а распаковка отключена (--no-unpack)"
            out="${workdir}/unpacked.txt"
            gzip -dc "$src" >"$out" || die 1 "Не удалось распаковать $src"
            printf '%s' "$out" ;;
        *.zip)
            [ "$UNZIP" -eq 1 ] || die 1 "Источник сжат (.zip), а распаковка отключена (--no-unpack)"
            command -v unzip >/dev/null || die 1 "Нужен unzip для распаковки $src"
            mkdir -p "${workdir}/unz"
            unzip -o -qq "$src" -d "${workdir}/unz" || die 1 "Не удалось распаковать $src"
            out=$(find "${workdir}/unz" -type f \( -iname '*.txt' \) -size +1k | head -n1)
            [ -n "$out" ] || die 1 "В архиве нет .txt с базой"
            run_log "Из архива взят $(basename -- "$out")"
            printf '%s' "$out" ;;
        *)
            printf '%s' "$src" ;;
    esac
}

# --- скачивание --------------------------------------------------------------
download_one() {
    local url="$1" out="$2"
    local -a args=(-fsSL --retry "$RETRIES" --retry-delay 5 --connect-timeout 20
                   --max-time "$TIMEOUT" -A "AudiDashboard/0.2 (speedcam updater)")
    [ -n "$COOKIE" ] && args+=(-H "Cookie: $COOKIE")
    run_log "Скачивание: $url"
    if curl "${args[@]}" -o "$out" "$url"; then
        return 0
    fi
    run_log "Не удалось скачать: $url"
    return 1
}

# --- основная работа ---------------------------------------------------------
run_log "=== Обновление базы камер ($SCRIPT_NAME) ==="
run_log "Назначение: $DEST"

if [ "$CHECK_ONLY" -eq 1 ]; then
    [ -f "$DEST" ] || die 1 "Файла нет: $DEST"
    check_file "$DEST" || exit 3
    describe_file "$DEST"
    run_log "Результат: база на месте и выглядит рабочей."
    exit 0
fi

mkdir -p "$(dirname -- "$DEST")" || die 1 "Не удалось создать папку для $DEST"
WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/speedcam.XXXXXX")
trap 'rm -rf "$WORKDIR"' EXIT

SRC_FILE=""

if [ -n "$FILE_SRC" ]; then
    [ -f "$FILE_SRC" ] || die 1 "Нет такого файла: $FILE_SRC"
    run_log "Источник: готовый файл $FILE_SRC"
    SRC_FILE="$FILE_SRC"
else
    if [ ${#URLS[@]} -eq 0 ]; then
        cat >&2 <<'EOF'
Источник не задан.

Автоматически скачать базу с openspeedcam.net нельзя: их сервис экспорта
требует авторизации (API отвечает 401 Unauthorized), а готовые сборки
OpenSpeedcam раздаёт ссылками на сторонние зеркала.

Задайте источник одним из способов:
  1) готовый файл:      ./update_speedcam.sh --file ~/Downloads/speedcam.txt
  2) ссылка экспорта:   ./update_speedcam.sh --url "https://.../speedcam.txt"
     (после входа на openspeedcam.net: «Экспорт» → формат iGO → ссылка на файл)
  3) вписать в speedcam.conf рядом со скриптом:
        SPEEDCAM_URL="https://.../speedcam.txt"
        SPEEDCAM_COOKIE="PHPSESSID=..."      # если ссылка требует входа
        SPEEDCAM_DEST="/home/pi/.local/share/AudiDashboard/speedcam.txt"
EOF
        die 2 "Источник не задан"
    fi

    idx=0
    for url in "${URLS[@]}"; do
        idx=$((idx + 1))
        raw="${WORKDIR}/raw_${idx}"
        if download_one "$url" "$raw"; then
            SRC_FILE="$raw"
            break
        fi
    done
    [ -n "$SRC_FILE" ] || die 1 "Ни один источник не отдал файл"
fi

PACKED="$SRC_FILE"
SRC_FILE=$(unpack_if_needed "$PACKED" "$WORKDIR")

if ! check_file "$SRC_FILE"; then
    die 3 "Скачанный файл не прошёл проверку, старая база оставлена как есть"
fi

describe_file "$SRC_FILE"

if [ "$DRY_RUN" -eq 1 ]; then
    run_log "Режим --dry-run: файл $DEST не изменён."
    exit 0
fi

# --- атомарная установка -----------------------------------------------------
TMP_DEST="${DEST}.new.$$"
cp -- "$SRC_FILE" "$TMP_DEST" || die 1 "Не удалось записать $TMP_DEST"
if [ -f "$DEST" ]; then
    cp -p -- "$DEST" "${DEST}.bak" 2>/dev/null || true
fi
mv -f -- "$TMP_DEST" "$DEST" || die 1 "Не удалось подменить $DEST"

POINTS=$(count_points "$DEST")
SIZE=$(wc -c <"$DEST" | tr -d ' ')
run_log "Готово: $DEST — $POINTS точек, $SIZE Б. Предыдущая база сохранена в ${DEST}.bak"
run_log "=== Конец обновления ==="
