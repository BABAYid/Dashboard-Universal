pragma ComponentBehavior: Bound
import QtQuick 2.15
import Dashboard

// ============================================================================
//  Дождь и снег на фоне приборки.
//
//  Состояние погоды приходит из WeatherProvider (Open-Meteo, см.
//  WeatherProvider.h): clear/cloudy/fog/rain/snow/unknown. Слой виден
//  только при дожде и снеге, лежит ПОД приборами — эффект на фоне и не
//  мешает читать показания. Без сети слой просто невидим.
//
//  Капли/снежинки — обычный Repeater с анимациями: 90 тонких линий для
//  дождя, 70 кружков для снега. Случайные параметры читаются один раз
//  при создании (у Math.random нет зависимостей, повторной подстановки нет).
// ============================================================================
Item {
    id: fx

    readonly property bool rain: WeatherProvider.state === "rain"
    readonly property bool snow: WeatherProvider.state === "snow"
    readonly property bool active: rain || snow

    visible: active
    opacity: 0.55


    Repeater {
        model: fx.rain ? 90 : 70
        delegate: Rectangle {
            id: drop
            readonly property real startX: Math.random() * fx.width
            readonly property real startY: -(Math.random() * fx.height + 40)
            readonly property real fallMs: fx.rain
                ? 550 + Math.random() * 450
                : 5200 + Math.random() * 3800
            readonly property real driftX: Math.random() * 70 - 35

            width: fx.rain ? 2 : 5
            height: fx.rain ? 16 : 5
            radius: fx.rain ? 1 : 2.5
            color: fx.rain ? "#7FA8DD" : "#F2F6FF"

            NumberAnimation on y {
                from: drop.startY
                to: fx.height + 40
                duration: drop.fallMs
                loops: Animation.Infinite
                running: fx.active
            }
            NumberAnimation on x {
                from: drop.startX
                to: drop.startX + drop.driftX
                duration: fx.rain ? drop.fallMs : drop.fallMs * 1.5
                loops: Animation.Infinite
                running: fx.active
                easing.type: Easing.InOutSine
            }
        }
    }
}
