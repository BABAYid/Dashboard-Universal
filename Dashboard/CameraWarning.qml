import QtQuick 2.15
import QtQuick.Shapes 1.15
import QtMultimedia
import Dashboard

// ============================================================================
//  CameraWarning.qml — предупреждение о камере или опасности (Smart Driver).
//
//  Только то, что нужно водителю: знак ограничения — стрелка — сколько метров
//  осталось. Ни рамки, ни названия комплекса: лишнее на приборке мешает.
//
//    ( 60 )  ▶▶  350 м
//
//  Без превышения расстояние просто уменьшается по мере подъезда. Как только
//  едем быстрее ограничения — знак начинает пульсировать (и всё краснеет),
//  потому что «вы превышаете» должно бросаться в глаза.
// ============================================================================
Item {
    id: rootWarning

    // Показывать вообще (выключатель «Камеры» в настройках).
    property bool enabled: true
    // В навигации карта на весь экран — знак мельче, чтобы не закрывать её.
    property bool compact: false

    readonly property bool active: enabled && SpeedCamManager.cameraActive
    readonly property bool speeding: SpeedCamManager.cameraSpeeding
    readonly property color accent: speeding ? "#FF3B30" : "#FFC02A"
    readonly property color signRing: "#D8231A"
    readonly property color signFace: "#F4F6F9"
    readonly property color signInk: "#12161C"

    // Сколько осталось — всегда в метрах (предупреждение и так ближе 500 м).
    readonly property int metersLeft: Math.max(0, Math.round(SpeedCamManager.cameraDistance / 10) * 10)

    visible: opacity > 0
    opacity: active ? 1.0 : 0.0
    Behavior on opacity { NumberAnimation { duration: 180 } }

    // Бип при появлении точки: сигнал cameraApproaching приходит только в этот
    // момент, а не на каждый кадр GPS, поэтому писк не повторяется.
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

    // Пульс только на знаке: мигает сам знак, а стрелка и цифры остаются
    // на месте, чтобы расстояние можно было прочитать в любой момент.
    property real signPulse: 1.0
    SequentialAnimation {
        running: rootWarning.active && rootWarning.speeding
        loops: Animation.Infinite
        NumberAnimation { target: rootWarning; property: "signPulse"; to: 1.0; duration: 380; easing.type: Easing.InOutQuad }
        NumberAnimation { target: rootWarning; property: "signPulse"; to: 0.62; duration: 380; easing.type: Easing.InOutQuad }
    }
    onSpeedingChanged: if (!speeding) rootWarning.signPulse = 1.0

    Row {
        id: row
        // Рамки у предупреждения больше нет, поэтому содержимое центрируем
        // по своей ширине, а не растягиваем на всю отведённую область.
        width: childrenRect.width
        height: parent.height
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Math.min(height * 0.14, width * 0.05)

        // ------------------------- ЗНАК ОГРАНИЧЕНИЯ -------------------------
        // Как настоящий дорожный: белый круг, красная обводка, чёрное число.
        // У трёхзначных (100/110/130) шрифт мельче — как на реальных знаках.
        Item {
            id: sign
            width: parent.height
            height: parent.height
            anchors.verticalCenter: parent.verticalCenter
            opacity: rootWarning.signPulse
            scale: 0.86 + 0.14 * rootWarning.signPulse
            Behavior on scale { NumberAnimation { duration: 120 } }

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: rootWarning.signFace
                border.width: Math.max(2, width * 0.10)
                border.color: rootWarning.signRing
            }

            Text {
                id: signNumber
                anchors.centerIn: parent
                readonly property string label: SpeedCamManager.cameraSpeedLimit > 0
                                                ? String(SpeedCamManager.cameraSpeedLimit) : "!"
                text: label
                color: rootWarning.signInk
                font.pixelSize: parent.height * (label.length >= 3 ? 0.32 : 0.44)
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

        // ------------------------- СТРЕЛОЧКА -------------------------
        Shape {
            id: arrow
            width: parent.height * 0.30
            height: parent.height * 0.34
            anchors.verticalCenter: parent.verticalCenter

            ShapePath {
                fillColor: rootWarning.accent
                strokeWidth: 0
                startX: 0
                startY: arrow.height * 0.34
                PathLine { x: arrow.width * 0.52; y: arrow.height * 0.34 }
                PathLine { x: arrow.width * 0.52; y: arrow.height * 0.08 }
                PathLine { x: arrow.width;        y: arrow.height * 0.5 }
                PathLine { x: arrow.width * 0.52; y: arrow.height * 0.92 }
                PathLine { x: arrow.width * 0.52; y: arrow.height * 0.66 }
                PathLine { x: 0;                  y: arrow.height * 0.66 }
                PathLine { x: 0;                  y: arrow.height * 0.34 }
            }
        }

        // ------------------------- СКОЛЬКО ОСТАЛОСЬ -------------------------
        Row {
            id: distanceRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: parent.height * 0.03

            Text {
                text: rootWarning.metersLeft
                color: "#FFFFFF"
                font.pixelSize: row.height * 0.46
                font.bold: true
                anchors.baseline: unitText.baseline
            }

            Text {
                id: unitText
                text: "м"
                color: rootWarning.accent
                font.pixelSize: row.height * 0.26
                font.bold: true
            }
        }
    }
}
