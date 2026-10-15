import QtQuick 2.15

Item {
    id: root
    width: 714
    height: 714

    // Свойства для данных
    property real speed: 0
    property real maxSpeed: 220

    // Углы стрелки спидометра.
    // Стрелка (needls_spd.svg) при rotation = 0 смотрит не вверх, а влево —
    // примерно на 191°. Углы ниже посчитаны как (угол метки на шкале минус 191°).
    // Метки шкалы в Speedometr.png стоят через 22.29° (по 20 км/ч): «0» на
    // 135.1°, «220» на 20.3°.
    //   speed = 0   → стрелка на 135.1° → rotation = 135.1 - 191.2 = -56.1
    //   speed = 220 → стрелка на  20.3° → rotation = (20.3 - 191.2) + 360 = 189.1
    // Раньше стояло -60…220 (размах 280° вместо 245°), из-за чего у нуля ошибка
    // была 4°, а на 220 км/ч стрелка уходила на 31° за метку.
    property real speedStartAngle: -56.1
    property real speedEndAngle: 189.1

    property real fuelLevel: 0
    property real maxFuel: 100
    property real fuelStartAngle: -75
    property real fuelEndAngle: -130
    property bool startup: false
    property bool nightMode: false
    property string gearMode: "P"

    // Состояние ламп (приходит из Main.qml, источник — CanBackend)
    property bool seatBeltWarning: false
    property bool batteryWarning: false
    property bool fuelWarning: false
    property bool handBrakeWarning: false

    // Коэффициенты для масштабирования (относительно базового размера 714)
    readonly property real baseSize: 714
    readonly property real scaleFactor: width / baseSize

    // Шкала спидометра
    Image {
        anchors.fill: parent
        source: "images/Speedometr.png"
        fillMode: Image.PreserveAspectFit
    }

    // Стрелка топлива (под кругом)
    Image {
        id: needleFuel
        width: parent.width * 1.05
        height: parent.height * 1.05
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        source: "images/needls_fuel.svg"
        fillMode: Image.PreserveAspectFit
        transformOrigin: Item.Center
        rotation: fuelStartAngle + (fuelLevel / maxFuel) * (fuelEndAngle - fuelStartAngle)
        Behavior on rotation {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
    }

    // Центральный круг (поверх стрелки топлива)
    Image {
        width: parent.width * 0.622
        height: parent.height * 0.622
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        source: "images/around_in.png"
        fillMode: Image.PreserveAspectFit
    }


    // Угол поворота стрелки скорости: во время самопроверки показываем
    // sweepAngle (его ведёт анимация), после неё — обычное значение.
    // Анимация пишет в отдельное свойство: если бы она
    // писала прямо в rotation, привязка разрушилась бы и стрелка «застыла».
    readonly property real speedAngle: speedStartAngle + (speed / maxSpeed) * (speedEndAngle - speedStartAngle)
    property real sweepAngle: 0

    // Стрелка спидометра (поверх всего)
    Image {
        id: needleSpeed
        width: parent.width * 1.05
        height: parent.height * 1.05
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        source: "images/needls_spd.svg"
        fillMode: Image.PreserveAspectFit
        transformOrigin: Item.Center
        rotation: root.startup ? root.sweepAngle : root.speedAngle
        Behavior on rotation {
            enabled: !root.startup
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
    }
    // ======================= ЦИФРОВАЯ СКОРОСТЬ =======================
    // Место: полоса прямо над ступицей. Она зажата между иконкой ремня
    // (заканчивается на y=228) и иконкой передачи (начинается с y=307),
    // поэтому высота ровно 79 px — это проверено замером.
    // Выше ставить нельзя: там ходят обе стрелки — и спидометра, и топлива
    // (стрелка топлива той же длины, её сектор 61°…116°, то есть низ циферблата).
    // Подложка нужна, чтобы стрелка, проходящая через цифры, не мешала читать:
    // без неё белые цифры сливаются со светлой стрелкой.
    Column {
        id: digitalSpeed
        x: parent.width * 0.39
        y: parent.height * 0.325
        width: parent.width * 0.22

        // Появляются после самопроверки приборов, как в серийных панелях
        opacity: root.startup ? 0.0 : 1.0
        Behavior on opacity { NumberAnimation { duration: 400 } }

        Text {
            id: speedDigits
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: Math.round(root.speed)
            color: root.nightMode ? "#FF8800" : "white"
            font.pixelSize: 40
            font.bold: true
            font.family: "Kdam Thmor Pro"
            // Подложки нет, поэтому цифры отделяем от стрелки тонким контуром
            style: Text.Outline
            styleColor: "#000000"
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "км/ч"
            color: root.nightMode ? "#FF8800" : "#8C8C8C"
            font.pixelSize: 15
            font.family: "Kdam Thmor Pro"
        }
    }


    // ======================= ЛАМПЫ СПИДОМЕТРА =======================
    // Каждая лампа загорается по своему сигналу; гаснет — opacity 0.
    // Длительность перехода небольшая, чтобы включение читалось мягко.

    // Ремень безопасности
    Image {
        source: "images/belt.png"
        width: parent.width * 0.07
        height: parent.width * 0.07
        x: parent.width * 0.47
        y: parent.height * 0.25
        fillMode: Image.PreserveAspectFit
        opacity: root.seatBeltWarning ? 1.0 : 0.0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    // Зарядка АКБ
    Image {
        source: "images/batt.png"
        width: parent.width * 0.07
        height: parent.width * 0.07
        x: parent.width * 0.35
        y: parent.height * 0.58
        fillMode: Image.PreserveAspectFit
        opacity: root.batteryWarning ? 1.0 : 0.0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    // Значок шкалы топлива — это часть разметки прибора, он виден ВСЕГДА.
    // Мигает только при низком уровне топлива.
    property bool fuelWarnBlink: false
    Timer {
        interval: 500
        repeat: true
        running: root.fuelWarning
        onRunningChanged: if (!running) root.fuelWarnBlink = false
        onTriggered: root.fuelWarnBlink = !root.fuelWarnBlink
    }

    Image {
        source: "images/fuel_tank.png"
        width: parent.width * 0.07
        height: parent.width * 0.07
        x: parent.width * 0.28
        y: parent.height * 0.77
        fillMode: Image.PreserveAspectFit
        opacity: (root.fuelWarning && root.fuelWarnBlink) ? 0.3 : 1.0
    }
    // Ручник
    Image {
        source: "images/H_brake.png"
        width: parent.width * 0.07
        height: parent.width * 0.07
        x: parent.width * 0.45
        y: parent.height * 0.58
        fillMode: Image.PreserveAspectFit
        opacity: root.handBrakeWarning ? 1.0 : 0.0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    // Пониженная передача (режим L)
    Image {
        source: "images/low_L.png"
        width: parent.width * 0.07
        height: parent.width * 0.07
        x: parent.width * 0.55
        y: parent.height * 0.58
        fillMode: Image.PreserveAspectFit
        opacity: (root.gearMode === "L") ? 1.0 : 0.0
        visible: opacity > 0
    }

    // === ИНДИКАТОР АКПП (P/R/N/D1..D4/L) ===
    Image {
        id: gearIcon
        source: "images/gear_" + root.gearMode + ".png"
        width: parent.width * 0.12
        height: parent.width * 0.12
        x: parent.width * 0.6
        y: parent.height * 0.43
        fillMode: Image.PreserveAspectFit
    }

    // Анимация запуска (Sweep). Флагом startup управляет Main.qml.
    SequentialAnimation {
        id: startupAnimation
        running: root.startup

        NumberAnimation {
            target: root
            property: "sweepAngle"
            from: root.speedStartAngle
            to: root.speedEndAngle
            duration: 800
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root
            property: "sweepAngle"
            from: root.speedEndAngle
            to: root.speedAngle
            duration: 400
            easing.type: Easing.InOutQuad
        }
    }
}
