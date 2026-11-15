# Задание: приём маршрута от Android (route_handoff)

Цель: Android (мультимедиа) присылает точку назначения по WebSocket —
приборка строит маршрут сама (GraphHopper) и отдаёт состояние назад.
Кадры экрана от Android — только резерв, когда приборка маршрут не взяла.

Контракт — `docs/integration.md` §6.2 (`route_handoff`, `route_clear`)
и §6.1 (`route_state`).

## Что где менять

### NetworkServer.cpp — onTextMessage

- `route_handoff`: поля `lat`, `lon`, необязательное `name`.
  Проверка координат: конечные числа, −90…90 / −180…180, не (0, 0).
  Некорректные — игнорировать с `qWarning`.
  Валидные — `emit routeRequested(lat, lon, name)`.
- `route_clear` — `emit routeCancelled()`.
- Незнакомые типы — по-прежнему игнорируются.

### NetworkServer — отправка состояния

- `setRouteState(active, remainingM, etaS, maneuver, nextDistanceM, street)` —
  Q_INVOKABLE: QML обновляет поля (по 1-Гц таймеру в Main.qml).
- `pushRouteState()` — отправка `{"type":"route_state", …}` клиентам,
  повесить на существующий 1-Гц таймер (`m_carTimer`, 1000 мс).
- `setOfflineRouteActive(bool)` — приборка взяла маршрут на себя:
  `map_subscribe` off (кадры — резерв); сняли маршрут — снова on,
  если навигация активна.

### Main.qml — Connections

- `onRouteRequested(lat, lon, name)`:
  `navDestLat/Lon/Name`, `route.startLat/startLon = gpsLat/gpsLon`,
  `routeService.requestTo(lat, lon)`, затем `root.navigationMode = true`
  (существующая ветка сама гасит запрос кадров экрана через
  `setOfflineRouteActive`). `name` — в «Недавние».
- `onRouteCancelled()`: `route.clear()`, `navigationMode = false`.
- Таймер 1 Гц: `NetworkServer.setRouteState(...)` из текущего маршрута.

### RouteService.qml

- `requestTo(toLat, toLon)` — маршрут от `startLat/startLon` (позиция машины).
- `clear()` — сброс маршрута и подсказок.
- Поля `steps` (шаги с `maneuver`) и `nextStep` (`{maneuver, distanceM, street}`).
- Таблица `maneuverOfSign(sign)`: знак GraphHopper → `maneuver` из §6.2
  (`straight`, `slight_left`, `left`, `sharp_left`, `slight_right`,
  `right`, `sharp_right`, `uturn`, `roundabout`, `arrive`, `none`).
  Запрос к GraphHopper — с `points_encoded=false&instructions=true`.

## Проверка на столе

```bash
# 1) двигатели: тайлы + маршруты
./tools/nav-serve.sh          # сервер тайлов :8090 (если ещё не запущен)
./tools/nav-route.sh          # GraphHopper :8989 (если ещё не запущен)

# 2) приборка (демо-данные)
./tools/desk_demo.sh          # проверяет :8090/:8989 и запускает ./run.sh --mock --window

# 3) эмулировать Android: прислать точку
python3 tools/send_route_handoff.py --lat 55.770 --lon 37.640 --name "Тест"
python3 tools/send_route_handoff.py --clear
```

Что смотреть:

- в приложении: `Маршрут от Android: Тест 55.77000 37.64000`, затем
  «Маршрут: N.NN км …»; карта показывает маршрут, внизу плашка манёвра;
- в логе приложения: `Сеть: route_handoff …`, `Маршрут от Android: …`,
  при `--clear` — `Маршрут от Android: сброшен`;
- `route_state` раз в секунду: у эмулятора Android в консоли
  `{"type":"route_state","active":true,"remaining_m":…,"maneuver":"right",…}`;
- `map_subscribe` off после того, как приборка взяла маршрут (кадры — резерв).

## Границы ответственности

- Приборка владеет маршрутом, когда построила его сама (офлайн-карта):
  кадры экрана Android не нужны и не запрашиваются.
- Если приборка маршрут не взяла (нет GraphHopper/маршрут сброшен) —
  остаётся прежний режим: подсказки и кадры карты от Android.
- Android не обязан присылать `route_clear`: повторный `route_handoff`
  перестраивает маршрут; уход из навигации гасит всё сам.
