pragma ComponentBehavior: Bound
import QtQuick

// ==========================================================================
//  МАРШРУТЫ ОТ GRAPHHOPPER (офлайн)
// ==========================================================================
//
//  Запрос уходит на локальный GraphHopper (http://127.0.0.1:8989/route),
//  ответ разбирается здесь же: геометрия — для карты, instructions — для
//  плашки подсказок. Интернет не нужен: сервер маршрутов свой.
//
//  Логика подсказок: GraphHopper даёт distance (длина участка до следующего
//  манёвра) и text (что делать). Переводим их в накопительные расстояния:
//  манёвр №k происходит на расстоянии sum(distance[0..k-1]) от старта.
//  По позиции машины считаем пройденный путь по геометрии и берём первый
//  манёвр, до которого осталось ехать — это и есть «через N м поверните».
Item {
    id: root

    property url server: "http://127.0.0.1:8989/route"
    property string profile: "car"

    // ---- состояние маршрута ----
    property bool ready: false
    property bool loading: false
    property string errorText: ""
    property real routeDistanceM: 0
    property real routeTimeS: 0
    property var points: []            // [[lon, lat], ...] для карты
    property var maneuvers: []         // [{at: метры от старта, text, sign}]

    // ---- текущее положение на маршруте ----
    property real traveledM: 0
    property string hintText: ""
    property real hintDistanceM: 0
    property string hintSign: ""

    signal routeReady(var coordinates)

    // Построить маршрут между двумя точками
    function buildRoute(fromLat, fromLon, toLat, toLon) {
        if (root.loading)
            return
        root.loading = true
        root.ready = false
        root.errorText = ""
        const url = root.server + "?point=" + fromLat + "," + fromLon
                  + "&point=" + toLat + "," + toLon
                  + "&profile=" + root.profile
                  + "&locale=ru&instructions=true&points_encoded=false"
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            root.loading = false
            if (xhr.status !== 200) {
                root.errorText = "маршрут недоступен (" + xhr.status + ")"
                console.log("Маршрут:", root.errorText)
                return
            }
            try {
                const d = JSON.parse(xhr.responseText)
                const p = d.paths[0]
                root.routeDistanceM = p.distance
                root.routeTimeS = p.time
                root.points = p.points.coordinates   // [lon, lat]

                // накопительные расстояния манёвров
                const ins = p.instructions || []
                const ms = []
                let acc = 0
                for (let i = 0; i < ins.length; i++) {
                    ms.push({ at: acc, text: ins[i].text || "",
                              sign: String(ins[i].sign || ""),
                              distance: ins[i].distance })
                    acc += ins[i].distance || 0
                }
                root.maneuvers = ms
                root.ready = true
                root.traveledM = 0
                root.updateHint()
                root.routeReady(root.points)
                console.log("Маршрут:", (p.distance/1000).toFixed(2), "км,",
                            Math.round(p.time/60000), "мин, манёвров", ms.length)
            } catch (e) {
                root.errorText = "не разобрал ответ: " + e
                console.log("Маршрут:", root.errorText)
            }
        }
        xhr.open("GET", url)
        xhr.send()
    }

    // Машина проехала расстояние t — обновить подсказку
    function setTraveled(t) {
        root.traveledM = Math.max(0, Math.min(root.routeDistanceM, t))
        root.updateHint()
    }

    function updateHint() {
        if (!root.ready || root.maneuvers.length === 0)
            return
        const t = root.traveledM
        for (let i = 0; i < root.maneuvers.length; i++) {
            const m = root.maneuvers[i]
            if (m.at + (m.distance || 0) > t) {
                root.hintText = m.text
                root.hintSign = m.sign
                root.hintDistanceM = Math.max(0, m.at - t)
                return
            }
        }
        root.hintText = "Прибытие"
        root.hintDistanceM = Math.max(0, root.routeDistanceM - t)
        root.hintSign = "4"
    }
}
