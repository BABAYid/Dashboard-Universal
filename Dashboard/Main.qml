import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import "."

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
    // ВНИМАНИЕ: сейчас это заглушка, значения меняет Timer внизу файла.
    // На этапе 2 источником станут свойства CAN-бэкенда (см. can/CanBackend).
    property real speed: 0
    property real rpm: 0
    property real fuelLevel: 0        // 0..100 % (как в CAN-протоколе, ID 0x300 байт 1)
    property real tankCapacity: 60    // объём бака, л — для показания в литрах
    property real temp: 0
    property real voltage: 14.2
    property string timeString: "12:34"
    property real outsideTemp: 5.0
    property bool leftTurn: false
    property bool rightTurn: false
    property bool highBeam: false
    property bool checkEngine: false
    property bool abs: false
    property string gearMode: "P"
    property real odometer: 123456.7
    property real tripA: 123.4
    property real tripB: 456.7
    property string displayMode: "odo"
    property real speedFactor: 1.0
    property real rpmFactor: 1.0
    property real fuelFactor: 1.0
    property real tempFactor: 1.0
    property bool startup: true
    property real brightness: 1.0
    property bool nightMode: false
    property bool navigationMode: false
    property real navigationAnimDuration: 400

    // ======================= ГЕОМЕТРИЯ МАКЕТА =======================
    readonly property int dialSize: 714        // диаметр прибора
    readonly property int dialY: 3             // (720 - 714) / 2 — по центру экрана
    readonly property int dialLeftX: 0         // спидометр вплотную к левому краю
    readonly property int dialRightX: 1206     // тахометр вплотную к правому краю
    readonly property int centerX: 714         // центральная область: 714..1206
    readonly property int centerWidth: 492
    readonly property int navOffsetX: 200      // сдвиг приборов за край в режиме навигации
    readonly property real navScale: 0.7

    // Масштабирование всего макета под размер окна (на устройстве ровно 1.0)
    readonly property real canvasScale: Math.min(width / 1920, height / 720)

    Item {
        id: canvas
        width: 1920
        height: 720
        transformOrigin: Item.TopLeft
        scale: root.canvasScale
        x: (root.width - width * scale) / 2
        y: (root.height - height * scale) / 2

        // ========== РАЗДЕЛИТЕЛЬНЫЕ ЛИНИИ ЦЕНТРАЛЬНОЙ ОБЛАСТИ ==========
        Image {
            source: "images/line_up.png"
            x: 710; y: 146
            width: 500; height: 10
            fillMode: Image.Stretch
        }
        Image {
            source: "images/line_down.png"
            x: 710; y: 555
            width: 500; height: 10
            fillMode: Image.Stretch
        }

        // ========== КОНТЕЙНЕР СПИДОМЕТРА ==========
        Item {
            id: speedoContainer
            x: navigationMode ? -navOffsetX : dialLeftX
            y: dialY
            width: dialSize
            height: dialSize
            scale: navigationMode ? navScale : 1.0

            Behavior on x { NumberAnimation { duration: navigationAnimDuration; easing.type: Easing.InOutQuad } }
            Behavior on scale { NumberAnimation { duration: navigationAnimDuration; easing.type: Easing.InOutQuad } }

            // Круг-подложка под прибором в режиме навигации
            Rectangle {
                width: parent.width * 0.7
                height: parent.height * 0.7
                radius: width / 2
                color: "black"
                opacity: navigationMode ? 0.9 : 0.0
                visible: opacity > 0
                anchors.centerIn: parent
                Behavior on opacity { NumberAnimation { duration: navigationAnimDuration; easing.type: Easing.InOutQuad } }
            }

            Speedometer {
                id: speedo
                anchors.fill: parent
                speed: root.speed * root.speedFactor
                gearMode: root.gearMode
                fuelLevel: root.fuelLevel * root.fuelFactor
                startup: root.startup
                nightMode: root.nightMode
                z: 1
            }
        }

        // ========== КОНТЕЙНЕР ТАХОМЕТРА ==========
        Item {
            id: tachoContainer
            x: navigationMode ? dialRightX + navOffsetX : dialRightX
            y: dialY
            width: dialSize
            height: dialSize
            scale: navigationMode ? navScale : 1.0

            Behavior on x { NumberAnimation { duration: navigationAnimDuration; easing.type: Easing.InOutQuad } }
            Behavior on scale { NumberAnimation { duration: navigationAnimDuration; easing.type: Easing.InOutQuad } }

            Rectangle {
                width: parent.width * 0.7
                height: parent.height * 0.7
                radius: width / 2
                color: "black"
                opacity: navigationMode ? 0.9 : 0.0
                visible: opacity > 0
                anchors.centerIn: parent
                Behavior on opacity { NumberAnimation { duration: navigationAnimDuration; easing.type: Easing.InOutQuad } }
            }

            Tachometer {
                id: tacho
                anchors.fill: parent
                rpm: root.rpm * root.rpmFactor
                temp: root.temp * root.tempFactor
                startup: root.startup
                nightMode: root.nightMode
                z: 1
            }
        }

        // ========== ЦЕНТРАЛЬНАЯ ОБЛАСТЬ (x=714..1206, y=146..555) ==========
        Item {
            id: centerPanel
            x: root.centerX
            y: 146
            width: root.centerWidth
            height: 409

            Column {
                id: infoColumn
                width: parent.width
                y: 46
                spacing: 16

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: root.voltage.toFixed(1) + " V"
                    color: root.nightMode ? "#FF8800" : "white"
                    font.pixelSize: 28
                    font.bold: true
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: (root.fuelLevel * root.fuelFactor / 100 * root.tankCapacity).toFixed(1) + " л"
                    color: root.nightMode ? "#FF8800" : "white"
                    font.pixelSize: 28
                    font.bold: true
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: root.temp.toFixed(0) + " °C"
                    color: root.nightMode ? "#FF8800" : "white"
                    font.pixelSize: 28
                    font.bold: true
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: root.timeString
                    color: root.nightMode ? "#FF8800" : "white"
                    font.pixelSize: 28
                    font.bold: true
                }
            }

            // Предупреждение о гололёде — под колонкой данных, над нижней линией
            Text {
                id: iceWarning
                text: "⚠ Будьте осторожны,\nвозможен гололёд!"
                color: "#FF4444"
                font.pixelSize: 26
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
                y: 264
                visible: root.outsideTemp <= 0

                SequentialAnimation on opacity {
                    running: iceWarning.visible
                    loops: Animation.Infinite
                    NumberAnimation { from: 0.35; to: 1.0; duration: 700 }
                    NumberAnimation { from: 1.0; to: 0.35; duration: 700 }
                }
            }

            // Долгое нажатие по центру — переключение режима навигации
            MouseArea {
                anchors.fill: parent
                onPressAndHold: root.navigationMode = !root.navigationMode
            }
        }

        Indicators {
            leftTurn: root.leftTurn
            rightTurn: root.rightTurn
            highBeam: root.highBeam
            checkEngine: root.checkEngine
            abs: root.abs
            gearMode: root.gearMode
            outsideTemp: root.outsideTemp
            odometer: root.odometer
            tripA: root.tripA
            tripB: root.tripB
        }

        // ========== КАРТА (режим навигации) ==========
        MapWebView {
            id: navMap
            anchors.fill: parent
            opacity: navigationMode ? 1.0 : 0.0
            visible: navigationMode || opacity > 0
            active: navigationMode
            z: -1

            Behavior on opacity {
                NumberAnimation { duration: navigationAnimDuration; easing.type: Easing.InOutQuad }
            }
        }

        Button {
            text: "Навигация"
            x: 900; y: 30
            visible: !navigationMode
            onClicked: navigationMode = true
            z: 2
        }

        Rectangle {
            id: closeNavButton
            width: 60; height: 60
            radius: 30; color: "#CC0000"
            x: parent.width - width - 20
            y: 20
            visible: navigationMode
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
                onClicked: navigationMode = false
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
        //  ЗАГЛУШКА ДАННЫХ. Удаляется при подключении CAN-бэкенда (этап 2).
        // ====================================================================
        Timer {
            interval: 500
            running: true
            repeat: true
            onTriggered: {
                root.speed = (root.speed + 1) % 221
                root.rpm = root.rpm + 50
                if (root.rpm > 8000) root.rpm = 0
                root.fuelLevel = (root.fuelLevel + 1) % 101
                root.temp = (root.temp + 1) % 121
                root.voltage = 12.0 + Math.random() * 3.0
                var now = new Date()
                root.timeString = now.getHours().toString().padStart(2, '0') + ":" + now.getMinutes().toString().padStart(2, '0')
                var modes = ["P", "R", "N", "D1", "D2", "D3", "D4", "L"]
                root.gearMode = modes[Math.floor(Math.random() * modes.length)]
                root.odometer += 0.01
                root.tripA += 0.01
                root.tripB += 0.01
                root.brightness = 0.7 + Math.random() * 0.3
                root.nightMode = (root.speed % 3 == 0)
                root.outsideTemp = -5 + Math.random() * 30
            }
        }
    }
}
