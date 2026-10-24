pragma ComponentBehavior: Bound
import QtQuick 2.15
import Dashboard

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
    property bool abs: false
    property bool handBrake: false
    property bool seatBelt: false
    property bool gearLock: false
    property string gearMode: "P"
    property real odometer: 0
    property real tripA: 0
    property real tripB: 0
    property string displayMode: "odo"
    property string timeString: "--:--"

    // Самопроверка ламп при включении зажигания: все лампы горят ~2,5 с
    property bool selfTest: false

    // Фаза мигания поворотников приходит снаружи (Main.qml, один таймер):
    // так стрелки на панели и лампы на 3D-модели мигают синхронно.
    property bool blinkOn: false

    // Левый поворотник (на циферблате спидометра, прибор сдвинут по макету)
    Image {
        source: "images/left_turn.png"
        x: 332
        y: 130
        width: 50
        height: 50
        fillMode: Image.PreserveAspectFit
        opacity: (root.selfTest || (root.leftTurn && root.blinkOn)) ? 1.0 : 0.0
        visible: opacity > 0
    }

    // Правый поворотник
    Image {
        source: "images/right_turn.png"
        x: 1538
        y: 130
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















    // === ВЕРХНЯЯ ЗОНА ЦЕНТРА: часы и лампы ===
    // Всё это держим в центральной полосе между приборами (x 714..1206),
    // а не на циферблатах: приборы — круги радиусом 357 с центрами 357 и 1563,
    // и любая точка ближе этого радиуса оказывается на шкале тахометра.
    // Лампы (дальний / туманки / габариты) стоят по центру полосы.

    // Часы — слева от ламп
    Text {
        id: clockText
        x: 730
        y: 24
        text: root.timeString
        color: "white"
        font.pixelSize: 34
        font.bold: true
        font.family: "Kdam Thmor Pro"
    }

    // Наружная температура здесь больше не показывается (убрана 16.10.2026):
    // дублировала температуру в нижней строке показаний. Само значение
    // (CanBackend.outsideTemp) осталось и работает — от него загорается
    // предупреждение «ГОЛОЛЁД» в Main.qml.


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
        y: 622
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
