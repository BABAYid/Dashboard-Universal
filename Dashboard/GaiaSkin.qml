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
    // Погашенная лампа НЕ просматривается совсем (просьба заказчика):
    // раньше оставался еле видный силуэт 10–16 %, и значки читались днём
    // даже выключенными. Теперь в выключенном состоянии их просто нет.
    readonly property real lampOnOpacity: 1.0
    readonly property real lampOffOpacity: 0.0
    readonly property real gearOnOpacity: 1.0
    // Передачи видны только активной (просьба заказчика): подсвечиваются
    // окантовка карточки и буква, остальные карточки остаются тёмными.
    readonly property real gearOffOpacity: 0.0
    readonly property real arrowOffOpacity: 0.0

    // ---- геометрия из макета ----
    readonly property real dialLeftPivotX: 583.4
    readonly property real dialLeftPivotY: 367.2
    readonly property real dialRightPivotX: 1337.8
    readonly property real dialRightPivotY: 365.9
    readonly property real needleWidth: 9.9
    readonly property real needleLength: 289.6
    readonly property real needleTipWidth: 7.4
    // Куда смотрит стрелка на каждом делении — замер с макета
    // (tools/gaia_scale.py). Шкалы нарисованы на эллипсе, а стрелка ходит
    // по кругу вокруг оси, смещённой от центра эллипса на 72 px, поэтому
    // равномерный поворот «0…270°» с цифрами не совпадает: у нуля ошибка
    // была ~8–13°, у максимума ~18°. Здесь — углы поворота спрайта,
    // снятые прямо с цифр 0…180 км/ч и 0…8 «×1000/min».
    readonly property var speedAngles: [-121.6, -94.1, -66.0, -42.2, -15.6,
                                        12.6, 40.0, 65.1, 94.0, 121.7]
    readonly property var rpmAngles: [-118.9, -90.2, -59.9, -31.1, -0.6,
                                      30.0, 58.8, 90.2, 120.5]

    // Поворот стрелки для значения: кусочно-линейная интерполяция по
    // таблице делений. Между делениями стрелка идёт равномерно.
    function needleAngle(value, maxValue, table) {
        const t = Math.max(0, Math.min(1, value / maxValue))
        const pos = t * (table.length - 1)
        const i = Math.min(table.length - 2, Math.floor(pos))
        const f = pos - i
        return table[i] + (table[i + 1] - table[i]) * f
    }

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
    // Семисегментный шрифт экранчика одометра («как на калькуляторе»):
    // Digital-7 Mono, регистрируется в main.cpp, файл —
    // fonts/Digital7Mono.ttf, EULA рядом с ним.
    readonly property string digiFont: "Digital-7 Mono"

    // Режимы экранчика: 0 — общий пробег (ODO), 1 — Trip A, 2 — Trip B.
    // Переключаются нажатием на сам экранчик (мышью/тапом) или клавишей O
    // на столе; в машине будет кнопка на подрулевом — как придёт в CAN.
    property int odoMode: 0
    function nextOdoMode() { root.odoMode = (root.odoMode + 1) % 3 }

    // Подпись режима: у ODO — в верхнем углу, у поездок — в нижнем.
    readonly property string odoLabel:
        root.odoMode === 0 ? "ODO" : (root.odoMode === 1 ? "TRIP A" : "TRIP B")

    // Что показываем. Общий пробег — шесть знакомест целыми километрами
    // (как у механического одометра), поездки — с одним знаком после точки.
    readonly property string odoText: {
        if (root.odoMode === 0) {
            var v = Math.round(Math.max(0, CanBackend.odometer))
            var s = String(v)
            while (s.length < 6)
                s = "0" + s
            return s
        }
        var t = root.odoMode === 1 ? CanBackend.tripA : CanBackend.tripB
        return (Math.round(Math.max(0, t) * 10) / 10).toFixed(1)
    }

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

    // ======================= ЭКРАН ОДОМЕТРА =======================
    // ЭКРАН ОБЪЯВЛЕН ДО СТРЕЛОК: так стрелка проходит поверх плашки
    // (просьба заказчика — экран под стрелкой).
    // Светлая плашка с чёрными сегментными цифрами («как на калькуляторе»).
    // Геометрия плашки и цвета — из рендера макета (см. свойства выше).
    // Подпись режима: ODO — в верхнем углу, TRIP A/TRIP B — в нижнем.
    Rectangle {
        id: odometerScreen
        x: root.screenX
        y: root.screenY
        width: root.screenW
        height: root.screenH
        radius: 5
        color: "#9FA597"
        border.width: 1
        border.color: "#767F72"

        MouseArea {
            anchors.fill: parent
            onClicked: root.nextOdoMode()
        }

        Text {
            text: root.odoLabel
            color: "#333934"
            font.family: root.numericFont
            font.pixelSize: 13
            font.letterSpacing: 1.5
            x: 12
            // ODO — сверху, поездки — снизу, как просил заказчик.
            y: root.odoMode === 0 ? 7 : (parent.height - height - 7)
        }

        // Цифры идут справа, левая часть плашки остаётся под подпись.
        // Шрифт семисегментный (Digital-7 Mono), поэтому цифры выглядят
        // как на калькуляторе без ручной отрисовки сегментов.
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: root.odoText
            color: "#000000"
            font.family: root.digiFont
            // В макете цифры 33 px высотой: у Digital-7 Mono высота цифры
            // ~0.65 от кегля, отсюда pixelSize 50.
            font.pixelSize: 50
            font.letterSpacing: 0
        }
    }

    // ======================= СТРЕЛКИ =======================
    // Стрелка — прямоугольник с градиентом макета и закруглённым кончиком.
    // Ось — нижний центр холста, поэтому поворот идёт вокруг оси прибора.
    component Needle: Item {
        id: needle

        required property real pivotX
        required property real pivotY
        required property real angle            // поворот спрайта, градусы

        x: pivotX - width / 2
        y: pivotY - height
        width: root.needleWidth
        height: root.needleLength
        transformOrigin: Item.Bottom
        rotation: needle.angle

        // Пружина как в классическом скине (Gauge.qml) и Genesis: без неё
        // стрелка дёргается по кадрам CAN, с ней — перелетает на 2–3 % и
        // успокаивается за ~0.5 с. Числа те же, что в классике, чтобы
        // характер движения приборки не менялся от скина к скину.
        Behavior on rotation {
            SpringAnimation {
                spring: 2.0
                damping: 0.2
                mass: 1.0
                epsilon: 0.1
            }
        }

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
        angle: root.needleAngle(root.speed, 180, root.speedAngles)
    }
    Needle {
        pivotX: root.dialRightPivotX
        pivotY: root.dialRightPivotY
        angle: root.needleAngle(root.rpm, 8000, root.rpmAngles)
    }

    // ======================= КОЛОНКА ПЕРЕДАЧ =======================
    // Шесть карточек P R N D 2 L сверху вниз. Плашки карточек — в фоне,
    // здесь поверх них: окантовка активной карточки и её буква.
    // Геометрия карточки из макета: x 936.9, 46.5 × 44, радиус 6.5,
    // обводка 1.86 (tools/gaia_scale.py печатает ту же колонку).
    readonly property var gearOrder: ["P", "R", "N", "D", "2", "L"]
    // Цвета передач (просьба заказчика): P — зелёная, R — оранжевая,
    // N и D — зелёные, 2 и L — оранжевые. Спрайты покрашены заранее
    // (tools/gaia_assets.py): цвет в QML на программном рендерере не работает.
    readonly property var gearColors: ["green", "orange", "green", "green", "orange", "orange"]
    // Окантовка активной карточки красится в цвет передачи — тем же HEX,
    // что и цветные спрайты букв (tools/gaia_assets.py).
    readonly property color gearGreen: "#57D68A"
    readonly property color gearOrange: "#F67E53"
    function gearTint(i) {
        return root.gearColors[Math.max(0, Math.min(root.gearColors.length - 1, i))] === "orange"
                ? root.gearOrange : root.gearGreen
    }
    readonly property int activeGearIndex:
        Math.max(0, root.gearOrder.indexOf(root.activeGear()))

    Rectangle {
        x: 936.9
        y: root.gearFirstRowY + root.activeGearIndex * root.gearRowStep
        width: 46.5
        height: 44
        radius: 6.5
        color: "transparent"
        border.width: 1.9
        // Окантовка в цвет передачи: P/N/D зелёные, R/2/L оранжевые.
        border.color: root.gearTint(root.activeGearIndex)
        Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 160 } }
    }
    Repeater {
        model: ["P", "R", "N", "D", "2", "L"]

        delegate: Image {
            required property int index
            required property string modelData

            source: "images/gaia/gear_" + modelData + "_" + root.gearColors[index] + ".png"
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
    // Картинки — белые стрелки из классического скина, покрашенные в
    // зелёный заранее (tools/gaia_arrows.py): цвет в QML на программном
    // рендерере не работает.
    Image {
        source: "images/gaia/turn_left_green.png"
        width: 52.5
        height: 50
        fillMode: Image.PreserveAspectFit
        x: 873 - width / 2
        y: 79 - height / 2
        smooth: true
        opacity: root.lampTest || root.leftTurnOn ? 1.0 : root.arrowOffOpacity
    }
    Image {
        source: "images/gaia/turn_right_green.png"
        width: 52.5
        height: 50
        fillMode: Image.PreserveAspectFit
        x: 1048 - width / 2
        y: 79 - height / 2
        smooth: true
        opacity: root.lampTest || root.rightTurnOn ? 1.0 : root.arrowOffOpacity
    }

    // Дальний свет — между поворотниками. Иконка из классического скина,
    // покрашена в синий заранее (tools/gaia_lamps.py). В макете на этом
    // месте стоял белый значок «5 полос + мачта» — он вырезан из фона
    // (tools/gaia_bake.py, ZONE_HIGHBEAM).
    Image {
        source: "images/gaia/hi_beam_blue.png"
        width: 42
        height: 42
        fillMode: Image.PreserveAspectFit
        x: 960 - width / 2
        y: 80 - height / 2
        smooth: true
        opacity: root.lampTest || CanBackend.highBeam ? 1.0 : root.arrowOffOpacity
    }

    // ======================= РЯД ЛАМП =======================
    // Положения и размеры — из макета (tools/gaia_assets.py печатает ту же
    // таблицу). Информационные лампы (топливо, ECO, двери, подушка, ремень)
    // берутся из макета Gaia; предупреждающие (двигатель, ABS, масло, АКБ,
    // ручник) — из прошлых скинов, tools/gaia_lamps.py: они уже в палитре
    // Genesis (янтарный/красный) и выгружены в 256×224.
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
            // У информационных ламп пропорции из макета, у предупреждающих
            // (из Genesis) — 256×224, поэтому вписываем по меньшей стороне.
            fillMode: Image.PreserveAspectFit
            x: modelData.cx - width / 2
            y: modelData.cy - height / 2
            smooth: true
            opacity: modelData.on ? root.lampOnOpacity : root.lampOffOpacity
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }
    }

    // Клавиша O на столе — переключение ODO → Trip A → Trip B.
    Shortcut {
        sequence: "O"
        enabled: root.visible
        onActivated: root.nextOdoMode()
    }
}
