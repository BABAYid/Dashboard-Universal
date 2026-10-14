import QtQuick 2.15

Item {
    id: root
    width: 714
    height: 714

    // Свойства для данных
    property real speed: 0
    property real maxSpeed: 220
    property real speedStartAngle: -60
    property real speedEndAngle: 220
    property real fuelLevel: 0
    property real maxFuel: 100
    property real fuelStartAngle: -75
    property real fuelEndAngle: -130
    property bool startup: false
    property bool nightMode: false
    property string gearMode: "P"

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
        rotation: speedStartAngle + (speed / maxSpeed) * (speedEndAngle - speedStartAngle)
        Behavior on rotation {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
    }
    // Ремень безопасности
        Image {
            source: "images/belt.png"
            width: parent.width * 0.07   // ~50px при 714x714
            height: parent.width * 0.07
            x: parent.width * 0.47
            y: parent.height * 0.25
            opacity: 1.0
            fillMode: Image.PreserveAspectFit
        }
        // Дополнительная иконка для режима L
        Image {
            source: "images/low_L.png"
            width: parent.width * 0.07   // ~50px при 714x714
            height: parent.width * 0.07
            x: parent.width * 0.55
            y: parent.height * 0.58
            fillMode: Image.PreserveAspectFit
            visible: (root.gearMode === "L")
        }

        // Зарядка АКБ
        Image {
            source: "images/batt.png"
            width: parent.width * 0.07   // ~50px при 714x714
            height: parent.width * 0.07
            x: parent.width * 0.35
            y: parent.height * 0.58
            opacity: 1.0
            fillMode: Image.PreserveAspectFit
        }
        // === ИНДИКАТОР АКПП ===
        Image {
            id: gearIcon
            source: "images/gear_" + root.gearMode + ".png"
            width: parent.width * 0.12   // ~50px при 714x714
            height: parent.width * 0.12
            x: parent.width * 0.6
            y: parent.height * 0.43
            fillMode: Image.PreserveAspectFit
        }
        // Топливо
        Image {
            source: "images/fuel_tank.png"
            width: parent.width * 0.07   // ~50px при 714x714
            height: parent.width * 0.07
            x: parent.width * 0.28
            y: parent.height * 0.77
            opacity: 1.0
            fillMode: Image.PreserveAspectFit
        }
        // Ручник
        Image {
            source: "images/H_brake.png"
            width: parent.width * 0.07   // ~50px при 714x714
            height: parent.width * 0.07
            x: parent.width * 0.45
            y: parent.height * 0.58
            opacity: 1.0
            fillMode: Image.PreserveAspectFit
        }

    // Анимация запуска (Sweep)
    SequentialAnimation {
        id: startupAnimation
        running: root.startup
        onFinished: root.startup = false

        NumberAnimation {
            target: needleSpeed
            property: "rotation"
            from: speedStartAngle
            to: speedEndAngle
            duration: 800
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: needleSpeed
            property: "rotation"
            from: speedEndAngle
            to: speedStartAngle + (speed / maxSpeed) * (speedEndAngle - speedStartAngle)
            duration: 400
            easing.type: Easing.InOutQuad
        }
    }
}
