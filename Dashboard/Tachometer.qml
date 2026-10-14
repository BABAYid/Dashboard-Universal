import QtQuick 2.15

Item {
    id: root
    width: 714
    height: 714

    property real rpm: 0
    property real maxRpm: 8000
    property real rpmStartAngle: -80
    property real rpmEndAngle: 200

    property real temp: 0
    property real maxTemp: 120
    property real tempStartAngle: -80
    property real tempEndAngle: -103

    property bool startup: false
    property bool nightMode: false

    // Состояние ламп (приходит из Main.qml, источник — CanBackend)
    property bool absWarning: false
    property bool checkEngineWarning: false
    property bool oilPressureWarning: false
    property bool tempWarning: false

    // Центр вращения
    readonly property point centerPoint: Qt.point(width/2, height/2)

    // Подложка (общая шкала)
    Image {
        anchors.fill: parent
        source: "images/taho.png"
        fillMode: Image.PreserveAspectFit
    }

    // === СТРЕЛКА ТЕМПЕРАТУРЫ ===
    Image {
        id: needleTemp
        source: "images/needls_temp.svg"
        x: centerPoint.x - width/2
        y: centerPoint.y - height/2
        width: parent.width * 1.05
        height: parent.height * 1.05
        fillMode: Image.PreserveAspectFit
        transformOrigin: Item.Center
        rotation: tempStartAngle + (temp / maxTemp) * (tempEndAngle - tempStartAngle)
        Behavior on rotation {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
    }

    // Центральный круг
    Image {
        width: parent.width * 0.638
        height: parent.height * 0.638
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        source: "images/around_in.png"
        fillMode: Image.PreserveAspectFit

    }

    // Угол стрелки тахометра: во время самопроверки — sweepAngle (ведёт
    // анимация), после неё — значение по оборотам. Анимация не пишет в rotation
    // напрямую, иначе привязка разрушилась бы (раньше это лечилось костылём
    // onRpmChanged, который переписывал угол вручную).
    readonly property real rpmAngle: rpmStartAngle + (rpm / maxRpm) * (rpmEndAngle - rpmStartAngle)
    property real sweepAngle: 0

    // === СТРЕЛКА ТАХОМЕТРА ===
    Image {
        id: needleRpm
        source: "images/needls_tho.svg"
        x: centerPoint.x - width/2
        y: centerPoint.y - height/2
        width: parent.width * 1.05
        height: parent.height * 1.05
        fillMode: Image.PreserveAspectFit
        transformOrigin: Item.Center
        rotation: root.startup ? root.sweepAngle : root.rpmAngle
        Behavior on rotation {
            enabled: !root.startup
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
    }

    // ======================= ЛАМПЫ ТАХОМЕТРА =======================
    // Температура двигателя (перегрев)
    Image {
        source: "images/temp_dvs.png"
        width: parent.width * 0.08
        height: parent.width * 0.08
        x: parent.width * 0.65
        y: parent.height * 0.77
        fillMode: Image.PreserveAspectFit
        opacity: root.tempWarning ? 1.0 : 0.0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }
    // ABS
    Image {
        source: "images/ABS.png"
        width: parent.width * 0.07
        height: parent.width * 0.07
        x: parent.width * 0.55
        y: parent.height * 0.58
        fillMode: Image.PreserveAspectFit
        opacity: root.absWarning ? 1.0 : 0.0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }
    // Check Engine
    Image {
        source: "images/check.png"
        width: parent.width * 0.07
        height: parent.width * 0.07
        x: parent.width * 0.45
        y: parent.height * 0.58
        fillMode: Image.PreserveAspectFit
        opacity: root.checkEngineWarning ? 1.0 : 0.0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }
    // Давление масла (авария)
    Image {
        source: "images/oil_press.png"
        width: parent.width * 0.07
        height: parent.width * 0.07
        x: parent.width * 0.35
        y: parent.height * 0.58
        fillMode: Image.PreserveAspectFit
        opacity: root.oilPressureWarning ? 1.0 : 0.0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    // Анимация запуска. Флагом startup управляет Main.qml.
    SequentialAnimation {
        id: startupAnimation
        running: root.startup

        NumberAnimation {
            target: root
            property: "sweepAngle"
            from: root.rpmStartAngle
            to: root.rpmEndAngle
            duration: 800
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root
            property: "sweepAngle"
            from: root.rpmEndAngle
            to: root.rpmAngle
            duration: 400
            easing.type: Easing.InOutQuad
        }
    }
}
