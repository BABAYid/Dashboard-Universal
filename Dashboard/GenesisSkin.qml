pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes

// ==========================================================================
//  ВТОРОЙ СКИН «GENESIS»
// ==========================================================================
//
//  Геометрия и палитра сняты с макета дизайнера
//  («Genesis · цифровая приборная панель · 1920×720.svg»), а не на глаз:
//
//    диски      666.6 × 597.9  в (84.2, 21.5) и (1168.0, 21.5)
//               → центры (417, 320) и (1501, 320)
//    стрелки     23 × 353.2    в (413.2, 13.4) и (1489.6, 13.4)
//               → ось вращения на 306.6 px от верха картинки (в макете
//                 хвост стрелки уходит ниже центра диска)
//
//    палитра: фон #070D13, светлые #E8F4F0 / #B8D4D5 / #BCEAF1 / #D1F3F5,
//    средние #587286 / #45627D / #5B7187 / #405A72 / #40556A
//
//  Из макета взяты две растровые части (они лежат в SVG встроенными PNG):
//  свечение диска и белая стрелка. Кольца, деления и цифры рисуются кодом:
//  так они остаются векторными и чёткими, а фильтры Figma (размытия и тени)
//  Qt не умеет — их «мягкость» уже зашита в картинку свечения и стрелку.
Item {
    id: root

    // ---- данные (те же свойства, что у классического скина) ----
    property real speed: 0           // км/ч
    property real rpm: 0             // об/мин
    property string gear: "P"
    property real fuel: 0            // %
    property real temp: 0            // °C
    property string clock: "--:--"
    property real tripKm: 0
    property real rangeKm: 0
    property bool nightMode: false

    // ---- палитра из макета ----
    readonly property color bg: "#070D13"
    readonly property color light: "#E8F4F0"
    readonly property color light2: "#B8D4D5"
    readonly property color glow1: "#BCEAF1"
    readonly property color mid1: "#587286"
    readonly property color mid2: "#45627D"
    readonly property color mid3: "#5B7187"
    readonly property color deep: "#40556A"

    // ---- геометрия из макета ----
    readonly property int dialW: 666
    readonly property int dialH: 598
    readonly property int dialY: 21
    readonly property int dialCx1: 417
    readonly property int dialCx2: 1501
    readonly property int dialCy: 320
    readonly property int needleW: 23
    readonly property int needleH: 353
    readonly property real needlePivotFromTop: 306.6

    // Размах шкалы 270°, 0 — вверх (как у Item.rotation).
    // У тахометра шкала ЗЕРКАЛЬНАЯ: ноль справа, максимум слева, стрелка
    // идёт против часовой. Так же сделано и в классическом скине — это
    // стандарт для приборок, а не прихоть: правое поле зеркально левому.
    function needleAngle(value, max, mirrored) {
        const v = Math.max(0, Math.min(max, value))
        return mirrored ? 135 - 270 * v / max : -135 + 270 * v / max
    }

    // ======================= ФОН =======================
    Rectangle {
        anchors.fill: parent
        color: root.bg
    }

    // Мягкое подсвеченное пятно в центре экрана (в макете — радиальный градиент)
    Rectangle {
        anchors.centerIn: parent
        width: 1500
        height: 900
        radius: width / 2
        opacity: 0.5
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0E1A22" }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // ======================= ПРИБОР =======================
    component Dial: Item {
        id: dial
        required property int cx
        required property real value
        required property real valueMax
        required property int majorStep
        required property string caption
        required property string unit
        property bool mirrored: false

        width: root.dialW
        height: root.dialH
        x: cx - width / 2
        y: root.dialY

        // 1. свечение диска — растровый слой из макета (в нём уже размытия,
        //    которые Qt сам нарисовать не может)
        Image {
            anchors.fill: parent
            source: "images/genesis/dial_glow.png"
            fillMode: Image.PreserveAspectFit
            cache: true
        }

        // 2. кольца шкалы — вектор, остаётся чётким на любом разрешении
        Shape {
            anchors.fill: parent

            // ВАЖНО: PathAngleArc считает углы иначе, чем Item.rotation —
            // ноль градусов у него на востоке, положительное направление
            // против часовой. Деления шкалы стоят при поворотах -135…+135
            // (0 — вверх), это соответствует дуге от -45° (юго-восток) через
            // восток, север, запад до 225° (юго-запад). Отсюда startAngle -45
            // и размах 270: раньше стояло -135, и кольцо было повёрнуто на
            // 90° относительно шкалы.
            ShapePath {
                strokeColor: root.mid1
                strokeWidth: 2
                fillColor: "transparent"
                PathAngleArc {
                    centerX: dial.width / 2
                    centerY: dial.height / 2
                    radiusX: dial.height / 2 - 30
                    radiusY: dial.height / 2 - 30
                    startAngle: -45
                    sweepAngle: 270
                }
            }
            ShapePath {
                strokeColor: root.deep
                strokeWidth: 1
                fillColor: "transparent"
                PathAngleArc {
                    centerX: dial.width / 2
                    centerY: dial.height / 2
                    radiusX: dial.height / 2 - 92
                    radiusY: dial.height / 2 - 92
                    startAngle: -45
                    sweepAngle: 270
                }
            }
        }

        // деления: 37 штук по 7.5°, каждое пятое длинное и светлое
        Repeater {
            model: 37
            Item {
                required property int index
                width: dial.width
                height: dial.height
                rotation: dial.mirrored ? 135 - index * 7.5 : -135 + index * 7.5

                Rectangle {
                    width: index % 5 === 0 ? 3 : 1.5
                    height: index % 5 === 0 ? 22 : 11
                    x: dial.width / 2 - width / 2
                    y: 28
                    color: index % 5 === 0 ? root.light : root.mid1
                    antialiasing: true
                }
            }
        }

        // цифры у крупных делений
        Repeater {
            model: Math.floor(dial.valueMax / dial.majorStep) + 1
            Item {
                required property int index
                width: dial.width
                height: dial.height
                rotation: dial.mirrored
                          ? 135 - index * (270 / (dial.valueMax / dial.majorStep))
                          : -135 + index * (270 / (dial.valueMax / dial.majorStep))

                Text {
                    x: dial.width / 2 - width / 2
                    y: 58
                    text: index * dial.majorStep
                    color: root.light2
                    font.pixelSize: 22
                    font.bold: true
                    // компенсируем поворот родителя: цифры шкалы должны
                    // читаться прямо, а не вверх ногами у нижних делений
                    rotation: -parent.rotation
                }
            }
        }

        // 3. стрелка — картинка из макета, вращается вокруг оси из макета.
        // Угол отдельным свойством: Behavior внутри Rotation не работает
        // (проверено — стрелка рисовалась, но не поворачивалась), поэтому
        // пружина висит на свойстве, а Rotation лишь читает его.
        property real shownAngle: root.needleAngle(dial.value, dial.valueMax, dial.mirrored)
        Behavior on shownAngle {
            SpringAnimation { spring: 2.6; damping: 0.22; epsilon: 0.15 }
        }

        Image {
            width: root.needleW
            height: root.needleH
            x: dial.width / 2 - width / 2
            y: dial.height / 2 - root.needlePivotFromTop
            source: "images/genesis/needle.png"
            cache: true
            transform: Rotation {
                origin.x: root.needleW / 2
                origin.y: root.needlePivotFromTop
                angle: dial.shownAngle
            }
        }

        // ступица
        Rectangle {
            width: 30; height: 30; radius: 15
            anchors.centerIn: parent
            color: root.mid2
            border.color: root.mid1
            border.width: 1
        }

        // цифровое значение и подпись
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: dial.height * 0.56
            spacing: 0

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Math.round(dial.value)
                color: root.light
                font.pixelSize: 58
                font.bold: true
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: dial.unit
                color: root.mid3
                font.pixelSize: 17
                font.letterSpacing: 2
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: dial.caption
                color: root.mid1
                font.pixelSize: 15
                font.letterSpacing: 3
            }
        }
    }

    Dial {
        cx: root.dialCx1
        value: root.speed
        valueMax: 200
        majorStep: 20
        caption: "СКОРОСТЬ"
        unit: "КМ/Ч"
    }

    Dial {
        cx: root.dialCx2
        value: root.rpm / 1000.0
        valueMax: 8
        majorStep: 1
        caption: "ТАХОМЕТР"
        unit: "x1000 ОБ/МИН"
        mirrored: true      // шкала зеркальна спидометру, стрелка против часовой
    }

    // ======================= ЦЕНТРАЛЬНАЯ КОЛОНКА =======================
    Item {
        x: 714
        y: 120
        width: 492
        height: 380

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.gear
            color: root.light
            font.pixelSize: 118
            font.bold: true
        }

        Column {
            anchors.top: parent.top
            anchors.topMargin: 145
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 16
            width: parent.width - 60

            Repeater {
                model: [
                    { label: "ТОПЛИВО", value: root.fuel, max: 100, unit: "%" },
                    { label: "ДВИГАТЕЛЬ", value: root.temp, max: 120, unit: "°C" }
                ]
                Row {
                    required property var modelData
                    spacing: 10
                    width: parent.width

                    Text {
                        text: modelData.label
                        color: root.mid1
                        font.pixelSize: 15
                        font.letterSpacing: 2
                        width: 125
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Rectangle {
                        width: 205; height: 8; radius: 4
                        color: root.deep
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, modelData.value / modelData.max))
                            height: parent.height
                            radius: parent.radius
                            color: root.glow1
                            Behavior on width { NumberAnimation { duration: 300 } }
                        }
                    }
                    Text {
                        text: Math.round(modelData.value) + " " + modelData.unit
                        color: root.light2
                        font.pixelSize: 17
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            Row {
                width: parent.width
                spacing: 20
                Text {
                    text: "ПОЕЗДКА " + root.tripKm.toFixed(1) + " КМ"
                    color: root.deep
                    font.pixelSize: 15
                }
                Text {
                    text: root.rangeKm > 0 ? "ЗАПАС " + Math.round(root.rangeKm) + " КМ" : ""
                    color: root.deep
                    font.pixelSize: 15
                }
            }
        }
    }

    // ======================= НИЖНЯЯ ПАНЕЛЬ =======================
    // В макете внизу три небольшие плашки (143.4×48, 99×48, 120×48) —
    // скорость, часы и передача цифрами.
    Row {
        y: parent.height - 96
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 28

        Repeater {
            model: [
                { text: Math.round(root.speed) + "  КМ/Ч", w: 210 },
                { text: root.clock, w: 150 },
                { text: root.gear, w: 120 }
            ]
            Rectangle {
                required property var modelData
                width: modelData.w; height: 56
                radius: 8
                color: "#12212B"
                border.color: root.mid2
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: modelData.text
                    color: root.light
                    font.pixelSize: 30
                    font.bold: true
                }
            }
        }
    }
}
