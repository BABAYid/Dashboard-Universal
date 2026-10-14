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
        rotation: rpmStartAngle + (rpm / maxRpm) * (rpmEndAngle - rpmStartAngle)
        Behavior on rotation {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
    }

    // Индикаторы
    Image {
        source: "images/temp_dvs.png"
        width: parent.width * 0.08
        height: parent.width * 0.08
        x: parent.width * 0.65
        y: parent.height * 0.77
        opacity: 1.0
        fillMode: Image.PreserveAspectFit
    }
    Image {
        source: "images/ABS.png"
        width: parent.width * 0.07
        height: parent.width * 0.07
        x: parent.width * 0.55
        y: parent.height * 0.58
        opacity: 1.0
        fillMode: Image.PreserveAspectFit
    }
    Image {
        source: "images/check.png"
        width: parent.width * 0.07
        height: parent.width * 0.07
        x: parent.width * 0.45
        y: parent.height * 0.58
        opacity: 1.0
        fillMode: Image.PreserveAspectFit
    }
    Image {
        source: "images/oil_press.png"
        width: parent.width * 0.07
        height: parent.width * 0.07
        x: parent.width * 0.35
        y: parent.height * 0.58
        fillMode: Image.PreserveAspectFit
    }

    // Анимация запуска
    SequentialAnimation {
        id: startupAnimation
        running: root.startup
        onFinished: root.startup = false

        NumberAnimation {
            target: needleRpm
            property: "rotation"
            from: rpmStartAngle
            to: rpmEndAngle
            duration: 800
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: needleRpm
            property: "rotation"
            from: rpmEndAngle
            to: rpmStartAngle + (rpm / maxRpm) * (rpmEndAngle - rpmStartAngle)
            duration: 400
            easing.type: Easing.InOutQuad
        }
    }

    onRpmChanged: {
        if (!startup) {
            needleRpm.rotation = rpmStartAngle + (rpm / maxRpm) * (rpmEndAngle - rpmStartAngle)
        }
    }
}
