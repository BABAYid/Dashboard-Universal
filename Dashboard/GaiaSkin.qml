pragma ComponentBehavior: Bound
import QtQuick
import Dashboard

// ==========================================================================
//  ТРЕТИЙ СКИН «GAIA» — по макету дизайнера, вариант 2
// ==========================================================================
//
//  Макет: Gaia/Приборная панель · Вариант 2 · 1920 × 722.svg
//  Задача этого скина — повторить макет как есть, без дополнительных окон,
//  камер и 3D-машины. Всё «живое» здесь: две стрелки приборов, буква
//  передачи, указатели поворота и ряд ламп. Остальное (колодцы, шкалы,
//  цифры на шкалах, подписи «км/ч» и «×1000/min», карточки передач, декор
//  углов) — статичный фон, выпеченный из SVG.
//
//  ГЕОМЕТРИЯ — ИЗ МАКЕТА, А НЕ НА ГЛАЗ. Числа сняты скриптами tools/:
//
//    tools/gaia_geom.py   габариты узлов SVG, центры и оси приборов
//    tools/gaia_text.py   какие цифры и подписи стоят на шкалах (OCR)
//    tools/gaia_match.py  где в макете лежит каждая иконка дизайнера
//    tools/gaia_bake.py   вырезает из SVG «живые» узлы и рендерит фон
//    tools/gaia_assets.py раскладывает иконки и буквы передач в images/gaia
//
//  Ключевые числа (все в пикселях макета 1920×720):
//
//    левый колодец   кольцо 605×463 с центром (584.7, 295.0);
//                    ось стрелки — (583.4, 367.2), то есть ниже центра
//                    кольца: так нарисована перспектива «чаши».
//    правый колодец  то же, центр (1335.3, 295.0), ось (1337.8, 365.9).
//    стрелка         ширина 9.9, длина от оси до кончика 289.6,
//                    ось — внизу холста стрелки (transformOrigin: Bottom).
//    шкалы           270°, ноль внизу-слева. Левая: 0…180 км/ч шагом 20
//                    (ноль под 140°, максимум под 410°). Правая: 0…8
//                    «×1000/min», ноль под 138°, максимум под 408°.
//                    Поэтому поворот стрелки = (угол + 90°): -130…+140
//                    для левой и -132…+138 для правой.
//    передачи        колонка карточек x 936.9…983.4, шаг 68.1, сверху вниз
//                    P R N D 2 L; центр буквы — (960.5, y0 + 22).
//    поворотники     центры (873, 79) и (1048, 79), картинка 52.5×50.
//    лампы           центры по x: 362 топливо, 639 двигатель, 741 ABS,
//                    884 ECO, 1084 масло, 1165 двери, 1261 АКБ, 1351
//                    тормоза, 1439 подушка, 1544 ремень; все на y ≈ 600.
//
//  Палитра макета монохромная (белое/серое на фоне), единственный цвет —
//  красно-оранжевые стрелки. Фон специально чёрный (#000000), а не тёмно-
//  серый #14171A из макета: на матрице приборки чистый чёрный не даёт
//  серого свечения. Лампы поэтому тоже белые: в макете у
//  них нет ни жёлтого, ни красного. Погашенная лампа не исчезает совсем —
//  остаётся еле видный силуэт, как на подсвеченной приборке.
Item {
    id: root

    // ---- данные: тот же контракт, что у GenesisSkin ----
    property real speed: 0                 // км/ч
    property real rpm: 0                   // об/мин
    property string gear: "P"              // P/R/N/D1…D4/L
    property real fuel: 0                  // %
    property real temp: 0                  // °C
    property string clock: "--:--"
    property real tripKm: 0
    property real rangeKm: 0
    property bool nightMode: false

    // Скин ничего не рисует в центре, но Main.qml передаёт режим панели —
    // принимаем, чтобы связка свойств не ругалась.
    property int centerMode: 0
    // По клавише L Main.qml зажигает все лампы сразу — приёмка раскладки.
    property bool allLampsOn: false
    property bool blindSpotEnabled: true
    property string promoVideoLeft: ""
    property string promoVideoRight: ""
    property bool cameraLeft: false
    property bool cameraRight: false

    // Настройки открывает Main.qml: двойной клик по колонке передач.
    signal settingsRequested()

    // ---- палитра из макета ----
    readonly property color accentIn: "#E46444"
    readonly property color accentMid: "#ED7D53"
    readonly property color accentOut: "#F67E53"
    readonly property color accentDark: "#832913"
    readonly property color lampColor: "#E8EAE6"
    readonly property real lampOnOpacity: 1.0
    readonly property real lampOffOpacity: 0.14
    readonly property real gearOnOpacity: 1.0
    readonly property real gearOffOpacity: 0.16
    readonly property real arrowOffOpacity: 0.10

    // ---- геометрия из макета ----
    readonly property real dialLeftPivotX: 583.4
    readonly property real dialLeftPivotY: 367.2
    readonly property real dialRightPivotX: 1337.8
    readonly property real dialRightPivotY: 365.9
    readonly property real needleWidth: 9.9
    readonly property real needleLength: 289.6
    readonly property real needleTipWidth: 7.4
    readonly property real gearColumnX: 960.5
    readonly property real gearRowStep: 68.1
    readonly property real gearFirstRowY: 136.6

    // Экранчик одометра под левым колодцем. Координаты и цвета сняты с
    // PNG-рендера макета: плашка 248×43 в (466, 466), тело #9FA597,
    // кромка #767F72, цифры чёрные. В SVG этого узла нет — SVG и PNG
    // дизайнера разошлись, поэтому плашку рисуем примитивами, а цифры
    // живые, шрифтом приборки.
    readonly property real screenX: 466
    readonly property real screenY: 466
    readonly property real screenW: 248
    readonly property real screenH: 43
    readonly property string numericFont: "Kdam Thmor Pro"
    // Пробег: целые километры, выровнены вправо, как в макете.
    readonly property string odometerText: String(Math.round(Math.max(0, CanBackend.odometer)))

    // ---- состояние ламп из CAN ----
    readonly property bool engineRunning: CanBackend.rpm > 400
    readonly property bool fuelLow: CanBackend.fuelLevel <= 10
    readonly property bool batteryLow: root.engineRunning && CanBackend.voltage < 12.8
    readonly property bool lampTest: root.selfTest || root.allLampsOn
    readonly property bool leftTurnOn: CanBackend.leftTurn && root.blinkOn
    readonly property bool rightTurnOn: CanBackend.rightTurn && root.blinkOn

    // Самопроверка при старте: все лампы на 2.5 с, как зажигание.
    property bool selfTest: true
    Timer {
        interval: 2500
        running: root.selfTest
        onTriggered: root.selfTest = false
    }

    // Мигание поворотников, пока включён хотя бы один.
    property bool blinkOn: true
    Timer {
        interval: 480
        repeat: true
        running: CanBackend.leftTurn || CanBackend.rightTurn
        onTriggered: root.blinkOn = !root.blinkOn
        onRunningChanged: if (!running) root.blinkOn = true
    }

    // Какая карточка передачи горит. В CAN «D1…D4» — это одна передача
    // «D» на карточке макета; отдельная карточка «2» остаётся резервной,
    // пока машина не пришлёт отдельный режим.
    function activeGear() {
        const g = root.gear
        if (g === "P" || g === "R" || g === "N" || g === "L" || g === "2")
            return g
        if (g.length > 0 && g.charAt(0) === "D")
            return "D"
        return "P"
    }

    // ======================= ФОН =======================
    // Фон — рендер макета без стрелок, букв передач, поворотников и ламп:
    // их рисует скин. Выпекает tools/gaia_bake.py.
    Image {
        anchors.fill: parent
        source: "images/gaia/gaia_bg.png"
        fillMode: Image.Stretch
        smooth: true
    }

    // ======================= СТРЕЛКИ =======================
    // Стрелка — прямоугольник с градиентом макета и закруглённым кончиком.
    // Ось — нижний центр холста, поэтому поворот идёт вокруг оси прибора.
    component Needle: Item {
        id: needle

        required property real pivotX
        required property real pivotY
        required property real value01          // 0…1 по шкале
        required property real startAngle       // угол поворота при 0

        x: pivotX - width / 2
        y: pivotY - height
        width: root.needleWidth
        height: root.needleLength
        transformOrigin: Item.Bottom
        rotation: startAngle + 270 * Math.max(0, Math.min(1, value01))

        Rectangle {
            anchors.fill: parent
            radius: 1.6
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: root.accentIn }
                GradientStop { position: 0.2; color: root.accentMid }
                GradientStop { position: 0.56; color: root.accentOut }
                GradientStop { position: 1.0; color: root.accentDark }
            }
        }
        // Наконечник: в макете это отдельный светлый квадратик у кончика.
        Rectangle {
            width: root.needleTipWidth
            height: root.needleTipWidth
            radius: 1.0
            x: (parent.width - width) / 2
            y: 1.3
            color: root.accentMid
        }
    }

    Needle {
        pivotX: root.dialLeftPivotX
        pivotY: root.dialLeftPivotY
        value01: root.speed / 180
        startAngle: -130
    }
    Needle {
        pivotX: root.dialRightPivotX
        pivotY: root.dialRightPivotY
        value01: root.rpm / 8000
        startAngle: -132
    }

    // ======================= КОЛОНКА ПЕРЕДАЧ =======================
    // Шесть карточек P R N D 2 L сверху вниз. Карточки — в фоне, здесь
    // только буквы: активная светится, остальные еле видны.
    Repeater {
        model: ["P", "R", "N", "D", "2", "L"]

        delegate: Image {
            required property int index
            required property string modelData

            source: "images/gaia/gear_" + modelData + ".png"
            width: implicitWidth / 2          // картинки выгружены в @2x
            height: implicitHeight / 2
            x: root.gearColumnX - width / 2
            y: root.gearFirstRowY + index * root.gearRowStep + 22 - height / 2
            smooth: true
            opacity: root.activeGear() === modelData ? root.gearOnOpacity
                                                     : root.gearOffOpacity
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }
    }

    // Двойной клик по колонке — настройки (как в классическом скине).
    MouseArea {
        x: 900
        y: root.gearFirstRowY - 10
        width: 120
        height: 6 * root.gearRowStep + 20
        onDoubleClicked: root.settingsRequested()
    }

    // ======================= ПОВОРОТНИКИ =======================
    // По центру сверху, между ними — статичный значок из фона.
    Image {
        source: "images/gaia/turn_left.png"
        width: 52.5
        height: 50
        x: 873 - width / 2
        y: 79 - height / 2
        smooth: true
        opacity: root.lampTest || root.leftTurnOn ? 1.0 : root.arrowOffOpacity
    }
    Image {
        source: "images/gaia/turn_right.png"
        width: 52.5
        height: 50
        x: 1048 - width / 2
        y: 79 - height / 2
        smooth: true
        opacity: root.lampTest || root.rightTurnOn ? 1.0 : root.arrowOffOpacity
    }

    // ======================= РЯД ЛАМП =======================
    // Положения и размеры — из макета (tools/gaia_assets.py печатает ту же
    // таблицу). Размер в макете = размер PNG / 2: иконки выгружены в @2x.
    readonly property var lamps: [
        { art: "lamp_fuel.png",   cx: 362.2,  cy: 600.0, w: 33.5, h: 35.0, on: root.lampTest || root.fuelLow },
        { art: "lamp_engine.png", cx: 639.5,  cy: 600.5, w: 46.0, h: 31.0, on: root.lampTest || CanBackend.checkEngine },
        { art: "lamp_abs.png",    cx: 741.5,  cy: 599.5, w: 54.5, h: 36.5, on: root.lampTest || CanBackend.absWarning },
        { art: "lamp_eco.png",    cx: 883.5,  cy: 600.0, w: 48.0, h: 20.5, on: root.lampTest },
        { art: "lamp_oil.png",    cx: 1083.5, cy: 598.5, w: 56.0, h: 25.0, on: root.lampTest || CanBackend.oilPressureAlarm },
        { art: "lamp_doors.png",  cx: 1165.0, cy: 599.5, w: 38.5, h: 37.5, on: root.lampTest },
        { art: "lamp_batt.png",   cx: 1261.5, cy: 599.0, w: 40.0, h: 31.0, on: root.lampTest || root.batteryLow },
        { art: "lamp_brake.png",  cx: 1351.0, cy: 599.5, w: 54.5, h: 36.5, on: root.lampTest || CanBackend.handBrake },
        { art: "lamp_airbag.png", cx: 1439.0, cy: 600.0, w: 36.0, h: 38.5, on: root.lampTest },
        { art: "lamp_belt.png",   cx: 1544.5, cy: 599.5, w: 33.5, h: 40.0, on: root.lampTest || CanBackend.seatBeltUnfastened }
    ]

    Repeater {
        model: root.lamps

        delegate: Image {
            required property var modelData
            source: "images/gaia/" + modelData.art
            width: modelData.w
            height: modelData.h
            x: modelData.cx - width / 2
            y: modelData.cy - height / 2
            smooth: true
            opacity: modelData.on ? root.lampOnOpacity : root.lampOffOpacity
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }
    }

    // ======================= ЭКРАН ОДОМЕТРА =======================
    // Светлая плашка с чёрными цифрами — как в макете. Геометрия и цвета
    // в свойствах выше; цифры идут справа, левая часть плашки остаётся
    // пустой (в макете там тоже пусто).
    Rectangle {
        x: root.screenX
        y: root.screenY
        width: root.screenW
        height: root.screenH
        radius: 5
        color: "#9FA597"
        border.width: 1
        border.color: "#767F72"

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: root.odometerText
            color: "#000000"
            // В макете цифры 33 px высотой с шагом ~26 px — под эти
            // размеры подобраны pixelSize и letterSpacing.
            font.family: root.numericFont
            font.pixelSize: 42
            font.letterSpacing: 8
        }
    }
}
