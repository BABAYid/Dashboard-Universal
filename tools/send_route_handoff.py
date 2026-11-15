#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
#  Эмуляция Android: прислать приборке маршрут по WebSocket.
#
#      python3 tools/send_route_handoff.py --lat 55.770 --lon 37.640 \
#              --name "ул. Ленина 5" --listen 4
#      python3 tools/send_route_handoff.py --clear
#
#  --listen N — столько секунд печатать то, что приборка присылает обратно
#  (route_state раз в секунду).
# ============================================================================
import argparse
import json
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))), "build", "pylibs"))

import websocket


def main():
    ap = argparse.ArgumentParser(description="route_handoff/route_clear для приборки")
    ap.add_argument("--url", default="ws://127.0.0.1:8080/ws")
    ap.add_argument("--lat", type=float)
    ap.add_argument("--lon", type=float)
    ap.add_argument("--name", default="")
    ap.add_argument("--clear", action="store_true", help="route_clear вместо handoff")
    ap.add_argument("--listen", type=float, default=0.0,
                    help="сколько секунд печатать ответы приборки")
    args = ap.parse_args()

    ws = websocket.create_connection(args.url, timeout=10)
    ws.send(json.dumps({"type": "hello", "role": "media",
                        "version": "1.0", "api": 1}))
    time.sleep(0.2)

    if args.clear:
        ws.send(json.dumps({"type": "route_clear"}))
        print("отправлено: route_clear")
    else:
        if args.lat is None or args.lon is None:
            ap.error("нужны --lat и --lon (или --clear)")
        ws.send(json.dumps({"type": "route_handoff", "lat": args.lat,
                            "lon": args.lon, "name": args.name,
                            "ts": int(time.time() * 1000)}))
        print(f"отправлено: route_handoff {args.lat},{args.lon} «{args.name}»")

    if args.listen > 0:
        end = time.time() + args.listen
        ws.settimeout(0.5)
        while time.time() < end:
            try:
                msg = json.loads(ws.recv())
            except Exception:
                continue
            if msg.get("type") == "route_state":
                print("route_state:", json.dumps(msg, ensure_ascii=False))
            elif msg.get("type") == "map_subscribe":
                print("map_subscribe:", json.dumps(msg, ensure_ascii=False))
    ws.close()


if __name__ == "__main__":
    main()
