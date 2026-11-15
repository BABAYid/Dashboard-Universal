import QtQuick

// ==========================================================================
//  ПЛАШКА МАНЁВРА ДЛЯ ОФЛАЙН-КАРТЫ
// ==========================================================================
//
//  В навигации на своей карте (offlineMap) подсказки берутся из
//  RouteService (GraphHopper): текст манёвра, расстояние до него, остаток
//  пути. Плашка висит снизу по центру — между уменьшенными приборами,
//  карту не закрывает.
//
//  Для Android-режима остаётся NavPanel: тот же вид, но данные по сети.
Item {
    id: root

    property real distanceM: 0        // до следующего манёвра, м
    property string sign: ""         // sign из GraphHopper (число строкой)
    property string hintText: ""     // «Поверните направо на …»
    property real remainM: 0         // осталось до цели, м
    property real remainS: 0         // до цели, с
    property bool visible: false

    readonly property color colorText: "#E8F1F5"
    readonly property color colorDim: "#6E8597"
    readonly property color colorAccent: "#BCEAF1"

    // Знак GraphHopper (int как строка) → стрелка.
    function signGlyph(sign) {
        switch (String(sign)) {
        case "2":  return "▶"   // right
        case "3":  return "▶"   // sharp right
        case "7":  return "▶"   // keep/slight right
        case "-2": return "◀"   // left
        case "-3": return "◀"   // sharp left
        case "-7": return "◀"   // keep/slight left
        case "4":  return "◍"   // roundabout
        case "-8": return "↺"   // uturn
        default:   return "▲"   // straight / continue
        }
    }

    function distanceText(m) {
        if (m >= 1000)
            return (m / 1000).toFixed(1).replace(".", ",") + " км"
        if (m >= 10)
            return Math.round(m / 10) * 10 + " м"
        return Math.round(m) + " м"
    }

    function timeText(s) {
        const min = Math.max(1, Math.round(s / 60))
        if (min > 60)
            return Math.floor(min / 60) + " ч " + (min % 60) + " мин"
        return min + " мин"
    }

    visible: root.visible
    width: 640
    height: 88

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: "#0B141CDD"
        border.color: "#24343F"
    }

    Text {
        id: glyph
        x: 18
        anchors.verticalCenter: parent.verticalCenter
        text: root.signGlyph(root.sign)
        color: root.colorAccent
        font.pixelSize: 46
        font.bold: true
    }

    Column {
        x: 86
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Text {
            text: root.hintDistanceM > 0
                  ? "ЧЕРЕЗ " + root.distanceText(root.distanceM).toUpperCase()
                  : ""
            color: root.colorText
            font.pixelSize: 26
            font.bold: true
            font.letterSpacing: 1
        }
        Text {
            text: root.hintText
            color: root.colorText
            font.pixelSize: 18
            width: 380
            elide: Text.ElideRight
        }
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        text: root.timeText(root.remainS) + " · "
              + root.distanceText(root.remainM)
        color: root.colorDim
        font.pixelSize: 15
        horizontalAlignment: Text.AlignRight
    }
}
