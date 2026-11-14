#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
#  Эмуляция телефона: отправить адрес в приборку по WebSocket (/ws).
#
#  Запуск (приборка должна быть запущена, NetworkServer на :8080):
#      python3 tools/send_address.py "Красная площадь"
#
#  Приборка ищет адрес в maps/addresses.sqlite (через /search) и строит
#  маршрут — так на приборке вводится адрес без тачскрина.
# ============================================================================
import json
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))), "build", "pylibs"))

import websocket

text = sys.argv[1] if len(sys.argv) > 1 else "Красная площадь"
ws = websocket.create_connection("ws://127.0.0.1:8080/ws", timeout=5)
ws.send(json.dumps({"type": "hello", "role": "media", "version": "1.0", "api": 1}))
time.sleep(0.3)
ws.send(json.dumps({"type": "address", "text": text, "ts": int(time.time() * 1000)}))
print("отправлено:", text)
ws.close()
