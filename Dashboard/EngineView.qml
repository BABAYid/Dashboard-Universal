pragma ComponentBehavior: Bound
import QtQuick
import QtQuick3D
import QtQuick3D.AssetUtils
import "assets/engine_anim.js" as EngineAnim

// ============================================================================
//  Двигатель V6 (assets/3.glb) на центральном экране.
//
//  RuntimeLoader не проигрывает glTF-анимации, поэтому анимация из файла
//  (коленвал + поршни + шатуны) вытащена скриптом tools/make_engine_anim.py
//  в assets/engine_anim.js: ключи поворотов/переводов. Здесь мы гоняем фазу
//  по оборотам: стоит мотор — стоит анимация; больше оборотов — быстрее.
//
//  Узлы glTF сопоставляются по их трансформации из файла: имена в QML
//  не сохраняются, а положения у всех узлов разные.
// ============================================================================
Item {
    id: root

    // Обороты двигателя (об/мин): 0 — анимация стоит.
    property real rpm: 0
    // Накопленная фаза анимации (в секундах её таймлайна).
    property real animSeconds: 0
    // Элементы сцены по индексу узла glTF.
    property var nodeItems: ({})

    readonly property var anim: EngineAnim.ENGINE_ANIM

    // Сколько «секунд анимации» за секунду реального времени: 1000 об/мин
    // → 1× (анимация 0.6 с на цикл), 6000 об/мин → 6×.
    readonly property real animSpeed: Math.max(0, rpm) / 1000.0

    View3D {
        anchors.fill: parent
        environment: SceneEnvironment {
            backgroundMode: SceneEnvironment.Color
            clearColor: "black"
            antialiasingMode: SceneEnvironment.MSAA
        }

        PerspectiveCamera {
            id: camera
            // Камера чуть сверху (~30° вниз) и ближе — двигатель крупнее
            position: Qt.vector3d(0, 78, 120)
            eulerRotation: Qt.vector3d(-30, 0, 0)
            fieldOfView: 42
        }

        // Тёплый свет, чтобы металл не был чёрным
        DirectionalLight {
            eulerRotation: Qt.vector3d(-45, -35, 0)
            brightness: 1.5
            color: "#FFF4E0"
        }
        DirectionalLight {
            eulerRotation: Qt.vector3d(-10, 120, 0)
            brightness: 0.7
            color: "#CFE0FF"
        }

        RuntimeLoader {
            id: loader
            source: "assets/3.glb"
            scale: Qt.vector3d(0.92, 0.92, 0.92)
            // Опускаем двигатель: иначе макушка заходит на верхнюю полосу
            position: Qt.vector3d(0, -18, 0)
            onStatusChanged: if (status === RuntimeLoader.Success) root.bindNodes()
        }
    }

    // Рекурсивно собираем все узлы сцены
    function collectNodes(node, out) {
        const kids = node.children || []
        for (let i = 0; i < kids.length; ++i) {
            const k = kids[i]
            if (k.position !== undefined && k.position !== null)
                out.push(k)
            collectNodes(k, out)
        }
    }

    // Сопоставляем элементы RuntimeLoader с индексами узлов glTF по
    // трансформации из файла (см. ENGINE_ANIM.nodes).
    function bindNodes() {
        const items = []
        collectNodes(loader, items)
        const nodes = root.anim.nodes
        const map = ({})
        for (const key in nodes) {
            const t = nodes[key].t
            for (let i = 0; i < items.length; ++i) {
                const p = items[i].position
                if (Math.abs(p.x - t[0]) < 0.01
                        && Math.abs(p.y - t[1]) < 0.01
                        && Math.abs(p.z - t[2]) < 0.01) {
                    map[key] = items[i]
                    break
                }
            }
        }
        root.nodeItems = map
    }

    // Интерполяция значения канала на фазе phase (ключи в анимации ровные)
    function sampleTrack(track, phase) {
        const times = track.times
        const vals = track.vals
        const n = times.length
        let i = 0
        while (i < n - 2 && times[i + 1] < phase)
            ++i
        const t0 = times[i]
        const t1 = times[i + 1]
        const k = t1 > t0 ? (phase - t0) / (t1 - t0) : 0
        const a = vals[i]
        const b = vals[i + 1]
        const out = []
        for (let c = 0; c < a.length; ++c)
            out.push(a[c] + (b[c] - a[c]) * k)
        return out
    }

    // Двигаем анимацию по оборотам
    Timer {
        interval: 16
        repeat: true
        running: root.animSpeed > 0.001 && Object.keys(root.nodeItems).length > 0
        onTriggered: {
            const phases = {}
            root.animSeconds += 0.016 * root.animSpeed
            const phase = root.animSeconds % root.anim.duration
            const tracks = root.anim.tracks
            for (const key in tracks) {
                const tr = tracks[key]
                const item = root.nodeItems[tr.node]
                if (!item)
                    continue
                const v = root.sampleTrack(tr, phase)
                if (tr.path === "translation") {
                    item.position = Qt.vector3d(v[0], v[1], v[2])
                } else if (tr.path === "rotation") {
                    // glTF: (x, y, z, w), Qt.quaternion(scalar, x, y, z)
                    const len = Math.sqrt(v[0]*v[0] + v[1]*v[1] + v[2]*v[2] + v[3]*v[3]) || 1
                    item.rotation = Qt.quaternion(v[3] / len, v[0] / len, v[1] / len, v[2] / len)
                } else if (tr.path === "scale") {
                    item.scale = Qt.vector3d(v[0], v[1], v[2])
                }
            }
        }
    }

}
