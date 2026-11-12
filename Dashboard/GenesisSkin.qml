pragma ComponentBehavior: Bound
import QtQuick

// ==========================================================================
//  ВТОРОЙ СКИН «GENESIS» — по комплекту дизайнера
// ==========================================================================
//
//  Ассеты из папки Genesis/ (43 файла) разложены по `images/genesis/`:
//
//    dial_speed.png / dial_tach.png   диски с делениями и цифрами (2104×2104)
//    needle.png                       стрелка (1360×1360, ось в центре холста)
//    footer.png                       нижняя панель (1640×408, ставится 2×)
//    odometer.png / range.png         блоки пробега и запаса хода
//    icon_*.png                       4 значка (часы, антифриз, топливо, снег)
//    ind_gear.png, ind_speed_limit.png, ind_driving_mode.png
//    warn_*.png                       26 иконок ошибок и ламп
//
//  Геометрия дисков взята из макета: центры (417, 320) и (1501, 320).
//  Размер картинки диска подобран так, чтобы сам диск был ~666 px: у файла
//  контент занимает 1750 из 2104 px, отсюда artSize.
//
//  Тахометр зеркальный: ноль справа, стрелка идёт против часовой.
//  Данные приходят свойствами из Main.qml — логика общая с классическим
//  скином, второй разбор CAN не нужен.
Item {
    id: root

    // ---- данные ----
    property real speed: 0
    property real rpm: 0
    property string gear: "P"
    property real fuel: 0
    property real temp: 0
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
    readonly property color mid3: "#5B7187"
    readonly property color deep: "#40556A"

    // ---- геометрия ----
    readonly property int dialCx1: 417
    readonly property int dialCx2: 1501
    readonly property int dialCy: 320
    readonly property int artSize: 800        // картинка диска на экране
    readonly property int needleCanvas: 520   // холст стрелки на экране

    // Угол стрелки. Зеркальный прибор идёт против часовой.
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
        required property string art
        required property real value
        required property real valueMax
        property bool mirrored: false

        width: root.artSize
        height: root.artSize
        x: cx - width / 2
        y: root.dialCy - height / 2

        // диск с делениями и цифрами — арт дизайнера
        Image {
            anchors.fill: parent
            source: dial.art
            fillMode: Image.PreserveAspectFit
            cache: true
            asynchronous: true
        }

        // стрелка: холст 1360×1360, ось вращения в центре холста,
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
            transform: Rotation {
                origin.x: root.needleCanvas / 2
                origin.y: root.needleCanvas / 2
                angle: dial.shownAngle
            }
        }

        // цифровое значение под диском
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: dial.height - 40
            text: Math.round(dial.value)
            color: root.light
            font.pixelSize: 44
            font.bold: true
        }
    }

    Dial {
        cx: root.dialCx1
        art: "images/genesis/dial_speed.png"
        value: root.speed
        valueMax: 200
    }

    Dial {
        cx: root.dialCx2
        art: "images/genesis/dial_tach.png"
        value: root.rpm / 1000.0
        valueMax: 8
        mirrored: true
    }

    // ======================= ЦЕНТРАЛЬНАЯ КОЛОНКА =======================
    Item {
        x: 714
        y: 130
        width: 492
        height: 300

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.gear
            color: root.light
            font.pixelSize: 104
            font.bold: true
        }

        Row {
            anchors.top: parent.top
            anchors.topMargin: 130
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 40

            Column {
                spacing: 4
                Row {
                    spacing: 8
                    Image { width: 40; height: 34; source: "images/genesis/icon_fuel.png" }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Math.round(root.fuel) + " %"
                        color: root.light2
                        font.pixelSize: 22
                    }
                }
                Row {
                    spacing: 8
                    Image { width: 40; height: 34; source: "images/genesis/icon_coolant.png" }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Math.round(root.temp) + " °C"
                        color: root.light2
                        font.pixelSize: 22
                    }
                }
            }

            Column {
                spacing: 4
                Row {
                    spacing: 8
                    Image { width: 40; height: 34; source: "images/genesis/icon_clock.png" }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.clock
                        color: root.light
                        font.pixelSize: 26
                        font.bold: true
                    }
                }
                Row {
                    spacing: 8
                    Image { width: 40; height: 34; source: "images/genesis/icon_snow.png"; opacity: 0.7 }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.rangeKm > 0 ? Math.round(root.rangeKm) + " км" : "—"
                        color: root.light2
                        font.pixelSize: 22
                    }
                }
            }
        }
    }

    // ======================= НИЖНЯЯ ПАНЕЛЬ =======================
    // footer.png 1640×408, на экране 2× → 820×204
    Image {
        x: (parent.width - width) / 2
        y: parent.height - height
        width: 820
        height: 204
        source: "images/genesis/footer.png"
        fillMode: Image.PreserveAspectFit
    }

    // Пробег и запас хода над панелью
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - 120
        spacing: 120

        Image { width: 180; height: 55; source: "images/genesis/odometer.png" }
        Image { width: 205; height: 55; source: "images/genesis/range.png" }
    }
}
