import QtQuick 2.15
import QtLocation 6.0
import QtPositioning 6.0

Item {
    id: root
    width: 1000
    height: 500
    visible: false

    property bool active: false

    // Используем WebView для простоты
    MapWebView {
        anchors.fill: parent
        visible: true
    }
}


