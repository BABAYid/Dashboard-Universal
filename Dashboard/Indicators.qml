import QtQuick 2.15

Item {
    id: root
    width: 1920
    height: 720

    property bool leftTurn: false
    property bool rightTurn: false
    property bool highBeam: false
    property bool lowBeam: false
    property bool positionLights: false
    property bool fogLights: false
    property bool brakeLights: false
    property bool reverseLights: false
    property bool checkEngine: false
    property real outsideTemp: 0
    property bool abs: false
    property bool handBrake: false
    property bool seatBelt: false
    property bool gearLock: false
    property string gearMode: "P"
    property real odometer: 0
    property real tripA: 0
    property real tripB: 0
    property string displayMode: "odo"

    // Самопроверка ламп при включении зажигания: все лампы горят ~2,5 с
    property bool selfTest: false

    // Мигание поворотников — 1,5 Гц, как у штатного реле
    property bool blinkOn: false

    Timer {
        interval: 333
        repeat: true
        running: root.leftTurn || root.rightTurn
        onRunningChanged: if (!running) root.blinkOn = false
        onTriggered: root.blinkOn = !root.blinkOn
    }

    // Левый поворотник (на циферблате спидометра, прибор сдвинут по макету)
    Image {
        source: "images/left_turn.png"
        x: 550
        y: 80
        width: 50
        height: 50
        fillMode: Image.PreserveAspectFit
        opacity: (root.selfTest || (root.leftTurn && root.blinkOn)) ? 1.0 : 0.0
        visible: opacity > 0
    }

    // Правый поворотник
    Image {
        source: "images/right_turn.png"
        x: 1320
        y: 80
        width: 50
        height: 50
        fillMode: Image.PreserveAspectFit
        opacity: (root.selfTest || (root.rightTurn && root.blinkOn)) ? 1.0 : 0.0
        visible: opacity > 0
    }





    // Габариты
    Image {
        source: "images/gabarit.png"
        x: 1050
        y: 50
        width: 40
        height: 40
        fillMode: Image.PreserveAspectFit
        opacity: (root.selfTest || root.positionLights) ? 1.0 : 0.0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    // Противотуманки
    Image {
        source: "images/tuman.png"
        x: 1000
        y: 50
        width: 40
        height: 40
        fillMode: Image.PreserveAspectFit
        opacity: (root.selfTest || root.fogLights) ? 1.0 : 0.0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    // Дальний свет
    Image {
        source: "images/hi_beam.png"
        x: 950
        y: 50
        width: 40
        height: 40
        fillMode: Image.PreserveAspectFit
        opacity: (root.selfTest || root.highBeam) ? 1.0 : 0.0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }















    // === НАРУЖНАЯ ТЕМПЕРАТУРА ===
    Item {
        x: 1750
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
            source: "images/snow.png"
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
        // Одетометр по центру центральной области (714..1206 → центр 960)
        x: (root.width - width) / 2
        y: 600
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
            // Долгое нажатие — сброс текущего trip (одометр не сбрасывается)
            onPressAndHold: {
                if (root.displayMode === "tripA") CanBackend.resetTripA()
                else if (root.displayMode === "tripB") CanBackend.resetTripB()
            }
        }
    }
}
