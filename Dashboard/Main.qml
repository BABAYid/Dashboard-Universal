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
    // Источник — CanBackend (Dashboard/can/CanBackend.cpp): приём кадров
    // 0x100/0x200/0x300/0x400 по SocketCAN либо генерация в демо-режиме (--mock).
    // Коэффициенты калибровки применяются на самих приборах.
    readonly property real speed: CanBackend.speed
    readonly property real rpm: CanBackend.rpm
    readonly property real fuelLevel: CanBackend.fuelLevel   // 0..100 % (0x300 байт 1)
    readonly property real tankCapacity: 60                  // объём бака, л — для показания в литрах
    readonly property real temp: CanBackend.engineTemp
    readonly property real voltage: CanBackend.voltage
    readonly property real outsideTemp: CanBackend.outsideTemp
    readonly property real fuelRate: CanBackend.fuelRate     // л/100 км (0x300 байт 5)
    readonly property bool leftTurn: CanBackend.leftTurn
    readonly property bool rightTurn: CanBackend.rightTurn
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
    property real tempFactor: 1.0
    property bool startup: true
    property real brightness: 1.0
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

    // ======================= КАЛИБРОВКА ПРИБОРОВ =======================
    // Окно открывается двойным кликом по центральной области.
    // Коэффициенты хранит Settings.qml (Qt.labs.settings).
    Settings {
        id: calibration

        onSettingsApplied: function(sf, rf, ff, tf) {
            root.speedFactor = sf
            root.rpmFactor = rf
            root.fuelFactor = ff
            root.tempFactor = tf
        }
    }

    Component.onCompleted: {
        root.speedFactor = calibration.speedFactor
        root.rpmFactor = calibration.rpmFactor
        root.fuelFactor = calibration.fuelFactor
        root.tempFactor = calibration.tempFactor
    }

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

            // Нет данных от блока сбора (ESP32): кадры не приходят дольше 1,5 с
            Text {
                id: noCanWarning
                anchors.horizontalCenter: parent.horizontalCenter
                y: 4
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
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: root.fuelRate.toFixed(1) + " л/100"
                    color: root.nightMode ? "#FF8800" : "white"
                    font.pixelSize: 24
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
                y: 304
                visible: root.outsideTemp <= 0

                SequentialAnimation on opacity {
                    running: iceWarning.visible
                    loops: Animation.Infinite
                    NumberAnimation { from: 0.35; to: 1.0; duration: 700 }
                    NumberAnimation { from: 1.0; to: 0.35; duration: 700 }
                }
            }

            // Двойной клик — калибровка приборов, долгое нажатие — навигация
            MouseArea {
                anchors.fill: parent
                onPressAndHold: root.navigationMode = !root.navigationMode
                onDoubleClicked: calibration.visible = true
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
    }
}
