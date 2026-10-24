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
    // Фаза мигания приходит из Main (общий таймер) — стрелки на панели и
    // лампы на модели мигают синхронно.
    property bool turnBlink: false

    // 6-й вид: машина развёрнута боком, и пневмоподвеска двигает кузов по Y.
    property bool viewSide: false
    property int suspensionLevel: 0        // -1 спорт, 0 стандарт, 1 бездорожье
    readonly property real suspensionOffset: suspensionLevel > 0 ? 0.18
                                             : suspensionLevel < 0 ? -0.10 : 0.0

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
            // Дымка: дальний край дороги и лучи фар уходят в синеватый мрак —
            // эффект объёма без пост-обработки (на Mali так дешевле).
            fog: Fog {
                enabled: true
                color: "#0D151C"
                density: 0.55
                depthEnabled: true
                depthNear: 6
                depthFar: 40
            }
        }

        // Текстура мягкого свечения (радиальный градиент) — для «bloom»
        // вокруг фар и стоп-сигналов без HDR-постобработки.
        Texture {
            id: lightsGlowTexture
            source: "images/lights_glow.png"
            generateMipmaps: true
            mipFilter: Texture.Linear
        }

        PerspectiveCamera {
            id: camera
            // Обычный вид — сбоку-сверху; в 6-м режиме (подвеска) — сверху
            // с наклоном ~12° от вертикали: так виден подъём кузова
            // (дорожный просвет), но машина остаётся почти «сверху».
            position: scene.viewSide ? Qt.vector3d(0, 8.6, 2.0)
                                     : Qt.vector3d(0, 6.0, 11.0)
            eulerRotation: scene.viewSide ? Qt.vector3d(-78, 0, 0)
                                          : Qt.vector3d(-28, 0, 0)
            fieldOfView: 40
            clipNear: 0.5
            clipFar: 1000
            Behavior on position { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }
            Behavior on eulerRotation { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }
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
            visible: scene.roadVisible && !scene.viewSide

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

        // Тень на земле для 6-го вида: остаётся на месте, когда кузов
        // поднимается, — так читается дорожный просвет.
        Model {
            source: "#Cylinder"
            visible: scene.viewSide
            position: Qt.vector3d(0, 0.002, 0)
            scale: Qt.vector3d(0.034, 0.0004, 0.034)
            materials: PrincipledMaterial {
                baseColor: Qt.rgba(0, 0, 0, 0.55)
                lighting: PrincipledMaterial.NoLighting
                alphaMode: PrincipledMaterial.Blend
                cullMode: PrincipledMaterial.NoCulling
            }
        }

        Node {
            id: carPivot
            position: Qt.vector3d(0, scene.suspensionOffset, scene.carDepth)
            scale: Qt.vector3d(scene.carScale, scene.carScale, scene.carScale)
            // В 6-м виде — боком (профиль); иначе обычный разворот заставки.
            eulerRotation: Qt.vector3d(0, scene.viewSide ? 0 : scene.carYaw, 0)
            // Behavior на eulerRotation тут ВРЕДИТ: разворот кормой идёт
            // анимацией carYaw, а Behavior перезапускался на каждом её кадре
            // и замораживал поворот. Позиция — другое дело: меняется только
            // при смене уровня подвески.
            Behavior on position {
                NumberAnimation { duration: 500; easing.type: Easing.InOutQuad }
            }

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

                // ===== СВЕТ ФАР И СТОПОВ (по CAN, объёмный) =====
                // Только новый эффект: мягкий bloom (сферы с радиальной
                // текстурой) и лучи-конусы вперёд; жёсткие «шарики» старого
                // варианта убраны. Локальные координаты в метрах: нос -2.5,
                // корма +2.5.
                Node {
                    visible: scene.headlightsOn && !scene.viewSide
                    // ===== Фейковый bloom вокруг фар: сферы с радиальной
                    // текстурой, полупрозрачные (замена HDR-глоу без
                    // пост-обработки — на RK3588 дешевле).
                    Model {
                        source: "#Sphere"
                        position: Qt.vector3d(-2.72, 0.62, -0.72)
                        scale: Qt.vector3d(0.009, 0.009, 0.009)
                        materials: PrincipledMaterial {
                            baseColorMap: lightsGlowTexture
                            baseColor: Qt.rgba(1.0, 0.94, 0.78, 0.50)
                            lighting: PrincipledMaterial.NoLighting
                            alphaMode: PrincipledMaterial.Blend
                            cullMode: PrincipledMaterial.NoCulling
                        }
                    }
                    Model {
                        source: "#Sphere"
                        position: Qt.vector3d(-2.72, 0.62, 0.72)
                        scale: Qt.vector3d(0.009, 0.009, 0.009)
                        materials: PrincipledMaterial {
                            baseColorMap: lightsGlowTexture
                            baseColor: Qt.rgba(1.0, 0.94, 0.78, 0.50)
                            lighting: PrincipledMaterial.NoLighting
                            alphaMode: PrincipledMaterial.Blend
                            cullMode: PrincipledMaterial.NoCulling
                        }
                    }

                    // ===== Лучи фар: два конуса вперёд (вдаль от машины),
                    // полупрозрачные, туман даёт им объём.
                    Model {
                        source: "#Cone"
                        position: Qt.vector3d(-6.0, 0.62, -0.72)
                        scale: Qt.vector3d(0.03, 0.07, 0.03)
                        eulerRotation: Qt.vector3d(0, 0, -90)
                        materials: PrincipledMaterial {
                            baseColor: Qt.rgba(1.0, 0.95, 0.80, 0.10)
                            lighting: PrincipledMaterial.NoLighting
                            alphaMode: PrincipledMaterial.Blend
                            cullMode: PrincipledMaterial.NoCulling
                        }
                    }
                    Model {
                        source: "#Cone"
                        position: Qt.vector3d(-6.0, 0.62, 0.72)
                        scale: Qt.vector3d(0.03, 0.07, 0.03)
                        eulerRotation: Qt.vector3d(0, 0, -90)
                        materials: PrincipledMaterial {
                            baseColor: Qt.rgba(1.0, 0.95, 0.80, 0.10)
                            lighting: PrincipledMaterial.NoLighting
                            alphaMode: PrincipledMaterial.Blend
                            cullMode: PrincipledMaterial.NoCulling
                        }
                    }

                    // Красный bloom вокруг задних фонарей/стопов
                    Model {
                        source: "#Sphere"
                        position: Qt.vector3d(2.92, 0.68, -0.72)
                        scale: Qt.vector3d(0.012, 0.012, 0.012)
                        materials: PrincipledMaterial {
                            baseColorMap: lightsGlowTexture
                            baseColor: Qt.rgba(1.0, 0.12, 0.06, 0.55)
                            lighting: PrincipledMaterial.NoLighting
                            alphaMode: PrincipledMaterial.Blend
                            cullMode: PrincipledMaterial.NoCulling
                        }
                    }
                    Model {
                        source: "#Sphere"
                        position: Qt.vector3d(2.92, 0.68, 0.72)
                        scale: Qt.vector3d(0.012, 0.012, 0.012)
                        materials: PrincipledMaterial {
                            baseColorMap: lightsGlowTexture
                            baseColor: Qt.rgba(1.0, 0.12, 0.06, 0.55)
                            lighting: PrincipledMaterial.NoLighting
                            alphaMode: PrincipledMaterial.Blend
                            cullMode: PrincipledMaterial.NoCulling
                        }
                    }
                }

                // ===== ПОВОРОТНИКИ (мигают вместе с лампой на панели) =====
                // Левый борт в локальных осях модели — +z (перед у неё −x):
                // тогда при виде спереди «левый» поворотник светится справа
                // на экране, как на настоящей машине.
                Node {
                    visible: scene.leftTurn && scene.turnBlink && !scene.viewSide
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
                Node {
                    visible: scene.rightTurn && scene.turnBlink && !scene.viewSide
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
            }
        }
    }
}
