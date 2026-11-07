pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes

// ==========================================================================
//  ВТОРОЙ СКИН «GENESIS» (по эскизу docs/design/genesis.jpg)
// ==========================================================================
//
//  Палитра снята с эскиза: тёмный сине-чёрный фон (градиент от #02060E),
//  приборы в сине-сером (#101A24 с кольцом #2A3644), шкалы и цифры светлые
//  (#A6B4BE / #C9D6E0), снизу — широкая светлая полоса (#A6B4BE) с тёмными
//  цифрами, как на эскизе.
//
//  Скин ничего не читает из CAN сам: все значения приходят свойствами из
//  Main.qml — так оба скина живут на одних данных и не дублируют логику.
//
//  Рисуется примитивами (Shape/Repeater), а не картинками: эскиз — это
//  настроение и палитра, а не готовый арт. Когда дизайнер отдаст настоящие
//  диски, достаточно заменить фоновые элементы на Image — геометрия ниже
//  совпадает с макетом 1920×720.
Item {
    id: root

    // ---- данные (те же свойства, что и у классического скина) ----
    property real speed: 0            // км/ч
    property real rpm: 0              // об/мин
    property string gear: "P"
    property real fuel: 0             // %
    property real temp: 0             // °C
    property string clock: "--:--"
    property real tripKm: 0
    property real rangeKm: 0
    property bool nightMode: false

    // ---- палитра ----
    readonly property color bgTop: "#02060E"
    readonly property color bgBottom: "#0B151C"
    readonly property color dialFill: "#0E1822"
    readonly property color dialRing: "#2A3644"
    readonly property color tickMinor: "#3E4C5E"
    readonly property color tickMajor: "#8FA0B2"
    readonly property color labelGrey: "#A6B4BE"
    readonly property color textMain: "#D6E2EC"
    readonly property color accent: "#7FD4FF"
    readonly property color strip: "#A6B4BE"
    readonly property color stripInk: "#0A1018"

    // ---- геометрия (макет 1920×720) ----
    readonly property int dialDiameter: 460
    readonly property int dialLeftX: 360      // центр левого прибора
    readonly property int dialRightX: 1560    // центр правого
    readonly property int dialY: 300          // центр по вертикали
    readonly property int stripHeight: 132

    // Углы шкалы: 0 — вверх (как у Item.rotation), размах 270°.
    function needleAngle(value, max, min) {
        const v = Math.max(min, Math.min(max, value))
        return -135 + 270 * (v - min) / (max - min)
    }

    // ======================= ФОН =======================
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.bgTop }
            GradientStop { position: 0.55; color: "#071018" }
            GradientStop { position: 1.0; color: root.bgBottom }
        }
    }

    // Мягкое свечение за приборами — на эскизе приборы светлее фона
    Rectangle {
        width: root.dialDiameter * 1.9
        height: width
        radius: width / 2
        x: root.dialLeftX - width / 2
        y: root.dialY - height / 2
        color: "#0A1622"
        opacity: 0.55
    }
    Rectangle {
        width: root.dialDiameter * 1.9
        height: width
        radius: width / 2
        x: root.dialRightX - width / 2
        y: root.dialY - height / 2
        color: "#0A1622"
        opacity: 0.55
    }

    // ======================= ПРИБОР =======================
    // Один компонент на два прибора: отличается только шкалой и подписью.
    component Dial: Item {
        id: dial
        required property int cx
        required property int cy
        required property real value
        required property real valueMax
        required property string caption
        required property string unit
        required property int majorStep

        width: root.dialDiameter
        height: root.dialDiameter
        x: cx - width / 2
        y: cy - height / 2

        // тело прибора
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: root.dialFill
            border.color: root.dialRing
            border.width: 3
        }

        // деления: 37 штук по 7.5°, каждое пятое — длинное
        Repeater {
            model: 37
            Item {
                required property int index
                width: dial.width
                height: dial.height
                anchors.centerIn: parent
                rotation: -135 + index * 7.5

                Rectangle {
                    width: index % 5 === 0 ? 4 : 2
                    height: index % 5 === 0 ? 26 : 14
                    x: dial.width / 2 - width / 2
                    y: 10
                    color: index % 5 === 0 ? root.tickMajor : root.tickMinor
                    antialiasing: true
                }
            }
        }

        // цифры у крупных делений
        Repeater {
            model: Math.floor((dial.valueMax) / dial.majorStep) + 1
            Item {
                required property int index
                width: dial.width
                height: dial.height
                anchors.centerIn: parent
                rotation: -135 + index * (270 / (dial.valueMax / dial.majorStep))

                Text {
                    x: dial.width / 2 - width / 2
                    y: 46
                    text: index * dial.majorStep
                    color: root.labelGrey
                    font.pixelSize: 24
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }

        // стрелка: вращается вокруг центра, 0° — вверх
        Rectangle {
            width: 4
            height: dial.width / 2 - 40
            radius: 2
            x: dial.width / 2 - width / 2
            y: dial.height / 2 - height
            color: root.accent
            antialiasing: true
            transformOrigin: Item.Bottom
            rotation: root.needleAngle(dial.value, dial.valueMax, 0)
            Behavior on rotation {
                SpringAnimation { spring: 2.6; damping: 0.22; epsilon: 0.15 }
            }
        }

        // ступица
        Rectangle {
            width: 26; height: 26; radius: 13
            anchors.centerIn: parent
            color: root.accent
        }
        Rectangle {
            width: 12; height: 12; radius: 6
            anchors.centerIn: parent
            color: root.dialFill
        }

        // цифровое значение и подпись
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: dial.height * 0.62
            spacing: 2

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Math.round(dial.value)
                color: root.textMain
                font.pixelSize: 62
                font.bold: true
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: dial.unit
                color: root.labelGrey
                font.pixelSize: 20
                font.letterSpacing: 2
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: dial.caption
                color: root.labelGrey
                font.pixelSize: 16
                font.letterSpacing: 3
                opacity: 0.75
            }
        }
    }

    Dial {
        cx: root.dialLeftX
        cy: root.dialY
        value: root.speed
        valueMax: 200
        majorStep: 20
        caption: "СКОРОСТЬ"
        unit: "КМ/Ч"
    }

    Dial {
        cx: root.dialRightX
        cy: root.dialY
        value: root.rpm / 1000.0
        valueMax: 8
        majorStep: 1
        caption: "ТАХОМЕТР"
        unit: "x1000 ОБ/МИН"
    }

    // ======================= ЦЕНТРАЛЬНАЯ КОЛОНКА =======================
    Item {
        id: center
        x: 714
        y: 120
        width: 492
        height: 380

        // передача — крупно
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.gear
            color: root.textMain
            font.pixelSize: 128
            font.bold: true
        }

        // топливо и температура — две горизонтальные шкалы
        Column {
            anchors.top: parent.top
            anchors.topMargin: 150
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 18
            width: parent.width - 40

            Repeater {
                model: [
                    { label: "ТОПЛИВО", value: root.fuel, max: 100, unit: "%" },
                    { label: "ДВИГАТЕЛЬ", value: root.temp, max: 120, unit: "°C" }
                ]
                Row {
                    required property var modelData
                    spacing: 12
                    width: parent.width

                    Text {
                        text: modelData.label
                        color: root.labelGrey
                        font.pixelSize: 16
                        font.letterSpacing: 2
                        width: 130
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Rectangle {
                        width: 220; height: 10; radius: 5
                        color: "#16222E"
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, modelData.value / modelData.max))
                            height: parent.height
                            radius: parent.radius
                            color: root.accent
                            Behavior on width { NumberAnimation { duration: 300 } }
                        }
                    }
                    Text {
                        text: Math.round(modelData.value) + " " + modelData.unit
                        color: root.textMain
                        font.pixelSize: 18
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // поездка и запас хода
            Row {
                width: parent.width
                spacing: 24
                Text {
                    text: "ПОЕЗДКА " + root.tripKm.toFixed(1) + " КМ"
                    color: root.labelGrey
                    font.pixelSize: 16
                }
                Text {
                    text: root.rangeKm > 0 ? "ЗАПАС " + Math.round(root.rangeKm) + " КМ" : ""
                    color: root.labelGrey
                    font.pixelSize: 16
                }
            }
        }
    }

    // ======================= НИЖНЯЯ СВЕТЛАЯ ПОЛОСА =======================
    Rectangle {
        y: parent.height - root.stripHeight
        width: parent.width
        height: root.stripHeight
        color: root.strip

        Row {
            anchors.centerIn: parent
            spacing: 120

            Text {
                text: Math.round(root.speed) + "  КМ/Ч"
                color: root.stripInk
                font.pixelSize: 44
                font.bold: true
            }
            Text {
                text: root.clock
                color: root.stripInk
                font.pixelSize: 44
                font.bold: true
            }
            Text {
                text: root.gear
                color: root.stripInk
                font.pixelSize: 44
                font.bold: true
            }
        }
    }
}
