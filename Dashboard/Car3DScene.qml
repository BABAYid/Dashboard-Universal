pragma ComponentBehavior: Bound
import QtQuick
import QtQuick3D

// ============================================================================
//  3D-сцена с моделью машины: View3D, камера, света, загрузка сцены.
//
//  Модель (cruiser300.glb) предобработана на этапе разработки:
//  tools/bake_glb.py запекает мир в вершины, balsam собирает готовую
//  сцену (Dashboard/CarModel.qml + assets/cruiser/.mesh + WebP-атлас).
//  В рантайме — обычный QML-компонент в модуле, без импортёров.
//  Почему не RuntimeLoader: в этой сборке Qt рантайм-импорт glTF
//  «успешен», но даёт испорченную геометрию. Почему не Loader:
//  загруженный через Loader 3D-узел не получает сцену и не рисуется.
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
    readonly property real lampPower: spotPower
    readonly property real spotCone: 8 + 14 * spotPower
    readonly property real carTravel: Math.min(1.0, Math.max(0.0, (progress - 0.375) / 0.375))
    readonly property real carDepth: -7.0 * (1.0 - carTravel)
    readonly property real carScale: 0.78 + 0.22 * carTravel

    // Модель cruiser300 в сантиметрах, длина вдоль X: +90° ставит её вдоль Z
    // носом к камере; после заставки разворот на 180° — корма к зрителю.
    property real carYaw: 90
    SequentialAnimation on carYaw {
        running: scene.progress >= 0.999
        PauseAnimation { duration: 800 }
        NumberAnimation {
            from: 90; to: -90
            duration: 2200
            easing.type: Easing.InOutCubic
        }
    }

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
            // clipNear по умолчанию 10: машина ближе него — и не рисуется
            // вообще (нашли по «красному фону»: он рисовался, модели нет).
            clipNear: 0.5
            clipFar: 1000
        }

        // Слабая заливка, чтобы кузов не был чёрным силуэтом
        DirectionalLight {
            eulerRotation: Qt.vector3d(-35, -20, 0)
            brightness: 1.5 * Math.min(1.0, scene.progress / 0.125)
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

        // «Фары из темноты»: два объёмных луча к зрителю + сами лампы.
        // Луч — конус от машины на камеру, полупрозрачный и аддитивный
        // по цвету; лампы — светящиеся шарики на месте фар.
        Model {
            source: "#Cone"
            position: Qt.vector3d(-0.9, 0.85, 4.1)
            scale: Qt.vector3d(0.008, 0.038, 0.008)
            eulerRotation: Qt.vector3d(-90, 0, 8)
            visible: scene.lampPower > 0.01
            materials: PrincipledMaterial {
                baseColor: Qt.rgba(1.0, 0.95, 0.82, 0.5 * scene.lampPower * Math.max(0.0, (scene.carYaw + 90) / 180))
                lighting: PrincipledMaterial.NoLighting
                alphaMode: PrincipledMaterial.Blend
                cullMode: PrincipledMaterial.NoCulling
            }
        }
        Model {
            source: "#Cone"
            position: Qt.vector3d(0.9, 0.85, 4.1)
            scale: Qt.vector3d(0.008, 0.038, 0.008)
            eulerRotation: Qt.vector3d(-90, 0, -8)
            visible: scene.lampPower > 0.01
            materials: PrincipledMaterial {
                baseColor: Qt.rgba(1.0, 0.95, 0.82, 0.5 * scene.lampPower * Math.max(0.0, (scene.carYaw + 90) / 180))
                lighting: PrincipledMaterial.NoLighting
                alphaMode: PrincipledMaterial.Blend
                cullMode: PrincipledMaterial.NoCulling
            }
        }
        Model {
            source: "#Sphere"
            position: Qt.vector3d(-0.8, 0.62, 2.1)
            scale: Qt.vector3d(0.04, 0.04, 0.04)
            visible: scene.lampPower > 0.01
            materials: PrincipledMaterial {
                baseColor: Qt.rgba(1.0, 0.97, 0.88, Math.max(0.0, (scene.carYaw + 90) / 180))
                lighting: PrincipledMaterial.NoLighting
            }
        }
        Model {
            source: "#Sphere"
            position: Qt.vector3d(0.8, 0.62, 2.1)
            scale: Qt.vector3d(0.04, 0.04, 0.04)
            visible: scene.lampPower > 0.01
            materials: PrincipledMaterial {
                baseColor: Qt.rgba(1.0, 0.97, 0.88, Math.max(0.0, (scene.carYaw + 90) / 180))
                lighting: PrincipledMaterial.NoLighting
            }
        }

        Node {
            id: carPivot
            position: Qt.vector3d(0, 0, scene.carDepth)
            scale: Qt.vector3d(scene.carScale, scene.carScale, scene.carScale)
            eulerRotation: Qt.vector3d(0, scene.carYaw, 0)

            // Модель cruiser300 в сантиметрах: CarModel.qml сам ставит
            // масштаб 0.001, здесь ещё 0.75 — подгонка под кадр.
            Node {
                scale: Qt.vector3d(0.9, 0.9, 0.9)

                SequentialAnimation on eulerRotation.y {
                    running: scene.progress >= 0.99 && scene.idleMotion
                    loops: Animation.Infinite
                    NumberAnimation { from: -6; to: 6; duration: 7000; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 6; to: -6; duration: 7000; easing.type: Easing.InOutSine }
                }

                // Готовая сцена от balsam, объявленная как компонент модуля.
                // Важно: через Loader 3D-узел не привязывается к сцене и не
                // рисуется — поэтому это обычное объявление типа, как Model.
                CarModel {
                    id: carModel
                }
            }
        }
    }
}
