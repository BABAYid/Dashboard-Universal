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

    // ---- для приёма маршрута от Android (route_handoff) ----
    // Точка старта (позиция машины) — Main.qml выставляет перед requestTo().
    property real startLat: 55.7558
    property real startLon: 37.6173
    // Шаги для route_state: [{at, distance, sign, text, maneuver}]
    readonly property var steps: maneuvers
    // Текущий (ближайший) манёвр: {maneuver, distanceM, street}
    property var nextStep: null

    // ---- текущее положение на маршруте ----
    property real traveledM: 0
    property string hintText: ""
    property real hintDistanceM: 0
    property string hintSign: ""
    property string hintManeuver: ""

    signal routeReady(var coordinates)
    // Маршрут не построился (точки вне офлайн-карты, GraphHopper ответил не
    // 200): Main.qml превращает это в route_state с "error":"no_route".
    signal routeFailed(string reason)

    // Знак GraphHopper (int строкой) → maneuver из контракта §6.2
    // (straight / slight_left / left / sharp_left / slight_right / right /
    //  sharp_right / uturn / roundabout / arrive / none).
    function maneuverOfSign(sign) {
        switch (String(sign)) {
        case "0":  return "straight"       // CONTINUE
        case "2":  return "right"          // RIGHT
        case "3":  return "sharp_right"    // SHARP_RIGHT
        case "7":  return "slight_right"   // KEEP_RIGHT
        case "-2": return "left"           // LEFT
        case "-3": return "sharp_left"     // SHARP_LEFT
        case "-7": return "slight_left"    // KEEP_LEFT
        case "4":  return "roundabout"
        case "5":  return "arrive"         // REACHED_DESTINATION
        case "-4": return "roundabout"
        default:   return "straight"
        }
    }

    // Принять маршрут от Android (route_handoff): точка назначения,
    // источник — текущая позиция машины (startLat/startLon).
    function requestTo(toLat, toLon) {
        root.buildRoute(root.startLat, root.startLon, toLat, toLon)
    }

    // Сбросить маршрут (route_clear от Android).
    function clear() {
        root.ready = false
        root.loading = false
        root.errorText = ""
        root.routeDistanceM = 0
        root.routeTimeS = 0
        root.points = []
        root.maneuvers = []
        root.traveledM = 0
        root.hintText = ""
        root.hintDistanceM = 0
        root.hintSign = ""
        root.hintManeuver = ""
        root.nextStep = null
    }

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
                root.routeFailed("no_route")
                return
            }
            try {
                const d = JSON.parse(xhr.responseText)
                const p = d.paths[0]
                root.routeDistanceM = p.distance
                // GraphHopper отдаёт time в миллисекундах — храним секунды
                root.routeTimeS = p.time / 1000
                root.points = p.points.coordinates   // [lon, lat]

                // накопительные расстояния манёвров
                const ins = p.instructions || []
                const ms = []
                let acc = 0
                for (let i = 0; i < ins.length; i++) {
                    const sign = String(ins[i].sign || "")
                    ms.push({ at: acc, text: ins[i].text || "",
                              sign: sign,
                              distance: ins[i].distance,
                              maneuver: root.maneuverOfSign(sign) })
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
                root.routeFailed("no_route")
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
            // Участок уже пройден (или идёт) — этот манёвр позади.
            if (m.at <= t + 1e-6)
                continue
            root.hintText = m.text
            root.hintSign = m.sign
            root.hintManeuver = m.maneuver
            root.hintDistanceM = m.at - t
            root.nextStep = { maneuver: m.maneuver,
                              distanceM: m.at - t,
                              street: m.text }
            return
        }
        root.hintText = "Прибытие"
        root.hintDistanceM = Math.max(0, root.routeDistanceM - t)
        root.hintSign = "5"
        root.hintManeuver = "arrive"
        root.nextStep = { maneuver: "arrive", distanceM: root.hintDistanceM,
                          street: "Прибытие" }
    }
}
