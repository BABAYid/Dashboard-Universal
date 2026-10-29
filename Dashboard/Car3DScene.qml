pragma ComponentBehavior: Bound
import QtQuick
import QtQuick3D
import QtQuick3D.AssetUtils

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

    // Тестовый режим дверей/капота/багажника: кнопки в настройках.
    property bool doorsOpen: false
    property real doorOpenAngle: 45
    property bool capotOpen: false
    property real capotOpenAngle: 35
    property bool trunkOpen: false
    property real trunkOpenAngle: 55

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

    // Увеличение машины под окно между приборами (окно 492 px из 800):
    // масштаб контейнера множится на этот коэффициент, свет фар едет вместе.
    property real carEnlarge: 1.9

    // 6-й вид: машина развёрнута боком, и пневмоподвеска двигает кузов по Y.
    property bool viewSide: false
    property int suspensionLevel: 0        // -1 спорт, 0 стандарт, 1 бездорожье
    // Амплитуда хода кузова. Раньше было 0.18/−0.10 — на глаз почти не
    // читалось (это ~4% длины машины); теперь заметно, но колёса не
    // отрываются от земли настолько, чтобы это выглядело сломанным.
    readonly property real suspensionOffset: suspensionLevel > 0 ? 0.9
                                             : suspensionLevel < 0 ? -0.5 : 0.0

    signal modelReady()
    signal modelFailed()

    // Рекурсивно собираем все QQuick3DModel в порядке обхода дерева:
    // у RuntimeLoader порядок совпадает с порядком узлов glTF.
    function collectModels(node, out) {
        const kids = node.children || []
        for (let i = 0; i < kids.length; ++i) {
            const k = kids[i]
            if (k.toString().indexOf("QQuick3DModel") === 0)
                out.push(k)
            collectModels(k, out)
        }
    }

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
            // Подъём подвески теперь не здесь: кузов поднимается
            // относительно колёс (см. ipsumCar.bodyLift), колёса стоят
            // на земле — как на настоящей пневмоподвеске.
            position: Qt.vector3d(0, 0, scene.carDepth)
            scale: Qt.vector3d(scene.carScale * scene.carEnlarge, scene.carScale * scene.carEnlarge, scene.carScale * scene.carEnlarge)
            // В 6-м виде — боком (профиль); иначе обычный разворот заставки.
            eulerRotation: Qt.vector3d(0, scene.viewSide ? 0 : scene.carYaw, 0)
            // Behavior на eulerRotation тут ВРЕДИТ: разворот кормой идёт
            // анимацией carYaw, а Behavior перезапускался на каждом её кадре
            // и замораживал поворот. Позиция — другое дело: меняется только
            // при смене уровня подвески.
            Behavior on position {
                NumberAnimation { duration: 500; easing.type: Easing.InOutQuad }
            }

            // ===== НОВАЯ МОДЕЛЬ: ipsum_3D.glb (единицы — метры, ~1.9 м) =====
            // Грузим в рантайме через RuntimeLoader. В нашем GLB узлы идут
            // в порядке: 0 Capot, 1 Car_body, 2 Door_5 (багажник), 3 Door_FL,
            // 4 Door_FR, 5 Door_RL, 6 Door_RR, 7 Wheel_FL, 8 Wheel_FR,
            // 9 Wheel_RL, 10 Wheel_RR. Имена в QML не сохраняются
            // (objectName пустые) — порядок и позиции проверены разбором
            // GLB, поэтому роли назначаем по индексу после загрузки.
            Node {
                id: ipsumCar
                scale: Qt.vector3d(2.6, 2.6, 2.6)   // подгонка под кадр

                property var wheels: []     // модели колёс (ось вращения — z)
                property var doors: []      // двери салона (ось — y)
                property var capot: null    // капот (петля — задняя верхняя кромка)
                property var trunk: null    // багажник (петля — верх, 5-я дверь)
                // Части, которые поднимаются вместе с кузовом (всё, кроме
                // колёс): 0 Capot, 1 Car_body, 2 Door_5, 3..6 двери.
                property var bodyParts: []
                property var bodyOrigY: []
                property real bodyLift: 0
                property real capotAngle: scene.capotOpen ? scene.capotOpenAngle : 0
                property real trunkAngle: scene.trunkOpen ? scene.trunkOpenAngle : 0
                Behavior on capotAngle { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                Behavior on trunkAngle { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                property real wheelAngle: 0
                property real doorAngle: scene.doorsOpen ? scene.doorOpenAngle : 0

                Behavior on doorAngle {
                    NumberAnimation { duration: 700; easing.type: Easing.OutCubic }
                }

                RuntimeLoader {
                    id: ipsumLoader
                    source: "assets/ipsum_3D.glb"

                    onStatusChanged: {
                        if (status !== RuntimeLoader.Success)
                            return

                        // Модели в порядке узлов glTF (проверено позициями).
                        const models = []
                        scene.collectModels(ipsumLoader, models)
                        const names = ["Capot", "Car_body", "Door_5", "Door_FL",
                                       "Door_FR", "Door_RL", "Door_RR",
                                       "Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]
                        console.log("3D: ipsum_3D.glb загружена, узлов:", models.length)
                        for (let i = 0; i < models.length; ++i) {
                            const m = models[i]
                            m.objectName = names[i] || ("node" + i)
                            const p = m.position
                            console.log("3D: узел", i, m.objectName,
                                        "pos=", p.x.toFixed(3), p.y.toFixed(3), p.z.toFixed(3))
                        }
                        // На Door_FL в файле лежит случайный поворот — сбрасываем,
                        // позу дверей задаём сами.
                        for (let d = 3; d <= 6 && d < models.length; ++d)
                            models[d].eulerRotation = Qt.vector3d(0, 0, 0)

                        ipsumCar.capot = models[0]
                        ipsumCar.trunk = models[2]
                        // Кузов и двери поднимаются подвеской; колёса —
                        // нет, поэтому их позиции не трогаем.
                        // Собираем локально и присваиваем разом: push в
                        // существующий массив не меняет свойство, и binding
                        // `running` у таймера подъёма не пересчитался бы.
                        const parts = []
                        const origY = []
                        for (let b = 0; b <= 6 && b < models.length; ++b) {
                            parts.push(models[b])
                            origY.push(models[b].position.y)
                        }
                        ipsumCar.bodyOrigY = origY
                        ipsumCar.bodyParts = parts
                        ipsumCar.doors = [models[3], models[4], models[5], models[6]]
                        ipsumCar.wheels = [models[7], models[8], models[9], models[10]]
                    }
                }

                // Крутим колёса: угол растёт со скоростью, в покое — стоит.
                // Ось колеса в модели — локальная z (диск лежит в x-y).
                Timer {
                    interval: 16
                    repeat: true
                    running: ipsumCar.wheels.length > 0
                    onTriggered: {
                        const spd = scene.roadSpeed
                        if (spd > 0.5)
                            ipsumCar.wheelAngle += spd * 0.015
                        for (let i = 0; i < ipsumCar.wheels.length; ++i) {
                            const w = ipsumCar.wheels[i]
                            if (w)
                                w.eulerRotation = Qt.vector3d(0, 0, ipsumCar.wheelAngle)
                        }
                    }
                }

                // Подвеска: кузов плавно поднимается/опускается относительно
                // колёс. suspensionOffset задан в единицах сцены, а части
                // кузова — внутри масштабированного контейнера, поэтому
                // делим на полный масштаб цепочки.
                Timer {
                    interval: 16
                    repeat: true
                    running: ipsumCar.bodyParts.length > 0
                    onTriggered: {
                        const totalScale = scene.carScale * scene.carEnlarge * 2.6
                        const target = scene.suspensionOffset / totalScale
                        // плавное догоняние (~0.2 с)
                        ipsumCar.bodyLift += (target - ipsumCar.bodyLift) * 0.25
                        for (let b = 0; b < ipsumCar.bodyParts.length; ++b) {
                            const m = ipsumCar.bodyParts[b]
                            if (!m)
                                continue
                            const p = m.position
                            m.position = Qt.vector3d(p.x, ipsumCar.bodyOrigY[b] + ipsumCar.bodyLift, p.z)
                        }
                    }
                }

                // Капот и багажник: поворот вокруг горизонтальной оси z.
                // Капот — петля сзади сверху (передняя кромка идёт вверх);
                // багажник — 5-я дверь, нижняя кромка уходит вверх.
                Timer {
                    interval: 16
                    repeat: true
                    running: ipsumCar.capot !== null
                    onTriggered: {
                        if (ipsumCar.capot)
                            ipsumCar.capot.eulerRotation = Qt.vector3d(0, 0, -ipsumCar.capotAngle)
                        if (ipsumCar.trunk)
                            ipsumCar.trunk.eulerRotation = Qt.vector3d(0, 0, ipsumCar.trunkAngle)
                    }
                }

                // Двери: открываются наружу поворотом вокруг вертикали.
                // Левая сторона (z+) и правая (z−) — знак разный.
                Timer {
                    interval: 16
                    repeat: true
                    running: ipsumCar.doors.length > 0
                    onTriggered: {
                        for (let i = 0; i < ipsumCar.doors.length; ++i) {
                            const d = ipsumCar.doors[i]
                            if (!d)
                                continue
                            // 0=FL, 1=FR, 2=RL, 3=RR; слева (z+) — плюс,
                            // справа (z−) — минус.
                            const left = (i === 0 || i === 2)
                            const sign = left ? -1 : 1
                            d.eulerRotation = Qt.vector3d(0, sign * ipsumCar.doorAngle, 0)
                        }
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
