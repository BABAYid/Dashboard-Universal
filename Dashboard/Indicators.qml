import QtQuick 2.15

Item {
    id: root
    width: 1920
    height: 720

    property bool leftTurn: false
    property bool rightTurn: false
    property bool highBeam: false
    property bool checkEngine: false
    property real outsideTemp: 0
    property bool abs: false
    property string gearMode: "P"
    property real odometer: 0
    property real tripA: 0
    property real tripB: 0
    property string displayMode: "odo"

    // Левый поворотник
    Image {
        source: "file:///home/oleg/Документы/новая приборка/Dashboard/images/left_turn.png"
        x: 650
        y: 80
        width: 50
        height: 50
        opacity: 1.0
        fillMode: Image.PreserveAspectFit
    }

    // Правый поворотник
    Image {
        source: "file:///home/oleg/Документы/новая приборка/Dashboard/images/right_turn.png"
        x: 1220
        y: 80
        width: 50
        height: 50
        opacity: 1.0
        fillMode: Image.PreserveAspectFit
    }





    // Габариты
    Image {
        source: "file:///home/oleg/Документы/новая приборка/Dashboard/images/gabarit.png"
        x: 1050
        y: 50
        width: 40
        height: 40
        opacity: 1.0
        fillMode: Image.PreserveAspectFit
    }

    // Противотуманки
    Image {
        source: "file:///home/oleg/Документы/новая приборка/Dashboard/images/tuman.png"
        x: 1000
        y: 50
        width: 40
        height: 40
        opacity: 1.0
        fillMode: Image.PreserveAspectFit
    }

    // Дальний свет
    Image {
        source: "file:///home/oleg/Документы/новая приборка/Dashboard/images/hi_beam.png"
        x: 950
        y: 50
        width: 40
        height: 40
        opacity: 1.0
        fillMode: Image.PreserveAspectFit
    }















    // === НАРУЖНАЯ ТЕМПЕРАТУРА ===
    Item {
        x: 1650
        y: 50
        width: 100
        height: 120

        Text {
            id: outsideTempText
            text: root.outsideTemp.toFixed(1) + "°C"
            color: "white"
            font.pixelSize: 24
            font.bold: true
            font.family: "Kdam Thmor Pro"
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
        }

        Image {
            source: "file:///home/oleg/Документы/новая приборка/Dashboard/images/snow.png"
            width: 40
            height: 40
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: outsideTempText.bottom
            anchors.topMargin: 5
            visible: root.outsideTemp <= 0
            fillMode: Image.PreserveAspectFit
        }
    }


    // === ОДОМЕТР/TRIP ===
    Text {
        id: displayText
        text: {
            if (root.displayMode === "odo") return "ODO: " + root.odometer.toFixed(1) + " km"
            else if (root.displayMode === "tripA") return "TRIP A: " + root.tripA.toFixed(1) + " km"
            else if (root.displayMode === "tripB") return "TRIP B: " + root.tripB.toFixed(1) + " km"
            else return ""
        }
        x: 870
        y: 680
        color: "white"
        font.pixelSize: 20
        font.family: "Kdam Thmor Pro"
        font.bold: true
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (root.displayMode === "odo") root.displayMode = "tripA"
                else if (root.displayMode === "tripA") root.displayMode = "tripB"
                else if (root.displayMode === "tripB") root.displayMode = "odo"
            }
        }
    }
}
