pragma ComponentBehavior: Bound
import QtQuick
import Dashboard

// ==========================================================================
//  ВТОРОЙ СКИН «GENESIS» — по комплекту дизайнера
// ==========================================================================
//
//  Ассеты из папки Genesis/ разложены по `images/genesis/`:
//
//    dial_speed.png / dial_tach.png   диски с делениями и цифрами (2104×2104)
//    needle.png                       стрелка с осью в центре холста (1360×1360)
//    footer.png                       нижняя панель (1640×408)
//    odometer.png / range.png         блоки пробега и запаса хода
//    icon_*.png                       значки расхода, антифриза, часов, снега
//    ind_gear.png, ind_speed_limit.png, ind_driving_mode.png
//    warn_*.png                       27 иконок ламп (белые, цвет задаётся кодом)
//
//  ГЕОМЕТРИЯ — ИЗ МАКЕТА, А НЕ НА ГЛАЗ. Числа сняты из SVG дизайнера
//  (`Genesis · цифровая приборная панель · 1920×720.svg`, версия 13.11.2026)
//  разбором координат: скрипт разбора и сами замеры — в Genesis/README.md,
//  раздел «Геометрия из макета».
//
//    диски           радиус 326 → диаметр 652, центры (421.2, 357.0) и
//                    (1501.6, 357.6). В макете это две окружности
//                    filter16_f/filter39_f и оси стрелок (матрицы 419.2|325.1
//                    и 1500.25|326.6).
//    стрелка         от оси до кончика 344 px, ось — в центре холста картинки.
//    центральная     буква передачи в (714, 51) высотой 48 px (капс);
//    колонка         линия-разделитель y=110 от x=718 до 1211;
//                    строки данных: значки 40×33 в x=792, значения
//                    прижаты справа к x=1061, единицы — от x=1074;
//                    строки на y=303, 379, 457 (шаг 78).
//
//  Масштаб картинок дисков. В dial_speed.png кольцо шкалы лежит на радиусе
//  641 px из 2104 (замер по самому файлу, tools/genesis_geom.py png), а в
//  макете кольцо — радиус 326. Значит картинку надо рисовать в
//  2104 × 326 / 641 ≈ 1069 px — это artSize.
//  Размер приборов меняется одной строкой dialDiameter ниже.
//
//  Тахометр зеркальный: ноль справа, стрелка идёт против часовой. Данные
//  приходят свойствами из Main.qml, лампы читаются из CanBackend напрямую:
//  второй разбор CAN не нужен, и этот файл не требует правок в Main.qml.
Item {
    id: root

    // ---- данные (те же свойства root, что у классики) ----
    property real speed: 0
    property real rpm: 0
    property string gear: "P"
    property real fuel: 0
    property real temp: 0
    property string clock: "--:--"
    // Пробег за поездку (Main.qml передаёт journeyKm). Полный одометр в этом
    // скине пока не выводится: в макете под него нет отдельного поля.
    property real tripKm: 0
    property real rangeKm: 0
    property bool nightMode: false

    // ---- палитра из макета ----
    // Ночной режим НЕ гасит панель: в машине он включён всегда, когда горят
    // габариты (Main.qml: nightMode = positionLights), то есть всю ночную езду.
    // Поэтому меняется только фоновое свечение и чуть-чуть яркость арта,
    // а цифры и значения остаются читаемыми.
    readonly property color bg: "#070D13"
    readonly property color light: "#E8F4F0"
    readonly property color light2: nightMode ? "#A6C0C2" : "#B8D4D5"
    readonly property color glow1: nightMode ? "#9CCAD2" : "#BCEAF1"
    readonly property color mid1: nightMode ? "#44596B" : "#587286"
    readonly property color mid3: nightMode ? "#44566B" : "#5B7187"
    readonly property color deep: nightMode ? "#32424F" : "#40556A"
    // Яркость арта: днём 1.0, ночью 0.88 — заметно мягче, но всё видно.
    readonly property real artLevel: nightMode ? 0.88 : 1.0

    // Цвета ламп. В палитре макета их нет (она монохромная, циан + белый),
    // поэтому взяты стандартные автомобильные: информация — светлая, внимание —
    // янтарный, авария — красный. Эти же значения зашиты в
    // tools/tint_genesis_icons.py, которым красятся файлы иконок: меняете
    // цвет здесь — прогоняете скрипт, иначе файлы останутся прежнего цвета.
    readonly property color lampInfo: "#BCEAF1"
    readonly property color lampWarn: "#F2C14E"
    readonly property color lampAlarm: "#FF5252"
    readonly property color lampIdle: "#00000000"

    // ==================== ГЕОМЕТРИЯ (из макета) ====================
    readonly property int dialCx1: 421
    readonly property int dialCy1: 357
    readonly property int dialCx2: 1502
    readonly property int dialCy2: 358
    // Диаметр видимого диска, px (макет: радиус 326).
    readonly property int dialDiameter: 652
    // Масштаб картинки диска. У dial_speed.png яркое кольцо шкалы лежит на
    // радиусе 641 из 2104 px (замер по файлу: пик медианой яркости по
    // окружностям — tools/genesis_geom.py png), то есть кольцо занимает
    // 0.3047 полухолста. В макете кольцо — радиус 326, отсюда
    // artSize = 326 / 0.3047 = 1069.
    // Раньше здесь стояло 900 «на глаз»: кольцо получалось 276 px вместо 326,
    // а до этого 1245 (кольцо 382) — отсюда и просьба «сделать меньше».
    readonly property real dialArtRingRatio: 0.3047
    readonly property int artSize: Math.round((dialDiameter / 2) / dialArtRingRatio)
    // Холст стрелки: ось в центре холста, кончик достаёт до 344 px от оси
    // (макет: кончик на y=12.8 при оси y=357).
    readonly property real needleLength: dialDiameter * 0.528
    readonly property int needleCanvas: Math.round(needleLength * 2)

    // Показывать ли дуги топлива и температуры поверх дисков. В макете
    // 13.11 их нет — топливо и температура выведены числами в центральной
    // колонке (см. ниже). Дуги оставлены на случай, если заказчик захочет
    // вернуть: включить одной строкой.
    property bool showAuxScales: false
    readonly property real auxScale: 0.42
    readonly property real auxOffsetX: 0.22
    readonly property real auxOffsetY: 0.26

    // ==================== ЛАМПЫ ====================
    // Раскладка. В макете места под лампы не размечены (дизайнер отдал иконки
    // отдельным комплектом), поэтому заняты два свободных поля макета:
    //   верхняя полоса между приборами (x 730…1200, y 26…96) — указатели
    //   поворота, дальний свет, габариты, туманки;
    //   нижняя кромка экрана (y ≈ 686) — предупреждения и аварии.
    // Положение каждой группы меняется одним числом: topLampY / bottomLampY.
    property real topLampY: 30
    property real bottomLampY: 688
    property real topLampSize: 38
    property real bottomLampSize: 30
    property int topLampSpacing: 22
    property int bottomLampSpacing: 26

    // Самопроверка ламп при включении зажигания: все горят 2.5 с.
    property bool selfTest: true
    Timer {
        interval: 2500
        running: true
        onTriggered: root.selfTest = false
    }

    // Фаза мигания поворотников. В классическом скине её даёт Main.qml, чтобы
    // мигали и лампы, и огни 3D-машины; здесь скин живёт сам, поэтому фаза
    // своя (1.5 Гц, как у настоящего реле).
    property bool blinkOn: true
    Timer {
        interval: 333
        repeat: true
        running: root.turnActive
        onTriggered: root.blinkOn = !root.blinkOn
        onRunningChanged: if (!running) root.blinkOn = true
    }
    readonly property bool turnActive: root.leftTurn || root.rightTurn

    // ---- данные ламп: откуда берутся ----
    readonly property bool engineRunning: CanBackend.rpm > 400
    readonly property bool leftTurn: CanBackend.leftTurn && !root.selfTest
    readonly property bool rightTurn: CanBackend.rightTurn && !root.selfTest
    readonly property bool highBeamOn: CanBackend.highBeam
    readonly property bool positionOn: CanBackend.positionLights
    readonly property bool fogOn: CanBackend.fogLights
    readonly property bool checkOn: CanBackend.checkEngine
    readonly property bool absOn: CanBackend.absWarning
    readonly property bool handBrakeOn: CanBackend.handBrake
    readonly property bool beltOn: CanBackend.seatBeltUnfastened
    readonly property bool oilOn: CanBackend.oilPressureAlarm
    readonly property bool batteryOn: root.engineRunning && CanBackend.voltage < 12.8
    readonly property bool overheat: CanBackend.engineTemp >= 110
    readonly property bool fuelLow: CanBackend.fuelLevel <= 10
    readonly property bool coldRoad: CanBackend.outsideTemp <= 3 && CanBackend.outsideTemp > -40

    // Верхняя группа: то, что видно постоянно и чаще всего (указатели поворота
    // по краям, как на любой машине). Стрелки поворота в комплекте дизайнера
    // не нарисованы — силуэты `turn_left/turn_right` сделаны из старых стрелок
    // классического скина (альфа та же).
    //
    // Иконки берутся уже покрашенными (суффикс _cyan/_amber/_red): цвет в QML
    // задаётся только шейдерным MultiEffect, а на программном рендерере он не
    // работает и лампы пропадают совсем. Красит `tools/tint_genesis_icons.py`
    // из тех же белых исходников дизайнера.
    readonly property var topLamps: [
        { art: "turn_left_cyan.png",            on: root.selfTest || (root.leftTurn && root.blinkOn) },
        { art: "warn_high_beam_cyan.png",       on: root.selfTest || root.highBeamOn },
        { art: "warn_position_lights_cyan.png", on: root.selfTest || root.positionOn },
        { art: "warn_fog_front_cyan.png",       on: root.selfTest || root.fogOn },
        { art: "turn_right_cyan.png",           on: root.selfTest || (root.rightTurn && root.blinkOn) }
    ]

    // Нижняя группа: предупреждения и аварии.
    readonly property var bottomLamps: [
        { art: "warn_oil_pressure_red.png",      on: root.selfTest || root.oilOn },
        { art: "warn_brake_red_red.png",         on: root.selfTest || root.handBrakeOn },
        { art: "warn_seat_belt_red.png",         on: root.selfTest || root.beltOn },
        { art: "warn_battery_red.png",           on: root.selfTest || root.batteryOn },
        { art: "warn_check_engine_amber.png",    on: root.selfTest || root.checkOn },
        { art: "warn_abs_amber.png",             on: root.selfTest || root.absOn },
        { art: "warn_car_triangle_red.png",      on: root.selfTest || root.overheat },
        { art: "warn_attention_yellow_amber.png", on: root.selfTest || root.fuelLow },
        { art: "warn_snowflake_cyan.png",        on: root.selfTest || root.coldRoad }
    ]

    // Угол стрелки в градусах поворота холста. Зеркальный прибор идёт
    // против часовой: ноль справа (135°), максимум слева (-135°).
    function needleAngle(value, max, mirrored) {
        const v = Math.max(0, Math.min(max, value))
        return mirrored ? 135 - 270 * v / max : -135 + 270 * v / max
    }

    // ======================= ФОН =======================
    Rectangle {
        anchors.fill: parent
        color: root.bg
    }
    Rectangle {
        anchors.centerIn: parent
        width: 1500
        height: 900
        radius: width / 2
        opacity: nightMode ? 0.28 : 0.5
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0E1A22" }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // ======================= ПРИБОР =======================
    component Dial: Item {
        id: dial
        required property int cx
        required property int cy
        required property string art
        required property real value
        required property real valueMax
        property bool mirrored: false

        // Вспомогательная шкала (топливо/температура) — по умолчанию выключена.
        property bool hasAux: false
        property real auxValue: 0
        property real auxMin: 0
        property real auxMax: 100
        property string auxArt: ""
        property string auxUnit: ""

        width: root.artSize
        height: root.artSize
        x: cx - width / 2
        y: cy - height / 2

        // диск с делениями и цифрами — арт дизайнера
        Image {
            anchors.fill: parent
            source: dial.art
            fillMode: Image.PreserveAspectFit
            cache: true
            asynchronous: true
            opacity: root.artLevel
        }

        // стрелка: холст квадратный, ось вращения — в центре холста,
        // поэтому ставим её центром на центр диска
        property real shownAngle: root.needleAngle(dial.value, dial.valueMax, dial.mirrored)
        Behavior on shownAngle {
            SpringAnimation { spring: 2.6; damping: 0.22; epsilon: 0.15 }
        }

        Image {
            width: root.needleCanvas
            height: root.needleCanvas
            x: dial.width / 2 - width / 2
            y: dial.height / 2 - height / 2
            source: "images/genesis/needle.png"
            cache: true
            opacity: root.artLevel
            transform: Rotation {
                origin.x: root.needleCanvas / 2
                origin.y: root.needleCanvas / 2
                angle: dial.shownAngle
            }
        }

        // ---- вспомогательная шкала: картинка дизайнера + мини-стрелка ----
        Item {
            id: aux
            visible: root.showAuxScales && dial.hasAux
            width: dial.width * root.auxScale
            height: width * 0.86
            x: dial.width / 2 - width / 2 + dial.width * (dial.mirrored ? root.auxOffsetX
                                                                      : -root.auxOffsetX)
            y: dial.height / 2 - height / 2 + dial.height * root.auxOffsetY

            Image {
                anchors.fill: parent
                source: dial.auxArt
                fillMode: Image.PreserveAspectFit
                cache: true
            }

            Rectangle {
                width: 3
                height: aux.width * 0.34
                radius: 1.5
                x: aux.width / 2 - width / 2
                y: aux.height / 2 - height
                color: root.light
                antialiasing: true
                transformOrigin: Item.Bottom
                rotation: 40 + 100 * Math.max(0, Math.min(1,
                              (dial.auxValue - dial.auxMin) / (dial.auxMax - dial.auxMin)))
                Behavior on rotation { NumberAnimation { duration: 250 } }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height - 4
                text: dial.auxUnit
                color: root.mid3
                font.pixelSize: 12
            }
        }
    }

    Dial {
        cx: root.dialCx1
        cy: root.dialCy1
        art: "images/genesis/dial_speed.png"
        value: root.speed
        valueMax: 200
        hasAux: true
        auxValue: root.fuel
        auxMax: 100
        auxArt: "images/genesis/scale_fuel.png"
        auxUnit: "ТОПЛИВО"
    }

    Dial {
        cx: root.dialCx2
        cy: root.dialCy2
        art: "images/genesis/dial_tach.png"
        value: root.rpm / 1000.0
        valueMax: 8
        mirrored: true
        hasAux: true
        auxValue: root.temp
        auxMin: 40
        auxMax: 120
        auxArt: "images/genesis/scale_temp.png"
        auxUnit: "ТЕМП."
    }

    // ======================= ЦЕНТРАЛЬНАЯ КОЛОНКА =======================
    // Всё по координатам макета: буква передачи, линия-разделитель,
    // три строки данных (топливо, температура, часы) и строка пробега.

    // Буква передачи: капс 48 px → кегль ~66.
    Text {
        x: 714
        y: 36
        width: 200
        text: root.gear
        color: root.light
        font.pixelSize: 66
        font.bold: true
    }

    // Линия-разделитель: в макете путь от (718, 110) до (1211, 110)
    // с градиентом от прозрачного к светлому.
    Rectangle {
        x: 718
        y: 110
        width: 493
        height: 2
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.18; color: root.mid1 }
            GradientStop { position: 0.5; color: root.glow1 }
            GradientStop { position: 0.82; color: root.mid1 }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // Строка данных: значок 40×33 слева, значение справа (прижато к x=1061),
    // единица измерения — от x=1074, как в макете.
    component InfoRow: Item {
        id: row
        required property string icon
        required property string value
        required property string unit

        width: 365
        height: 40

        Image {
            x: 0
            anchors.verticalCenter: parent.verticalCenter
            width: 40
            height: 34
            source: row.icon
            fillMode: Image.PreserveAspectFit
            opacity: root.nightMode ? 0.8 : 0.95
        }

        Text {
            id: valueText
            x: 0
            width: 269
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            text: row.value
            color: root.light
            font.pixelSize: 52
            font.bold: true
        }

        Text {
            x: 282
            anchors.verticalCenter: parent.verticalCenter
            text: row.unit
            color: root.light2
            font.pixelSize: 28
        }
    }

    InfoRow {
        x: 792
        y: 303
        icon: "images/genesis/icon_fuel.png"
        value: Math.round(root.fuel)
        unit: "%"
    }

    InfoRow {
        x: 792
        y: 379
        icon: "images/genesis/icon_coolant.png"
        value: Math.round(root.temp)
        unit: "°C"
    }

    InfoRow {
        x: 792
        y: 457
        icon: "images/genesis/icon_clock.png"
        value: root.clock
        unit: root.rangeKm > 0 ? Math.round(root.rangeKm) + " км" : "—"
    }

    // Строка пробега за поездку: в макете на этом месте широкая надпись
    // (785…1132, y=193).
    Text {
        x: 785
        width: 348
        y: 189
        horizontalAlignment: Text.AlignHCenter
        text: root.tripKm.toFixed(1) + " км"
        color: root.light2
        font.pixelSize: 34
    }

    // ======================= ЛАМПЫ =======================
    // Одна лампа: картинка дизайнера в нужном цвете, без эффектов.
    component Lamp: Item {
        id: lamp
        required property string art
        required property bool isOn
        property real lampSize: root.bottomLampSize

        width: lampSize
        height: lampSize
        opacity: lamp.isOn ? (root.nightMode ? 0.85 : 1.0) : 0.0
        visible: opacity > 0

        Image {
            anchors.fill: parent
            source: lamp.art
            fillMode: Image.PreserveAspectFit
            cache: true
        }
    }

    // Верхняя полоса между приборами: поворотники по краям, между ними свет.
    Row {
        x: (root.width - width) / 2
        y: root.topLampY
        spacing: root.topLampSpacing

        Repeater {
            model: root.topLamps
            delegate: Lamp {
                required property var modelData
                lampSize: root.topLampSize
                art: "images/genesis/" + modelData.art
                isOn: modelData.on
            }
        }
    }

    // Нижняя кромка: предупреждения и аварии.
    Row {
        x: (root.width - width) / 2
        y: root.bottomLampY
        spacing: root.bottomLampSpacing

        Repeater {
            model: root.bottomLamps
            delegate: Lamp {
                required property var modelData
                art: "images/genesis/" + modelData.art
                isOn: modelData.on
            }
        }
    }

    // ======================= ИНДИКАТОРЫ =======================
    // Знак ограничения скорости (кружок дизайнера) — в свободном поле
    // над тахометром: в макете там пусто. Берётся из базы камер
    // (SpeedCamManager — QML-синглтон модуля): показываем ограничение той
    // камеры, что впереди по курсу. Нет камеры — знак скрыт.
    readonly property int speedLimit:
        SpeedCamManager.cameraAhead && SpeedCamManager.cameraIsSpeedControl
        ? SpeedCamManager.cameraSpeedLimit : 0
    Image {
        x: 1258
        y: 40
        width: 84
        height: 84
        visible: root.speedLimit > 0
        source: "images/genesis/ind_speed_limit.png"
        fillMode: Image.PreserveAspectFit
        opacity: root.artLevel

        Text {
            anchors.centerIn: parent
            text: root.speedLimit
            color: root.bg
            font.pixelSize: 34
            font.bold: true
        }
    }

    // Режим движения (надпись дизайнера) — под строкой пробега.
    property string drivingMode: ""
    Image {
        x: 960 - width / 2
        y: 236
        width: 200
        height: 96
        visible: root.drivingMode.length > 0
        source: "images/genesis/ind_driving_mode.png"
        fillMode: Image.PreserveAspectFit
        opacity: root.nightMode ? 0.8 : 0.9
    }

    // ======================= НИЖНЯЯ ПАНЕЛЬ =======================
    // footer.png 1640×408 ставится 2× (820×204) — как в макете: полоса
    // по центру низа, поверх неё пробег и запас хода.
    Image {
        x: (parent.width - width) / 2
        y: parent.height - height
        width: 820
        height: 204
        source: "images/genesis/footer.png"
        fillMode: Image.PreserveAspectFit
        opacity: root.nightMode ? 0.8 : 1.0
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - 120
        spacing: 120

        Image {
            width: 180
            height: 55
            source: "images/genesis/odometer.png"
            fillMode: Image.PreserveAspectFit
            opacity: root.nightMode ? 0.75 : 0.9
        }
        Image {
            width: 205
            height: 55
            source: "images/genesis/range.png"
            fillMode: Image.PreserveAspectFit
            opacity: root.nightMode ? 0.75 : 0.9
        }
    }
}
