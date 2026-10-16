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
    readonly property real tankCapacity: CanBackend.tankCapacity   // объём бака, л
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
    // Самопроверка ламп при включении зажигания (гаснет через 2,5 с)
    property bool lampSelfTest: true
    property real brightness: 1.0
    property bool navigationMode: false
    property real navigationAnimDuration: 400

    // Режим центральной зоны: 0 — стандарт, 1 — компьютер, 2 — диагностика.
    // Переключается нажатием по центру или клавишами (стрелки, пробел).
    property int centerMode: 0
    readonly property int centerModeCount: 3

    function nextCenterMode() {
        centerMode = (centerMode + 1) % centerModeCount
    }

    function prevCenterMode() {
        centerMode = (centerMode + centerModeCount - 1) % centerModeCount
    }

    // ======================= ГЕОМЕТРИЯ МАКЕТА =======================
    readonly property int dialSize: 714        // диаметр прибора
    readonly property int dialY: 3             // (720 - 714) / 2 — по центру экрана
    readonly property int dialLeftX: 0         // спидометр вплотную к левому краю
    readonly property int dialRightX: 1206     // тахометр вплотную к правому краю
    readonly property int centerX: 714         // центральная область: 714..1206
    readonly property int centerWidth: 492

    // Приборы в режиме навигации: уменьшаются и уходят в нижние углы, как в Audi,
    // освобождая экран под карту. Карта при этом идёт под приборы, поэтому под
    // каждым прибором ставится непрозрачная подложка: сами циферблаты
    // полупрозрачные (альфа 255 только в центре, на радиусе 300 — уже 16)
    // и поверх карты становятся нечитаемыми.
    readonly property real navScale: 0.5
    readonly property int navMargin: 8
    readonly property real navInset: dialSize * (1 - navScale) / 2

    // Масштабирование всего макета под размер окна (на устройстве ровно 1.0)
    readonly property real canvasScale: Math.min(width / 1920, height / 720)

    // ======================= НАСТРОЙКИ ПРИБОРКИ =======================
    // Открываются кнопкой «Настройки» внизу центральной полосы или двойным
    // кликом по центральной области. Сам оверлей объявлен внутри canvas —
    // там он масштабируется вместе с макетом (см. Settings.qml).
    // Коэффициенты хранит Settings.qml, пробег — CanBackend.

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
        // Натуральный размер картинок 641x5 (раньше их растягивали до 500x10 —
        // сжимали по ширине и вдвое утолщали, поэтому концы не доходили до
        // приборов). Ширина 800: концы заходят под циферблаты и там скрываются —
        // под каждым прибором лежит непрозрачная чёрная подложка, без неё
        // полупрозрачные циферблаты просвечивают и полосы видно на шкалах.
        // В навигации полосы убираем: там карта на весь экран, резать её незачем.
        Image {
            source: "images/line_up.png"
            x: 560; y: 149
            width: 800; height: 5
            fillMode: Image.Stretch
            opacity: navigationMode ? 0.0 : 1.0
            Behavior on opacity { NumberAnimation { duration: navigationAnimDuration } }
        }
        Image {
            source: "images/line_down.png"
            x: 560; y: 558
            width: 800; height: 5
            fillMode: Image.Stretch
            opacity: navigationMode ? 0.0 : 1.0
            Behavior on opacity { NumberAnimation { duration: navigationAnimDuration } }
        }

        // ========== КАРТА: на весь экран, как в Audi ==========
        // Лежит под всем остальным (z = -10). Приборы в навигации уменьшаются
        // и уходят в нижние углы, поэтому карта под ними не мешает.
        MapWebView {
            id: navMap
            anchors.fill: parent
            opacity: navigationMode ? 1.0 : 0.0
            visible: navigationMode || opacity > 0
            active: navigationMode
            z: -10

            Behavior on opacity {
                NumberAnimation { duration: navigationAnimDuration; easing.type: Easing.InOutQuad }
            }
        }

        // Затемнение верхнего и нижнего края карты: показания (лампы, часы,
        // строка значений) должны читаться поверх карты.
        Rectangle {
            anchors.fill: parent
            z: -5
            opacity: navigationMode ? 1.0 : 0.0
            visible: opacity > 0
            gradient: Gradient {
                GradientStop { position: 0.00; color: "#E6000000" }
                GradientStop { position: 0.14; color: "#B3000000" }
                GradientStop { position: 0.32; color: "#00000000" }
                GradientStop { position: 0.62; color: "#00000000" }
                GradientStop { position: 0.76; color: "#B3000000" }
                GradientStop { position: 1.00; color: "#E6000000" }
            }
            Behavior on opacity { NumberAnimation { duration: navigationAnimDuration } }
        }

        // Здесь была скруглённая подложка под часами и наружной температурой
        // (x 1726, y 26) — остаток прежней раскладки, когда они стояли на
        // тахометре. Сейчас и часы, и температура живут в центральной полосе,
        // под затемнением сверху, поэтому подложка только мазала карту.

        // ========== КОНТЕЙНЕР СПИДОМЕТРА ==========
        Item {
            id: speedoContainer
            x: navigationMode ? (navMargin - navInset) : dialLeftX
            y: navigationMode ? (parent.height - dialSize * navScale - navMargin - navInset) : dialY
            width: dialSize
            height: dialSize
            scale: navigationMode ? navScale : 1.0
            z: 1

            Behavior on x { NumberAnimation { duration: navigationAnimDuration; easing.type: Easing.InOutQuad } }
            Behavior on y { NumberAnimation { duration: navigationAnimDuration; easing.type: Easing.InOutQuad } }
            Behavior on scale { NumberAnimation { duration: navigationAnimDuration; easing.type: Easing.InOutQuad } }

            // Непрозрачная подложка под прибором. Нужна в обоих режимах:
            // циферблаты полупрозрачные (альфа 255 только в центре, на радиусе
            // 300 — уже 16), поэтому без подложки под ними просвечивают
            // разделительные полосы, а в навигации — карта.
            Rectangle {
                anchors.centerIn: parent
                width: parent.width
                height: parent.height
                radius: width / 2
                color: "black"
            }

            Speedometer {
                id: speedo
                anchors.fill: parent
                speed: root.speed * root.speedFactor
                gearMode: root.gearMode
                fuelLevel: root.fuelLevel * root.fuelFactor
                startup: root.startup
                nightMode: root.nightMode
                seatBeltWarning: root.lampSelfTest || root.seatBelt
                handBrakeWarning: root.lampSelfTest || root.handBrake
                fuelWarning: root.lampSelfTest || (root.fuelLevel <= 10)
                batteryWarning: root.lampSelfTest || (root.rpm > 400 && root.voltage < 12.8)
                z: 1
            }
        }

        // ========== КОНТЕЙНЕР ТАХОМЕТРА ==========
        Item {
            id: tachoContainer
            x: navigationMode ? (parent.width - navMargin - dialSize * navScale - navInset) : dialRightX
            y: navigationMode ? (parent.height - dialSize * navScale - navMargin - navInset) : dialY
            width: dialSize
            height: dialSize
            scale: navigationMode ? navScale : 1.0
            z: 1

            Behavior on x { NumberAnimation { duration: navigationAnimDuration; easing.type: Easing.InOutQuad } }
            Behavior on y { NumberAnimation { duration: navigationAnimDuration; easing.type: Easing.InOutQuad } }
            Behavior on scale { NumberAnimation { duration: navigationAnimDuration; easing.type: Easing.InOutQuad } }

            // Непрозрачная подложка под прибором (см. спидометр)
            Rectangle {
                anchors.centerIn: parent
                width: parent.width
                height: parent.height
                radius: width / 2
                color: "black"
            }

            Tachometer {
                id: tacho
                anchors.fill: parent
                rpm: root.rpm * root.rpmFactor
                temp: root.temp * root.tempFactor
                startup: root.startup
                nightMode: root.nightMode
                absWarning: root.lampSelfTest || root.abs
                checkEngineWarning: root.lampSelfTest || root.checkEngine
                oilPressureWarning: root.lampSelfTest || root.oilPressureAlarm
                tempWarning: root.lampSelfTest || (root.temp >= 110)
                z: 1
            }
        }

        // ========== ЦЕНТРАЛЬНАЯ ОБЛАСТЬ ==========
        // Ровно между линиями-разделителями. Внутри — переключаемые режимы
        // (CenterPanel.qml); навигация отдельно, карта рисуется на весь экран.
        Item {
            id: centerPanel
            x: root.centerX
            y: 154
            width: root.centerWidth
            height: 404

            CenterPanel {
                anchors.fill: parent
                mode: root.centerMode
                nightMode: root.nightMode

                // В навигации карта занимает весь экран, и панель поверх неё
                // только мешает: гасим её так же, как разделительные полосы.
                // Область нажатий (MouseArea ниже) остаётся живой — долгое
                // нажатие по центру по-прежнему выводит из навигации.
                opacity: root.navigationMode ? 0.0 : 1.0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: root.navigationAnimDuration } }
            }

            // Одиночное нажатие — следующий режим, двойное — калибровка,
            // долгое — навигация. Одиночное ждём 220 мс, иначе двойной клик
            // успевал бы заодно переключить режим.
            MouseArea {
                anchors.fill: parent
                onPressAndHold: root.navigationMode = !root.navigationMode
                onClicked: centerTap.restart()
                onDoubleClicked: {
                    centerTap.stop()
                    calibration.open()
                }
            }

            Timer {
                id: centerTap
                interval: 220
                onTriggered: root.nextCenterMode()
            }
        }

        // Клавиши — удобно на столе и пригодится для кнопок на руле
        Shortcut { sequence: "Space"; onActivated: root.nextCenterMode() }
        Shortcut { sequence: "Right"; onActivated: root.nextCenterMode() }
        Shortcut { sequence: "Left"; onActivated: root.prevCenterMode() }

        // ========== ВЕРХНЯЯ ЗОНА ЦЕНТРА: предупреждения ==========
        // Держим их вне области карты, чтобы были видны и в навигации.
        Item {
            x: root.centerX
            y: 92
            width: root.centerWidth
            height: 42

            Row {
                anchors.centerIn: parent
                spacing: 22

                // Нет данных от блока сбора (ESP32): кадры не приходят дольше 1,5 с
                Text {
                    id: noCanWarning
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

                // Гололёд
                Text {
                    id: iceWarning
                    text: "⚠ ГОЛОЛЁД"
                    color: "#FF4444"
                    font.pixelSize: 20
                    font.bold: true
                    visible: root.outsideTemp <= 0

                    SequentialAnimation on opacity {
                        running: iceWarning.visible
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.35; to: 1.0; duration: 700 }
                        NumberAnimation { from: 1.0; to: 0.35; duration: 700 }
                    }
                }
            }
        }

        // ========== НИЖНЯЯ ЗОНА ЦЕНТРА: показания ==========
        // Вольтметр, топливо, температура двигателя, расход. Раньше это была
        // колонка в центре — в навигации она попадала на карту.
        Item {
            x: root.centerX
            y: 570
            width: root.centerWidth
            height: 40

            Row {
                anchors.centerIn: parent
                spacing: 12

                Text {
                    text: root.voltage.toFixed(1) + " В"
                    color: root.nightMode ? "#FF8800" : "white"
                    font.pixelSize: 24
                    font.bold: true
                }
                Text {
                    text: "·"
                    color: "#555555"
                    font.pixelSize: 24
                }
                Text {
                    text: (root.fuelLevel * root.fuelFactor / 100 * root.tankCapacity).toFixed(1) + " л"
                    color: root.nightMode ? "#FF8800" : "white"
                    font.pixelSize: 24
                    font.bold: true
                }
                Text {
                    text: "·"
                    color: "#555555"
                    font.pixelSize: 24
                }
                Text {
                    // Температура — как соседние показания, с одним знаком:
                    // «0,0 °C», а не «0 °C».
                    text: root.temp.toFixed(1) + " °C"
                    color: root.nightMode ? "#FF8800" : "white"
                    font.pixelSize: 24
                    font.bold: true
                }
                Text {
                    text: "·"
                    color: "#555555"
                    font.pixelSize: 24
                }
                Text {
                    text: root.fuelRate.toFixed(1) + " л/100"
                    color: root.nightMode ? "#FF8800" : "white"
                    font.pixelSize: 22
                    font.bold: true
                }
            }
        }

        Indicators {
            leftTurn: root.leftTurn
            rightTurn: root.rightTurn
            highBeam: root.highBeam
            lowBeam: root.lowBeam
            positionLights: root.positionLights
            fogLights: root.fogLights
            brakeLights: root.brakeLights
            reverseLights: root.reverseLights
            checkEngine: root.checkEngine
            abs: root.abs
            handBrake: root.handBrake
            seatBelt: root.seatBelt
            gearLock: root.gearLock
            gearMode: root.gearMode
            timeString: root.timeString
            odometer: root.odometer
            tripA: root.tripA
            tripB: root.tripB
            selfTest: root.lampSelfTest
        }

        Button {
            text: "Навигация"
            x: 730; y: 658
            visible: !navigationMode
            onClicked: navigationMode = true
            z: 2
        }

        // Вход в настройки — тот же путь, что потом будет у кнопки на руле:
        // одна функция calibration.open(), а не жест мышью.
        Button {
            text: "Настройки"
            x: 860; y: 658
            visible: !navigationMode
            onClicked: calibration.open()
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
        //  Настройки приборки. Оверлей поверх всего остального (z 300):
        //  объявлен внутри canvas, поэтому масштабируется вместе с макетом.
        //  Открывается кнопкой «Настройки» или двойным кликом по центру.
        // ====================================================================
        Settings {
            id: calibration

            nightMode: root.nightMode

            onSettingsApplied: function(sf, rf, ff, tf) {
                root.speedFactor = sf
                root.rpmFactor = rf
                root.fuelFactor = ff
                root.tempFactor = tf
            }
        }

        // ====================================================================
        //  Самопроверка ламп и стрелок при включении зажигания
        // ====================================================================
        Timer {
            interval: 2500
            running: true
            onTriggered: {
                root.lampSelfTest = false
                root.startup = false
            }
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
