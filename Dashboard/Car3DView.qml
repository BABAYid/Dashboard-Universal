pragma ComponentBehavior: Bound
import QtQuick
import QtQuick3D
import Dashboard

// ============================================================================
//  3D-модель машины для центральной зоны (492×404) и кинематографичный запуск.
//
//  Вся 3D-часть живёт здесь: View3D, света, камера, модель, анимации фаз.
//  Main.qml двигает только одно свойство — progress (0…1 за 4 секунды), а
//  как оно раскладывается по свету и машине, решается здесь.
//
//  Раскладка progress по сценарию:
//     0.000–0.125  (0.0–0.5 с)   всё тёмное: фары погашены, машина за кадром
//     0.125–0.375  (0.5–1.5 с)   две фары разгораются и расширяют пятна
//     0.375–0.750  (1.5–3.0 с)   машина выезжает из глубины и приближается
//     0.750–1.000  (3.0–4.0 с)   стоит по центру, начинается ленивое вращение
//
//  После запуска (progress = 1) компонент остаётся фоном центральной зоны:
//  притушен и медленно покачивается. В навигации его скрывает Main.qml.
//
//  Производительность: View3D рендерит ТОЛЬКО в свою зону (492×404), модель
//  прорежена до ~36 тысяч треугольников (было 3.09 млн — см. tools/decimate_glb.py),
//  тени выключены, сглаживание NoAA. Замер FPS — в PROJECT_STATE.md.
// ============================================================================
Item {
    id: root

    // 0…1: прогресс стартовой анимации. Main.qml анимирует его от 0 до 1.
    property real progress: 1.0

    // После старта модель остаётся фоном и слегка покачивается.
    property bool idleMotion: true

    // Появление модели: пока .glb не загружен, кадр пустой (сцена чёрная).
    // Сигнал нужен Main.qml: если модель не загрузилась, приборка не должна
    // ждать 4 секунды впустую.
    signal modelReady()
    signal modelFailed()

    // ---- раскладка progress по шагам сценария ----
    readonly property real spotPower: Math.min(1.0, Math.max(0.0, (progress - 0.125) / 0.25))
    readonly property real spotCone: 8 + 14 * spotPower               // 8° → 22°
    readonly property real carTravel: Math.min(1.0, Math.max(0.0, (progress - 0.375) / 0.375))
    readonly property real carDepth: -7.0 * (1.0 - carTravel)         // из глубины к нулю
    readonly property real carScale: 0.78 + 0.22 * carTravel

    View3D {
        anchors.fill: parent
        // Рендер только в зону компонента, не в полный экран — экономия для Mali
        renderMode: View3D.Offscreen
        camera: camera

        environment: SceneEnvironment {
            backgroundMode: SceneEnvironment.Color
            clearColor: "black"
            antialiasingMode: SceneEnvironment.NoAA
            // без AO и прочих постэффектов: на Mali-G610 они дороже всей сцены
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
            brightness: root.progress > 0.125 ? 0.18 : 0.0
            castsShadow: false
        }

        // Две «фары»: пятна света перед машиной, разгораются на шаге 0.5–1.5 с
        SpotLight {
            position: Qt.vector3d(-1.6, 2.2, 5.2)
            eulerRotation: Qt.vector3d(-12, 8, 0)
            coneAngle: root.spotCone
            innerConeAngle: root.spotCone * 0.45
            brightness: 55 * root.spotPower
            color: "#FFF3D6"
            castsShadow: false
        }

        SpotLight {
            position: Qt.vector3d(1.6, 2.2, 5.2)
            eulerRotation: Qt.vector3d(-12, -8, 0)
            coneAngle: root.spotCone
            innerConeAngle: root.spotCone * 0.45
            brightness: 55 * root.spotPower
            color: "#FFF3D6"
            castsShadow: false
        }

        // Контейнер машины: его двигаем по глубине и масштабу
        Node {
            id: carNode
            position: Qt.vector3d(0, 0, root.carDepth)
            scale: Qt.vector3d(root.carScale, root.carScale, root.carScale)
            // модель в файле длиной ~7 «единиц» — приводим к ~4.2, чтобы влезала в кадр
            eulerRotation: Qt.vector3d(0, 0, 0)

            Node {
                id: modelHolder
                scale: Qt.vector3d(0.6, 0.6, 0.6)

                // Ленивое покачивание после старта
                SequentialAnimation on eulerRotation.y {
                    running: root.progress >= 0.99 && root.idleMotion
                    loops: Animation.Infinite
                    NumberAnimation { from: -6; to: 6; duration: 7000; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 6; to: -6; duration: 7000; easing.type: Easing.InOutSine }
                }
            }

            RuntimeLoader {
                source: "assets/car.glb"
                onStatusChanged: {
                    if (status === RuntimeLoader.Success)
                        root.modelReady()
                    else if (status === RuntimeLoader.Error)
                        root.modelFailed()
                }
            }
        }
    }
}
