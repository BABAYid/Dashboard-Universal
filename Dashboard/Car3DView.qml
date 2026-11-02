pragma ComponentBehavior: Bound
import QtQuick

// ============================================================================
//  3D-машина в центральной зоне (492×404) + стартовая заставка.
//
//  Сам 3D-мир живёт в Car3DScene.qml и загружается через Loader: сцена грузит
//  готовую модель (assets/balsam/Car.qml + .mesh, собранные balsam) и требует
//  только модуль QtQuick3D. Если QtQuick3D в системе нет — Loader остаётся
//  пустым, приборка работает без 3D, а в логе будет одна ошибка вместо падения
//  всего приложения.
//
//  Main.qml двигает только progress (0…1 за 4 с), всё остальное — в сцене.
// ============================================================================
Item {
    id: root

    property real progress: 1.0
    property bool idleMotion: true
    property bool roadVisible: true
    property real roadSpeed: 0
    property bool headlightsOn: false
    property bool leftTurn: false
    property bool rightTurn: false
    property bool turnBlink: false
    property bool viewSide: false
    property int suspensionLevel: 0
    property bool doorsOpen: false
    property bool doorFL: false
    property bool doorFR: false
    property bool doorRL: false
    property bool doorRR: false
    property bool capotOpen: false
    property bool trunkOpen: false

    // Необязательная зависимость: отсутствие модуля не ломает приборку
    readonly property bool sceneLoaded: sceneLoader.status === Loader.Ready
    signal modelReady()
    signal modelFailed()

    Loader {
        id: sceneLoader
        anchors.fill: parent
        source: "Car3DScene.qml"

        onStatusChanged: console.log("3D: Loader статус", status)
        onLoaded: {
            console.log("3D: сцена загружена")
            // Явное приведение: у Loader.item тип QObject, без него
            // компилятор QML не знает свойств и сигналов Car3DScene.
            const scene = item as Car3DScene
            scene.progress = Qt.binding(function() { return root.progress })
            scene.idleMotion = Qt.binding(function() { return root.idleMotion })
            scene.roadVisible = Qt.binding(function() { return root.roadVisible })
            scene.roadSpeed = Qt.binding(function() { return root.roadSpeed })
            scene.headlightsOn = Qt.binding(function() { return root.headlightsOn })
            scene.leftTurn = Qt.binding(function() { return root.leftTurn })
            scene.rightTurn = Qt.binding(function() { return root.rightTurn })
            scene.turnBlink = Qt.binding(function() { return root.turnBlink })
            scene.viewSide = Qt.binding(function() { return root.viewSide })
            scene.suspensionLevel = Qt.binding(function() { return root.suspensionLevel })
            scene.doorsOpen = Qt.binding(function() { return root.doorsOpen })
            scene.doorFL = Qt.binding(function() { return root.doorFL })
            scene.doorFR = Qt.binding(function() { return root.doorFR })
            scene.doorRL = Qt.binding(function() { return root.doorRL })
            scene.doorRR = Qt.binding(function() { return root.doorRR })
            scene.capotOpen = Qt.binding(function() { return root.capotOpen })
            scene.trunkOpen = Qt.binding(function() { return root.trunkOpen })
            scene.modelReady.connect(root.modelReady)
            scene.modelFailed.connect(root.modelFailed)
        }
    }
}
