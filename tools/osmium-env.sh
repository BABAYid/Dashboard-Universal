# Окружение локального osmium (создаётся tools/osmium-bootstrap.sh)
export OSMIUM_BIN="/home/oleg/Документы/новая приборка/build/osmium-tool/root/usr/bin/osmium"
export LD_LIBRARY_PATH="/home/oleg/Документы/новая приборка/build/osmium-tool/root/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
osmium() { "$OSMIUM_BIN" "$@"; }
