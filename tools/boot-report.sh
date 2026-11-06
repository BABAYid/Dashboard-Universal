#!/usr/bin/env bash
# ============================================================================
#  Снимок загрузки: что сколько занял. Запускать на плате после старта.
#
#  Нужен, чтобы ускорять загрузку по числам, а не на глаз: сначала снимаем
#  «как есть» (boot-before.txt), потом после каждого изменения — снова, и
#  сравниваем системное и пользовательское время.
#
#      ./boot-report.sh > ~/boot-before.txt
# ============================================================================
set -u

echo "=== дата"
date

echo
echo "=== командная строка ядра"
cat /proc/cmdline

echo
echo "=== время загрузки (firmware/loader/kernel/userspace)"
systemd-analyze || echo "systemd-analyze недоступен (не системd?)"

echo
echo "=== кто дольше всех стартовал (userspace, топ-30)"
systemd-analyze blame 2>/dev/null | head -30

echo
echo "=== критическая цепочка"
systemd-analyze critical-chain 2>/dev/null | head -25

echo
echo "=== включённые службы"
systemctl list-unit-files --state=enabled --no-pager 2>/dev/null | head -60

echo
echo "=== неудачные службы"
systemctl --failed --no-pager 2>/dev/null

echo
echo "=== время инициализации драйверов ядра (топ-20 по времени)"
if [ -r /proc/initcall_debug ] || grep -q "initcall_debug" /proc/cmdline; then
    dmesg | grep -E "initcall .* returned .* after" | sort -t' ' -k5 -n -r | head -20
else
    echo "(включите initcall_debug в командной строке ядра, чтобы это увидеть)"
fi

echo
echo "=== старт ядра по dmesg"
dmesg | head -40

echo
echo "=== версия и сборка ядра"
uname -a

echo
echo "=== модель платы"
cat /proc/device-tree/model 2>/dev/null || echo "(нет /proc/device-tree/model)"
