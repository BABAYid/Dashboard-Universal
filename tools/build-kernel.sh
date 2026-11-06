#!/usr/bin/env bash
# ============================================================================
#  Кросс-сборка ядра и device tree для RK3588 (BTP-PCM-A-022A) на ПК x86_64.
#
#  Зачем кросс-сборка, а не сборка на плате: при настройке LVDS и загрузки
#  device tree пересобирается десятки раз, а это один `make dtbs` — секунды
#  на ПК. Плату жалко занимать на час.
#
#  Что нужно один раз на ПК (Ubuntu/Debian):
#      sudo apt install build-essential bc bison flex libssl-dev libelf-dev \
#                       device-tree-compiler gcc-aarch64-linux-gnu
#  Если вендор дал свой тулчейн (обычно prebuilts/gcc/.../aarch64-none-linux-gnu)
#  — используем его: он гарантированно совпадает с тем, чем собирали образ.
#
#  Использование:
#      ./build-kernel.sh /path/to/vendor-kernel [defconfig|dtbs|modules|clean]
# ============================================================================
set -euo pipefail

KDIR="${1:?путь к исходникам ядра вендора}"
WHAT="${2:-image}"

# Тулчейн: вендорский, если найдётся в PATH или в KDIR/prebuilts, иначе системный
CROSS="${CROSS_COMPILE:-}"
if [ -z "$CROSS" ]; then
    if command -v aarch64-none-linux-gnu-gcc >/dev/null 2>&1; then
        CROSS="aarch64-none-linux-gnu-"
    elif command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
        CROSS="aarch64-linux-gnu-"
    else
        echo "Нет aarch64-кросс-компилятора. Установите gcc-aarch64-linux-gnu" >&2
        exit 1
    fi
fi
export ARCH=arm64 CROSS_COMPILE="$CROSS"

JOBS="${JOBS:-$(nproc)}"
OUT="${OUT:-out}"          # сборка вне дерева исходников: дерево остаётся чистым
DEFCONFIG="${DEFCONFIG:-rk3588_linux_defconfig}"

cd "$KDIR"

case "$WHAT" in
defconfig)
    echo "== конфиг: $DEFCONFIG"
    make O="$OUT" "$DEFCONFIG"
    echo "Дальше: make O=$OUT menuconfig  — и правьте под себя"
    ;;
image|all)
    # Ядро + device tree + модули. LZ4: распаковка на плате быстрее gzip,
    # для приборки это реальные доли секунды на каждом старте.
    if ! grep -q "CONFIG_KERNEL_LZ4=y" "$OUT/.config" 2>/dev/null; then
        echo "== включаю CONFIG_KERNEL_LZ4"
        ./scripts/config --file "$OUT/.config" -e KERNEL_LZ4 -d KERNEL_GZIP || true
        make O="$OUT" olddefconfig
    fi
    echo "== сборка Image + dtbs + modules ($JOBS потоков)"
    make O="$OUT" -j"$JOBS" Image dtbs modules
    echo
    echo "Готово. Забрать с ПК:"
    echo "  $KDIR/$OUT/arch/arm64/boot/Image"
    echo "  $KDIR/$OUT/arch/arm64/boot/dts/rockchip/*.dtb"
    echo "  модули: make O=$OUT INSTALL_MOD_PATH=staging modules_install"
    ;;
dtbs)
    # Только device tree: секунды. Это 90 % итераций при настройке LVDS.
    echo "== пересборка dtbs"
    make O="$OUT" -j"$JOBS" dtbs
    echo "  $KDIR/$OUT/arch/arm64/boot/dts/rockchip/"
    ;;
modules)
    make O="$OUT" -j"$JOBS" modules
    make O="$OUT" INSTALL_MOD_PATH=staging modules_install
    echo "  модули в $KDIR/staging/lib/modules/\$(uname -r зерно)/"
    ;;
clean)
    make O="$OUT" clean
    ;;
*)
    echo "Неизвестный режим: $WHAT (defconfig|image|dtbs|modules|clean)" >&2
    exit 1
    ;;
esac
