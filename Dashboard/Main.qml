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

    // Приколы (анимация в правом верхнем углу) включаются и выключаются
    // в настройках, отдельной строкой «Приколы». Состояние хранит Settings.qml.
    readonly property bool funEnabled: calibration.funEnabled
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
    property real brightness: 1.0
    property bool navigationMode: false
    property real navigationAnimDuration: 400

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
            // Медиа-режим центральной панели (7). Карта при этом закрывается:
            // это два разных «полноэкранных» вида, и вместе они не нужны.
            root.navigationMode = false
            root.centerMode = 7
            break
        case "radio":
            root.navigationMode = false
            root.centerMode = 6
            break
        case "option":
        case "menu":
            calibration.open()
            break
        case "left":
            root.prevCenterMode()
            break
        case "right":
        case "press":
            root.nextCenterMode()
            break
        case "next":
            lamps.cycleOdometer(1)
            break
        case "prev":
            lamps.cycleOdometer(-1)
            break
        case "up":
        case "down":
            // Зарезервировано: зум карты и листание списков в навигации.
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
    // Открываются кнопкой «Настройки» внизу центральной полосы или двойным
    // кликом по центральной области. Сам оверлей объявлен внутри canvas —
    // там он масштабируется вместе с макетом (см. Settings.qml).
    // Коэффициенты хранит Settings.qml, пробег — CanBackend.

    Component.onCompleted: {
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

        // ============ 3D-МАШИНА: 5-й вид центральной зоны (714,154,492×404) ============
        // Машина живёт только в пятом режиме панели: там нет никаких данных —
        // ни чисел, ни режимных подписей. В остальных режимах её нет вовсе,
        // чтобы показания не ложились поверх модели.
        Car3DView {
            id: carView
            // Шире центральной зоны: концы дороги упираются в точки, где
            // горизонтальные полосы уходят под тахометр и спидометр
            // (560…1360), при 492 они висели бы внутри зоны.
            x: 560
            y: 149
            width: 800
            height: 406
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
        MapWebView {
            id: navMap
            anchors.fill: parent
            opacity: root.navigationMode ? 1.0 : 0.0
            visible: root.navigationMode || opacity > 0
            active: root.navigationMode
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
                seatBeltWarning: root.lampSelfTest || root.seatBelt
                handBrakeWarning: root.lampSelfTest || root.handBrake
                fuelWarning: root.lampSelfTest || (root.fuelLevel <= 10)
                batteryWarning: root.lampSelfTest || (root.rpmShown > 400 && root.voltage < 12.8)
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
                absWarning: root.lampSelfTest || root.abs
                checkEngineWarning: root.lampSelfTest || root.checkEngine
                oilPressureWarning: root.lampSelfTest || root.oilPressureAlarm
                tempWarning: root.lampSelfTest || (root.temp >= 110)
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
            selfTest: root.lampSelfTest
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

        // ========== ВЕРХНИЙ ПРАВЫЙ УГОЛ: индикация газа ==========
        // Угол выбран по геометрии: циферблат тахометра — круг радиусом 357 с
        // центром (1563, 360), и правее x≈1720 в верхней полосе уже чёрное поле
        // вне шкалы. В навигации блок скрыт: там в этом углу кнопка закрытия.
        //
        // По просьбе заказчика вместо статичной надписи GAS здесь анимация:
        // на газу монетки сыплются в кошелёк (газ дешевле бензина — экономим),
        // а выше 5000 об/мин появляется кочегар и бросает пачки денег в топку
        // (на таких оборотах топливо летит в трубу). Всё нарисовано примитивами
        // в GasAnimation.qml, поэтому убирается одной этой строкой.
        GasAnimation {
            x: 1650
            y: 8
            width: 190
            height: 150
            gasOn: root.gasDisplay
            highBurn: root.rpmShown > 5000
            rpm: root.rpmShown
            visible: root.car3d && !root.navigationMode && root.funEnabled && (gasOn || highBurn)
            z: 2
        }

        Button {
            text: "Навигация"
            x: 730; y: 658
            visible: root.car3d && !root.navigationMode
            onClicked: root.navigationMode = true
            z: 2
        }

        // Вход в настройки — тот же путь, что потом будет у кнопки на руле:
        // одна функция calibration.open(), а не жест мышью.
        Button {
            text: "Настройки"
            x: 860; y: 658
            visible: root.car3d && !root.navigationMode
            onClicked: calibration.open()
            z: 2
        }

        // ========== ОТЛАДКА: переключатель газ/бензин ==========
        // Перекрывает признак из CAN, чтобы потыкать и посмотреть, как приборка
        // выглядит на газу. Цвет кнопки показывает, что сейчас на экране.
        // Убрать, когда появится кнопка на руле или прошивка блока сбора.
        Button {
            id: gasDebugButton
            x: 990; y: 658
            visible: root.car3d && !root.navigationMode
            z: 2
            text: root.gasDisplay ? "Газ: вкл" : "Газ: выкл"
            onClicked: {
                root.gasOverride = !root.gasDisplay
                root.gasOverrideActive = true
            }

            background: Rectangle {
                color: root.gasDisplay ? "#33CC44" : "#3A3A3A"
                radius: 6
                border.color: root.gasDisplay ? "#1E7A2A" : "#5A5A5A"
            }
            contentItem: Text {
                text: gasDebugButton.text
                color: root.gasDisplay ? "#0A2A10" : "white"
                font.pixelSize: 18
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

        // ========== ОТЛАДКА: «газ в пол» ==========
        // Принудительно 5400 об/мин: стрелка и цифры тахометра уходят вверх,
        // и в углу появляется кочегар с деньгами — не дожидаясь всплеска
        // в демо-сценарии. Красная, когда «педаль в пол».
        Button {
            id: fullThrottleButton
            x: 1110; y: 658
            visible: root.car3d && !root.navigationMode
            z: 2
            text: "Газ в пол"
            onClicked: root.debugFullThrottle = !root.debugFullThrottle

            background: Rectangle {
                color: root.debugFullThrottle ? "#F07A16" : "#3A3A3A"
                radius: 6
                border.color: root.debugFullThrottle ? "#A82A06" : "#5A5A5A"
            }
            contentItem: Text {
                text: fullThrottleButton.text
                color: root.debugFullThrottle ? "#2A0E02" : "white"
                font.pixelSize: 18
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
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
        //  Открывается кнопкой «Настройки» или двойным кликом по центру.
        // ====================================================================
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
