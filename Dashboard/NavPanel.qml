pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import Dashboard

// ==========================================================================
//  НАВИГАЦИОННЫЙ РЕЖИМ ПРИБОРКИ
// ==========================================================================
//
// Приборка сама маршрутов не строит и карту не рисует: и то, и другое делает
// Android (docs/integration.md). Сюда приходят два потока:
//
//   1. подсказки — знак манёвра, расстояние, улица, лимит, остаток;
//   2. кадры карты — JPEG-снимок экрана навигатора раз в секунду.
//
// Поэтому режим работает в двух видах:
//
//   карта есть (Android присылает кадры)  — карта на весь экран, поверх неё
//     компактная плашка манёвра. Приборы уезжают в углы (Main.qml) и не
//     мешают карте;
//   карты нет (нет Android, он не умеет снимать экран, или кадры устарели) —
//     в центре большая карточка манёвра с кольцом расстояния: тот же
//     «приборы расступились», только без картинки.
//
// Ничего не блокируется ожиданием: нет данных — показываем то, что есть,
// и честно говорим «нет связи», а не рисуем вчерашнюю карту.
Item {
    id: root

    property bool active: false          // приборка в навигационном режиме

    readonly property bool haveNav: NetworkServer.clientConnected
                                    && NetworkServer.navActive
                                    && !NetworkServer.navStale

    // Доля пути до манёвра для кольца: 500 м — полный круг, 0 м — пусто.
    readonly property real approach: {
        if (!root.haveNav || NetworkServer.navDistanceM < 0)
            return 0
        return Math.max(0, Math.min(1, 1.0 - NetworkServer.navDistanceM / 500.0))
    }

    // Цвет кольца: чем ближе манёвр, тем горячее.
    readonly property color ringColor: {
        const d = NetworkServer.navDistanceM
        if (d < 0) return "#3A3A3A"
        if (d < 60) return "#FF3B30"
        if (d < 150) return "#FF9500"
        return "#37C2FF"
    }

    function maneuverGlyph(code) {
        switch (code) {
        case "left":        return "◀"
        case "slight_left": return "◀"
        case "sharp_left":  return "◀"
        case "right":       return "▶"
        case "slight_right":return "▶"
        case "sharp_right": return "▶"
        case "uturn":       return "↺"
        case "roundabout":  return "◍"
        case "arrive":      return "⚑"
        case "none":        return ""
        default:            return "▲"   // straight
        }
    }

    function distanceText(meters) {
        if (meters < 0) return ""
        if (meters < 1000) return meters + " м"
        return (meters / 1000).toFixed(1) + " км"
    }

    function etaText(seconds) {
        if (seconds < 0) return ""
        const m = Math.round(seconds / 60)
        if (m < 60) return m + " мин"
        return Math.floor(m / 60) + " ч " + (m % 60) + " мин"
    }

    // ====================== КАРТА ОТ ANDROID ======================
    // Источник — провайдер картинки в NetworkServer: кадр лежит в памяти, а
    // номер в URL заставляет QML перерисовать его при каждом новом кадре.
    Image {
        anchors.fill: parent
        visible: root.active && NetworkServer.mapVisible
        source: NetworkServer.mapVisible
                ? "image://mapframe/" + NetworkServer.mapFrameSeq
                : ""
        fillMode: Image.PreserveAspectCrop
        // Кадр 1920×720 уже совпадает с экраном, кэш не нужен: следующий
        // кадр придёт через секунду.
        cache: false
        asynchronous: true
    }

    // ====================== ПЛАШКА МАНЁВРА ПОВЕРХ КАРТЫ ======================
    // Когда карта есть, подсказка должна занимать минимум места, но читаться.
    Rectangle {
        id: mapHint
        visible: root.active && NetworkServer.mapVisible && root.haveNav
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 14
        width: hintRow.implicitWidth + 48
        height: 92
        radius: 16
        color: "#CC0B0B0E"
        border.color: root.ringColor
        border.width: 2

        Row {
            id: hintRow
            anchors.centerIn: parent
            spacing: 22

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.maneuverGlyph(NetworkServer.navManeuver)
                color: root.ringColor
                font.pixelSize: 54
                font.bold: true
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                    text: root.distanceText(NetworkServer.navDistanceM)
                    color: "white"
                    font.pixelSize: 34
                    font.bold: true
                }
                Text {
                    text: NetworkServer.navStreet
                    color: "#B9C2CC"
                    font.pixelSize: 18
                }
            }

            // Ограничение скорости — круг, как на шкале спидометра
            Item {
                width: 62; height: 62
                anchors.verticalCenter: parent.verticalCenter
                visible: NetworkServer.navSpeedLimitKmh > 0

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "#FFFFFF"
                    border.color: "#E00B0B"
                    border.width: 5
                }
                Text {
                    anchors.centerIn: parent
                    text: NetworkServer.navSpeedLimitKmh
                    color: "#111111"
                    font.pixelSize: 26
                    font.bold: true
                }
            }
        }
    }

    // ====================== КАРТОЧКА БЕЗ КАРТЫ ======================
    // Центральная полоса (714…1206). Приборы уехали в углы, здесь — знак,
    // кольцо расстояния и остаток пути.
    Item {
        id: card
        visible: root.active && !NetworkServer.mapVisible && root.haveNav
        anchors.centerIn: parent
        width: 520
        height: 420

        // Кольцо: полный круг — 500 м до манёвра, пусто — доехали.
        Shape {
            id: ring
            anchors.fill: parent
            visible: NetworkServer.navDistanceM >= 0

            ShapePath {
                strokeColor: "#242A31"
                strokeWidth: 14
                fillColor: "transparent"
                capStyle: ShapePath.FlatCap
                PathAngleArc {
                    centerX: ring.width / 2; centerY: ring.height / 2
                    radiusX: ring.width / 2 - 10; radiusY: ring.height / 2 - 10
                    startAngle: -90
                    sweepAngle: 359.9
                }
            }
            ShapePath {
                strokeColor: root.ringColor
                strokeWidth: 14
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: ring.width / 2; centerY: ring.height / 2
                    radiusX: ring.width / 2 - 10; radiusY: ring.height / 2 - 10
                    startAngle: -90
                    sweepAngle: Math.max(0.1, 359.9 * root.approach)
                }
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 6

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.maneuverGlyph(NetworkServer.navManeuver)
                color: root.ringColor
                font.pixelSize: 150
                font.bold: true
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.distanceText(NetworkServer.navDistanceM)
                color: "white"
                font.pixelSize: 52
                font.bold: true
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: NetworkServer.navStreet
                color: "#B9C2CC"
                font.pixelSize: 22
            }
        }

        // Остаток и время — внизу карточки
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: -6
            spacing: 28
            visible: NetworkServer.navRemainingM >= 0 || NetworkServer.navEtaSec >= 0

            Text {
                visible: NetworkServer.navRemainingM >= 0
                text: "осталось " + root.distanceText(NetworkServer.navRemainingM)
                color: "#8A939C"
                font.pixelSize: 20
            }
            Text {
                visible: NetworkServer.navEtaSec >= 0
                text: root.etaText(NetworkServer.navEtaSec)
                color: "#8A939C"
                font.pixelSize: 20
            }
        }
    }

    // ====================== НЕТ ДАННЫХ ======================
    // Маршрут не построен или Android молчит. Честный текст вместо пустого
    // экрана и вместо устаревшей карты.
    Column {
        visible: root.active && !root.haveNav
        anchors.centerIn: parent
        spacing: 10

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: NetworkServer.clientConnected ? "МАРШРУТ НЕ ЗАДАН" : "НЕТ СВЯЗИ С МУЛЬТИМЕДИА"
            color: "#7A838C"
            font.pixelSize: 34
            font.bold: true
            font.letterSpacing: 3
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: NetworkServer.clientConnected
                  ? "постройте маршрут на экране мультимедиа"
                  : "путь: мультимедиа → Ethernet → приборка"
            color: "#4E565E"
            font.pixelSize: 20
        }
    }
}
