# База камер для приборки: обновление и формат

Приборка (Smart Driver) предупреждает о камерах по базе в формате iGO
`speedcam.txt`. База лежит в `Dashboard/assets/speedcam/speedcam.txt` и
обновляется скриптом `update_speedcam.sh` (раз в сутки, systemd timer).

## Формат строки

```
X,Y,TYPE,SPEED[,DIRTYPE,DIRECTION]
```

| Поле | Смысл |
|------|-------|
| `X` | долгота, градусы (55.7520 → `37.6175`) |
| `Y` | широта, градусы |
| `TYPE` | тип объекта (1 — камера скорости, 2 — красный свет, …) |
| `SPEED` | ограничение км/ч, `0` — не задано |
| `DIRTYPE` | `0` — камера без направления, `1` — направленная |
| `DIRECTION` | азимут камеры, 0…359° (только при `DIRTYPE=1`) |

Строки, начинающиеся с `#`, и пустые строки игнорируются. Разделитель —
запятая (допускается `;` и табуляция).

## Почему в скрипте нет «одной волшебной ссылки»

Сайт [openspeedcam.net](https://openspeedcam.net) — свободно редактируемая база,
но её сервис экспорта закрыт авторизацией:

```
$ curl -s https://openspeedcam.net/api/export/history
{"message":"Unauthorized"}          # HTTP 401
```

Готовые сборки сам OpenSpeedcam раздаёт только ссылками на сторонние зеркала
(страница «Полезное → Готовые сборки»: 7Ways, iGO/Primo/NextGen, NewNavitel,
Datakam G5, RNS/MIB). Поэтому скрипт умеет три способа получить файл и никогда
не портит рабочую базу, если скачалось что-то не то.

## Способы обновления

**A. Готовый файл с диска (самый простой):**

```bash
./update_speedcam.sh --file ~/Downloads/speedcam.txt
```

**B. Личная ссылка экспорта OpenSpeedcam** (после входа на сайт:
«Экспорт» → страна → формат iGO → ссылка на файл):

```bash
./update_speedcam.sh --url "https://openspeedcam.net/api/export/...."
# если ссылка требует cookie сессии:
SPEEDCAM_COOKIE="PHPSESSID=..." ./update_speedcam.sh --url "https://..."
```

Удобнее вписать в `speedcam.conf` рядом со скриптом
(шаблон — `speedcam.conf.example`), тогда systemd timer подхватит сам:

```ini
SPEEDCAM_URL="https://openspeedcam.net/api/export/...."
SPEEDCAM_COOKIE="PHPSESSID=...."
SPEEDCAM_DEST="/home/pi/.local/share/AudiDashboard/speedcam.txt"
```

**C. Любое публичное зеркало** с прямым `.txt`, `.gz` или `.zip` — тоже через
`--url` / `SPEEDCAM_URL`.

## Что делает скрипт

1. Скачивает (curl, 3 попытки, таймаут 120 с) или берёт файл с диска.
2. Распаковывает `.gz`/`.zip`, если нужно.
3. Проверяет, что это база: не HTML/JSON, есть минимум `--min-lines` строк
   с координатами (по умолчанию 100).
4. Атомарно подменяет файл (старый — в `speedcam.txt.bak`).
5. Пишет в лог дату, источник, число строк, размер, результат
   (`~/.local/state/audi-dashboard/speedcam-update.log`).

Полезные режимы:

```bash
./update_speedcam.sh --check      # проверить текущую базу, ничего не качая
./update_speedcam.sh --dry-run    # скачать и проверить, но не заменять
./update_speedcam.sh --help
```

Коды возврата: `0` — успех, `1` — ошибка загрузки/записи, `2` — не задан
источник, `3` — скачанное не похоже на базу камер.

## Автоматический запуск (systemd)

Файлы юнитов: `deploy/systemd/dashboard-speedcam.{service,timer}`.

**Вариант 1 — системный (нужен root):**

```bash
sudo cp deploy/systemd/dashboard-speedcam.* /etc/systemd/system/
sudo nano /etc/systemd/system/dashboard-speedcam.service   # User= и путь
sudo systemctl daemon-reload
sudo systemctl enable --now dashboard-speedcam.timer
systemctl list-timers dashboard-speedcam.timer
journalctl -u dashboard-speedcam.service -n 50     # что было ночью
```

**Вариант 2 — пользовательский (без root, работает только когда пользователь
залогинен; для приборки в машине с автологином — подходит):**

```bash
mkdir -p ~/.config/systemd/user
sed -e '/^User=/d' -e '/^Group=/d' deploy/systemd/dashboard-speedcam.service \
    > ~/.config/systemd/user/dashboard-speedcam.service
cp deploy/systemd/dashboard-speedcam.timer ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now dashboard-speedcam.timer
loginctl enable-linger "$USER"     # чтобы работало и без входа в сессию
```

**Cron вместо systemd** (если systemd нет):

```
0 3 * * * cd /home/oleg/Документы/новая\ приборка && ./update_speedcam.sh --quiet
```

## Где приборка ищет базу

`SpeedCamManager` перебирает пути в таком порядке:

1. переменная окружения `DASHBOARD_SPEEDCAM`;
2. ключ `speedcam/path` в настройках приборки (`QSettings`);
3. `$XDG_STATE_HOME/audi-dashboard/speedcam.txt` (`~/.local/state/...`);
4. `$XDG_DATA_HOME/AudiDashboard/speedcam.txt` (`~/.local/share/...`);
5. `<папка сборки>/../Dashboard/assets/speedcam/speedcam.txt` (запуск из репозитория);
6. `<папка приложения>/assets/speedcam/speedcam.txt` (установленная копия).

Поэтому на устройстве достаточно положить базу в одну из этих папок — путь
можно не прописывать. Если файла нет, приборка работает как обычно, просто
без предупреждений.
