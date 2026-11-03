import QtQuick 2.15
import QtMultimedia
import Dashboard

// ============================================================================
//  CameraWarning.qml — предупреждение о камере (Smart Driver).
//
//  Встаёт в верхнюю полосу между приборами (x центральной области, над
//  центральной панелью) и живёт там, пока камера впереди ближе 500 м.
//  Звук — короткий бип на появление новой камеры (сигнал cameraApproaching
//  от C++ приходит только в этот момент, а не на каждое обновление GPS).
//
//  Цвет: жёлтый — едем в пределах ограничения, красный — превышаем.
//  Текст: «КАМЕРА: 60 км/ч» и «ДО КАМЕРЫ: 350 м».
// ============================================================================
Item {
    id: rootWarning

    // Показывать вообще (настройка в настройках приборки).
    property bool enabled: true
    // В навигации карта занимает весь экран — предупреждение всё равно нужно,
    // но рисуем его чуть плотнее, чтобы не мешало разметке карты.
    property bool compact: false

    readonly property bool active: enabled && SpeedCamManager.cameraActive
    readonly property color accent: SpeedCamManager.cameraSpeeding ? "#FF3B30" : "#FFC02A"
    readonly property color accentSoft: SpeedCamManager.cameraSpeeding ? "#66201012" : "#66241C05"

    visible: opacity > 0
    opacity: active ? 1.0 : 0.0
    Behavior on opacity { NumberAnimation { duration: 180 } }

    // Бип при появлении камеры. SoundEffect не блокирует интерфейс, а при
    // отсутствии звуковой карты просто молчит (ошибку в лог, не в UI).
    SoundEffect {
        id: beep
        source: "assets/sounds/camera_beep.wav"
        volume: 0.8
    }

    Connections {
        target: SpeedCamManager
        function onCameraApproaching(typeName, speedLimit, distance) {
            if (rootWarning.enabled)
                beep.play()
        }
    }

    // Пульс на превышении: спокойное предупреждение не мигает, а «вы превышаете»
    // должно бросаться в глаза.
    property real pulse: 1.0
    SequentialAnimation {
        running: rootWarning.active && SpeedCamManager.cameraSpeeding
        loops: Animation.Infinite
        NumberAnimation { target: rootWarning; property: "pulse"; to: 1.0; duration: 420; easing.type: Easing.InOutQuad }
        NumberAnimation { target: rootWarning; property: "pulse"; to: 0.55; duration: 420; easing.type: Easing.InOutQuad }
    }
    onActiveChanged: if (!active) rootWarning.pulse = 1.0

    // Мягкое свечение в цвет предупреждения: два полупрозрачных «ореола»
    // вместо шейдерной тени — дешевле на слабом GPU и не ломает рендер.
    Rectangle {
        anchors.fill: parent
        anchors.margins: -height * 0.06
        radius: height * 0.22
        color: "transparent"
        border.width: height * 0.10
        border.color: rootWarning.accentSoft
        opacity: rootWarning.active ? rootWarning.pulse : 0
        Behavior on border.color { ColorAnimation { duration: 200 } }
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: height * 0.18
        color: "#E60A0E14"
        border.width: 2
        border.color: rootWarning.accent
        opacity: rootWarning.active ? rootWarning.pulse : 0
        Behavior on border.color { ColorAnimation { duration: 200 } }

        // ---------------- значок камеры (нарисован примитивами) ----------------
        Item {
            id: icon
            width: parent.height * 0.52
            height: width
            anchors.left: parent.left
            anchors.leftMargin: width * 0.28
            anchors.verticalCenter: parent.verticalCenter
            opacity: rootWarning.pulse

            // корпус
            Rectangle {
                id: body
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: parent.height * 0.06
                width: parent.width * 0.92
                height: parent.height * 0.58
                radius: height * 0.24
                color: rootWarning.accent
            }

            // «козырёк» сверху (объектив с направленным взглядом)
            Rectangle {
                anchors.horizontalCenter: body.horizontalCenter
                anchors.bottom: body.top
                width: body.width * 0.46
                height: body.height * 0.22
                radius: height * 0.3
                color: rootWarning.accent
            }

            // объектив
            Rectangle {
                anchors.centerIn: body
                width: body.height * 0.66
                height: width
                radius: width / 2
                color: "#10151C"
                border.width: Math.max(1, width * 0.16)
                border.color: "#F2F5F8"
            }

            // вспышка-«глазок» справа сверху
            Rectangle {
                anchors.right: body.right
                anchors.rightMargin: body.width * 0.08
                anchors.top: body.top
                anchors.topMargin: body.height * 0.12
                width: body.height * 0.2
                height: width
                radius: width / 2
                color: "#10151C"
            }
        }

        // ---------------- тексты ----------------
        Column {
            id: texts
            anchors.left: icon.right
            anchors.leftMargin: icon.width * 0.3
            anchors.right: card.right
            anchors.rightMargin: card.height * 0.18
            anchors.verticalCenter: parent.verticalCenter
            spacing: card.height * 0.03

            Text {
                text: SpeedCamManager.cameraHeader
                color: rootWarning.accent
                font.pixelSize: card.height * 0.30
                font.bold: true
                elide: Text.ElideRight
                width: texts.width
            }

            Text {
                text: SpeedCamManager.cameraRangeText
                color: "#E8EDF3"
                font.pixelSize: card.height * 0.22
                elide: Text.ElideRight
                width: texts.width
            }

            Text {
                // Тип комплекса — мелким шрифтом: «КАМЕРА КОНТРОЛЯ СКОРОСТИ»,
                // «КАМЕРА НА КРАСНЫЙ СВЕТ» и т.д.
                text: SpeedCamManager.cameraTypeName
                color: "#9AA4B2"
                font.pixelSize: card.height * 0.155
                elide: Text.ElideRight
                width: texts.width
                visible: !rootWarning.compact
            }
        }
    }
}
