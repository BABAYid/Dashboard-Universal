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
    property real mapZoom: 13
    property bool active: false      // карта нужна только в навигации

    // Адрес страницы карты: по умолчанию наш локальный сервер тайлов
    property string mapUrl: "http://127.0.0.1:8090/map.html"

    // Готовность страницы (после неё можно вызывать setPose)
    property bool ready: false

    // Показать/обновить позицию машины и курс
    function updatePose() {
        if (!view.loadProgress === 1)
            return
        view.runJavaScript(
            "window.setPose && window.setPose("
            + root.longitude + "," + root.latitude + ","
            + root.course + "," + root.mapZoom + ")")
    }

    // Показать маршрут: список пар [[lon,lat], ...]
    function setRoute(points) {
        view.runJavaScript("window.setRoute && window.setRoute(" + JSON.stringify(points) + ")")
    }

    WebView {
        id: view
        anchors.fill: parent
        visible: root.active
        url: root.active ? root.mapUrl : "about:blank"

        onLoadingChanged: function(request) {
            if (request.status === WebView.LoadSucceededStatus) {
                root.ready = true
                root.updatePose()
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
