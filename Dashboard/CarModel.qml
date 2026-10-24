// Сгенерировано balsam из assets/cruiser300.glb (см. tools/bake_glb.py и README):
// не редактировать вручную. Пересборка: bake → balsam → добавить
// масштаб 0.001 (модель в сантиметрах) к Model.
import QtQuick
import QtQuick3D

Node {
    id: node

    // Resources
    property url textureData: "assets/cruiser/maps/textureData.web"
    Texture {
        id: _0_texture
        generateMipmaps: true
        mipFilter: Texture.Linear
        source: node.textureData
    }
    PrincipledMaterial {
        id: principledMaterial
        baseColorMap: _0_texture
        roughness: 0.6000000238418579
        emissiveMap: _0_texture
        emissiveFactor: Qt.vector3d(0.0, 0.0, 0.0)
        alphaMode: PrincipledMaterial.Opaque
    }

    // Nodes:
    Model {
        id: nodes_0_
        objectName: "nodes[0]"
        source: "assets/cruiser/meshes/meshes_0__mesh.mesh"
        scale: Qt.vector3d(0.001, 0.001, 0.001)
        materials: [
            principledMaterial
        ]
    }

    // Animations:
}
