import QtQuick 2.15
import QtWebView 6.0
import QtQuick.Controls 2.15

Item {
    id: root
    // width и height не задаём — они будут из Main.qml
    visible: false

    property bool active: false
    property string mapUrl: "https://www.openstreetmap.org/export/embed.html?bbox=37.5%2C55.7%2C37.8%2C55.8&layer=mapnik"

    WebView {
        id: webView
        anchors.fill: parent
        url: root.mapUrl
    }

    // Кнопка закрытия уже не нужна, т.к. добавили в Main.qml
    // Можно оставить или убрать — по желанию
}
