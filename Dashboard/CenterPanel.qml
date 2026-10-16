import QtQuick 2.15

// ============================================================================
//  Центральная зона между приборами (492 x 404).
//
//  Режимы переключаются нажатием по центру, внизу — точки-индикаторы.
//  Смысл: не пихать всё сразу. Каждый режим показывает только то, что нужно
//  сейчас. Навигация сюда не входит — она отдельный режим на весь экран.
//
//    0 — Стандарт:    цифровая скорость, передача, часы
//    1 — Компьютер:   средний расход, запас хода, средняя скорость, время
//    2 — Диагностика: состояние блока сбора (прошивка, время работы, сбои)
//
//  Данные берём из CanBackend напрямую — он синглтон этого же QML-модуля.
// ============================================================================
Item {
    id: root

    property int mode: 0
    readonly property int modeCount: 3
    property string clockString: "--:--"
    property bool nightMode: false

    readonly property color valueColor: nightMode ? "#FF8800" : "white"
    readonly property color labelColor: nightMode ? "#C46A00" : "#9A9A9A"

    // Пустая строка вместо нуля: ноль в маршрутном компьютере означает
    // «данных ещё нет», а не «ноль литров на сто километров»
    function fmtValue(v, digits) {
        return v > 0 ? v.toFixed(digits) : "—"
    }

    function fmtDuration(sec) {
        var h = Math.floor(sec / 3600)
        var m = Math.floor((sec % 3600) / 60)
        if (h > 0)
            return h + " ч " + m + " мин"
        if (m > 0)
            return m + " мин"
        return sec + " с"
    }

    // Строка «подпись — значение» для режимов «Компьютер» и «Диагностика»
    component InfoRow: Row {
        property string label
        property string value
        property color valueColour: root.valueColor

        spacing: 16

        Text {
            text: parent.label
            width: 230
            horizontalAlignment: Text.AlignRight
            color: root.labelColor
            font.pixelSize: 20
        }

        Text {
            text: parent.value
            color: parent.valueColour
            font.pixelSize: 22
            font.bold: true
            font.family: "Kdam Thmor Pro"
        }
    }

    // ======================= РЕЖИМ 0: СТАНДАРТ =======================
    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -14
        spacing: 2
        visible: root.mode === 0

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Math.round(CanBackend.speed)
            color: root.valueColor
            font.pixelSize: 104
            font.bold: true
            font.family: "Kdam Thmor Pro"
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "км/ч"
            color: root.labelColor
            font.pixelSize: 18
        }

        Item { width: 1; height: 14 }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: CanBackend.gearMode
            color: root.valueColor
            font.pixelSize: 46
            font.bold: true
            font.family: "Kdam Thmor Pro"
        }

        Item { width: 1; height: 10 }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.clockString
            color: root.valueColor
            font.pixelSize: 34
            font.bold: true
            font.family: "Kdam Thmor Pro"
        }
    }

    // ======================= РЕЖИМ 1: КОМПЬЮТЕР =======================
    Column {
        anchors.centerIn: parent
        spacing: 16
        visible: root.mode === 1

        InfoRow {
            label: "Средний расход"
            value: root.fmtValue(CanBackend.avgConsumption, 1) + (CanBackend.avgConsumption > 0 ? " л/100" : "")
        }

        InfoRow {
            label: "Запас хода"
            value: root.fmtValue(CanBackend.rangeKm, 0) + (CanBackend.rangeKm > 0 ? " км" : "")
        }

        InfoRow {
            label: "Средняя скорость"
            value: root.fmtValue(CanBackend.avgSpeed, 0) + (CanBackend.avgSpeed > 0 ? " км/ч" : "")
        }

        InfoRow {
            label: "Время в пути"
            value: root.fmtDuration(CanBackend.journeySeconds)
        }

        InfoRow {
            label: "Пробег за поездку"
            value: CanBackend.journeyKm.toFixed(1) + " км"
        }

        InfoRow {
            label: "Израсходовано"
            value: CanBackend.fuelUsed.toFixed(1) + " л"
        }
    }

    // ======================= РЕЖИМ 2: ДИАГНОСТИКА =======================
    Column {
        anchors.centerIn: parent
        spacing: 14
        visible: root.mode === 2

        InfoRow {
            label: "Блок сбора"
            value: CanBackend.deviceAlive ? ("прошивка " + CanBackend.deviceFirmware) : "нет данных"
            valueColour: CanBackend.deviceAlive ? root.valueColor : "#FF4444"
        }

        InfoRow {
            label: "Работает"
            value: root.fmtDuration(CanBackend.deviceUptimeSec)
        }

        InfoRow {
            label: "Перезапусков"
            value: String(CanBackend.deviceRestarts)
            valueColour: CanBackend.deviceRestarts > 0 ? "#FF8800" : root.valueColor
        }

        InfoRow {
            label: "Ошибок шины"
            value: String(CanBackend.deviceBusErrors)
            valueColour: CanBackend.deviceBusErrors > 0 ? "#FF4444" : root.valueColor
        }

        InfoRow {
            label: "Принято кадров"
            value: String(CanBackend.framesReceived)
        }

        InfoRow {
            label: "Интерфейс"
            value: CanBackend.sourceName
            valueColour: CanBackend.connected ? root.valueColor : "#FF4444"
        }

        InfoRow {
            label: "Свежесть данных"
            value: CanBackend.dataValid ? "ок" : "устарели"
            valueColour: CanBackend.dataValid ? root.valueColor : "#FF4444"
        }
    }

    // ======================= ТОЧКИ-ИНДИКАТОРЫ =======================
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 12
        spacing: 10

        Repeater {
            model: root.modeCount

            Rectangle {
                width: 10
                height: 10
                radius: 5
                color: index === root.mode ? root.valueColor : "#4A4A4A"
            }
        }
    }
}
