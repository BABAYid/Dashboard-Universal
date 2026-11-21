pragma ComponentBehavior: Bound
import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import "."
import Dashboard

// ============================================================================
//  Приборная панель. Геометрия снята с макета дизайнера "Group 57.png"
//  (1919x720): два круглых прибора диаметром 714 px вплотную к краям экрана,
//  по центру по вертикали; между ними центральная область шириной 492 px,
//  ограниченная двумя горизонтальными линиями (y=146 и y=555).
// ============================================================================

Window {
    id: root
    width: 1920
    height: 720
    visible: true
    color: "black"
    title: "Audi Dashboard"

    // ======================= ДАННЫЕ =======================
    // Источник — CanBackend (Dashboard/can/CanBackend.cpp): приём кадров
    // 0x100/0x200/0x300/0x400 по SocketCAN либо генерация в демо-режиме (--mock).
    // Коэффициенты калибровки применяются на самих приборах.
    readonly property real speed: CanBackend.speed
    readonly property real rpm: CanBackend.rpm
    readonly property real fuelLevel: CanBackend.fuelLevel   // 0..100 % (0x300 байт 1)
    readonly property real tankCapacity: CanBackend.tankCapacity   // объём бака, л
    readonly property real temp: CanBackend.engineTemp
    readonly property real voltage: CanBackend.voltage
    readonly property real outsideTemp: CanBackend.outsideTemp
    readonly property real fuelRate: CanBackend.fuelRate     // л/100 км (0x300 байт 5)

    // Газовое оборудование (0x500): признак «едем на газе», исправность датчика
    // уровня газа и остаток газа в процентах (0 В — пусто, 5 В — полный)
    readonly property bool gasMode: CanBackend.gasMode
    readonly property bool gasSensorValid: CanBackend.gasSensorValid
    readonly property int gasLevelPercent: CanBackend.gasLevelPercent

    // Отладка: пока прошивки блока сбора нет, режим газа приходит только из
    // демо-режима (там газ включается с 15-й по 45-ю секунду каждой минуты).
    // Кнопка «Газ» на панели перекрывает то, что приходит по CAN, чтобы
    // посмотреть, как выглядит приборка на газу. Когда появится кнопка на руле
    // (или прошивка блока), эти два свойства и саму кнопку надо убрать.
    property bool gasOverrideActive: false
    property bool gasOverride: false

    // Что показываем на самом деле: данные CAN, если отладка не вмешалась
    readonly property bool gasDisplay: gasOverrideActive ? gasOverride : gasMode

    // Промо-ролики камер (пока вместо живого видео с USB-захвата).
    // Пустая строка — показывается заглушка «КАМЕРА L/R».
    property string promoVideoLeft: "file:///home/oleg/Документы/новая приборка/левая.mp4"
    property string promoVideoRight: "file:///home/oleg/Документы/новая приборка/правая.mp4"

    // Демо: клавиши ←/→ включают/выключают поворотник (для показа камер).
    property bool demoLeftTurn: false
    property bool demoRightTurn: false

    // Отладка «Газ в пол»: принудительно показать 5400 об/мин, чтобы увидеть
    // анимацию «деньги в топку» не дожидаясь всплеска в демо-сценарии.
    // Перекрываем именно обороты, которые видит приборка: стрелка, цифры и
    // анимация идут вместе, а не вразнобой.
    property bool debugFullThrottle: false
    // Отладка: DASHBOARD_DEMO_LIGHTS=1 включает фары на модели (для снимков).
    property bool debugHeadlights: false
    property bool debugLowBeam: false
    readonly property real rpmShown: debugFullThrottle ? 5400 : rpm

    readonly property bool weatherEnabled: calibration.weatherEnabled

    // Предупреждения о камерах (см. CameraWarning.qml и SpeedCamManager).
    // Выключить можно в настройках: строка «Камеры» в разделе предупреждений.
    readonly property bool cameraWarningEnabled: calibration.cameraWarningEnabled

    // Видео с камер в колодцах приборов (контроль мёртвых зон): включается
    // в настройках, иначе колодцы остаются обычными приборами.
    readonly property bool blindSpotEnabled: calibration.blindSpotEnabled

    // Запас хода (считает CanBackend по среднему расходу за 5 минут).
    // Пока расчёт недостоверен — в QML это «—», и предупреждение не горит:
    // ноль в rangeKm означает «неизвестно», а не «ноль километров».
    readonly property real rangeKm: CanBackend.rangeKm
    readonly property bool rangeKmValid: CanBackend.rangeKmValid
    readonly property bool rangeCritical: rangeKmValid && rangeKm < 20
    property bool rangeBlinkOn: true   // фаза мигания предупреждения о запасе

    readonly property bool leftTurn: demoLeftTurn || CanBackend.leftTurn
    // Общая фаза мигания поворотников: одна на панель и на 3D-модель
    property bool turnBlink: false
    Timer {
        interval: 333
        repeat: true
        running: root.leftTurn || root.rightTurn
        onRunningChanged: if (!running) root.turnBlink = false
        onTriggered: root.turnBlink = !root.turnBlink
    }
    readonly property bool rightTurn: demoRightTurn || CanBackend.rightTurn
    readonly property bool highBeam: CanBackend.highBeam
    readonly property bool lowBeam: CanBackend.lowBeam
    readonly property bool fogLights: CanBackend.fogLights
    readonly property bool positionLights: CanBackend.positionLights
    readonly property bool brakeLights: CanBackend.brakeLights
    readonly property bool reverseLights: CanBackend.reverseLights
    readonly property bool checkEngine: CanBackend.checkEngine
    readonly property bool abs: CanBackend.absWarning
    readonly property bool handBrake: CanBackend.handBrake
    readonly property bool seatBelt: CanBackend.seatBeltUnfastened
    readonly property bool oilPressureAlarm: CanBackend.oilPressureAlarm
    readonly property bool gearLock: CanBackend.gearLock
    readonly property string gearMode: CanBackend.gearMode
    readonly property real odometer: CanBackend.odometer
    readonly property real tripA: CanBackend.tripA
    readonly property real tripB: CanBackend.tripB
    readonly property bool canDataValid: CanBackend.dataValid

    // Ночной режим включается вместе с габаритами (0x200 байт 0, бит 4)
    readonly property bool nightMode: CanBackend.positionLights

    // ======================= ПРОЧЕЕ =======================
    property string timeString: "12:34"
    property string displayMode: "odo"
    property real speedFactor: 1.0
    property real rpmFactor: 1.0
    property real fuelFactor: 1.0
    // Множитель топлива из настроек. В конфиге осталось 3.0 от тестов:
    // с ним бак 60 л показывал «138.6 л», а стрелка показывала «полный бак»
    // при 77 %. Такую величину считаем битой и берём 1.0; разумная
    // калибровка — 0.5…1.5.
    readonly property real fuelFactorEffective:
        (fuelFactor >= 0.5 && fuelFactor <= 1.5) ? fuelFactor : 1.0
    property real tempFactor: 1.0
    property bool startup: true
    // Самопроверка ламп при включении зажигания (гаснет через 2,5 с)
    property bool lampSelfTest: true
    // Отладка раскладки: клавиша L зажигает ВСЕ лампы постоянно, на обоих
    // скинах — видно, какой значок где стоит. Обычная самопроверка при
    // старте (lampSelfTest) остаётся как была.
    property bool lampsAllOn: false
    readonly property bool lampTestOn: lampSelfTest || lampsAllOn
    property real brightness: 1.0
    property bool navigationMode: false
    property real navigationAnimDuration: 400
    // Зум офлайн-карты: джойстик ▲/▼ в навигации. Тайлы собраны до z15.
    property real mapZoom: 14
    readonly property real mapZoomMin: 8
    readonly property real mapZoomMax: 15

    // ---- выбор точки назначения без тачскрина ----
    // Избранное: энкодер листает список, PRESS строит маршрут к выбранной
    // точке. «По карте»: ◀/▶ сдвигают вид, в центре появляется
    // перекрестие, PRESS строит маршрут «сюда».
    property var favorites: [
        { name: "Дом",    lat: 55.7600, lon: 37.6250 },
        { name: "Работа", lat: 55.7560, lon: 37.6120 },
        { name: "АЗС",    lat: 55.7630, lon: 37.6330 },
        { name: "Мойка",  lat: 55.7500, lon: 37.6180 }
    ]
    property int favoriteIndex: 0
    // Недавние пункты назначения (последние 10). Хранятся в C++
    // (RecentDestinations → QSettings), поэтому переживают перезапуск.
    readonly property var recentRoutes: RecentDestinations.items
    // Единый список для выбора энкодером: избранное, затем недавние
    // (недавние, совпадающие с избранным, не дублируем).
    readonly property var navChoices: {
        const out = []
        for (let i = 0; i < favorites.length; i++)
            out.push(favorites[i])
        for (let i = 0; i < recentRoutes.length; i++) {
            const r = recentRoutes[i]
            let dup = false
            for (let j = 0; j < favorites.length; j++) {
                const f = favorites[j]
                if (f.name === r.name && Math.abs(f.lat - r.lat) < 1e-6
                        && Math.abs(f.lon - r.lon) < 1e-6)
                    dup = true
            }
            if (!dup)
                out.push(r)
        }
        return out
    }
    // Текущее назначение маршрута («Дом» по умолчанию).
    property real navDestLat: 55.7600
    property real navDestLon: 37.6250
    property string navDestName: "Дом"
    // Вид оторван от машины: джойстик двигает карту, в центре перекрестие.
    property bool mapDetached: false

    // Второй скин (docs/design/genesis.jpg): тёмно-синий фон, приборы
    // примитивами, светлая полоса внизу. Классический скин — classic.
    // Переключается клавишей F8 и переменной DASHBOARD_SKIN при запуске.
    property string skin: "classic"

    // ---- офлайн-карта в навигационном режиме ----
    // Карта рисуется на месте (MapLibre + локальные тайлы), интернет не нужен.
    // Пока нет GPS — играем записанный трек по Москве, чтобы проверить
    // поведение карты: следование за машиной, поворот по курсу, зум.
    property bool offlineMap: true
    // Демо-трек включается, только когда реального GPS нет. Своего приёмника
    // пока нет — на столе данные отдаёт tools/gps_test_server.py (gpsd по
    // TCP), на плате — настоящий gpsd.
    property bool fakeGps: true
    readonly property bool realGps: GpsBackend.valid
    property real gpsLat: 55.7558
    property real gpsLon: 37.6173
    property real gpsCourse: 0
    property real gpsSpeedKmh: -1
    property int gpsTrackIndex: 0

    // Трек для проверки: небольшой маршрут по центру Москвы
    readonly property var demoTrack: [
        [55.7558, 37.6173], [55.7570, 37.6185], [55.7583, 37.6198],
        [55.7596, 37.6212], [55.7608, 37.6228], [55.7619, 37.6245],
        [55.7628, 37.6263], [55.7636, 37.6281], [55.7643, 37.6300],
        [55.7649, 37.6319]
    ]

    function bearing(lat1, lon1, lat2, lon2) {
        const toRad = Math.PI / 180
        const dLon = (lon2 - lon1) * toRad
        const y = Math.sin(dLon) * Math.cos(lat2 * toRad)
        const x = Math.cos(lat1 * toRad) * Math.sin(lat2 * toRad)
                - Math.sin(lat1 * toRad) * Math.cos(lat2 * toRad) * Math.cos(dLon)
        return (Math.atan2(y, x) / toRad + 360) % 360
    }

    // В навигации строим маршрут от текущей точки до «пункта назначения»
    // и едем по нему: позиция берётся из геометрии маршрута, курс — по
    // следующему сегменту. Так проверяем и маршрут, и карту, и подсказки.
    property real routeProgress: 0          // метры от старта
    readonly property real routeSpeed: 18   // м/с, чтобы не ждать минут


    Timer {
        interval: 250
        repeat: true
        running: root.fakeGps && !root.realGps && root.navigationMode && route.ready
        onTriggered: {
            root.routeProgress += root.routeSpeed * 0.25
            route.setTraveled(root.routeProgress)

            // положение на маршруте по пройденному расстоянию
            const pts = route.points
            if (!pts || pts.length < 2)
                return
            // грубая интерполяция по длине полилинии
            let total = 0
            const seg = []
            for (let i = 1; i < pts.length; i++) {
                const a = pts[i-1], b = pts[i]
                const d = root.distanceM(a[1], a[0], b[1], b[0])
                seg.push(d); total += d
            }
            const target = Math.min(root.routeProgress, total)
            let acc = 0, k = 1
            for (; k < seg.length; k++) {
                if (acc + seg[k-1] >= target) break
                acc += seg[k-1]
            }
            const a = pts[k-1], b = pts[Math.min(k, pts.length-1)]
            const f = seg[k-1] ? (target - acc) / seg[k-1] : 0
            root.gpsLat = a[1] + (b[1]-a[1]) * f
            root.gpsLon = a[0] + (b[0]-a[0]) * f
            root.gpsCourse = root.bearing(a[1], a[0], b[1], b[0])
        }
    }

    // Реальный GPS (gpsd) важнее демо-трека: пока есть фикс, позиция и курс
    // приходят от приёмника, и карта едет за ним.
    // ---- пункты назначения: избранное, недавние, телефон ----

    // Запомнить пункт назначения в «Недавние» (без дублей, последние 10).
    // Хранит C++ (RecentDestinations), поэтому список живёт между запусками.
    function rememberDestination(name, lat, lon) {
        RecentDestinations.add(name, lat, lon)
    }

    // Выбрать пункт назначения из объединённого списка и построить маршрут.
    function chooseDestination(index) {
        const c = root.navChoices[index]
        if (!c)
            return
        root.favoriteIndex = index
        root.navDestLat = c.lat
        root.navDestLon = c.lon
        root.navDestName = c.name
        root.routeProgress = 0
        root.mapDetached = false
        route.buildRoute(root.gpsLat, root.gpsLon, root.navDestLat, root.navDestLon)
        root.rememberDestination(c.name, c.lat, c.lon)
        offlineMapView.flyTo(c.lon, c.lat, root.mapZoom)
        console.log("Маршрут к:", c.name)
    }

    // Адрес от телефона: ищем в базе адресов (SQLite FTS на сервере тайлов)
    // и строим маршрут. Без тачскрина это основной способ ввести адрес.
    function searchAddress(text) {
        const base = offlineMapView.mapUrl.replace(/map\.html$/, "").replace(/\/$/, "")
        // Позиция машины — чтобы ближайшие совпадения шли первыми.
        const url = base + "/search?q=" + encodeURIComponent(text)
                  + "&lat=" + root.gpsLat + "&lon=" + root.gpsLon
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            if (xhr.status !== 200) {
                console.log("Поиск адреса: сервер", xhr.status)
                return
            }
            let res = null
            try { res = JSON.parse(xhr.responseText) } catch (e) {}
            const hits = res && res.results ? res.results : []
            if (hits.length === 0) {
                console.log("Поиск адреса: не найдено —", text)
                return
            }
            const h = hits[0]
            root.navDestLat = h.lat
            root.navDestLon = h.lon
            root.navDestName = h.name || text
            root.routeProgress = 0
            root.mapDetached = false
            if (!root.navigationMode)
                root.navigationMode = true   // syncInputRouting построит маршрут
            else
                route.buildRoute(root.gpsLat, root.gpsLon, root.navDestLat, root.navDestLon)
            root.rememberDestination(h.name || text, h.lat, h.lon)
            offlineMapView.flyTo(h.lon, h.lat, root.mapZoom)
            console.log("Поиск адреса:", text, "→", h.name || "?")
        }
        xhr.open("GET", url)
        xhr.send()
    }

    // Сколько фиксов приняли от gpsd — для диагностики в логе (первый
    // и каждый 600-й: при 10 Гц это раз в минуту, лог не засоряется).
    property int gpsFixCount: 0

    // Позиция от gpsd. Подключаемся явно (а не `Connections`): сигнал
    // приходит из другого потока, и на стенде было видно, что обработчик
    // `Connections` не вызывается вовсе — позиция оставалась демо-московской,
    // а маршрут строился от неё (route.startLat), а не от приёмника.
    function attachGps() {
        GpsBackend.positionUpdated.connect(function(lat, lon, course, speedKmh) {
            root.gpsLat = lat
            root.gpsLon = lon
            root.gpsCourse = course
            root.gpsSpeedKmh = speedKmh
            root.gpsFixCount += 1
            if (root.gpsFixCount === 1 || root.gpsFixCount % 600 === 0)
                console.log("GPS: фиксов", root.gpsFixCount,
                            "позиция", lat.toFixed(5), lon.toFixed(5))
        })
        console.log("GPS: подписка на приёмник готова, valid =", GpsBackend.valid)
    }

    // расстояние между двумя точками на сфере (метры)
    function distanceM(lat1, lon1, lat2, lon2) {
        const R = 6371000, rad = Math.PI / 180
        const dLat = (lat2-lat1)*rad, dLon = (lon2-lon1)*rad
        const x = Math.sin(dLat/2)*Math.sin(dLat/2)
                + Math.cos(lat1*rad)*Math.cos(lat2*rad)*Math.sin(dLon/2)*Math.sin(dLon/2)
        return 2*R*Math.atan2(Math.sqrt(x), Math.sqrt(1-x))
    }

    // Вошли в навигацию — просим у Android кадры карты; вышли — перестаём.
    // В обычном режиме канал не должен тратиться на картинку, которую никто
    // не смотрит.
    onNavigationModeChanged: root.syncInputRouting()

    // Правило фокуса (ARCHITECTURE.md §6): пока приборка в навигации или в
    // настройках, джойстик принадлежит ей и в мультимедиа не уходит.
    function syncInputRouting() {
        NetworkServer.setNavigationActive(root.navigationMode)
        NetworkServer.setInputForwarding(!root.navigationMode && !calibration.visible)

        // вошли в навигацию с офлайн-картой — строим маршрут к navDest.
        // Если маршрут только что запрошен через requestTo() (route_handoff),
        // второй запрос не нужен: RouteService сам игнорирует перегрузку.
        if (root.navigationMode && root.offlineMap) {
            root.routeProgress = 0
            route.startLat = root.gpsLat
            route.startLon = root.gpsLon
            if (!route.loading)
                route.buildRoute(root.gpsLat, root.gpsLon,
                                 root.navDestLat, root.navDestLon)
        }
        if (!root.navigationMode) {
            root.mapDetached = false
            // Вышли из навигации — маршрута больше нет, состояние устарело.
            NetworkServer.setRouteState(false, 0, 0, "", 0, "")
            NetworkServer.setRouteError("")
            NetworkServer.setRoutePath([])
        }
        NetworkServer.setOfflineRouteActive(
                    root.navigationMode && root.offlineMap && route.ready)
    }

    Connections {
        target: calibration
        function onVisibleChanged() { root.syncInputRouting() }
    }

    // Адрес, присланный телефоном (мультимедиа):
    //   {"type":"address","text":"Москва, улица Ленина 5"}
    Connections {
        target: NetworkServer
        function onAddressReceived(text) { root.searchAddress(text) }
    }

    // Маршрут от Android (docs/priberka_route_handoff.md):
    //   {"type":"route_handoff","lat":..,"lon":..,"name":".."} — строим сами
    //   {"type":"route_clear"} — сбрасываем
    // Кадры экрана Android после route_handoff — только резерв.
    Connections {
        target: NetworkServer
        function onRouteRequested(lat, lon, name) {
            root.navDestLat = lat
            root.navDestLon = lon
            root.navDestName = (name && name.length > 0) ? name : "Точка от Android"
            route.startLat = root.gpsLat
            route.startLon = root.gpsLon
            root.routeProgress = 0
            NetworkServer.setRouteError("")   // новый маршрут — прошлый отказ забыт
            route.requestTo(lat, lon)
            root.navigationMode = true
            if (name && name.length > 0)
                root.rememberDestination(name, lat, lon)
            console.log("Маршрут от Android:", root.navDestName,
                        lat.toFixed(5), lon.toFixed(5))
        }
        function onRouteCancelled() {
            route.clear()
            NetworkServer.setRoutePath([])
            root.navigationMode = false
            // Пока маршрут был активен, приборка каждый секунду сообщала
            // route_state с "active": true. После сброса это состояние
            // устарело: без явного сброса мультимедиа так и считает, что
            // ведёт приборка, и не поднимает свой навигатор.
            NetworkServer.setRouteState(false, 0, 0, "", 0, "")
            NetworkServer.setRouteError("")
            console.log("Маршрут от Android: сброшен")
        }
    }

    // Состояние своего маршрута для route_state (Android):
    // QML обновляет поля, NetworkServer отправляет их раз в секунду.
    Timer {
        interval: 1000
        repeat: true
        running: root.navigationMode && root.offlineMap
        onTriggered: {
            const remain = Math.max(0, route.routeDistanceM - route.traveledM)
            const eta = route.routeDistanceM > 0
                      ? route.routeTimeS * remain / route.routeDistanceM : 0
            NetworkServer.setRouteState(route.ready, remain, eta,
                                        route.hintManeuver,
                                        route.hintDistanceM, route.hintText)
        }
    }

    // Маршрут готов/пропал — обновить подписку на кадры экрана.
    Connections {
        target: route
        function onReadyChanged() {
            if (route.ready)
                NetworkServer.setRouteError("")   // маршрут есть — отказа нет
            NetworkServer.setOfflineRouteActive(
                        root.navigationMode && root.offlineMap && route.ready)
        }
        // GraphHopper не смог (чаще всего — точки вне офлайн-карты):
        // говорим мультимедиа "no_route", оно возвращается к кадрам экрана.
        function onRouteFailed(reason) {
            NetworkServer.setRouteError(reason)
            console.log("Маршрут: отказ, мультимедиа —", reason)
        }
    }

    // --- Кинематографичный запуск с 3D-машиной (см. Car3DView.qml) ---
    // Приборка читает флаг командной строки сама: при --no-3d старт без
    // 3D-заставки (экономия на слабом железе). main.cpp объявляет тот же
    // флаг для --help, а QML берёт его из аргументов приложения: так имя
    // не «зовётся из воздуха» и qmllint молчит.
    readonly property bool car3d: Qt.application.arguments.indexOf("--no-3d") === -1
    property real startupStage: 1.0     // 0…1: стартовая анимация машины, 4 секунды
    property real gaugesOpacity: 1.0    // проявление приборов на 3…4 с
    // Панель полностью прогрузилась (приборы проявились): до этого на
    // стартовом экране только машина — дорога появляется после.
    readonly property bool panelReady: gaugesOpacity >= 0.999

    // Первый кадр реально отрисован (main.cpp ставит флаг после afterRendering).
    property bool firstFrameRendered: false
    // Заставка уже запущена (ровно один раз).
    property bool startupStarted: false

    // Сигнал «запуск закончен»: по нему приборка переходит в штатный режим.
    signal startupFinished()

    // Запуск стартовой заставки. Ждём первый отрисованный кадр: на слабом
    // железе он приходит через несколько секунд, и иначе заставка успевает
    // проиграться, пока экран ещё чёрный (казалось, что 3D повис).
    function beginStartup() {
        if (root.startupStarted)
            return
        root.startupStarted = true
        startupSequence.start()
    }

    onFirstFrameRenderedChanged: if (root.firstFrameRendered) root.beginStartup()

    // Страховка: если хук первого кадра почему-то не сработал — стартуем сами.
    Timer {
        interval: 12000
        repeat: false
        running: root.car3d && !root.startupStarted
        onTriggered: root.beginStartup()
    }

    // Применить коэффициенты из настроек (после их загрузки с диска).
    function applyCalibration() {
        root.speedFactor = calibration.speedFactor
        root.rpmFactor = calibration.rpmFactor
        root.fuelFactor = calibration.fuelFactor
        root.tempFactor = calibration.tempFactor
    }

    // ======================= ВВОД (джойстик) =======================
    // Тачскрина нет, поэтому интерфейсом управляет джойстик BMW iDrive через
    // ESP32 и кадр 0x530 (протокол 1.4). InputController переводит код кнопки
    // в имя действия, а что именно делать — решает root.applyInput ниже:
    // состояние интерфейса (режимы, навигация, настройки) живёт здесь.
    InputController {
        id: input
        onCommand: function(name) { root.applyInput(name) }
    }

    // Живой джойстик: кадры 0x530 → CanBackend → сигналы.
    Connections {
        target: CanBackend

        // Кнопку обрабатываем по нажатию. Отпускание нужно позже, для длинных
        // нажатий (сброс trip удержанием) — тогда оно же сюда придёт.
        function onButtonEvent(code, pressed) {
            if (pressed)
                input.button(code)
        }

        function onEncoderTurned(delta) {
            input.encoder(delta)
        }
    }

    // Что делает действие. Пока открыты настройки — ввод уходит им: из
    // джойстика доступны только «назад»/«опции» (закрыть без сохранения),
    // остальное гасим, чтобы случайно не переключить режим под оверлеем.
    function applyInput(name) {
        // Печатаем каждое действие: без этого на устройстве не видно, дошёл
        // ли ввод до интерфейса (кадр в шине есть, а реакция не та — ищем тут).
        console.log("Ввод:", name)

        if (calibration.visible) {
            if (name === "back" || name === "option" || name === "menu")
                calibration.revert()
            return
        }

        switch (name) {
        case "nav":
            root.navigationMode = !root.navigationMode
            break
        case "back":
            if (root.navigationMode)
                root.navigationMode = false
            break
        case "media":
        case "radio":
            // Медиа-режим центральной панели (6). Карта при этом закрывается:
            // это два разных «полноэкранных» вида, и вместе они не нужны.
            // RADIO делает то же самое: радио — часть медиа, отдельного вида
            // у него больше нет, а климат переехал на экран мультимедиа.
            root.navigationMode = false
            root.centerMode = 6
            break
        case "option":
        case "menu":
            calibration.open()
            break
        case "left":
        case "right":
            // На карте ◀/▶ двигают вид: так выбирается точка «по карте».
            // Вне навигации — как раньше, листают режимы центральной панели.
            if (root.navigationMode && root.offlineMap) {
                root.mapDetached = true
                offlineMapView.panBy(name === "left" ? -90 : 90, 0)
            } else {
                if (name === "left")
                    root.prevCenterMode()
                else
                    root.nextCenterMode()
            }
            break
        case "press":
            if (root.navigationMode && root.offlineMap) {
                if (root.mapDetached) {
                    // «Сюда»: точка под перекрестием становится пунктом назначения
                    offlineMapView.centerCoords(function(c) {
                        if (!c || c.length < 2)
                            return
                        root.navDestLon = c[0]
                        root.navDestLat = c[1]
                        root.navDestName = "Точка на карте"
                        root.mapDetached = false
                        root.routeProgress = 0
                        route.buildRoute(root.gpsLat, root.gpsLon,
                                         root.navDestLat, root.navDestLon)
                        root.rememberDestination("Точка на карте", c[1], c[0])
                        offlineMapView.attachToCar()
                        console.log("Маршрут к: точке на карте")
                    })
                } else {
                    // Маршрут к выбранному избранному/недавнему
                    root.chooseDestination(root.favoriteIndex)
                }
            } else {
                root.nextCenterMode()
            }
            break
        case "next":
        case "prev":
            if (root.navigationMode && root.offlineMap) {
                // Энкодер в навигации листает избранное + недавние
                const n = root.navChoices.length
                if (n > 0) {
                    root.favoriteIndex = (root.favoriteIndex + (name === "next" ? 1 : -1) + n) % n
                    console.log("Ввод: назначение", root.navChoices[root.favoriteIndex].name)
                }
            } else {
                lamps.cycleOdometer(name === "next" ? 1 : -1)
            }
            break
        case "up":
        case "down":
            // В навигации ▲/▼ — зум карты; вне её остаются резервом под
            // списки (избранное, пункты меню).
            if (root.navigationMode) {
                const step = name === "up" ? 1 : -1
                root.mapZoom = Math.max(root.mapZoomMin,
                                        Math.min(root.mapZoomMax,
                                                 root.mapZoom + step))
                console.log("Ввод: зум карты", root.mapZoom)
            }
            break
        default:
            console.log("Ввод: действие не назначено —", name)
        }
    }

    // Режим центральной зоны: 0 — стандарт, 1 — компьютер, 2 — диагностика,
    // 3 — напряжение. Переключается нажатием по центру или клавишами.
    //
    // Счётчик режимов берём у самой панели, а не держим своё число: раньше их
    // было два (здесь 3, в CenterPanel 4), и четвёртый режим не включался —
    // цикл переключения упирался в старое число.
    property int centerMode: 0
    readonly property int centerModeCount: centerPanelView.modeCount

    // ---- Пневмоподвеска (6-й вид): -1 спорт, 0 стандарт, 1 бездорожье ----
    property int suspensionLevel: 0
    // Тесты: кнопки в настройках открывают двери/капот/багажник на модели
    property bool doorsOpen: calibration.doorsOpen
    // Демонстрация с клавиатуры: 1 — FL, 2 — FR, 3 — RL, 4 — RR,
    // 5 — капот, 6 — багажник (каждое нажатие открывает/закрывает)
    property bool demoDoorFL: false
    property bool demoDoorFR: false
    property bool demoDoorRL: false
    property bool demoDoorRR: false
    property bool capotOpen: calibration.capotOpen
    property bool trunkOpen: calibration.trunkOpen
    // Куда только что нажали: +1 вверх, -1 вниз (для мигания стрелки)
    property int suspensionDirection: 0
    property bool suspBlinkOn: false

    Timer {
        id: suspHoldTimer
        interval: 1600
        repeat: false
        onTriggered: root.suspensionDirection = 0
    }
    Timer {
        id: suspBlinkTimer
        interval: 500
        repeat: true
        running: root.suspensionDirection !== 0
        onRunningChanged: if (!running) root.suspBlinkOn = false
        onTriggered: root.suspBlinkOn = !root.suspBlinkOn
    }

    function suspensionUp() {
        root.suspensionLevel = Math.min(1, root.suspensionLevel + 1)
        root.suspensionDirection = 1
        suspHoldTimer.restart()
    }

    function suspensionDown() {
        root.suspensionLevel = Math.max(-1, root.suspensionLevel - 1)
        root.suspensionDirection = -1
        suspHoldTimer.restart()
    }

    function nextCenterMode() {
        centerMode = (centerMode + 1) % centerModeCount
    }

    function prevCenterMode() {
        centerMode = (centerMode + centerModeCount - 1) % centerModeCount
    }

    // ======================= ГЕОМЕТРИЯ МАКЕТА =======================
    readonly property int dialSize: 714        // диаметр прибора
    readonly property int dialY: 3             // (720 - 714) / 2 — по центру экрана
    readonly property int dialLeftX: 0         // спидометр вплотную к левому краю
    readonly property int dialRightX: 1206     // тахометр вплотную к правому краю
    readonly property int centerX: 714         // центральная область: 714..1206
    readonly property int centerWidth: 492

    // Приборы в режиме навигации: уменьшаются и уходят в нижние углы, как в Audi,
    // освобождая экран под карту. Карта при этом идёт под приборы, поэтому под
    // каждым прибором ставится непрозрачная подложка: сами циферблаты
    // полупрозрачные (альфа 255 только в центре, на радиусе 300 — уже 16)
    // и поверх карты становятся нечитаемыми.
    readonly property real navScale: 0.5
    readonly property int navMargin: 8
    readonly property real navInset: dialSize * (1 - navScale) / 2

    // Масштабирование всего макета под размер окна (на устройстве ровно 1.0)
    readonly property real canvasScale: Math.min(width / 1920, height / 720)

    // ======================= НАСТРОЙКИ ПРИБОРКИ =======================
    // Открываются клавишей S (или F1/F3 — MENU/OPTION джойстика) либо двойным
    // кликом по центральной области. Сам оверлей объявлен внутри canvas —
    // там он масштабируется вместе с макетом (см. Settings.qml).
    // Коэффициенты хранит Settings.qml, пробег — CanBackend.

    Component.onCompleted: {
        root.attachGps()
        // Коэффициенты и настройки загружаются в Settings.qml в ЕГО
        // Component.onCompleted, а он выполняется ПОСЛЕ родительского —
        // поэтому читаем значения отложенно, иначе сохраноённые брались бы
        // как значения по умолчанию.
        Qt.callLater(root.applyCalibration)

        // С 3D-машиной старт идёт по сценарию 4 секунды: сначала темно,
        // потом машина выезжает по дороге, и только на 3–4 с проявляются
        // приборы (пока видна машина — никаких показаний).
        // Без 3D (--no-3d) всё как раньше: лампы и стрелки сразу, 2.5 секунды.
        if (root.car3d) {
            root.startupStage = 0.0
            root.gaugesOpacity = 0.0
            root.startup = false
            root.lampSelfTest = false
            // Стартовый экран — это 5-й вид: машина на дороге, никаких данных.
            // Так и остаётся: нужный вид пользователь выберет сам (щелчок по
            // центру листает режимы).

            root.centerMode = 4
            // Сама заставка стартует в beginStartup() — после первого кадра.
        }
    }

    // Сценарий запуска: машина едет 0–4 с, приборы проявляются 3–4 с,
    // затем обычная самопроверка ламп и стрелок (2.5 с).
    SequentialAnimation {
        id: startupSequence

        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "startupStage"
                from: 0.0
                to: 1.0
                duration: 9000
                // Линейно: иначе в самом начале был «мёртвый» участок, пока
                // кривая разгонялась, и детали стояли на месте.
                easing.type: Easing.Linear
            }
            SequentialAnimation {
                // Машина собирается ~5.3 с и стоит — приборы проявляются
                // только после сборки
                PauseAnimation { duration: 7000 }
                // Самопроверка запускается вместе с проявлением приборов,
                // иначе проход стрелок проходит, пока приборов ещё не видно
                ScriptAction { script: { root.startup = true; root.lampSelfTest = true } }
                NumberAnimation {
                    target: root
                    property: "gaugesOpacity"
                    from: 0.0
                    to: 1.0
                    duration: 1200
                }
            }
        }

        // Лампы горят 2.5 с (как в исходной самопроверке), затем штатный режим
        PauseAnimation { duration: 2500 }
        ScriptAction {
            script: {
                root.startup = false
                root.lampSelfTest = false
                root.startupFinished()
            }
        }
    }

    // Мигание предупреждения о запасе хода: 1 Гц — 500 мс горит, 500 мс нет.
    // Флаг сбрасывается, когда мигание прекращается, чтобы текст не остался
    // погашенным.
    Timer {
        interval: 500
        repeat: true
        running: root.rangeCritical
        onRunningChanged: if (!running) root.rangeBlinkOn = true
        onTriggered: root.rangeBlinkOn = !root.rangeBlinkOn
    }

    Item {
        id: canvas
        width: 1920
        height: 720
        transformOrigin: Item.TopLeft
        scale: root.canvasScale
        x: (root.width - width * scale) / 2
        y: (root.height - height * scale) / 2

        // ============ МАРШРУТЫ (офлайн GraphHopper) ============
        RouteService {
            id: route
            onRouteReady: function(coords) {
                offlineMapView.setRoute(coords)
                // Геометрия для мини-карты мультимедиа (§6.6): в route_state
                // она не нужна, а полилиния на телефоне полезна.
                NetworkServer.setRoutePath(coords)
            }
        }

        // ============ ОФЛАЙН-КАРТА (навигация) ============
        // Живёт под приборами: когда включается навигация, приборы уезжают
        // в углы, а тут остаётся карта. Тайлы отдаёт локальный сервер.
        MapView {
            id: offlineMapView
            anchors.fill: parent
            z: -20
            active: root.navigationMode && root.offlineMap
            latitude: root.gpsLat
            longitude: root.gpsLon
            course: root.gpsCourse
            mapZoom: root.mapZoom
        }

        // ============ ПОДСКАЗКА МАНЁВРА (свой маршрут) ============
        // В навигации на своей карте плашка с ближайшим манёвром и
        // остатком пути (данные RouteService/GraphHopper).
        RouteHint {
            id: routeHint
            x: (parent.width - width) / 2
            y: parent.height - height - 12
            z: 6
            shown: root.navigationMode && root.offlineMap && route.ready
            distanceM: route.hintDistanceM
            sign: route.hintSign
            hintText: route.hintText
            nextHintText: route.nextHintText
            nextManeuver: route.nextHintManeuver
            nextDistanceM: route.nextHintDistanceM
            remainM: Math.max(0, route.routeDistanceM - route.traveledM)
            remainS: route.routeDistanceM > 0
                     ? route.routeTimeS
                       * Math.max(0, route.routeDistanceM - route.traveledM)
                       / route.routeDistanceM
                     : 0
        }

        // ============ ИЗБРАННОЕ НА КАРТЕ ============
        // В навигации слева сверху: энкодер листает список, PRESS строит
        // маршрут к выбранной точке; ◀/▶ сдвигают вид карты — тогда в
        // центре перекрестие, и PRESS означает «сюда».
        Item {
            id: favoritesPanel
            x: root.navMargin
            y: 12
            width: 190
            height: favoriteCol.height + 22
            z: 5
            visible: root.navigationMode && root.offlineMap

            Rectangle {
                anchors.fill: parent
                radius: 8
                color: "#0B141CCC"
                border.color: "#24343F"
            }
            Column {
                id: favoriteCol
                x: 10
                y: 8
                spacing: 2
                Text {
                    text: root.mapDetached ? "ПЕРЕКРЕСТИЕ" : "НАЗНАЧЕНИЕ"
                    color: "#5D7484"
                    font.pixelSize: 10
                    font.letterSpacing: 2
                }
                Repeater {
                    model: root.navChoices
                    delegate: Text {
                        required property int index
                        required property var modelData
                        text: modelData.name
                        color: root.mapDetached ? "#3A4A57"
                             : (index === root.favoriteIndex ? "#BCEAF1" : "#7A8B99")
                        font.pixelSize: 15
                        font.bold: index === root.favoriteIndex && !root.mapDetached
                    }
                }
                Text {
                    text: root.mapDetached ? "PRESS — сюда" : "PRESS — маршрут"
                    color: "#40556A"
                    font.pixelSize: 10
                }
            }
        }

        // ============ ВТОРОЙ СКИН «GENESIS» ============
        // Рисуется своими примитивами и, когда включён, закрывает классическую
        // раскладку плотным фоном. Данные — те же свойства root, поэтому оба
        // скина показывают одно и то же.
        GenesisSkin {
            anchors.fill: parent
            z: 50
            visible: root.skin === "genesis"
            speed: root.speed
            rpm: root.rpmShown
            gear: root.gearMode
            fuel: root.fuelLevel
            temp: root.temp
            clock: root.timeString
            tripKm: CanBackend.journeyKm
            rangeKm: root.rangeKmValid ? root.rangeKm : 0
            nightMode: root.nightMode
            // камеры слепых зон в колодцах приборов
            centerMode: root.centerMode
            allLampsOn: root.lampsAllOn
            blindSpotEnabled: root.blindSpotEnabled
            promoVideoLeft: root.promoVideoLeft
            promoVideoRight: root.promoVideoRight
            cameraLeft: root.leftTurn
            cameraRight: root.rightTurn
            // вход в настройки из скина (двойной клик по центру)
            onSettingsRequested: calibration.open()
        }

        // Оверлей настроек живёт на уровне canvas, а не внутри dashboardLayer:
        // иначе его z: 300 считается только среди соседей внутри слоя,
        // и скин Genesis (z: 50) закрывал бы настройки собой.
        Settings {
            id: calibration

            nightMode: root.nightMode

            onSettingsApplied: function(sf, rf, ff, tf) {
                root.speedFactor = sf
                root.rpmFactor = rf
                root.fuelFactor = ff
                root.tempFactor = tf
            }
        }

        // ============ 3D-МАШИНА: 5-й вид центральной зоны (714,154,492×404) ============
        // Машина живёт только в пятом режиме панели: там нет никаких данных —
        // ни чисел, ни режимных подписей. В остальных режимах её нет вовсе,
        // чтобы показания не ложились поверх модели.
        Car3DView {
            id: carView
            // В классике вид шире центральной зоны: концы дороги уходят под
            // приборы (560…1360). В скине Genesis приборы крупнее и ближе к
            // центру, поэтому вид ставится в свободную колонку между ними
            // (711…1229) и поднимается над скином (z 60 против 50).
            readonly property bool inGenesis: root.skin === "genesis"
            // В Genesis вид ставится ровно в просвет между приборами: кольца
            // шкал — радиус 326 от центров (421,357) и (1502,358), значит
            // просвет по горизонтали 747…1176. Берём с запасом 5 px по краям:
            // 752…1172 = 420 px. Пропорции как в классике (800×406 ≈ 1.97),
            // отсюда высота 213 и центр по вертикали приборов (251…464).
            x: inGenesis ? 752 : 560
            y: inGenesis ? 251 : 149
            width: inGenesis ? 420 : 800
            height: inGenesis ? 213 : 406
            z: inGenesis ? 60 : 0
            // Фон сцены: в Genesis он прозрачный, чтобы чёрный квадрат не
            // выделялся на панели; в классике как было — чёрный.
            transparentBackground: inGenesis
            backgroundColor: inGenesis ? "#080F15" : "black"

            progress: root.startupStage
            roadVisible: root.panelReady
            roadSpeed: root.speed
            // Свет по CAN: фары/габариты зажигают фары и задние фонари на
            // модели, поворотники мигают вместе с лампой на панели.
            // Два уровня света, как на настоящей машине:
            //   габариты (0x200 байт 0 бит 4) — слабое свечение ламп и фонарей;
            //   ближний свет (бит 3)         — основной, яркий свет и пятно
            //                                  на дороге.
            // Пока модель не собрана, света нет совсем.
            // debugHeadlights/debugLowBeam — только для снимков на стенде.
            headlightsOn: root.positionLights || root.debugHeadlights
            mainBeamOn: root.lowBeam || root.debugLowBeam
            leftTurn: root.leftTurn
            rightTurn: root.rightTurn
            turnBlink: root.turnBlink
            // 6-й вид — профиль машины и пневмоподвеска
            viewSide: root.centerMode === 5
            suspensionLevel: root.suspensionLevel
            doorsOpen: root.doorsOpen
            doorFL: root.demoDoorFL
            doorFR: root.demoDoorFR
            doorRL: root.demoDoorRL
            doorRR: root.demoDoorRR
            capotOpen: root.capotOpen
            trunkOpen: root.trunkOpen
            opacity: 1.0
            // Видна в 5-м режиме всегда; во время заставки — пока приборы
            // ещё погашены (gaugesOpacity < 0.01), чтобы данные не ложились
            // поверх машины.
            visible: root.car3d && !root.navigationMode
                     && (root.centerMode === 4 || root.centerMode === 5
                         || root.gaugesOpacity < 0.01)
        }

        // Виньетка поверх 3D-вида в скине Genesis: растворяет края
        // прямоугольника в фоне панели. Отдельный слой выше вида (z 62 против
        // 60), а не ребёнок Car3DView — так порядок отрисовки не зависит от
        // того, как Loader сцены вставляет свои узлы.
        Image {
            // на 8 px больше вида: внешняя кайма перекрывает его границу
            x: 744
            y: 243
            width: 436
            height: 229
            visible: root.skin === "genesis" && root.car3d && !root.navigationMode
            source: "images/genesis/car3d_fade.png"
            fillMode: Image.Stretch
            z: 62
        }

        // ============ СЛОЙ ПРИБОРОВ ============
        // Всё остальное лежит здесь: на старте слой погашен и проявляется
        // на 2.5–3.5 с. Машина — снаружи слоя, поэтому она видна всё время
        // и не гаснет вместе с приборами.
        Item {
            id: dashboardLayer
            anchors.fill: parent
            opacity: root.gaugesOpacity

        // ========== РАЗДЕЛИТЕЛЬНЫЕ ЛИНИИ ЦЕНТРАЛЬНОЙ ОБЛАСТИ ==========
        // Натуральный размер картинок 641x5 (раньше их растягивали до 500x10 —
        // сжимали по ширине и вдвое утолщали, поэтому концы не доходили до
        // приборов). Ширина 800: концы заходят под циферблаты и там скрываются —
        // под каждым прибором лежит непрозрачная чёрная подложка, без неё
        // полупрозрачные циферблаты просвечивают и полосы видно на шкалах.
        // В навигации полосы убираем: там карта на весь экран, резать её незачем.
        Image {
            source: "images/line_up.png"
            x: 560; y: 149
            width: 800; height: 5
            fillMode: Image.Stretch
            opacity: root.navigationMode ? 0.0 : 1.0
            Behavior on opacity { NumberAnimation { duration: root.navigationAnimDuration } }
        }
        Image {
            source: "images/line_down.png"
            x: 560; y: 558
            width: 800; height: 5
            fillMode: Image.Stretch
            opacity: root.navigationMode ? 0.0 : 1.0
            Behavior on opacity { NumberAnimation { duration: root.navigationAnimDuration } }
        }

        // ========== КАРТА: на весь экран, как в Audi ==========
        // Лежит под всем остальным (z = -10). Приборы в навигации уменьшаются
        // и уходят в нижние углы, поэтому карта под ними не мешает.
        // Навигационный режим: карта и подсказки приходят от Android по сети
        // (docs/integration.md). Когда Android присылает кадры карты — карта
        // на весь экран, приборы уезжают в углы. Когда не присылает (нет
        // связи, маршрут не задан) — карточка манёвра в центре.
        NavPanel {
            id: navPanel
            anchors.fill: parent
            active: root.navigationMode && !root.offlineMap
            opacity: root.navigationMode ? 1.0 : 0.0
            visible: root.navigationMode || opacity > 0
            z: -10

            Behavior on opacity {
                NumberAnimation { duration: root.navigationAnimDuration; easing.type: Easing.InOutQuad }
            }
        }

        // Затемнение верхнего и нижнего края карты: показания (лампы, часы,
        // строка значений) должны читаться поверх карты.
        Rectangle {
            anchors.fill: parent
            z: -5
            opacity: root.navigationMode ? 1.0 : 0.0
            visible: opacity > 0
            gradient: Gradient {
                GradientStop { position: 0.00; color: "#E6000000" }
                GradientStop { position: 0.14; color: "#B3000000" }
                GradientStop { position: 0.32; color: "#00000000" }
                GradientStop { position: 0.62; color: "#00000000" }
                GradientStop { position: 0.76; color: "#B3000000" }
                GradientStop { position: 1.00; color: "#E6000000" }
            }
            Behavior on opacity { NumberAnimation { duration: root.navigationAnimDuration } }
        }

        // Здесь была скруглённая подложка под часами и наружной температурой
        // (x 1726, y 26) — остаток прежней раскладки, когда они стояли на
        // тахометре. Сейчас и часы, и температура живут в центральной полосе,
        // под затемнением сверху, поэтому подложка только мазала карту.

        // ========== КОНТЕЙНЕР СПИДОМЕТРА ==========
        Item {
            id: speedoContainer
            x: root.navigationMode ? (root.navMargin - root.navInset) : root.dialLeftX
            y: root.navigationMode ? (parent.height - root.dialSize * root.navScale - root.navMargin - root.navInset) : root.dialY
            width: root.dialSize
            height: root.dialSize
            scale: root.navigationMode ? root.navScale : 1.0
            z: 1

            Behavior on x { NumberAnimation { duration: root.navigationAnimDuration; easing.type: Easing.InOutQuad } }
            Behavior on y { NumberAnimation { duration: root.navigationAnimDuration; easing.type: Easing.InOutQuad } }
            Behavior on scale { NumberAnimation { duration: root.navigationAnimDuration; easing.type: Easing.InOutQuad } }

            // Непрозрачная подложка под прибором. Нужна в обоих режимах:
            // циферблаты полупрозрачные (альфа 255 только в центре, на радиусе
            // 300 — уже 16), поэтому без подложки под ними просвечивают
            // разделительные полосы, а в навигации — карта.
            Rectangle {
                anchors.centerIn: parent
                width: parent.width
                height: parent.height
                radius: width / 2
                color: "black"
            }

            Speedometer {
                id: speedo
                anchors.fill: parent
                speed: root.speed * root.speedFactor
                gearMode: root.gearMode
                gearLock: root.gearLock
                // В 1-м виде (стандарт) скорость и передача уже в центре:
                // цифры на циферблате и индикатор АКПП не дублируем.
                showDigital: root.centerMode !== 0
                showGear: root.centerMode !== 0
                // На газу стрелка показывает уровень газа (проценты баллона),
                // на бензине — бензин: как на двухтопливной машине.
                fuelLevel: root.gasDisplay
                           ? root.gasLevelPercent
                           : root.fuelLevel * root.fuelFactorEffective
                fuelAngleE: calibration.fuelAngleE
                fuelAngleF: calibration.fuelAngleF
                startup: root.startup
                nightMode: root.nightMode
                cameraVisible: root.leftTurn && root.blindSpotEnabled
                cameraLabel: "L"
                cameraVideoSource: root.promoVideoLeft
                seatBeltWarning: root.lampTestOn || root.seatBelt
                handBrakeWarning: root.lampTestOn || root.handBrake
                fuelWarning: root.lampTestOn || (root.fuelLevel <= 10)
                batteryWarning: root.lampTestOn || (root.rpmShown > 400 && root.voltage < 12.8)
                gasMode: root.gasDisplay
                z: 1
            }
        }

        // ========== КОНТЕЙНЕР ТАХОМЕТРА ==========
        Item {
            id: tachoContainer
            x: root.navigationMode ? (parent.width - root.navMargin - root.dialSize * root.navScale - root.navInset) : root.dialRightX
            y: root.navigationMode ? (parent.height - root.dialSize * root.navScale - root.navMargin - root.navInset) : root.dialY
            width: root.dialSize
            height: root.dialSize
            scale: root.navigationMode ? root.navScale : 1.0
            z: 1

            Behavior on x { NumberAnimation { duration: root.navigationAnimDuration; easing.type: Easing.InOutQuad } }
            Behavior on y { NumberAnimation { duration: root.navigationAnimDuration; easing.type: Easing.InOutQuad } }
            Behavior on scale { NumberAnimation { duration: root.navigationAnimDuration; easing.type: Easing.InOutQuad } }

            // Непрозрачная подложка под прибором (см. спидометр)
            Rectangle {
                anchors.centerIn: parent
                width: parent.width
                height: parent.height
                radius: width / 2
                color: "black"
            }

            Tachometer {
                id: tacho
                anchors.fill: parent
                // В 1-м виде обороты уже в центре — цифры на циферблате скрыты
                showDigital: root.centerMode !== 0
                rpm: root.rpmShown * root.rpmFactor
                temp: root.temp * root.tempFactor
                cameraVisible: root.rightTurn && root.blindSpotEnabled
                cameraLabel: "R"
                cameraVideoSource: root.promoVideoRight
                tempAngleStart: calibration.tempAngleStart
                tempAngleEnd: calibration.tempAngleEnd
                startup: root.startup
                nightMode: root.nightMode
                absWarning: root.lampTestOn || root.abs
                checkEngineWarning: root.lampTestOn || root.checkEngine
                oilPressureWarning: root.lampTestOn || root.oilPressureAlarm
                tempWarning: root.lampTestOn || (root.temp >= 110)
                z: 1
            }
        }

        // ========== ЦЕНТРАЛЬНАЯ ОБЛАСТЬ ==========
        // Ровно между линиями-разделителями. Внутри — переключаемые режимы
        // (CenterPanel.qml); навигация отдельно, карта рисуется на весь экран.
        Item {
            id: centerPanel
            x: root.centerX
            y: 154
            width: root.centerWidth
            height: 404

            CenterPanel {
                id: centerPanelView
                // Панель — НАД областью кликов: иначе MouseArea перехватывает
                // нажатия и кнопки подвески ▲/▼ в 6-м виде не нажимаются.
                // Свободные от кнопок места панели клики не перехватывают —
                // листание режимов по центру продолжает работать.
                z: 1
                anchors.fill: parent
                mode: root.centerMode
                engineRpm: root.rpmShown * root.rpmFactor
                nightMode: root.nightMode
                suspensionLevel: root.suspensionLevel
                suspensionDirection: root.suspensionDirection
                suspBlinkOn: root.suspBlinkOn
                onSuspensionUp: root.suspensionUp()
                onSuspensionDown: root.suspensionDown()

                // В навигации карта занимает весь экран, и панель поверх неё
                // только мешает: гасим её так же, как разделительные полосы.
                // Область нажатий (MouseArea ниже) остаётся живой — долгое
                // нажатие по центру по-прежнему выводит из навигации.
                opacity: root.navigationMode ? 0.0 : 1.0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: root.navigationAnimDuration } }
            }

            // Одиночное нажатие — следующий режим, двойное — калибровка,
            // долгое — навигация. Одиночное ждём 220 мс, иначе двойной клик
            // успевал бы заодно переключить режим.
            MouseArea {
                anchors.fill: parent
                onPressAndHold: root.navigationMode = !root.navigationMode
                onClicked: centerTap.restart()
                onDoubleClicked: {
                    centerTap.stop()
                    calibration.open()
                }
            }

            Timer {
                id: centerTap
                interval: 220
                onTriggered: root.nextCenterMode()
            }
        }

        // Клавиши — удобно на столе и пригодится для кнопок на руле
        // ---- ДЕМО: двери/капот/багажник по клавишам 1..6 ----
        Shortcut { sequence: "1"; onActivated: { root.demoDoorFL = !root.demoDoorFL
                                                 console.log("DEMO: дверь FL", root.demoDoorFL ? "открыта" : "закрыта") } }
        Shortcut { sequence: "2"; onActivated: { root.demoDoorFR = !root.demoDoorFR
                                                 console.log("DEMO: дверь FR", root.demoDoorFR ? "открыта" : "закрыта") } }
        Shortcut { sequence: "3"; onActivated: { root.demoDoorRL = !root.demoDoorRL
                                                 console.log("DEMO: дверь RL", root.demoDoorRL ? "открыта" : "закрыта") } }
        Shortcut { sequence: "4"; onActivated: { root.demoDoorRR = !root.demoDoorRR
                                                 console.log("DEMO: дверь RR", root.demoDoorRR ? "открыта" : "закрыта") } }
        Shortcut { sequence: "5"; onActivated: { calibration.capotOpen = !calibration.capotOpen
                                                 console.log("DEMO: капот", calibration.capotOpen ? "открыт" : "закрыт") } }
        Shortcut { sequence: "6"; onActivated: { calibration.trunkOpen = !calibration.trunkOpen
                                                 console.log("DEMO: багажник", calibration.trunkOpen ? "открыт" : "закрыт") } }

        // C — демо-камера (Smart Driver): поставить в 420 м впереди машины,
        // повторное нажатие — убрать. Нужна для проверки предупреждения дома
        // и в --mock, где реальных камер рядом с трассой демо-маршрута нет.
        Shortcut { sequence: "C"; onActivated: {
                      if (SpeedCamManager.demoCameraActive) {
                          SpeedCamManager.clearSimulated()
                          console.log("DEMO: камера убрана")
                      } else {
                          SpeedCamManager.simulateCameraAhead(60, 420)
                          console.log("DEMO: камера в 420 м впереди, ограничение 60")
                      }
                  } }

        // N — навигация (тот же путь, что кнопка NAV на джойстике: кадр 0x530),
        // S — настройки. Пока на руле нет кнопок — удобные клавиши на столе.
        Shortcut { sequence: "N"; onActivated: input.button(6) }
        Shortcut { sequence: "S"; onActivated: calibration.open() }

        // F8 — переключить скин (классический ↔ Genesis): приёмка на столе
        // L — показать все лампы сразу (отладка раскладки значков)
        Shortcut { sequence: "L"; onActivated: {
                      root.lampsAllOn = !root.lampsAllOn
                      console.log("Отладка: все лампы", root.lampsAllOn ? "ВКЛ" : "выкл")
                  } }

        Shortcut { sequence: "F8"; onActivated: {
                      root.skin = root.skin === "genesis" ? "classic" : "genesis"
                      console.log("Скин:", root.skin)
                  } }

        Shortcut { sequence: "Space"; onActivated: root.nextCenterMode() }

        // ---- ЭМУЛЯТОР ДЖОЙСТИКА (на столе, без железа) ----
        // Клавиши повторяют кнопки BMW iDrive один в один и идут через тот же
        // InputController, что и кадры 0x530: проверяем реальный код, а не
        // отдельную «демо-ветку». В машине эти клавиши никто не нажимает.
        //   F1 MENU   F2 BACK   F3 OPTION   F4 RADIO   F5 MEDIA   F6 NAV
        //   F7 TEL    F9 UP     F10 DOWN    F11 LEFT    F12 RIGHT
        //   Insert PRESS     «=» энкодер вперёд     «-» энкодер назад
        Shortcut { sequence: "F1";  onActivated: input.button(1) }
        Shortcut { sequence: "F2";  onActivated: input.button(2) }
        Shortcut { sequence: "F3";  onActivated: input.button(3) }
        Shortcut { sequence: "F4";  onActivated: input.button(4) }
        Shortcut { sequence: "F5";  onActivated: input.button(5) }
        Shortcut { sequence: "F6";  onActivated: input.button(6) }
        Shortcut { sequence: "F7";  onActivated: input.button(7) }
        Shortcut { sequence: "F9";  onActivated: input.button(8) }
        Shortcut { sequence: "F10"; onActivated: input.button(9) }
        Shortcut { sequence: "F11"; onActivated: input.button(10) }
        Shortcut { sequence: "F12"; onActivated: input.button(11) }
        Shortcut { sequence: "Insert"; onActivated: input.button(12) }
        // На ноутбуках без Insert: Enter дублирует PRESS (выбор пункта назначения).
        Shortcut { sequence: "Return"; onActivated: input.button(12) }
        Shortcut { sequence: "="; onActivated: input.encoder(1) }
        Shortcut { sequence: "+"; onActivated: input.encoder(1) }
        Shortcut { sequence: "-"; onActivated: input.encoder(-1) }
        Shortcut { sequence: "_"; onActivated: input.encoder(-1) }
        // ←/→ — демо-поворотники: нажал — включил, ещё раз — отключил
        Shortcut { sequence: "Left"; onActivated: { root.demoLeftTurn = !root.demoLeftTurn
                                                    console.log("DEMO: левый поворотник", root.demoLeftTurn ? "ВКЛ" : "выкл") } }
        Shortcut { sequence: "Right"; onActivated: { root.demoRightTurn = !root.demoRightTurn
                                                     console.log("DEMO: правый поворотник", root.demoRightTurn ? "ВКЛ" : "выкл") } }

        // ========== ВЕРХНЯЯ ЗОНА ЦЕНТРА: предупреждения ==========
        // Держим их вне области карты, чтобы были видны и в навигации.
        Item {
            x: root.centerX
            y: 92
            width: root.centerWidth
            height: 42

            Row {
                anchors.centerIn: parent
                spacing: 22

                // Нет данных от блока сбора (ESP32): кадры не приходят дольше 1,5 с
                Text {
                    id: noCanWarning
                    text: "НЕТ ДАННЫХ CAN"
                    color: "#FF4444"
                    font.pixelSize: 20
                    font.bold: true
                    visible: !root.canDataValid

                    SequentialAnimation on opacity {
                        running: noCanWarning.visible
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.3; to: 1.0; duration: 600 }
                        NumberAnimation { from: 1.0; to: 0.3; duration: 600 }
                    }
                }

                // Гололёд
                Text {
                    id: iceWarning
                    text: "⚠ ГОЛОЛЁД"
                    color: "#FF4444"
                    font.pixelSize: 20
                    font.bold: true
                    visible: root.outsideTemp <= 0

                    SequentialAnimation on opacity {
                        running: iceWarning.visible
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.35; to: 1.0; duration: 700 }
                        NumberAnimation { from: 1.0; to: 0.35; duration: 700 }
                    }
                }

                // Мало топлива: запас хода меньше 50 км — жёлтым, меньше 20 км —
                // красным и мигает 1 Гц. Мигание — через отдельный флаг и Timer
                // (как поворотники в Indicators.qml): анимация на opacity,
                // остановившись, оставила бы текст притушенным на том кадре,
                // где мигание прекратилось.
                Text {
                    id: rangeWarning
                    text: "ЗАПРАВКА " + Math.round(root.rangeKm) + " КМ"
                    color: root.rangeCritical ? "#FF4444" : "#FFC64A"
                    font.pixelSize: 20
                    font.bold: true
                    visible: root.rangeKmValid && root.rangeKm < 50
                             && (!root.rangeCritical || root.rangeBlinkOn)
                }
            }
        }

        // ========== НИЖНЯЯ ЗОНА ЦЕНТРА: показания ==========
        // Вольтметр, топливо, температура двигателя, расход. Раньше это была
        // колонка в центре — в навигации она попадала на карту.
        Item {
            x: root.centerX
            y: 570
            width: root.centerWidth
            height: 40

            Row {
                anchors.centerIn: parent
                spacing: 12

                Text {
                    text: root.voltage.toFixed(1) + " В"
                    color: root.nightMode ? "#FF8800" : "white"
                    font.pixelSize: 24
                    font.bold: true
                }
                Text {
                    text: "·"
                    color: "#555555"
                    font.pixelSize: 24
                }
                // Топливо: на газу вместо литров бензина показываем остаток газа
                // в процентах — уровень бензина и так виден стрелкой на шкале
                // прибора, а на газу важно, сколько осталось в баллоне.
                // Если датчик уровня газа не отвечает, вместо числа прочерк:
                // показывать «0 %» было бы враньём (протокол 1.2).
                Text {
                    text: !root.gasDisplay
                          ? (Math.min(root.fuelLevel * root.fuelFactorEffective / 100, 1)
                             * root.tankCapacity).toFixed(1) + " л"
                          : (root.gasSensorValid
                             ? "газ " + root.gasLevelPercent + " %"
                             : "газ —")
                    color: root.gasDisplay ? "#33CC44"
                                           : (root.nightMode ? "#FF8800" : "white")
                    font.pixelSize: 24
                    font.bold: true
                }
                Text {
                    text: "·"
                    color: "#555555"
                    font.pixelSize: 24
                }
                Text {
                    // Температура — как соседние показания, с одним знаком:
                    // «0,0 °C», а не «0 °C».
                    text: root.temp.toFixed(1) + " °C"
                    color: root.nightMode ? "#FF8800" : "white"
                    font.pixelSize: 24
                    font.bold: true
                }
                Text {
                    text: "·"
                    color: "#555555"
                    font.pixelSize: 24
                }
                Text {
                    text: root.fuelRate.toFixed(1) + " л/100"
                    color: root.nightMode ? "#FF8800" : "white"
                    font.pixelSize: 22
                    font.bold: true
                }
            }
        }

        Indicators {
            id: lamps
            // Индикаторы (стрелки поворотников и лампы) — НАД циферблатами:
            // у контейнеров приборов z: 1, и без этого стрелки прятались
            // под непрозрачной подложкой спидометра.
            z: 2
            leftTurn: root.leftTurn
            rightTurn: root.rightTurn
            blinkOn: root.turnBlink
            highBeam: root.highBeam
            lowBeam: root.lowBeam
            positionLights: root.positionLights
            fogLights: root.fogLights
            brakeLights: root.brakeLights
            reverseLights: root.reverseLights
            checkEngine: root.checkEngine
            abs: root.abs
            handBrake: root.handBrake
            seatBelt: root.seatBelt
            gearLock: root.gearLock
            gearMode: root.gearMode
            timeString: root.timeString
            odometer: root.odometer
            tripA: root.tripA
            tripB: root.tripB
            selfTest: root.lampTestOn
        }

        // ========== ПРЕДУПРЕЖДЕНИЕ О КАМЕРЕ (Smart Driver) ==========
        // Верхняя полоса между приборами: циферблаты — это круги радиусом 357
        // с центрами на осях приборов, поэтому в центре сверху места хватает.
        // Пока камера дальше 500 м (или база пуста) — блока нет вообще,
        // и он не перекрывает центральную панель.
        CameraWarning {
            // Под верхней полосой и над машиной: раньше висело у самого края
            // экрана, теперь — в верхней части центральной области (панель
            // начинается с y=154, крыша машины примерно с 250).
            x: root.centerX + (root.centerWidth - width) / 2
            y: root.navigationMode ? 10 : 160
            width: root.navigationMode ? 300 : 480
            height: root.navigationMode ? 60 : 78
            z: 6
            compact: root.navigationMode
            enabled: root.cameraWarningEnabled
        }

        Rectangle {
            id: closeNavButton
            width: 60; height: 60
            radius: 30; color: "#CC0000"
            x: parent.width - width - 20
            y: 20
            visible: root.navigationMode
            z: 200

            Text {
                text: "✕"
                anchors.centerIn: parent
                color: "white"
                font.pixelSize: 32
                font.bold: true
            }
            MouseArea {
                anchors.fill: parent
                onClicked: root.navigationMode = false
            }
        }

        // Регулировка яркости (в будущем — от габаритов/датчика освещённости)
        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: 1.0 - root.brightness
            z: 100
            enabled: false
        }


        // ====================================================================
        //  Настройки приборки. Оверлей поверх всего остального (z 300):
        //  объявлен внутри canvas, поэтому масштабируется вместе с макетом.
        //  Открывается клавишей S (F1/F3) или двойным кликом по центру.
        // ====================================================================

        // ====================================================================
        //  Самопроверка ламп и стрелок при включении зажигания
        // ====================================================================
        Timer {
            interval: 2500
            // С 3D-заставкой самопроверку запускает startupSequence
            running: !root.car3d
            onTriggered: {
                root.lampSelfTest = false
                root.startup = false
            }
        }

        // ====================================================================
        //  Часы. Время в CAN-протоколе пока не передаётся — берём системное.
        // ====================================================================
        Timer {
            interval: 1000
            running: true
            repeat: true
            triggeredOnStart: true
            onTriggered: {
                var now = new Date()
                root.timeString = now.getHours().toString().padStart(2, '0') + ":"
                                + now.getMinutes().toString().padStart(2, '0')
            }
        }
        }   // dashboardLayer

        // ============ ПОГОДНЫЙ ФОН (дождь/снег) ============
        // Поверх приборов, а не под ними: циферблаты непрозрачные и
        // полностью закрывают экран — под ними дождь не виден вовсе.
        // Полупрозрачно, чтобы показания читались.
        WeatherFx {
            anchors.fill: parent
            enabled: root.weatherEnabled
        }
    }
}
