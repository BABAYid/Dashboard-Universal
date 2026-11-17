#!/usr/bin/env bash
# ============================================================================
#  osmium без root: скачать пакет и распаковать его в проект.
#
#  Зачем: `osmium` (C++) режет и склеивает выгрузки OSM за минуты, а наш
#  pyosmium-скрипт на 124 млн узлов работал часами и падал по памяти.
#  Ставить пакет в систему нужен root, поэтому берём .deb и распаковываем
#  внутрь проекта — binaries не трогают систему.
#
#  Использование:
#      ./tools/osmium-bootstrap.sh          # скачает в build/osmium-tool
#      source ./tools/osmium-env.sh && osmium --version
#
#  Проверено 17.11.2026: osmium 1.19.0 на Ubuntu работает из распакованного
#  пакета (зависимости уже есть в системе).
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

DEST="build/osmium-tool"
mkdir -p "$DEST"
cd "$DEST"

echo "Качаю osmium-tool (apt-get download, без установки в систему)"
apt-get download osmium-tool 2>&1 | tail -2
DEB=$(ls -t osmium-tool_*.deb | head -1)
[ -n "$DEB" ] || { echo "не удалось скачать пакет" >&2; exit 1; }

echo "Распаковываю $DEB"
rm -rf root
dpkg -x "$DEB" root

cat > "$(cd ../.. && pwd)/tools/osmium-env.sh" <<EOF
# Окружение локального osmium (создаётся tools/osmium-bootstrap.sh)
export OSMIUM_BIN="$(pwd)/root/usr/bin/osmium"
export LD_LIBRARY_PATH="$(pwd)/root/usr/lib/x86_64-linux-gnu\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
osmium() { "\$OSMIUM_BIN" "\$@"; }
EOF

echo
echo "Готово. Проверка:"
. tools/osmium-env.sh 2>/dev/null || . "$(cd ../.. && pwd)/tools/osmium-env.sh"
osmium --version | head -2
