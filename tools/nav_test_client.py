#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
#  Фейковый Android для проверки интеграции (docs/integration.md).
#
#  Пока нет мультимедиа-блока, этот скрипт играет его роль: подключается к
#  приборке по WebSocket, представляется (hello), раз в секунду присылает
#  подсказки навигации и кадр карты, и печатает всё, что приборка присылает
#  в ответ (события джойстика и телеметрию).
#
#  WebSocket реализован здесь же, на сокетах: тащить зависимость в проект
#  ради теста не хочется, а на устройстве её и вовсе не будет.
#
#  Использование:
#      ./nav_test_client.py                       # карта + подсказки
#      ./nav_test_client.py --no-map              # только подсказки
#      ./nav_test_client.py --speed 40            # быстрее идём по маршруту
#      ./nav_test_client.py --host 10.0.0.1
# ============================================================================
import argparse
import base64
import hashlib
import io
import json
import os
import socket
import struct
import sys
import time

WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


# --------------------------------------------------------------- WebSocket
class WebSocket:
    """Минимальный клиент: текстовые и двоичные сообщения, без сжатия."""

    def __init__(self, host, port, path="/ws", timeout=5.0):
        self.sock = socket.create_connection((host, port), timeout=timeout)
        key = base64.b64encode(os.urandom(16)).decode()
        request = (
            f"GET {path} HTTP/1.1\r\n"
            f"Host: {host}:{port}\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\n\r\n"
        )
        self.sock.sendall(request.encode())

        response = b""
        while b"\r\n\r\n" not in response:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise ConnectionError("сервер закрыл соединение на рукопожатии")
            response += chunk
        head, _, rest = response.partition(b"\r\n\r\n")
        if b"101" not in head.split(b"\r\n")[0]:
            raise ConnectionError("сервер не переключился на WebSocket: " + head.decode(errors="replace"))
        expected = base64.b64encode(hashlib.sha1((key + WS_GUID).encode()).digest()).decode()
        if expected.encode() not in head:
            raise ConnectionError("неверный Sec-WebSocket-Accept")
        self.buffer = rest
        self.sock.settimeout(0.05)

    def _send(self, opcode, payload):
        header = bytearray([0x80 | opcode])
        length = len(payload)
        if length < 126:
            header.append(0x80 | length)
        elif length < 65536:
            header.append(0x80 | 126)
            header += struct.pack(">H", length)
        else:
            header.append(0x80 | 127)
            header += struct.pack(">Q", length)
        mask = os.urandom(4)
        header += mask
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self.sock.sendall(bytes(header) + masked)

    def send_text(self, text):
        self._send(0x1, text.encode())

    def send_binary(self, data):
        self._send(0x2, data)

    def _read_frame(self):
        data = self.buffer
        while len(data) < 2:
            try:
                chunk = self.sock.recv(65536)
            except socket.timeout:
                return None, None
            if not chunk:
                raise ConnectionError("соединение закрыто")
            data += chunk
            self.buffer = data
        data = self.buffer
        if len(data) < 2:
            return None, None
        b0, b1 = data[0], data[1]
        opcode = b0 & 0x0F
        masked = b1 & 0x80
        length = b1 & 0x7F
        pos = 2
        if length == 126:
            while len(data) < pos + 2:
                data += self.sock.recv(4096)
            length = struct.unpack(">H", data[pos:pos + 2])[0]
            pos += 2
        elif length == 127:
            while len(data) < pos + 8:
                data += self.sock.recv(4096)
            length = struct.unpack(">Q", data[pos:pos + 8])[0]
            pos += 8
        mask = None
        if masked:
            while len(data) < pos + 4:
                data += self.sock.recv(4096)
            mask = data[pos:pos + 4]
            pos += 4
        while len(data) < pos + length:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError("соединение закрыто в середине кадра")
            data += chunk
        payload = data[pos:pos + length]
        if mask:
            payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self.buffer = data[pos + length:]
        return opcode, payload

    def poll(self):
        """Прочитать одно сообщение, если оно есть. Возвращает (тип, данные)."""
        opcode, payload = self._read_frame()
        if opcode is None:
            return None, None
        if opcode == 0x8:
            raise ConnectionError("сервер закрыл соединение")
        return opcode, payload


