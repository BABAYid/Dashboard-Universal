pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
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
//  Масштаб картинок дисков. У dial_speed.png контент занимает 1817 px из
//  2104 (замер по самому файлу), доля 0.8636. Чтобы видимый диск был 652 px,
//  картинку надо рисовать в 652 / 0.8636 = 755 px. Отсюда artSize.
//  Если захочется вернуть прежний, более крупный вид — менять одну строку
//  dialDiameter ниже (при 778 диск вылезает за верх экрана, это и было ошибкой).
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
    property real odometer: 0
    property real rangeKm: 0
    property bool nightMode: false

    // ---- палитра из макета (светлая часть; ночной режим — приглушённая) ----
    readonly property color bg: "#070D13"
    readonly property color light: nightMode ? "#8FA6A4" : "#E8F4F0"
    readonly property color light2: nightMode ? "#6C8280" : "#B8D4D5"
    readonly property color glow1: nightMode ? "#5E8A93" : "#BCEAF1"
    readonly property color mid1: nightMode ? "#31424F" : "#587286"
    readonly property color mid3: nightMode ? "#33424F" : "#5B7187"
    readonly property color deep: nightMode ? "#26333F" : "#40556A"

    // Цвета ламп. В палитре макета их нет (она монохромная, циан + белый),
    // поэтому взяты стандартные автомобильные: информация — светлая, внимание —
    // янтарный, авария — красный. Меняются здесь, в одном месте.
    readonly property color lampInfo: nightMode ? "#7FA6AC" : "#BCEAF1"
    readonly property color lampWarn: nightMode ? "#8A6A32" : "#F2C14E"
    readonly property color lampAlarm: nightMode ? "#8E3A3A" : "#FF5252"
    readonly property color lampIdle: "#00000000"

    // ==================== ГЕОМЕТРИЯ (из макета) ====================
    readonly property int dialCx1: 421
    readonly property int dialCy1: 357
    readonly property int dialCx2: 1502
    readonly property int dialCy2: 358
    // Диаметр видимого диска, px (макет: радиус 326).
    readonly property int dialDiameter: 652
    // Доля контента в картинке диска (1817 из 2104) — замер по файлу.
    readonly property real dialArtRatio: 0.8636
    readonly property int artSize: Math.round(dialDiameter / dialArtRatio)
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
    // не нарисованы — белые силуэты `turn_left/turn_right.png` сделаны из
    // старых стрелок классического скина (альфа та же, цвет задаётся кодом).
    readonly property var topLamps: [
        { art: "turn_left.png",             on: root.selfTest || (root.leftTurn && root.blinkOn),   color: root.lampInfo },
        { art: "warn_high_beam.png",        on: root.selfTest || root.highBeamOn,                    color: root.lampInfo },
        { art: "warn_position_lights.png",  on: root.selfTest || root.positionOn,                    color: root.lampInfo },
        { art: "warn_fog_front.png",        on: root.selfTest || root.fogOn,                         color: root.lampInfo },
        { art: "turn_right.png",            on: root.selfTest || (root.rightTurn && root.blinkOn),   color: root.lampInfo }
    ]

    // Нижняя группа: предупреждения и аварии.
    readonly property var bottomLamps: [
        { art: "warn_oil_pressure.png",  on: root.selfTest || root.oilOn,       color: root.lampAlarm },
        { art: "warn_brake_red.png",     on: root.selfTest || root.handBrakeOn, color: root.lampAlarm },
        { art: "warn_seat_belt.png",     on: root.selfTest || root.beltOn,      color: root.lampAlarm },
        { art: "warn_battery.png",       on: root.selfTest || root.batteryOn,   color: root.lampAlarm },
        { art: "warn_check_engine.png",  on: root.selfTest || root.checkOn,     color: root.lampWarn },
        { art: "warn_abs.png",           on: root.selfTest || root.absOn,       color: root.lampWarn },
        { art: "warn_car_triangle.png",  on: root.selfTest || root.overheat,    color: root.lampAlarm },
        { art: "warn_attention_yellow.png", on: root.selfTest || root.fuelLow, color: root.lampWarn },
        { art: "warn_snowflake.png",     on: root.selfTest || root.coldRoad,    color: root.lampInfo }
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
        opacity: nightMode ? 0.3 : 0.5
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
            opacity: root.nightMode ? 0.72 : 1.0
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
            opacity: root.nightMode ? 0.75 : 1.0
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
            opacity: root.nightMode ? 0.75 : 0.95
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

    // Строка пробега и запаса хода: в макете широкая надпись (785…1132, y=193).
    Text {
        x: 785
        width: 348
        y: 189
        horizontalAlignment: Text.AlignHCenter
        text: root.odometer > 0
              ? Math.round(root.odometer) + " км"
              : Math.round(root.fuel) + " %"
        color: root.light2
        font.pixelSize: 34
    }

    // ======================= ЛАМПЫ =======================
    // Одна лампа: белая иконка дизайнера, цвет задаётся тонированием
    // (MultiEffect.colorization), поэтому из 27 иконок не нужен ни один
    // цветной вариант файла.
    component Lamp: Item {
        id: lamp
        required property string art
        required property bool isOn
        required property color tone

        width: root.bottomLampSize
        height: root.bottomLampSize
        opacity: lamp.isOn ? 1.0 : 0.0
        visible: opacity > 0

        Image {
            id: lampArt
            anchors.fill: parent
            source: lamp.art
            fillMode: Image.PreserveAspectFit
            layer.enabled: true
            layer.effect: MultiEffect {
                colorization: 1.0
                colorizationColor: lamp.tone
            }
        }
    }

    // Верхняя полоса между приборами: поворотники по краям, между ними свет.
    Row {
        x: (root.width - width) / 2
        y: root.topLampY
        spacing: root.topLampSpacing

        Repeater {
            model: root.topLamps
            delegate: Item {
                required property var modelData
                width: root.topLampSize
                height: root.topLampSize

                // Поворотники рисуются кодом (в комплекте дизайнера их нет):
                // стрелка-треугольник в цвете ламп.
                Shape {
                    visible: modelData.draw !== undefined
                    anchors.fill: parent
                    opacity: modelData.on ? 1.0 : 0.0
                    ShapePath {
                        strokeWidth: 0
                        fillColor: modelData.color
                        scale: Qt.size(parent.width / 40, parent.height / 40)
                        startX: modelData.draw === "turnLeft" ? 34 : 6
                        startY: 4
                        PathLine { x: modelData.draw === "turnLeft" ? 6 : 34; y: 20 }
                        PathLine { x: modelData.draw === "turnLeft" ? 34 : 6; y: 36 }
                        PathLine { x: modelData.draw === "turnLeft" ? 34 : 6; y: 4 }
                    }
                }

                Image {
                    anchors.fill: parent
                    visible: modelData.draw === undefined
                    source: modelData.draw === undefined ? "images/genesis/" + modelData.art : ""
                    fillMode: Image.PreserveAspectFit
                    opacity: modelData.on ? 1.0 : 0.0
                    layer.enabled: opacity > 0
                    layer.effect: MultiEffect {
                        colorization: 1.0
                        colorizationColor: modelData.color
                    }
                }
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
                tone: modelData.color
            }
        }
    }

    // ======================= ИНДИКАТОРЫ =======================
    // Знак ограничения скорости (кружок дизайнера) — в свободном поле
    // над тахометром: в макете там пусто.
    property int speedLimit: 0
    Image {
        x: 1258
        y: 40
        width: 84
        height: 84
        visible: root.speedLimit > 0
        source: "images/genesis/ind_speed_limit.png"
        fillMode: Image.PreserveAspectFit
        opacity: root.nightMode ? 0.75 : 1.0

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
        opacity: root.nightMode ? 0.7 : 0.9
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
        opacity: root.nightMode ? 0.55 : 1.0
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
            opacity: root.nightMode ? 0.6 : 0.9
        }
        Image {
            width: 205
            height: 55
            source: "images/genesis/range.png"
            fillMode: Image.PreserveAspectFit
            opacity: root.nightMode ? 0.6 : 0.9
        }
    }
}
