pragma ComponentBehavior: Bound
import QtQuick
import QtWebView

// ==========================================================================
//  ОФЛАЙН-КАРТА (MapLibre в WebView)
// ==========================================================================
//
//  Карта рисуется MapLibre GL JS из векторных тайлов, которые отдаёт наш
//  локальный сервер (`tools/tile-server.py`, позже — QHttpServer).
//  Поэтому интернет не нужен: страница, стиль и тайлы лежат на устройстве.
//
//  Почему WebView, а не свой рендер векторных тайлов: MapLibre умеет
//  подписи, масштабирование, поворот и маршрут «из коробки»; писать
//  эквивалент на QML — недели. Цена — QtWebEngine в памяти.
//
//  Со стороны QML наружу два свойства (позиция и курс) и два вызова
//  (маршрут, зум). Всё остальное — внутри страницы.
Item {
    id: root

    // ---- входные данные ----
    property real latitude: 55.7558
    property real longitude: 37.6173
    property real course: 0          // градусы, 0 — на север
    property real mapZoom: 14
    property bool active: false      // карта нужна только в навигации

    // Адрес страницы карты: по умолчанию наш локальный сервер тайлов
    property string mapUrl: "http://127.0.0.1:8090/map.html"

    // Готовность страницы (после неё можно вызывать setPose)
    property bool ready: false

    // Обновляем карту всякий раз, когда меняется позиция или курс:
    // раньше setPose вызывался только один раз при загрузке страницы,
    // поэтому карта не поворачивалась и машина не двигалась.
    onLatitudeChanged: updatePose()
    onLongitudeChanged: updatePose()
    onCourseChanged: updatePose()
    onMapZoomChanged: updatePose()

    // ---- выбор точки на карте (избранное / «по карте») ----

    // Сдвинуть вид джойстиком; карта при этом отрывается от машины и
    // в центре появляется перекрестие.
    function panBy(dx, dy) {
        if (!root.ready)
            return
        view.runJavaScript("window.navPan && window.navPan(" + dx + "," + dy + ")")
    }
    // Вернуть вид к машине (следование по курсу, перекрестие скрыть).
    function attachToCar() {
        if (!root.ready)
            return
        view.runJavaScript("window.navAttach && window.navAttach()")
        root.updatePose()
    }
    // Плавный полёт к точке (после выбора пункта назначения) — карта
    // сама возвращается к машине через ~1.5 с.
    function flyTo(lon, lat, zoom) {
        if (!root.ready)
            return
        view.runJavaScript("window.navFlyTo && window.navFlyTo("
                           + lon + "," + lat + "," + zoom + ")")
    }

    // Координаты центра экрана (то, что под перекрестием): [lon, lat] или null.
    function centerCoords(cb) {
        if (!root.ready) {
            cb(null)
            return
        }
        view.runJavaScript("window.navCenter ? window.navCenter() : 'null'",
                           function(res) {
                               var v = null
                               try { v = JSON.parse(res) } catch (e) {}
                               cb(v)
                           })
    }

    // Показать/обновить позицию машины и курс
    function updatePose() {
        if (!root.ready)
            return
        view.runJavaScript(
            "window.setPose && window.setPose("
            + root.longitude + "," + root.latitude + ","
            + root.course + "," + root.mapZoom + ")")
    }

    // Последний построенный маршрут — чтобы дослать его, когда страница
    // доедет (маршрут строится раньше, чем WebView успевает загрузить map.html).
    property var pendingRoute: []

    // Показать маршрут: список пар [[lon,lat], ...]
    function setRoute(points) {
        root.pendingRoute = points
        if (!root.ready)
            return
        view.runJavaScript("window.setRoute && window.setRoute(" + JSON.stringify(points) + ")")
    }

    WebView {
        id: view
        anchors.fill: parent
        visible: root.active
        url: root.active ? root.mapUrl : "about:blank"

        onLoadingChanged: function(request) {
            // Готовность только для страницы карты: загрузка about:blank
            // (когда карта не нужна) не должна включать ready — иначе
            // setPose/setRoute уходят в пустую страницу и молча теряются.
            // request.url приходит как QUrl — сравниваем строкой
            if ((request.url + "") === root.mapUrl) {
                if (request.status === WebView.LoadSucceededStatus) {
                    root.ready = true
                    root.updatePose()
                    if (root.pendingRoute && root.pendingRoute.length)
                        root.setRoute(root.pendingRoute)
                } else {
                    root.ready = false
                }
            } else {
                root.ready = false
            }
        }
    }

    // Тело машины в центре рисует сама страница (CSS-маркер); здесь только
    // подстраховка: если карта не загрузилась, видно, что режим включён.
    Rectangle {
        visible: root.active && !root.ready
        anchors.fill: parent
        color: "transparent"
        Text {
            anchors.centerIn: parent
            text: "КАРТА ЗАГРУЖАЕТСЯ"
            color: "#40556A"
            font.pixelSize: 22
            font.letterSpacing: 3
        }
    }
}