# ------------------------------------------------------------------- карта
def make_map_frame(width, height, progress, maneuver_text):
    """Нарисовать «карту», похожую на экран навигатора (без зависимостей)."""
    from PIL import Image, ImageDraw

    img = Image.new("RGB", (width, height), (28, 34, 42))
    draw = ImageDraw.Draw(img)

    # сетка кварталов
    step = 120
    for x in range(0, width, step):
        draw.line([(x, 0), (x, height)], fill=(44, 52, 62), width=2)
    for y in range(0, height, step):
        draw.line([(0, y), (width, y)], fill=(44, 52, 62), width=2)

    # «дороги» пошире
    draw.line([(0, height * 0.55), (width * 0.45, height * 0.55)], fill=(70, 78, 90), width=34)
    draw.line([(width * 0.45, height * 0.55), (width * 0.45, 0)], fill=(70, 78, 90), width=34)

    # маршрут
    route = [(int(width * 0.02), int(height * 0.55)),
             (int(width * 0.45), int(height * 0.55)),
             (int(width * 0.45), int(height * 0.10))]
    draw.line(route, fill=(60, 160, 255), width=12)
    draw.ellipse([route[0][0] - 9, route[0][1] - 9, route[0][0] + 9, route[0][1] + 9],
                 fill=(255, 255, 255))

    # машина
    pos = (int(width * 0.02 + (width * 0.43) * min(progress, 1.0)), int(height * 0.55))
    draw.ellipse([pos[0] - 14, pos[1] - 14, pos[0] + 14, pos[1] + 14], fill=(255, 190, 0))

    draw.text((40, 40), "FAKE MAP FROM ANDROID", fill=(150, 160, 175))
    draw.text((40, 70), maneuver_text, fill=(220, 230, 240))
    return img


def jpeg_bytes(img, quality=70):
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=quality)
    return buf.getvalue()


def map_frame_message(jpeg, width, height):
    """Заголовок кадра по контракту §6.4 + JPEG."""
    header = b"MF" + bytes([1, 1]) + struct.pack(">HH", width, height) \
             + struct.pack(">I", int(time.time()) & 0xFFFFFFFF)
    return header + jpeg


# ------------------------------------------------------------------ сценарий
MANEUVERS = [
    ("left", 480, "ул. Ленина", 60),
    ("left", 240, "ул. Ленина", 60),
    ("straight", 120, "пр. Мира", 60),
    ("right", 90, "пр. Мира", 40),
    ("right", 30, "набережная", 40),
    ("arrive", 0, "точка назначения", -1),
]


def main():
    parser = argparse.ArgumentParser(description="Фейковый Android для приборки")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--no-map", action="store_true", help="не присылать кадры карты")
    parser.add_argument("--no-hints", action="store_true", help="не присылать подсказки")
    parser.add_argument("--speed", type=float, default=20.0, help="метров в секунду")
    parser.add_argument("--seconds", type=float, default=0, help="0 — до Ctrl+C")
    args = parser.parse_args()

    ws = WebSocket(args.host, args.port)
    print(f"подключено к ws://{args.host}:{args.port}/ws")

    caps = {"nav": True, "map_frames": not args.no_map, "climate": True}
    ws.send_text(json.dumps({"type": "hello", "role": "media", "version": "1.0",
                             "api": 1, "caps": caps}, ensure_ascii=False))

    started = time.time()
    distance = MANEUVERS[0][1]
    while True:
        now = time.time()
        if args.seconds and now - started > args.seconds:
            break

        # идём по маршруту: расстояние до манёвра уменьшается
        distance = max(0, distance - args.speed * 0.1)
        index = 0
        for i, item in enumerate(MANEUVERS):
            if distance <= item[1] + 120:
                index = i
        maneuver, _, street, limit = MANEUVERS[min(index, len(MANEUVERS) - 1)]

        if not args.no_hints:
            ws.send_text(json.dumps({
                "type": "nav", "active": True, "ts": int(now * 1000),
                "maneuver": maneuver, "distance_m": int(distance),
                "street": street, "speed_limit_kmh": limit,
                "eta_s": int(distance / 12) + 300, "remaining_m": int(distance) + 2400,
            }, ensure_ascii=False))

        if not args.no_map:
            frame = make_map_frame(1920, 720, 1.0 - distance / 600.0,
                                   f"{maneuver.upper()} через {int(distance)} м")
            jpeg = jpeg_bytes(frame)
            ws.send_binary(map_frame_message(jpeg, 1920, 720))

        # читаем ответы приборки, пока не придёт время следующего кадра
        deadline = time.time() + 1.0
        while time.time() < deadline:
            try:
                opcode, payload = ws.poll()
            except socket.timeout:
                break
            if opcode is None:
                continue
            if opcode == 0x1:
                try:
                    message = json.loads(payload)
                except json.JSONDecodeError:
                    continue
                kind = message.get("type")
                if kind == "input":
                    print("  input от приборки:", message.get("code"))
                elif kind == "car":
                    data = message.get("data", {})
                    print(f"  car: {data.get('speed_kmh')} км/ч, "
                          f"передача {data.get('gear')}")
                elif kind in ("status", "climate_result", "map_subscribe"):
                    print(f"  {kind}:", json.dumps(message, ensure_ascii=False)[:120])
            elif opcode == 0x2:
                print(f"  двоичное сообщение от приборки, {len(payload)} байт")

    print("готово")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nостановлено")
    except ConnectionError as error:
        print("ошибка соединения:", error, file=sys.stderr)
        sys.exit(1)
