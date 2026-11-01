#!/usr/bin/env python3
"""Извлекает анимацию из 3.glb (двигатель V6) в compact-JS для QML.

RuntimeLoader в Qt не проигрывает glTF-анимации, поэтому берём каналы
анимации (переводы/повороты/масштабы узлов) и складываем в массив ключей.
В QML фаза считается от оборотов, значения интерполируются.
"""
import json, struct, sys
import numpy as np

SRC = '3.glb'
OUT = 'Dashboard/assets/engine_anim.js'

data = open(SRC, 'rb').read()
_, _, length = struct.unpack('<III', data[:12])
off, js, bin_ = 12, None, None
while off < length:
    clen, ctype = struct.unpack('<II', data[off:off + 8])
    chunk = data[off + 8:off + 8 + clen]
    if ctype == 0x4E4F534A:
        js = json.loads(chunk.decode())
    elif ctype == 0x004E4942:
        bin_ = chunk
    off += 8 + clen


def acc(i):
    a = js['accessors'][i]
    bv = js['bufferViews'][a['bufferView']]
    nc = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a['type']]
    comp = {5126: np.float32}[a['componentType']]
    start = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    return np.frombuffer(bin_, dtype=comp, count=a['count'] * nc,
                         offset=start).reshape(a['count'], nc).astype(float)


anim = js['animations'][0]
# Общая длительность и времена ключей (у всех каналов одна сетка 35 ключей)
times = acc(anim['samplers'][0]['input'])[:, 0]
duration = float(times.max())
tracks = {}
for ch in anim['channels']:
    tgt = ch['target']
    node = tgt['node']
    path = tgt['path']
    vals = acc(anim['samplers'][ch['sampler']]['output'])
    key = f"{node}:{path}"
    tracks[key] = {
        'node': node,
        'path': path,
        'times': [round(float(v), 4) for v in acc(anim['samplers'][ch['sampler']]['input'])[:, 0]],
        'vals': [[round(float(x), 5) for x in row] for row in vals],
    }

# Статические трансформации анимируемых узлов — по ним в QML сопоставляем
# элементы RuntimeLoader с индексами узлов glTF (имён в QML нет).
node_info = {}
for ch in anim['channels']:
    node = ch['target']['node']
    if node in node_info:
        continue
    n = js['nodes'][node]
    node_info[node] = {
        't': [round(float(v), 5) for v in n.get('translation', [0, 0, 0])],
        'r': [round(float(v), 5) for v in n.get('rotation', [0, 0, 0, 1])],
    }

out = {
    'duration': round(duration, 4),
    'tracks': tracks,
    'nodes': node_info,
}
with open(OUT, 'w', encoding='utf-8') as f:
    f.write('// Сгенерировано tools/make_engine_anim.py из 3.glb — не править руками.\n')
    f.write('var ENGINE_ANIM = ')
    json.dump(out, f, ensure_ascii=False, separators=(',', ':'))
    f.write(';\n')
print("saved", OUT, "tracks:", len(tracks), "duration:", duration)
