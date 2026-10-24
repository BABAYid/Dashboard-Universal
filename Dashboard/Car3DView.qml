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
            item.progress = Qt.binding(function() { return root.progress })
            item.idleMotion = Qt.binding(function() { return root.idleMotion })
            item.modelReady.connect(root.modelReady)
            item.modelFailed.connect(root.modelFailed)
        }
    }
}
