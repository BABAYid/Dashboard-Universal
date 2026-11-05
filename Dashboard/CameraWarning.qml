import QtQuick 2.15
import QtQuick.Shapes 1.15
import QtMultimedia
import Dashboard

// ============================================================================
//  CameraWarning.qml — предупреждение о камере или опасности (Smart Driver).
//
//  Схема (по просьбе заказчика): знак — стрелочка — сколько осталось до точки.
//
//    ┌──────────────────────────────────────────────┐
//    │  ( 60 )   ▶▶   350 м                         │   ← знак ограничения,
//    │  📷 Статическая камера · Кордон              │     стрелка, дистанция
//    │  ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬░░░░░░░░░░░░░░░░       │   ← полоса «сколько
//    └──────────────────────────────────────────────┘     осталось»
//
//  Знак — как настоящий дорожный: белый круг, красная обводка, чёрное число
//  (ограничение из базы есть у каждой точки, даже у «лежачего полицейского»).
//  В углу знака маленький значок: камера (контроль) или треугольник
//  (опасность) — по cameraIsSpeedControl.
//
//  Цвет: спокойный янтарный, а при превышении всё краснеет и пульсирует.
//  Бип играет при появлении новой точки (сигнал cameraApproaching приходит
//  только в этот момент, а не на каждый кадр GPS).
// ============================================================================
Item {
    id: rootWarning

    // Показывать вообще (выключатель «Камеры» в настройках).
    property bool enabled: true
    // В навигации карта на весь экран — оставляем только знак, стрелку и
    // дистанцию, без типа и полосы.
    property bool compact: false
    // Полоса «сколько осталось до точки» (1 — только подъехали, 0 — у точки).
    property bool showProgress: true

    // Картинки от дизайнера для конкретных типов (ключ — код TYPE из базы).
    // Пока есть только «искусственная неровность» (102); для остальных типов
    // пиктограмма рисуется примитивами (камера или треугольник «!»).
    // Чтобы добавить новый значок: положить PNG с прозрачностью в
    // assets/images/speedcam/type_<код>.png и дописать строку в карту.
    readonly property var typeIcons: ({ "102": "images/speedcam/type_102.png" })
    readonly property string typeIcon: typeIcons[String(SpeedCamManager.cameraType)] || ""

    readonly property bool active: enabled && SpeedCamManager.cameraActive
    readonly property color accent: SpeedCamManager.cameraSpeeding ? "#FF3B30" : "#FFC02A"
    readonly property color accentSoft: SpeedCamManager.cameraSpeeding ? "#66201012" : "#66241C05"
    // Цвет кольца знака — как у настоящего знака ограничения.
    readonly property color signRing: "#D8231A"
    readonly property color signFace: "#F4F6F9"
    readonly property color signInk: "#12161C"

    // Сколько осталось: до 1000 м — метры (кратно 10), дальше — километры.
    readonly property int metersLeft: Math.max(0, Math.round(SpeedCamManager.cameraDistance / 10) * 10)
    readonly property string distanceValue: metersLeft >= 1000
                                            ? (metersLeft / 1000).toFixed(1)
                                            : String(metersLeft)
    readonly property string distanceUnit: metersLeft >= 1000 ? "км" : "м"
    // Доля оставшегося пути: в начале предупреждения 1, у точки 0.
    readonly property real leftShare: SpeedCamManager.cameraWarnDistance > 0
                                      ? Math.max(0, Math.min(1, SpeedCamManager.cameraDistance
                                                               / SpeedCamManager.cameraWarnDistance))
                                      : 0

    visible: opacity > 0
    opacity: active ? 1.0 : 0.0
    Behavior on opacity { NumberAnimation { duration: 180 } }

    // Бип при появлении точки. SoundEffect не блокирует интерфейс, а при
    // отсутствии звуковой карты просто молчит.
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

    // Пульс на превышении: спокойное предупреждение не мигает, а «вы
    // превышаете» должно бросаться в глаза.
    property real pulse: 1.0
    SequentialAnimation {
        running: rootWarning.active && SpeedCamManager.cameraSpeeding
        loops: Animation.Infinite
        NumberAnimation { target: rootWarning; property: "pulse"; to: 1.0; duration: 420; easing.type: Easing.InOutQuad }
        NumberAnimation { target: rootWarning; property: "pulse"; to: 0.55; duration: 420; easing.type: Easing.InOutQuad }
    }
    onActiveChanged: if (!active) rootWarning.pulse = 1.0

    // Мягкое свечение в цвет предупреждения: полупрозрачный «ореол» вместо
    // шейдерной тени — дешевле на слабом GPU и не ломает рендер видео.
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
        radius: height * 0.16
        color: "#E60A0E14"
        border.width: 2
        border.color: rootWarning.accent
        // Пульсирует не весь баннер (иначе половину времени его не прочесть),
        // а только ореол и толщина обводки: содержимое остаётся читаемым.
        opacity: rootWarning.active ? 1.0 : 0.0
        Behavior on border.color { ColorAnimation { duration: 200 } }

        // Пульсирующая обводка поверх карточки: при превышении красная рамка
        // «дышит», а текст, знак и стрелка остаются на месте.
        Rectangle {
            anchors.fill: parent
            radius: card.radius
            color: "transparent"
            border.width: Math.max(2, card.height * 0.03)
            border.color: card.border.color
            opacity: SpeedCamManager.cameraSpeeding ? rootWarning.pulse : 0.0
        }

        readonly property real pad: height * 0.12
        readonly property real signSize: height * (rootWarning.compact ? 0.74 : 0.60)

        // ------------------------- ЗНАК ОГРАНИЧЕНИЯ -------------------------
        Item {
            id: sign
            width: card.signSize
            height: width
            x: card.pad
            anchors.verticalCenter: parent.verticalCenter

            // Белый круг с красной обводкой — как настоящий знак «3.24».
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: rootWarning.signFace
                border.width: Math.max(2, width * 0.105)
                border.color: rootWarning.signRing
            }

            // Ограничение скорости из базы. У трёхзначных (100/110/130) шрифт
            // мельче — как на настоящих знаках, иначе число не влезает в круг.
            Text {
                id: signNumber
                anchors.centerIn: parent
                readonly property string label: SpeedCamManager.cameraSpeedLimit > 0
                                                ? String(SpeedCamManager.cameraSpeedLimit) : "!"
                text: label
                color: rootWarning.signInk
                font.pixelSize: parent.height * (label.length >= 3 ? 0.34 : 0.46)
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

        }

        // ------------------------- СТРЕЛОЧКА -------------------------
        Shape {
            id: arrow
            width: card.height * 0.26
            height: card.height * 0.30
            anchors.left: sign.right
            anchors.leftMargin: card.pad * 0.7
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
            anchors.left: arrow.right
            anchors.leftMargin: card.pad * 0.7
            anchors.verticalCenter: parent.verticalCenter
            spacing: card.height * 0.035

            Text {
                id: distanceValueText
                text: rootWarning.distanceValue
                color: "#FFFFFF"
                font.pixelSize: card.height * (rootWarning.compact ? 0.42 : 0.34)
                font.bold: true
                anchors.baseline: distanceUnitText.baseline
            }

            Text {
                id: distanceUnitText
                text: rootWarning.distanceUnit
                color: rootWarning.accent
                font.pixelSize: card.height * (rootWarning.compact ? 0.24 : 0.18)
                font.bold: true
            }
        }

        // ------------------------- ПИКТОГРАММА, ТИП И МОДЕЛЬ -------------------------
        // Камера и опасность различаются не мелкой точкой в углу знака, а
        // полноценным значком перед названием: на приборке это читается
        // боковым зрением, а микро-иконка в 17 px — нет.
        Item {
            id: typeBadge
            visible: !rootWarning.compact
            width: card.height * 0.24
            height: width
            anchors.left: distanceRow.left
            anchors.bottom: card.bottom
            anchors.bottomMargin: card.pad * (rootWarning.showProgress ? 1.45 : 0.55)

            // Готовая картинка от дизайнера, если для этого типа она есть.
            Image {
                anchors.fill: parent
                visible: rootWarning.typeIcon !== ""
                source: rootWarning.typeIcon
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }

            // Камера: корпус с объективом (контроль скорости).
            Item {
                anchors.fill: parent
                visible: rootWarning.typeIcon === "" && SpeedCamManager.cameraIsSpeedControl

                Rectangle {
                    anchors.fill: parent
                    radius: height * 0.22
                    color: rootWarning.accent
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.height * 0.58
                    height: width
                    radius: width / 2
                    color: "#12161C"
                    border.width: Math.max(1, width * 0.20)
                    border.color: "#F4F6F9"
                }
            }

            // Опасность: треугольник с восклицательным знаком.
            Item {
                anchors.fill: parent
                visible: rootWarning.typeIcon === "" && !SpeedCamManager.cameraIsSpeedControl

                Shape {
                    anchors.fill: parent
                    ShapePath {
                        fillColor: rootWarning.accent
                        strokeWidth: 0
                        startX: typeBadge.width * 0.5
                        startY: typeBadge.height * 0.02
                        PathLine { x: typeBadge.width * 0.98; y: typeBadge.height * 0.94 }
                        PathLine { x: typeBadge.width * 0.02; y: typeBadge.height * 0.94 }
                        PathLine { x: typeBadge.width * 0.5; y: typeBadge.height * 0.02 }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: parent.height * 0.16
                    text: "!"
                    color: "#12161C"
                    font.pixelSize: parent.height * 0.52
                    font.bold: true
                }
            }
        }

        Text {
            id: typeLine
            visible: !rootWarning.compact
            anchors.left: typeBadge.right
            anchors.leftMargin: card.height * 0.06
            anchors.right: card.right
            anchors.rightMargin: card.pad
            anchors.verticalCenter: typeBadge.verticalCenter
            text: SpeedCamManager.cameraModel.length > 0
                  ? SpeedCamManager.cameraTypeName + " · " + SpeedCamManager.cameraModel
                  : SpeedCamManager.cameraTypeName
            color: "#98A2AE"
            font.pixelSize: card.height * 0.135
            elide: Text.ElideRight
        }

        // ------------------------- ПОЛОСА «СКОЛЬКО ОСТАЛОСЬ» -------------------------
        // Заполнение = оставшаяся часть пути до точки: в начале предупреждения
        // полоса полная, у самой точки — пустая.
        Rectangle {
            id: progressTrack
            visible: rootWarning.showProgress && !rootWarning.compact
            anchors.left: distanceRow.left
            anchors.right: card.right
            anchors.rightMargin: card.pad
            anchors.bottom: card.bottom
            anchors.bottomMargin: card.pad * 0.55
            height: Math.max(3, card.height * 0.045)
            radius: height / 2
            color: "#2A3038"

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * rootWarning.leftShare
                radius: parent.radius
                color: rootWarning.accent
                Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }
            }
        }
    }
}
