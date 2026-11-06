pragma ComponentBehavior: Bound
import QtQuick 2.15
import Dashboard

// ============================================================================
//  Центральная зона между приборами (492 x 404).
//
//  Режимы переключаются нажатием по центру, внизу — точки-индикаторы.
//  Смысл: не пихать всё сразу. Каждый режим показывает только то, что нужно
//  сейчас. Навигация сюда не входит — она отдельный режим на весь экран.
//
//    0 — Стандарт:    цифровая скорость, передача
//    1 — Компьютер:   средний расход, запас хода, средняя скорость, время
//    2 — Диагностика: состояние блока сбора (прошивка, время работы, сбои)
//    3 — Напряжение:  график напряжения АКБ за последние 5 минут
//    4 — Машина:      3D-модель (сама модель — отдельным слоем под панелью)
//    5 — Подвеска:    пневмоподвеска, стрелки вверх/вниз
//    6 — Медиа:       что играет в мультимедиа-центре (JSON по сети)
//    7 — Двигатель:   3D-модель V6 (assets/3.glb), анимация по оборотам
//
//  Климата здесь больше нет: климат переехал на экран мультимедиа (Android),
//  где для него есть тачскрин и место под управление заслонками. Кадр 0x510
//  приборка по-прежнему разбирает — значения отдаются дальше по сети.
//
//  Данные берём из CanBackend и MediaBackend напрямую — это синглтоны
//  этого же QML-модуля.
// ============================================================================
Item {
    id: root

    property int mode: 0

    // Обороты для 3D-модели двигателя — те же, что видит тахометр
    // (с коэффициентом из настроек). Иначе модель крутилась бы при
    // «0» на приборе, если множитель обнулён.
    property real engineRpm: 0
    readonly property int modeCount: 8

    // ---- 6-й вид: пневмоподвеска ----
    signal suspensionUp()
    signal suspensionDown()
    property int suspensionLevel: 0
    property int suspensionDirection: 0
    property bool suspBlinkOn: false
    property bool nightMode: false

    readonly property color valueColor: nightMode ? "#FF8800" : "white"
    readonly property color labelColor: nightMode ? "#C46A00" : "#9A9A9A"

    // Цвет зоны по напряжению: < 11.5 В — красный, 11.5…12.8 — жёлтый,
    // > 12.8 — зелёный. По этой функции красятся и подпись значения,
    // и отрезки графика — чтобы цвета нигде не разъезжались.
    function zoneColour(v) {
        if (!(v > 0))
            return "#8A8A8A"
        if (v < 11.5)
            return "#FF4444"
        if (v <= 12.8)
            return "#FFC64A"
        return "#33CC44"
    }

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

        // Часы здесь были и дублировали часы верхней зоны (Indicators.qml) —
        // убраны, время показывается только сверху, рядом с наружной
        // температурой.
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
            value: CanBackend.rangeKmValid
                   ? "~" + Math.round(CanBackend.rangeKm) + " км"
                   : "—"
            // Те же цвета, что у предупреждения в верхней зоне: меньше 50 км —
            // жёлтый, меньше 20 — красный. Прочерк — когда расчёта ещё нет.
            valueColour: !CanBackend.rangeKmValid ? root.valueColor
                         : CanBackend.rangeKm < 20 ? "#FF4444"
                         : CanBackend.rangeKm < 50 ? "#FFC64A"
                         : root.valueColor
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

    // ======================= РЕЖИМ 3: НАПРЯЖЕНИЕ =======================
    // График напряжения АКБ за последние 5 минут (300 замеров по секунде).
    // Canvas, а не ShaderEffect: перерисовываем только по приходу нового
    // замера (раз в секунду), а не каждый кадр, поэтому график не отнимает
    // кадры у приборов. Замер частоты кадров с графиком и без — в
    // PROJECT_STATE.md, раздел «Производительность графиков».
    Item {
        anchors.fill: parent
        visible: root.mode === 3

        Text {
            text: "Напряжение АКБ, 5 мин"
            anchors.horizontalCenter: parent.horizontalCenter
            y: 4
            color: root.labelColor
            font.pixelSize: 18
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 24
            text: CanBackend.voltage.toFixed(1) + " В"
            color: root.zoneColour(CanBackend.voltage)
            font.pixelSize: 28
            font.bold: true
            font.family: "Kdam Thmor Pro"
        }

        Canvas {
            id: voltageGraph
            x: 12
            y: 62
            width: parent.width - 24
            height: parent.height - 96

            // Перерисовка по данным, а не по кадрам: раз в секунду.
            Connections {
                target: CanBackend
                function onVoltageHistoryChanged() { voltageGraph.requestPaint() }
            }
            Component.onCompleted: requestPaint()

            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()

                const w = width
                const h = height
                const yMin = 10.0
                const yMax = 15.0
                const left = 46                       // место под подписи оси Y
                const plotW = w - left - 4
                const yFor = v => h - 18 - (v - yMin) / (yMax - yMin) * (h - 26)

                // Зоны: красная < 11.5, жёлтая 11.5…12.8, зелёная > 12.8
                ctx.fillStyle = "rgba(255, 68, 68, 0.10)"
                ctx.fillRect(left, yFor(11.5), plotW, yFor(yMin) - yFor(11.5))
                ctx.fillStyle = "rgba(255, 198, 74, 0.08)"
                ctx.fillRect(left, yFor(12.8), plotW, yFor(11.5) - yFor(12.8))
                ctx.fillStyle = "rgba(51, 204, 68, 0.07)"
                ctx.fillRect(left, yFor(15.0), plotW, yFor(12.8) - yFor(15.0))

                // Сетка и подписи оси Y
                ctx.font = "13px sans-serif"
                ctx.textAlign = "left"
                const marks = [15.0, 12.8, 11.5, 10.0]
                for (let i = 0; i < marks.length; ++i) {
                    const v = marks[i]
                    const y = yFor(v)
                    ctx.strokeStyle = "rgba(255,255,255,0.10)"
                    ctx.beginPath()
                    ctx.moveTo(left, y)
                    ctx.lineTo(left + plotW, y)
                    ctx.stroke()
                    ctx.fillStyle = "#9A9A9A"
                    ctx.fillText(v.toFixed(1), 2, y + 4)
                }

                // Подписи оси X
                ctx.fillStyle = "#9A9A9A"
                ctx.textAlign = "left"
                ctx.fillText("−5 мин", left + 2, h - 3)
                ctx.textAlign = "right"
                ctx.fillText("сейчас", left + plotW, h - 3)

                // Линия: цвет отрезка по его значению. Свежий замер — у правого
                // края, поэтому график «растёт» справа налево по мере накопления.
                const data = CanBackend.voltageHistory
                const n = data.length
                if (n < 2)
                    return
                const slots = 300
                const xFor = i => left + plotW * (i + (slots - n)) / (slots - 1)

                ctx.lineWidth = 2
                ctx.lineJoin = "round"
                for (let i = 1; i < n; ++i) {
                    const a = data[i - 1]
                    const b = data[i]
                    if (isNaN(a) || isNaN(b))
                        continue                   // нет данных — разрыв линии
                    ctx.strokeStyle = root.zoneColour(b)
                    ctx.beginPath()
                    ctx.moveTo(xFor(i - 1), yFor(a))
                    ctx.lineTo(xFor(i), yFor(b))
                    ctx.stroke()
                }

                // Точка на последнем замере
                const last = data[n - 1]
                if (!isNaN(last)) {
                    ctx.fillStyle = root.zoneColour(last)
                    ctx.beginPath()
                    ctx.arc(xFor(n - 1), yFor(last), 3, 0, Math.PI * 2)
                    ctx.fill()
                }
            }
        }
    }

    // ======================= РЕЖИМ 4: МАШИНА =======================
    // Пятый вид центральной зоны: никаких показаний и подписей — видна только
    // 3D-машина (Car3DView лежит прямо под этим слоем, прозрачная панель её
    // не закрывает). Сюда переключаемся обычным щелчком по центру: 0→1→2→3→4→0.
    Item {
        id: carPage
        anchors.fill: parent
        visible: root.mode === 4

        // Уровень топлива в момент начала заправки: показываем, сколько
        // залито с этого момента («Заправлено: X.X л»).
        property real fuelAtStart: 0

        Connections {
            target: CanBackend
            function onIsFuelingChanged() {
                if (CanBackend.isFueling)
                    carPage.fuelAtStart = CanBackend.fuelLevel
            }
        }

        readonly property real litresAdded:
            Math.max(0, (CanBackend.fuelLevel - carPage.fuelAtStart) / 100.0
                     * CanBackend.tankCapacity)

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 6
            visible: CanBackend.isFueling
            text: "Заправлено: " + carPage.litresAdded.toFixed(1) + " л"
            color: root.valueColor
            font.pixelSize: 26
            font.bold: true
            font.family: "Kdam Thmor Pro"
        }
    }

    // ======================= РЕЖИМ 5: ПОДВЕСКА =======================
    // Пневмоподвеска: машина показана боком, вверху надпись режима,
    // стрелки вверх/вниз — кнопки; при нажатии стрелка мигает.
    Item {
        anchors.fill: parent
        visible: root.mode === 5

        Text {
            text: root.suspensionLevel > 0 ? "Бездорожье"
                : root.suspensionLevel < 0 ? "Спорт" : "Стандарт"
            anchors.horizontalCenter: parent.horizontalCenter
            y: 4
            color: root.valueColor
            font.pixelSize: 30
            font.bold: true
            font.family: "Kdam Thmor Pro"
        }

        // Вверх — поднять кузов
        Rectangle {
            id: suspUpButton
            width: 84; height: 84; radius: 42
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: -110
            // Внизу панели: по центру (y 250) кнопки ложились на машину
            y: parent.height - height - 8
            color: "#1A1A1A"
            border.color: root.valueColor
            border.width: 2

            Text {
                anchors.centerIn: parent
                text: "▲"
                color: root.valueColor
                font.pixelSize: 44
                opacity: (root.suspensionDirection === 1 && !root.suspBlinkOn) ? 0.25 : 1.0
            }
            MouseArea { anchors.fill: parent; onClicked: root.suspensionUp() }
        }

        // Вниз — опустить кузов (стандарт → спорт)
        Rectangle {
            id: suspDownButton
            width: 84; height: 84; radius: 42
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: 110
            // Внизу панели (см. кнопку «вверх»)
            y: parent.height - height - 8
            color: "#1A1A1A"
            border.color: root.valueColor
            border.width: 2

            Text {
                anchors.centerIn: parent
                text: "▼"
                color: root.valueColor
                font.pixelSize: 44
                opacity: (root.suspensionDirection === -1 && !root.suspBlinkOn) ? 0.25 : 1.0
            }
            MouseArea { anchors.fill: parent; onClicked: root.suspensionDown() }
        }
    }

    // ======================= РЕЖИМ 7: ДВИГАТЕЛЬ =======================
    // 3D-модель V6 (assets/3.glb): анимация коленвала/поршней привязана к
    // оборотам — стоит мотор, стоит и модель; больше оборотов — быстрее.
    Item {
        anchors.fill: parent
        visible: root.mode === 7

        EngineView {
            anchors.fill: parent
            rpm: root.engineRpm
        }
    }

    // ======================= РЕЖИМ 6: МЕДИА =======================
    // Что играет в мультимедиа-центре (Android). Данные идут не по CAN, а
    // маленьким JSON по сети — поэтому здесь MediaBackend, а не CanBackend.
    Item {
        id: mediaPage
        anchors.fill: parent
        visible: root.mode === 6

        readonly property bool haveData: MediaBackend.available

        Text {
            id: mediaSourceLabel
            anchors.horizontalCenter: parent.horizontalCenter
            y: 6
            text: mediaPage.haveData ? MediaBackend.sourceLabel : "МЕДИА"
            color: root.labelColor
            font.pixelSize: 18
        }

        // Название станции (если это радио) — отдельной строкой.
        Text {
            id: mediaStationText
            anchors.horizontalCenter: parent.horizontalCenter
            y: 34
            text: mediaPage.haveData ? MediaBackend.station : ""
            color: root.valueColor
            font.pixelSize: 26
            font.bold: true
            visible: text.length > 0
        }

        // Трек — самое крупное, по центру, в две строки максимум.
        Text {
            id: mediaTitleText
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: mediaPage.haveData && MediaBackend.station.length > 0 ? 10 : -6
            width: parent.width - 40
            text: mediaPage.haveData ? MediaBackend.title : "нет данных"
            color: mediaPage.haveData ? root.valueColor : "#FF8800"
            font.pixelSize: mediaPage.haveData ? 30 : 20
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
        }

        Text {
            id: mediaArtistText
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: mediaTitleText.bottom
            anchors.topMargin: 8
            text: mediaPage.haveData ? MediaBackend.artist : ""
            color: root.labelColor
            font.pixelSize: 20
            visible: text.length > 0
        }

        // Полоса прогресса: позиция / длительность. Пауза — полоса серая.
        Rectangle {
            id: mediaProgressTrack
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - 62
            width: parent.width - 80
            height: 4
            radius: 2
            color: "#333333"
            visible: mediaPage.haveData && MediaBackend.durationSec > 0

            Rectangle {
                width: MediaBackend.durationSec > 0
                       ? mediaProgressTrack.width * Math.min(1.0, MediaBackend.positionSec / MediaBackend.durationSec)
                       : 0
                height: parent.height
                radius: parent.radius
                color: MediaBackend.playing ? root.valueColor : "#666666"
            }

            Text {
                anchors.right: parent.right
                anchors.bottom: parent.top
                anchors.bottomMargin: 4
                text: MediaBackend.formatTime(MediaBackend.positionSec) + " / "
                      + MediaBackend.formatTime(MediaBackend.durationSec)
                color: root.labelColor
                font.pixelSize: 14
            }
        }

        // Значок «играет/пауза» — треугольник или две полоски.
        Item {
            id: mediaPlayIcon
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - 44
            width: 22
            height: 22
            visible: mediaPage.haveData

            Text {
                anchors.centerIn: parent
                text: MediaBackend.playing ? "▶" : "❚❚"
                color: MediaBackend.playing ? "#33CC44" : root.labelColor
                font.pixelSize: 20
            }
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
                // index объявляем явно: иначе qmllint ругается на неявный
                // доступ, а Repeater подставляет это свойство сам
                required property int index

                width: 10
                height: 10
                radius: 5
                color: index === root.mode ? root.valueColor : "#4A4A4A"
            }
        }
    }
}
