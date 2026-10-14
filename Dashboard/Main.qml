import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import "."
import QtWebView 6.0
import Qt5Compat.GraphicalEffects 1.0

Window {
    id: root
    width: 1280
    height: 600
    visible: true
    color: "black"
    title: "Audi Dashboard (real size 1920x720)"

    FontLoader {
        id: customFont
        source: "file:///home/oleg/Документы/новая приборка/Dashboard/fonts/KdamThmorPro-Regular.ttf"
        onStatusChanged: {
            if (status === FontLoader.Ready) {
                console.log("Шрифт Kdam Thmor Pro загружен")
                root.font.family = customFont.name
            } else if (status === FontLoader.Error) {
                console.log("Ошибка загрузки шрифта")
            }
        }
    }

    property real speed: 0
    property real rpm: 0
    property real fuelLevel: 0
    property real temp: 0
    property real voltage: 14.2
    property string timeString: "12:34"
    property bool leftTurn: true
    property bool rightTurn: false
    property bool highBeam: true
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
    property real outsideTemp: 5.0
    property bool navigationMode: false
    property real navigationAnimDuration: 400

    property int offsetX: 280
    property int offsetY: 80

    Flickable {
        anchors.fill: parent
        contentWidth: 1920
        contentHeight: 720
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalAndVerticalFlick

        Item {
            width: 1920
            height: 720

            Image {
                source: "file:///home/oleg/Документы/новая приборка/Dashboard/images/line_up.png"
                x: 700; y: 190
                width: 500; height: 10
                fillMode: Image.Stretch
            }
            Image {
                source: "file:///home/oleg/Документы/новая приборка/Dashboard/images/line_down.png"
                x: 700; y: 670
                width: 500; height: 10
                fillMode: Image.Stretch
            }

            // ========== КОНТЕЙНЕР СПИДОМЕТРА ==========
            Item {
                id: speedoContainer
                x: navigationMode ? (100 - offsetX) : 100
                y: navigationMode ? (80 + offsetY) : 80
                width: navigationMode ? 500 : 714
                height: navigationMode ? 500 : 714

                Behavior on x { NumberAnimation { duration: navigationAnimDuration; easing.type: Easing.InOutQuad } }
                Behavior on y { NumberAnimation { duration: navigationAnimDuration; easing.type: Easing.InOutQuad } }
                Behavior on width { NumberAnimation { duration: navigationAnimDuration; easing.type: Easing.InOutQuad } }
                Behavior on height { NumberAnimation { duration: navigationAnimDuration; easing.type: Easing.InOutQuad } }

                // Круг-подложка
                Rectangle {
                    width: parent.width * 0.7
                    height: parent.height * 0.7
                    radius: width / 2
                    color: "black"
                    opacity: navigationMode ? 0.9 : 0.0
                    visible: navigationMode
                    anchors.centerIn: parent
                    Behavior on opacity { NumberAnimation { duration: navigationAnimDuration; easing.type: Easing.InOutQuad } }
                }

                // Сам прибор
                Speedometer {
                    id: speedo
                    anchors.fill: parent
                    scale: navigationMode ? 0.7 : 1.0
                    speed: root.speed * root.speedFactor
                    gearMode: root.gearMode
                    fuelLevel: root.fuelLevel * root.fuelFactor
                    startup: root.startup
                    nightMode: root.nightMode
                    z: 1

                    Behavior on scale { NumberAnimation { duration: navigationAnimDuration; easing.type: Easing.InOutQuad } }
                }
            }

            // ========== КОНТЕЙНЕР ТАХОМЕТРА ==========
            Item {
                id: tachoContainer
                x: navigationMode ? (1106 + offsetX) : 1106
                y: navigationMode ? (80 + offsetY) : 80
                width: navigationMode ? 500 : 714
                height: navigationMode ? 500 : 714

                Behavior on x { NumberAnimation { duration: navigationAnimDuration; easing.type: Easing.InOutQuad } }
                Behavior on y { NumberAnimation { duration: navigationAnimDuration; easing.type: Easing.InOutQuad } }
                Behavior on width { NumberAnimation { duration: navigationAnimDuration; easing.type: Easing.InOutQuad } }
                Behavior on height { NumberAnimation { duration: navigationAnimDuration; easing.type: Easing.InOutQuad } }

                Rectangle {
                    width: parent.width * 0.7
                    height: parent.height * 0.7
                    radius: width / 2
                    color: "black"
                    opacity: navigationMode ? 0.9 : 0.0
                    visible: navigationMode
                    anchors.centerIn: parent
                    Behavior on opacity { NumberAnimation { duration: navigationAnimDuration; easing.type: Easing.InOutQuad } }
                }

                Tachometer {
                    id: tacho
                    anchors.fill: parent
                    scale: navigationMode ? 0.7 : 1.0
                    rpm: root.rpm * root.rpmFactor
                    temp: root.temp * root.tempFactor
                    startup: root.startup
                    nightMode: root.nightMode
                    z: 1

                    Behavior on scale { NumberAnimation { duration: navigationAnimDuration; easing.type: Easing.InOutQuad } }
                }
            }

            Indicators {
                leftTurn: root.leftTurn
                rightTurn: root.rightTurn
                highBeam: root.highBeam
                checkEngine: root.checkEngine
                abs: root.abs
                gearMode: root.gearMode
                odometer: root.odometer
                tripA: root.tripA
                tripB: root.tripB
            }

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
                x: 900; y: 20
                visible: !navigationMode
                onClicked: navigationMode = true
                z: 2
            }

            Rectangle {
                id: closeNavButton
                width: 60; height: 60
                radius: 30; color: "#CC0000"
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 20
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

            Column {
                id: column
                x: 930; y: 350
                spacing: 20
                z: 2

                Text { text: root.voltage.toFixed(1) + "V"; color: root.nightMode ? "#FF8800" : "white"; font.pixelSize: 28; font.bold: true }
                Text { text: root.fuelLevel + " L"; color: root.nightMode ? "#FF8800" : "white"; font.pixelSize: 28; font.bold: true }
                Text { text: root.temp + "°C"; color: root.nightMode ? "#FF8800" : "white"; font.pixelSize: 28; font.bold: true }
                Text { text: root.timeString; color: root.nightMode ? "#FF8800" : "white"; font.pixelSize: 28; font.bold: true }
            }

            MouseArea {
                anchors.fill: column
                onDoubleClicked: console.log("Настройки пока не подключены")
                onPressAndHold: root.navigationMode = !root.navigationMode
            }

            Text {
                id: iceWarning
                text: "⚠️ Будьте осторожны\nвозможен гололёд!"
                color: "#FF4444"
                font.pixelSize: 28
                font.bold: true
                font.family: "Kdam Thmor Pro"
                horizontalAlignment: Text.AlignHCenter
                x: 960 - width/2
                y: 360
                visible: root.outsideTemp <= 0
                opacity: 1.0
                Behavior on opacity {
                    SequentialAnimation {
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.4; to: 1.0; duration: 600 }
                        NumberAnimation { from: 1.0; to: 0.4; duration: 600 }
                    }
                }
                z: 3
            }

            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: 1.0 - root.brightness
                z: 100
                enabled: false
            }

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
                    root.timeString = now.getHours().toString().padStart(2,'0') + ":" + now.getMinutes().toString().padStart(2,'0')
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
}
