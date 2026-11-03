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

## Два поддерживаемых формата

Приборка читает обе выгрузки OpenSpeedcam — формат определяется по строке:

**iGO `speedcam.txt`** (компактный, его ставит `update_speedcam.sh`):

```
X,Y,TYPE,SPEED,DIRTYPE,DIRECTION
37.617500,55.752100,1,60,1,180
```

**PocketGIS** (то, что отдаёт сервис экспорта сайта как есть, ~22 МБ на 200+
тысяч точек, кодировка Windows-1251):

```
IDX,X,Y,TYPE,SPEED,DIRTYPE,DIRECTION,DISTANCE,ANGLE // id | тип | модель
1,37.617500,55.752100,1,60,1,180,500,25 // 5a1ec7ef | Статическая камера | Кордон
```

В PocketGIS дополнительно берутся: `DISTANCE` — своя дистанция предупреждения
(100 м для «лежачего полицейского», 500 м для камеры; меньше неё приборка не
предупреждает) и названия из комментария — тип и модель комплекса («Кордон»,
«Стрелка+», «Автоураган»). `ANGLE` (угол обзора) пока не используется.

Важно про колонки: `X` — **долгота**, `Y` — **широта**, в обоих форматах.
Перепутать их нельзя — в базе есть точки с долготой 140° (Дальний Восток),
а широта больше 90° не бывает.

Коды типов из выгрузки OpenSpeedcam (сентябрь 2026):

| TYPE | Что это | Сколько в базе |
|------|---------|----------------|
| 1 | Статическая камера | 65 186 |
| 3 | Контроль проезда на красный | 11 368 |
| 5 | Мобильная засада | 173 |
| 11 | Контроль движения по полосе | 527 |
| 20 | Стационарный пост ДПС | 761 |
| 21 | Железнодорожный переезд | 4 344 |
| 22 | Пешеходный переход | 12 738 |
| 100 | Начало населённого пункта | 30 282 |
| 101 | Ограничение скорости | 6 495 |
| 102 | Искусственная неровность | 45 589 |
| 103 | Плохая дорога | 6 176 |
| 104 | Опасный поворот | 14 960 |
| 105 | Опасный перекрёсток | 2 877 |
| 106 | Другая опасность | 1 339 |
| 107 | Обгон запрещён | 4 886 |

Ограничение скорости берётся из поля `SPEED`; если оно равно 0 (например, у
«лежачего полицейского»), в баннере показывается название типа, а не «КАМЕРА».

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

Явно заданный путь главнее всего: если выставлена переменная
`DASHBOARD_SPEEDCAM` или ключ `speedcam/path` в настройках приборки
(`QSettings`), читается ровно этот файл — без подстановки других (иначе
пустая база молча подменялась бы соседним файлом).

Если явного указания нет, перебираются пути по порядку:

1. `$XDG_STATE_HOME/audi-dashboard/speedcam.txt` (`~/.local/state/...`);
2. `$XDG_DATA_HOME/AudiDashboard/speedcam.txt` (`~/.local/share/...`);
3. `<папка сборки>/../Dashboard/assets/speedcam/speedcam.txt` (запуск из репозитория);
4. `<папка приложения>/assets/speedcam/speedcam.txt` (установленная копия);
5. `Dashboard/assets/speedcam/PocketGis.txt` и `PocketGis.txt` в корне репозитория.

Пустой файл (заглушка) пропускается, и берётся следующий кандидат — поэтому
`PocketGis.txt`, просто положенный в папку проекта, подхватывается сам.
Если базы нет совсем, приборка работает как обычно, просто без предупреждений.
