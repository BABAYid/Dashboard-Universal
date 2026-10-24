pragma ComponentBehavior: Bound
import QtQuick
import QtQuick3D
import QtQuick3D.AssetUtils

// ============================================================================
//  3D-сцена с моделью машины: View3D, камера, света, загрузка .glb.
//
//  Отдельный файл, потому что грузит модель RuntimeLoader из модуля
//  QtQuick3D.AssetUtils, а этот QML-модуль в системе не обязателен. Если его
//  нет, Loader в Car3DView.qml просто не загрузит сцену — приборка работает
//  без 3D, а не падает целиком. Поставить модуль:
//
//      sudo apt install qml6-module-qtquick3d-assetutils
//
//  Ещё нужен рабочий OpenGL/GLES: QtQuick3D рисует только через RHI. В среде
//  без работающего драйвера (или с QT_QPA_PLATFORM=offscreen) View3D честно
//  сообщает «The View3D item is not going to display anything».
//
//  Раскладка progress (0…1, 4 секунды) — здесь же:
//     0.000–0.125  всё тёмное, фары погашены, машина за кадром
//     0.125–0.375  две фары разгораются и расширяют пятна
//     0.375–0.750  машина выезжает из глубины и приближается
//     0.750–1.000  стоит по центру, ленивое покачивание
// ============================================================================
Item {
    id: scene

    // прогресс стартовой анимации, приходит из Car3DView
    property real progress: 1.0
    property bool idleMotion: true

    signal modelReady()
    signal modelFailed()

    readonly property real spotPower: Math.min(1.0, Math.max(0.0, (progress - 0.125) / 0.25))
    readonly property real spotCone: 8 + 14 * spotPower
    readonly property real carTravel: Math.min(1.0, Math.max(0.0, (progress - 0.375) / 0.375))
    readonly property real carDepth: -7.0 * (1.0 - carTravel)
    readonly property real carScale: 0.78 + 0.22 * carTravel

    View3D {
        anchors.fill: parent
        // Рендер только в зону компонента (492×404), не в полный экран
        renderMode: View3D.Offscreen
        camera: camera

        environment: SceneEnvironment {
            backgroundMode: SceneEnvironment.Color
            clearColor: "black"
            antialiasingMode: SceneEnvironment.NoAA
        }

        PerspectiveCamera {
            id: camera
            position: Qt.vector3d(0, 1.6, 9.5)
            eulerRotation: Qt.vector3d(-6, 0, 0)
            fieldOfView: 38
        }

        // Слабая заливка, чтобы кузов не был чёрным силуэтом
        DirectionalLight {
            eulerRotation: Qt.vector3d(-35, -20, 0)
            brightness: 0.18 * Math.min(1.0, scene.progress / 0.125)
            castsShadow: false
        }

        // Две «фары»: пятна света перед машиной
        SpotLight {
            position: Qt.vector3d(-1.6, 2.2, 5.2)
            eulerRotation: Qt.vector3d(-12, 8, 0)
            coneAngle: scene.spotCone
            innerConeAngle: scene.spotCone * 0.45
            brightness: 55 * scene.spotPower
            color: "#FFF3D6"
            castsShadow: false
        }

        SpotLight {
            position: Qt.vector3d(1.6, 2.2, 5.2)
            eulerRotation: Qt.vector3d(-12, -8, 0)
            coneAngle: scene.spotCone
            innerConeAngle: scene.spotCone * 0.45
            brightness: 55 * scene.spotPower
            color: "#FFF3D6"
            castsShadow: false
        }

        Node {
            position: Qt.vector3d(0, 0, scene.carDepth)
            scale: Qt.vector3d(scene.carScale, scene.carScale, scene.carScale)

            // модель длиной ~7 «единиц» — приводим к ~4.2, чтобы влезала в кадр
            Node {
                scale: Qt.vector3d(0.6, 0.6, 0.6)

                SequentialAnimation on eulerRotation.y {
                    running: scene.progress >= 0.99 && scene.idleMotion
                    loops: Animation.Infinite
                    NumberAnimation { from: -6; to: 6; duration: 7000; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 6; to: -6; duration: 7000; easing.type: Easing.InOutSine }
                }

                RuntimeLoader {
                    source: "assets/car.glb"
                    onStatusChanged: {
                        if (status === RuntimeLoader.Success)
                            scene.modelReady()
                        else if (status === RuntimeLoader.Error)
                            scene.modelFailed()
                    }
                }
            }
        }
    }
}
