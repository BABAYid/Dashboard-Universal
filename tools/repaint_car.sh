#!/usr/bin/env bash
# ============================================================================
#  repaint_car.sh — пересобрать раскраску модели машины «от дизайнера».
#
#  Один запуск повторяет всю цепочку: кузов → крыша и спойлеры → решётка →
#  тонировка стёкол. Исходник — файл от дизайнера (по умолчанию main_3.3.glb),
#  результат — то, что грузит приборка.
#
#    ./tools/repaint_car.sh                       # исходник ~/Документы/main_3.3.glb
#    ./tools/repaint_car.sh путь/к/модели.glb
# ============================================================================
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${1:-$HOME/Документы/main_3.3.glb}"
DST="$ROOT/Dashboard/assets/ipsum_fin.glb"
TMP="$ROOT/build/tmp"
mkdir -p "$TMP"

# --- цвета -------------------------------------------------------------------
BODY="#F7F5F0";        BODY_METAL=0.25; BODY_ROUGH=0.5     # белый перламутр, полуматовый лак
DARK="#3B2A22"                                             # тёмно-коричневый металлик
GLASS="#0A0C10";       GLASS_ALPHA=0.5;  GLASS_ROUGH=0.05  # тонировка: чёрное, полупрозрачное

[ -f "$SRC" ] || { echo "Нет исходной модели: $SRC" >&2; exit 1; }

python3 "$ROOT/tools/paint_model.py" --in "$SRC" --out "$TMP/car_1.glb" \
    --body "$BODY" --body-metal "$BODY_METAL" --body-rough "$BODY_ROUGH"
python3 "$ROOT/tools/paint_parts.py" --in "$TMP/car_1.glb" --out "$TMP/car_2.glb" \
    --roof "$DARK" --spoiler "$DARK"
python3 "$ROOT/tools/paint_parts.py" --in "$TMP/car_2.glb" --out "$TMP/car_3.glb" \
    --grille "$DARK"
python3 "$ROOT/tools/paint_model.py" --in "$TMP/car_3.glb" --out "$TMP/car_4.glb" \
    --glass "$GLASS" --glass-alpha "$GLASS_ALPHA" --glass-rough "$GLASS_ROUGH"
# Петли: в выгрузке дизайнера трансформации запечены в вершины, без этого
# двери и колёса крутились бы вокруг центра машины.
python3 "$ROOT/tools/restore_pivots.py" --in "$TMP/car_4.glb" --out "$DST"

echo "Готово: $DST"
