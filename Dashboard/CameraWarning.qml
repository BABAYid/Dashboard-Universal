pragma ComponentBehavior: Bound
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

    // Доля оставшегося пути (1 — только что появилось, 0 — у самой точки).
    // По ней гаснут стрелки: чем ближе, тем меньше «галочек».
    readonly property real leftShare: SpeedCamManager.cameraWarnDistance > 0
                                      ? Math.max(0, Math.min(1, SpeedCamManager.cameraDistance
                                                               / SpeedCamManager.cameraWarnDistance))
                                      : 0
    // Сдвиги по просьбе заказчика: знак левее, расстояние правее, галочки
    // остаются по центру. Значение — в логических пикселях панели (1920).
    readonly property int signShift: 78
    readonly property int distanceShift: 78
    // Сколько галочек ▶▶▶▶▶▶ всего; сколько из них горит — см. litChevrons.
    readonly property int chevronCount: 6
    // Сколько галочек осталось гореть: чем ближе точка, тем меньше.
    readonly property int litChevrons: Math.max(1, Math.ceil(leftShare * chevronCount))
    // Цифры чуть ниже центра: тогда галочки смотрят им ровно в середину.
    readonly property int distanceDrop: 15

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

    Item {
        id: row
        width: parent.width
        height: parent.height
        anchors.centerIn: parent

        readonly property real chevronWidth: height * 0.16
        readonly property real chevronGap: height * 0.03
        readonly property real arrowWidth: chevronWidth * rootWarning.chevronCount
                                            + chevronGap * (rootWarning.chevronCount - 1)
        readonly property real gap: height * 0.16

        // ------------------------- ЗНАК ОГРАНИЧЕНИЯ -------------------------
        // Как настоящий дорожный: белый круг, красная обводка, чёрное число.
        // У трёхзначных (100/110/130) шрифт мельче — как на реальных знаках.
        Item {
            id: sign
            width: row.height
            height: row.height
            anchors.right: arrows.left
            anchors.rightMargin: row.gap + rootWarning.signShift
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

        // ------------------------- СТРЕЛКИ ▶▶ -------------------------
        // Две галочки от знака к цифрам. По мере приближения гаснут по одной:
        // пока путь длинный — горят обе, на второй половине остаётся правая
        // (она и показывает на оставшееся расстояние).
        Item {
            id: arrows
            width: row.arrowWidth
            height: row.height * 0.36
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter

            // Две галочки ▶▶: левая гаснет, когда пройдена половина пути,
            // правая горит до самой точки и показывает на оставшееся
            // расстояние.
            Repeater {
                model: rootWarning.chevronCount
                delegate: Shape {
                    id: chevron
                    required property int index
                    // Без сэмплов края Shape выходят «лесенкой» — на маленькой
                    // галочке это заметно. Слой с 4 сэмплами сглаживает её.
                    layer.enabled: true
                    layer.samples: 4
                    x: index * (row.chevronWidth + row.chevronGap)
                    width: row.chevronWidth
                    height: row.height * 0.36
                    visible: opacity > 0
                    // Гаснут с левого края: чем ближе точка, тем меньше
                    // галочек остаётся, а последняя всегда смотрит на цифры.
                    opacity: index >= (rootWarning.chevronCount - rootWarning.litChevrons) ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 260 } }

                    ShapePath {
                        fillColor: rootWarning.accent
                        strokeWidth: 0
                        startX: 0
                        startY: 0
                        PathLine { x: chevron.width; y: chevron.height * 0.5 }
                        PathLine { x: 0; y: chevron.height }
                        PathLine { x: chevron.width * 0.34; y: chevron.height * 0.5 }
                        PathLine { x: 0; y: 0 }
                    }
                }
            }
        }

        // ------------------------- СКОЛЬКО ОСТАЛОСЬ -------------------------
        Row {
            id: distanceRow
            anchors.left: arrows.right
            anchors.leftMargin: row.gap + rootWarning.distanceShift
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: rootWarning.distanceDrop
            spacing: row.height * 0.03

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
