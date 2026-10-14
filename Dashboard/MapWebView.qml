import QtQuick 2.15
import QtWebView 6.0

Item {
    id: root
    // width и height не задаём — они будут из Main.qml
    visible: false

    property bool active: false
    property string mapUrl: "https://www.openstreetmap.org/export/embed.html?bbox=37.5%2C55.7%2C37.8%2C55.8&layer=mapnik"

    // WebView создаётся только при входе в режим навигации: иначе QtWebEngine
    // поднимает отдельный процесс и грузит карту при каждом запуске приборки,
    // что для nanoPC-T6 (RK3588) ощутимо и требует сети.
    Loader {
        anchors.fill: parent
        active: root.active
        sourceComponent: webComponent
    }

    Component {
        id: webComponent

        WebView {
            id: webView
            anchors.fill: parent
            url: root.mapUrl
        }
    }
}
