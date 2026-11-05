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
    // Двери по отдельности (демо с клавиатуры: 1 — FL, 2 — FR, 3 — RL, 4 — RR)
    property bool doorFL: false
    property bool doorFR: false
    property bool doorRL: false
    property bool doorRR: false
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

    // ---- Поворотники: свечение (emissive) вместо подмены геометрии ----
    // У модели есть свои узлы «lighter turner left/rigth» (по 4 см), но их
    // материал `orange` общий с задними фонарями, поэтому мигать будет всё
    // сразу. Даём каждому поворотнику СВОЙ материал — тогда левый и правый
    // мигают независимо, а стёкла/фонари остаются как были.
    // Частота 1.5 Гц — это фаза turnBlink из Main.qml (333 мс), поэтому
    // стрелки на панели и огни на модели мигают синхронно.
    PrincipledMaterial {
        id: turnMaterialLeft
        baseColor: "#CC2600"
        roughness: 0.5
        emissiveFactor: (scene.leftTurn && scene.turnBlink)
                        ? Qt.vector3d(1.0, 0.5, 0.0) : Qt.vector3d(0, 0, 0)
    }
    PrincipledMaterial {
        id: turnMaterialRight
        baseColor: "#CC2600"
        roughness: 0.5
        emissiveFactor: (scene.rightTurn && scene.turnBlink)
                        ? Qt.vector3d(1.0, 0.5, 0.0) : Qt.vector3d(0, 0, 0)
    }

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

    // ---- Поворот узла вокруг МИРОВОЙ оси с сохранением его собственного
    // поворота. Нужно потому, что у правых дверей узел в файле повёрнут на
    // 180° вокруг X (и отзеркален масштабом), а у колёс — на 90°: если просто
    // задать eulerRotation, этот поворот потеряется и деталь окажется не на
    // месте. Петля считается как q_new = q_hinge * q_orig (кватернионы [w,x,y,z]).
    function quatMul(a, b) {
        return [
            a[0]*b[0] - a[1]*b[1] - a[2]*b[2] - a[3]*b[3],
            a[0]*b[1] + a[1]*b[0] + a[2]*b[3] - a[3]*b[2],
            a[0]*b[2] - a[1]*b[3] + a[2]*b[0] + a[3]*b[1],
            a[0]*b[3] + a[1]*b[2] - a[2]*b[1] + a[3]*b[0]
        ]
    }

    // axis — мировая ось ([0,1,0] — вертикаль для дверей, [1,0,0] — поперечная
    // для капота, задней двери и колёс), degrees — угол петли.
    function pivotPart(car, index, axis, degrees) {
        if (!car || index >= car.models.length)
            return
        const node = car.models[index]
        if (!node)
            return
        const half = degrees * Math.PI / 360
        const s = Math.sin(half)
        const hinge = [Math.cos(half), axis[0]*s, axis[1]*s, axis[2]*s]
        const orig = car.origQuat[index] || [1, 0, 0, 0]
        const q = quatMul(hinge, orig)
        node.rotation = Qt.quaternion(q[0], q[1], q[2], q[3])
    }

    readonly property real carTravel: Math.min(1.0, Math.max(0.0, (progress - 0.375) / 0.375))
    readonly property real carDepth: -7.0 * (1.0 - carTravel)
    readonly property real carScale: 0.78 + 0.22 * carTravel

    // У финальной модели дизайнера нос смотрит в +Z (камера тоже с +Z),
    // поэтому 0 — машина стоит носом к зрителю; после заставки разворот на
    // 180° — кормой к зрителю, как и было.
    // Как было на прежней модели: выезжает носом к зрителю, после заставки
    // разворачивается на 180° и остаётся стоять кормой (нос у модели смотрит
    // в +Z, поэтому корма к камере — это 180°).
    property real carYaw: 0
    SequentialAnimation on carYaw {
        running: scene.progress >= 0.999
        PauseAnimation { duration: 800 }
        NumberAnimation {
            from: 0; to: 180
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
            // Выше и с наклоном 30°: при наклоне 30° камера с y=6 смотрела
            // выше центра машины, и она уезжала в верх кадра — с y=7 кузов
            // стоит по центру панели, а угол «сверху» остаётся тем же.
            position: scene.viewSide ? Qt.vector3d(0, 8.6, 2.0)
                                     : Qt.vector3d(0, 7.0, 11.0)
            // Наклон камеры: ~30° сверху — так видно и крышу, и корму,
            // а не плоскую проекцию сзади.
            eulerRotation: scene.viewSide ? Qt.vector3d(-78, 0, 0)
                                          : Qt.vector3d(-30, 0, 0)
            fieldOfView: 40
            clipNear: 0.5
            clipFar: 1000
            Behavior on position { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }
            Behavior on eulerRotation { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }
        }

        // Заливка, чтобы кузов читался: разгорается за первые 0.5 с.
        DirectionalLight {
            eulerRotation: Qt.vector3d(-35, -20, 0)
            brightness: 1.9 * Math.min(1.0, scene.progress / 0.125)
            castsShadow: false
        }

        // Вторая заливка с противоположной стороны: у финальной модели
        // материалы без текстуры, и одним источником половина кузова уходила
        // в чёрное (на ASCII-проверке тёмных пикселей было втрое больше).
        DirectionalLight {
            eulerRotation: Qt.vector3d(-25, 150, 0)
            brightness: 0.9 * Math.min(1.0, scene.progress / 0.125)
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
            eulerRotation: Qt.vector3d(0, scene.viewSide ? 90 : scene.carYaw, 0)
            // Behavior на eulerRotation тут ВРЕДИТ: разворот кормой идёт
            // анимацией carYaw, а Behavior перезапускался на каждом её кадре
            // и замораживал поворот. Позиция — другое дело: меняется только
            // при смене уровня подвески.
            Behavior on position {
                NumberAnimation { duration: 500; easing.type: Easing.InOutQuad }
            }

            // ===== ФИНАЛЬНАЯ МОДЕЛЬ ДИЗАЙНЕРА: ipsum_fin.glb =====
            // Габариты 4.59 (длина, Z) x 2.05 (ширина, X) x 1.73 (высота, Y),
            // нос смотрит в +Z, единицы — метры. Узлы идут в порядке:
            //   0 base (кузов)            1 door back (задняя дверь)
            //   2 door front left         3 door front right
            //   4 door left back          5 door right back
            //   6 front door (капот)      7-8 задние фонари
            //   9-10 фары                 11-12 поворотники
            //   13-16 колёса
            // Имена RuntimeLoader не сохраняет (objectName пустой), поэтому
            // роли раздаём по индексу — порядок проверен разбором GLB.
            Node {
                id: ipsumCar
                scale: Qt.vector3d(1, 1, 1)

                property var models: []     // все QQuick3DModel в порядке узлов
                property var origQuat: []   // их собственные повороты [w,x,y,z]
                property var wheels: []     // модели колёс (ось — мировая X)
                property var doors: []      // двери салона (ось — мировая Y)
                property var capot: null    // капот (петля — мировая X)
                property var trunk: null    // задняя дверь (петля — мировая X)
                // Кузов и всё, что над колёсами (0…6) — поднимается подвеской;
                // колёса (13…16) остаются на земле.
                property var bodyParts: []
                property var bodyOrigY: []
                property real bodyLift: 0
                property real capotAngle: scene.capotOpen ? scene.capotOpenAngle : 0
                property real trunkAngle: scene.trunkOpen ? scene.trunkOpenAngle : 0
                Behavior on capotAngle { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                Behavior on trunkAngle { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                property real wheelAngle: 0
                property real doorAngle: scene.doorsOpen ? scene.doorOpenAngle : 0
                property real doorAngleFL: (scene.doorFL || scene.doorsOpen) ? scene.doorOpenAngle : 0
                property real doorAngleFR: (scene.doorFR || scene.doorsOpen) ? scene.doorOpenAngle : 0
                property real doorAngleRL: (scene.doorRL || scene.doorsOpen) ? scene.doorOpenAngle : 0
                property real doorAngleRR: (scene.doorRR || scene.doorsOpen) ? scene.doorOpenAngle : 0
                Behavior on doorAngleFL { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
                Behavior on doorAngleFR { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
                Behavior on doorAngleRL { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
                Behavior on doorAngleRR { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }

                Behavior on doorAngle {
                    NumberAnimation { duration: 700; easing.type: Easing.OutCubic }
                }

                Node {
                    id: carModel
                    // У модели низ кузова на y=2.0, центр по X и Z — 1.40 и 2.00:
                    // сдвигаем, чтобы машина стояла на земле и вращалась вокруг
                    // собственного центра, а не вокруг угла файла.
                    position: Qt.vector3d(-1.40, -2.00, -2.00)

                    RuntimeLoader {
                        id: ipsumLoader
                        source: "assets/ipsum_fin.glb"

                        onStatusChanged: {
                            if (status !== RuntimeLoader.Success)
                                return

                            const models = []
                            scene.collectModels(ipsumLoader, models)
                            const names = ["base", "door back", "door front left", "door front right",
                                           "door left back", "door right back", "капот",
                                           "фонарь задний левый", "фонарь задний правый",
                                           "фара правая", "фара левая",
                                           "поворотник левый", "поворотник правый",
                                           "колесо", "колесо", "колесо", "колесо"]
                            console.log("3D: ipsum_fin.glb загружена, узлов:", models.length)

                            const quats = []
                            for (let i = 0; i < models.length; ++i) {
                                const m = models[i]
                                m.objectName = names[i] || ("node" + i)
                                const r = m.rotation
                                quats.push([r.scalar, r.x, r.y, r.z])
                                const p = m.position
                                console.log("3D: узел", i, m.objectName,
                                            "pos=", p.x.toFixed(3), p.y.toFixed(3), p.z.toFixed(3))
                            }

                            ipsumCar.models = models
                            ipsumCar.origQuat = quats
                            ipsumCar.capot = models[6]
                            ipsumCar.trunk = models[1]

                            // Кузов и всё над колёсами поднимаются подвеской.
                            const parts = []
                            const origY = []
                            for (let b = 0; b <= 6 && b < models.length; ++b) {
                                parts.push(models[b])
                                origY.push(models[b].position.y)
                            }
                            ipsumCar.bodyOrigY = origY
                            ipsumCar.bodyParts = parts
                            // Двери: 2 — передняя левая, 3 — передняя правая,
                            // 4 — задняя левая, 5 — задняя правая.
                            ipsumCar.doors = [models[2], models[3], models[4], models[5]]
                            ipsumCar.wheels = [models[13], models[14], models[15], models[16]]

                            // Поворотники: 11 — левый, 12 — правый. Подменяем
                            // материал на свой, чтобы управлять свечением
                            // независимо (родной `orange` общий с фонарями).
                            if (models.length > 12) {
                                models[11].materials = [turnMaterialLeft]
                                models[12].materials = [turnMaterialRight]
                                console.log("3D: поворотники — узлы 11 (левый) и 12 (правый), "
                                            + "emissive управляется фазой turnBlink")
                                console.log("3D: у узла 11 материалов", models[11].materials.length,
                                            "emissive", models[11].materials[0].emissiveFactor.x,
                                            "| у узла 12 материалов", models[12].materials.length,
                                            "emissive", models[12].materials[0].emissiveFactor.x)
                            }
                        }
                    }
                }

                // Крутим колёса: угол растёт со скоростью, в покое — стоит.
                Timer {
                    interval: 16
                    repeat: true
                    running: ipsumCar.wheels.length > 0
                    onTriggered: {
                        const spd = scene.roadSpeed
                        if (spd > 0.5)
                            ipsumCar.wheelAngle += spd * 0.015
                        for (let i = 13; i <= 16 && i < ipsumCar.models.length; ++i)
                            scene.pivotPart(ipsumCar, i, [1, 0, 0], ipsumCar.wheelAngle)
                    }
                }

                // Подвеска: кузов плавно поднимается/опускается относительно
                // колёс. suspensionOffset задан в единицах сцены, а части кузова —
                // внутри масштабированного контейнера, поэтому делим на полный
                // масштаб цепочки.
                Timer {
                    interval: 16
                    repeat: true
                    running: ipsumCar.bodyParts.length > 0
                    onTriggered: {
                        const totalScale = scene.carScale * scene.carEnlarge
                        const target = scene.suspensionOffset / totalScale
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

                // Капот и задняя дверь: петля — горизонтальная мировая ось X.
                // Капот поднимается передней кромкой (минус), задняя дверь —
                // нижней кромкой (плюс).
                Timer {
                    interval: 16
                    repeat: true
                    running: ipsumCar.capot !== null
                    onTriggered: {
                        scene.pivotPart(ipsumCar, 6, [1, 0, 0], -ipsumCar.capotAngle)
                        scene.pivotPart(ipsumCar, 1, [1, 0, 0], ipsumCar.trunkAngle)
                    }
                }

                // Двери открываются наружу поворотом вокруг мировой вертикали.
                // У правых дверей узел в файле повёрнут на 180° вокруг X и
                // отзеркален — поэтому петля идёт в другую сторону.
                Timer {
                    interval: 16
                    repeat: true
                    running: ipsumCar.doors.length > 0
                    onTriggered: {
                        const angles = [ipsumCar.doorAngleFL, ipsumCar.doorAngleFR,
                                        ipsumCar.doorAngleRL, ipsumCar.doorAngleRR]
                        const nodes = [2, 3, 4, 5]
                        const signs = [-1, 1, -1, 1]   // левые — минус, правые — плюс
                        for (let i = 0; i < nodes.length; ++i)
                            scene.pivotPart(ipsumCar, nodes[i], [0, 1, 0], signs[i] * angles[i])
                    }
                }

                // ===== ПОВОРОТНИКИ =====
                // У модели есть свои узлы поворотников, но они по 4 см — на
                // приборке не видны, поэтому светим шариками на их местах.
                // Координаты — мировые координаты модели минус её сдвиг
                // (-1.40, -2.00, -2.00), чтобы они сидели на фарах.
                Node {
                    visible: scene.leftTurn && scene.turnBlink && !scene.viewSide
                    Model {
                        source: "#Sphere"
                        position: Qt.vector3d(0.88, 0.84, 1.11)    // передний левый
                        scale: Qt.vector3d(0.0022, 0.0022, 0.0022)
                        materials: PrincipledMaterial {
                            baseColor: "#FF9A1A"
                            lighting: PrincipledMaterial.NoLighting
                        }
                    }
                    Model {
                        source: "#Sphere"
                        position: Qt.vector3d(0.78, 0.93, -2.07)   // задний левый
                        scale: Qt.vector3d(0.0022, 0.0022, 0.0022)
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
                        position: Qt.vector3d(-0.87, 0.88, 1.11)   // передний правый
                        scale: Qt.vector3d(0.0022, 0.0022, 0.0022)
                        materials: PrincipledMaterial {
                            baseColor: "#FF9A1A"
                            lighting: PrincipledMaterial.NoLighting
                        }
                    }
                    Model {
                        source: "#Sphere"
                        position: Qt.vector3d(-0.78, 0.93, -2.07)  // задний правый
                        scale: Qt.vector3d(0.0022, 0.0022, 0.0022)
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
