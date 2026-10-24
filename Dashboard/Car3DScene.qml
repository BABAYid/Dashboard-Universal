pragma ComponentBehavior: Bound
import QtQuick
import QtQuick3D

// ============================================================================
//  3D-сцена с моделью машины: View3D, камера, свет, стартовая анимация.
//
//  ЭТО КАРКАС. Модель (cruiser300.glb) — временная: дизайнер готовит
//  настоящую машину (двери, капот, колёса и т.д. — позже будут анимации).
//  Как вставить реальную модель: см. README (tools/bake_glb.py + balsam),
//  затем заменить Dashboard/assets/cruiser и CarModel.qml.
//
//  Модель предобработана на этапе разработки: tools/bake_glb.py запекает
//  мир в вершины, balsam собирает готовую сцену (CarModel.qml + .mesh +
//  WebP-атлас). В рантайме — обычный QML-компонент модуля, без импортёров.
//  Почему не RuntimeLoader: в этой сборке Qt рантайм-импорт glTF
//  «успешен», но даёт испорченную геометрию. Почему не Loader:
//  загруженный через Loader 3D-узел не получает сцену и не рисуется.
//  Почему clipNear:0.5: по умолчанию 10 и модель ближе — не рисуется.
//
//  Раскладка progress (0…1, 4 секунды):
//     0.000–0.125  темнота, машина за кадром
//     0.375–0.750  машина выезжает из глубины и приближается
//     0.750–1.000  стоит по центру, ленивое покачивание
//     после 4 с    разворот на 180° (корма к зрителю), остаётся фоном
// ============================================================================
Item {
    id: scene

    // прогресс стартовой анимации, приходит из Car3DView
    property real progress: 1.0
    property bool idleMotion: true

    // Дорога появляется только когда панель полностью прогрузилась
    property bool roadVisible: true
    // Скорость автомобиля (км/ч): дорога стоит на 0 и ускоряется с набором
    property real roadSpeed: 0

    // Свет по CAN: фары/габариты, поворотники. У модели нет отдельных узлов
    // фар, поэтому лампы — светящиеся шарики на местах огней.
    property bool headlightsOn: false
    property bool leftTurn: false
    property bool rightTurn: false
    // Мигание поворотников: CAN присылает состояние (бит постоянный пока
    // включён), а мигаем сами — тем же ритмом, что панель (1.5 Гц).
    property bool turnPhase: true

    Timer {
        interval: 333
        repeat: true
        running: scene.leftTurn || scene.rightTurn
        onRunningChanged: if (!running) scene.turnPhase = true
        onTriggered: scene.turnPhase = !scene.turnPhase
    }

    signal modelReady()
    signal modelFailed()

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
            position: Qt.vector3d(0, 6.0, 11.0)
            eulerRotation: Qt.vector3d(-28, 0, 0)
            fieldOfView: 40
            clipNear: 0.5
            clipFar: 1000
        }

        // Заливка, чтобы кузов читался: разгорается за первые 0.5 с.
        DirectionalLight {
            eulerRotation: Qt.vector3d(-35, -20, 0)
            brightness: 1.5 * Math.min(1.0, scene.progress / 0.125)
            castsShadow: false
        }

        // ===== ДОРОГА: две полосы разметки, уходящие в даль =====
        // Штрихи сдвигаются на период шага и перескакивают обратно: рисунок
        // повторяется, поэтому скачок не виден — получается эффект движения.
        // Видна только после загрузки панели (roadVisible): на стартовом
        // экране с машиной дороги нет.
        Node {
            visible: scene.roadVisible

            Repeater3D {
                model: 44                       // 2 полосы × 22 штриха
                delegate: Model {
                    id: dash
                    required property int index
                    readonly property int dashIndex: Math.floor(dash.index / 2)
                    readonly property real zStart: -36 + dashIndex * 2.0
                    source: "#Cube"
                    x: (dash.index % 2) === 0 ? -3.0 : 3.0
                    y: 0.008
                    z: dash.zStart
                    scale: Qt.vector3d(0.0009, 0.0002, 0.009)
                    materials: PrincipledMaterial {
                        baseColor: "#9A9A9A"
                        lighting: PrincipledMaterial.NoLighting
                    }
                    NumberAnimation on z {
                        from: dash.zStart
                        to: dash.zStart + 2.0
                        // Период ~900 мс на 30 км/ч, минимум 150 мс;
                        // на 0 км/ч дорога стоит.
                        duration: Math.max(150,
                                           Math.min(8000,
                                                   900 * 30 / Math.max(scene.roadSpeed, 1)))
                        loops: Animation.Infinite
                        running: scene.roadSpeed > 0.5
                    }
                }
            }
        }

        Node {
            id: carPivot
            position: Qt.vector3d(0, 0, scene.carDepth)
            scale: Qt.vector3d(scene.carScale, scene.carScale, scene.carScale)
            eulerRotation: Qt.vector3d(0, scene.carYaw, 0)

            // Временная cruiser300 в сантиметрах: CarModel.qml сам ставит
            // масштаб 0.001, здесь ещё 0.9 — подгонка под кадр.
            Node {
                scale: Qt.vector3d(1.25, 1.25, 1.25)

                // Готовая сцена от balsam, объявленная как компонент модуля.
                // Важно: через Loader 3D-узел не привязывается к сцене и не
                // рисуется — поэтому это обычное объявление типа, как Model.
                CarModel {
                    id: carModel
                }

                // ===== ФАРЫ И ЗАДНИЕ ФОНАРИ (по CAN) =====
                // Светящиеся шарики на местах фар: белые впереди, красные
                // сзади. Работает с любой моделью — узлы фар искать не нужно.
                // Локальные координаты в метрах: нос -2.5…0 по X, корма +2.5.
                Node {
                    visible: scene.headlightsOn
                    Model {
                        source: "#Sphere"
                        position: Qt.vector3d(-2.72, 0.62, -0.72)
                        scale: Qt.vector3d(0.0025, 0.0025, 0.0025)
                        materials: PrincipledMaterial {
                            baseColor: "#FFF6DC"
                            lighting: PrincipledMaterial.NoLighting
                        }
                    }
                    Model {
                        source: "#Sphere"
                        position: Qt.vector3d(-2.72, 0.62, 0.72)
                        scale: Qt.vector3d(0.0025, 0.0025, 0.0025)
                        materials: PrincipledMaterial {
                            baseColor: "#FFF6DC"
                            lighting: PrincipledMaterial.NoLighting
                        }
                    }
                    Model {
                        source: "#Sphere"
                        position: Qt.vector3d(2.72, 0.68, -0.72)
                        scale: Qt.vector3d(0.003, 0.003, 0.003)
                        materials: PrincipledMaterial {
                            baseColor: "#FF2A1A"
                            lighting: PrincipledMaterial.NoLighting
                        }
                    }
                    Model {
                        source: "#Sphere"
                        position: Qt.vector3d(2.72, 0.68, 0.72)
                        scale: Qt.vector3d(0.003, 0.003, 0.003)
                        materials: PrincipledMaterial {
                            baseColor: "#FF2A1A"
                            lighting: PrincipledMaterial.NoLighting
                        }
                    }
                    // Пятно света от фар на дороге перед машиной
                    Model {
                        source: "#Cube"
                        position: Qt.vector3d(-4.6, 0.003, 0)
                        scale: Qt.vector3d(0.044, 0.0004, 0.03)
                        materials: PrincipledMaterial {
                            baseColor: Qt.rgba(1.0, 0.94, 0.78, 0.20)
                            lighting: PrincipledMaterial.NoLighting
                            alphaMode: PrincipledMaterial.Blend
                            cullMode: PrincipledMaterial.NoCulling
                        }
                    }
                }

                // ===== ПОВОРОТНИКИ (мигают вместе с лампой на панели) =====
                Node {
                    visible: scene.leftTurn && scene.turnPhase
                    Model {
                        source: "#Sphere"
                        position: Qt.vector3d(-2.72, 0.55, -1.30)
                        scale: Qt.vector3d(0.003, 0.003, 0.003)
                        materials: PrincipledMaterial {
                            baseColor: "#FF9A1A"
                            lighting: PrincipledMaterial.NoLighting
                        }
                    }
                    Model {
                        source: "#Sphere"
                        position: Qt.vector3d(2.72, 0.60, -1.30)
                        scale: Qt.vector3d(0.003, 0.003, 0.003)
                        materials: PrincipledMaterial {
                            baseColor: "#FF9A1A"
                            lighting: PrincipledMaterial.NoLighting
                        }
                    }
                }
                Node {
                    visible: scene.rightTurn && scene.turnPhase
                    Model {
                        source: "#Sphere"
                        position: Qt.vector3d(-2.72, 0.55, 1.30)
                        scale: Qt.vector3d(0.003, 0.003, 0.003)
                        materials: PrincipledMaterial {
                            baseColor: "#FF9A1A"
                            lighting: PrincipledMaterial.NoLighting
                        }
                    }
                    Model {
                        source: "#Sphere"
                        position: Qt.vector3d(2.72, 0.60, 1.30)
                        scale: Qt.vector3d(0.003, 0.003, 0.003)
                        materials: PrincipledMaterial {
                            baseColor: "#FF9A1A"
                            lighting: PrincipledMaterial.NoLighting
                        }
                    }
                }
            }
        }
    }
}
