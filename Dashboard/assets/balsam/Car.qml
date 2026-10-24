import QtQuick
import QtQuick3D

Node {
    id: node

    // Resources
    property url textureData: "maps/textureData.web"
    Texture {
        id: _0_texture
        generateMipmaps: true
        mipFilter: Texture.Linear
        source: node.textureData
    }
    PrincipledMaterial {
        id: principledMaterial
        baseColor: "#ffe7e7e7"
        metalness: 1
        roughness: 0.42514416575431824
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: principledMaterial187
        baseColorMap: _0_texture
        metalness: 1
        roughness: 0.40454500913619995
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: principledMaterial133
        baseColor: "#ff595959"
        metalness: 1
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: principledMaterial116
        baseColor: "#ff000000"
        metalness: 0.6689544320106506
        roughness: 0.29714375734329224
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: principledMaterial5
        baseColor: "#ff404040"
        metalness: 0.4309999942779541
        roughness: 0.328000009059906
        alphaMode: PrincipledMaterial.Opaque
    }

    // Nodes:
    Node {
        id: audi_RS6_Avant_2023__Interior_included_
        objectName: "Audi RS6 Avant 2023 (Interior included)"
        Node {
            id: plane_076_2
            objectName: "Plane.076_2"
            Model {
                id: _gltfNode_0
                objectName: "_gltfNode_0"
                source: "meshes/mesh_mesh.mesh"
                materials: [
                    principledMaterial5
                ]
            }
        }
        Node {
            id: plane_001_3
            objectName: "Plane.001_3"
            Node {
                id: _gltfNode_2
                objectName: "_gltfNode_2"
            }
        }
        Node {
            id: plane_002_4
            objectName: "Plane.002_4"
            Node {
                id: _gltfNode_4
                objectName: "_gltfNode_4"
            }
        }
        Node {
            id: plane_006_5
            objectName: "Plane.006_5"
            Node {
                id: _gltfNode_6
                objectName: "_gltfNode_6"
            }
        }
        Node {
            id: plane_007_6
            objectName: "Plane.007_6"
            Node {
                id: _gltfNode_8
                objectName: "_gltfNode_8"
            }
        }
        Node {
            id: plane_005_7
            objectName: "Plane.005_7"
            Node {
                id: _gltfNode_10
                objectName: "_gltfNode_10"
            }
        }
        Node {
            id: plane_008_8
            objectName: "Plane.008_8"
            Node {
                id: _gltfNode_12
                objectName: "_gltfNode_12"
            }
        }
        Node {
            id: plane_009_9
            objectName: "Plane.009_9"
            Node {
                id: _gltfNode_14
                objectName: "_gltfNode_14"
            }
        }
        Node {
            id: plane_010_10
            objectName: "Plane.010_10"
            Node {
                id: _gltfNode_16
                objectName: "_gltfNode_16"
            }
        }
        Node {
            id: plane_011_11
            objectName: "Plane.011_11"
            Node {
                id: _gltfNode_18
                objectName: "_gltfNode_18"
            }
        }
        Node {
            id: plane_012_12
            objectName: "Plane.012_12"
            Node {
                id: _gltfNode_20
                objectName: "_gltfNode_20"
            }
        }
        Node {
            id: plane_013_13
            objectName: "Plane.013_13"
            Node {
                id: _gltfNode_22
                objectName: "_gltfNode_22"
            }
        }
        Node {
            id: plane_015_14
            objectName: "Plane.015_14"
            Node {
                id: _gltfNode_24
                objectName: "_gltfNode_24"
            }
        }
        Node {
            id: plane_014_15
            objectName: "Plane.014_15"
            Node {
                id: _gltfNode_26
                objectName: "_gltfNode_26"
            }
        }
        Node {
            id: plane_017_16
            objectName: "Plane.017_16"
            Node {
                id: _gltfNode_28
                objectName: "_gltfNode_28"
            }
        }
        Node {
            id: plane_016_17
            objectName: "Plane.016_17"
            Node {
                id: _gltfNode_30
                objectName: "_gltfNode_30"
            }
        }
        Node {
            id: plane_018_18
            objectName: "Plane.018_18"
            Node {
                id: _gltfNode_32
                objectName: "_gltfNode_32"
            }
        }
        Node {
            id: plane_019_19
            objectName: "Plane.019_19"
            Node {
                id: _gltfNode_34
                objectName: "_gltfNode_34"
            }
        }
        Node {
            id: plane_020_20
            objectName: "Plane.020_20"
            Node {
                id: _gltfNode_36
                objectName: "_gltfNode_36"
            }
        }
        Node {
            id: plane_021_21
            objectName: "Plane.021_21"
            Node {
                id: _gltfNode_38
                objectName: "_gltfNode_38"
            }
        }
        Node {
            id: plane_022_22
            objectName: "Plane.022_22"
            Node {
                id: _gltfNode_40
                objectName: "_gltfNode_40"
            }
        }
        Node {
            id: plane_024_23
            objectName: "Plane.024_23"
            Node {
                id: _gltfNode_42
                objectName: "_gltfNode_42"
            }
        }
        Node {
            id: plane_025_24
            objectName: "Plane.025_24"
            Node {
                id: _gltfNode_44
                objectName: "_gltfNode_44"
            }
        }
        Node {
            id: plane_004_25
            objectName: "Plane.004_25"
            Node {
                id: _gltfNode_46
                objectName: "_gltfNode_46"
            }
        }
        Node {
            id: plane_026_26
            objectName: "Plane.026_26"
            Node {
                id: _gltfNode_48
                objectName: "_gltfNode_48"
            }
        }
        Node {
            id: plane_023_27
            objectName: "Plane.023_27"
            Node {
                id: _gltfNode_50
                objectName: "_gltfNode_50"
            }
        }
        Node {
            id: plane_028_28
            objectName: "Plane.028_28"
            position: Qt.vector3d(0, 0, 0.0511166)
            Node {
                id: _gltfNode_52
                objectName: "_gltfNode_52"
            }
        }
        Node {
            id: plane_029_29
            objectName: "Plane.029_29"
            scale: Qt.vector3d(1.0497, 1, 1)
            Node {
                id: _gltfNode_54
                objectName: "_gltfNode_54"
            }
        }
        Node {
            id: lattice_32
            objectName: "Lattice_32"
            position: Qt.vector3d(0, 0.606768, 3.73314)
            scale: Qt.vector3d(1.5209, 0.314915, 0.109182)
            Node {
                id: plane_030_30
                objectName: "Plane.030_30"
                position: Qt.vector3d(0, -1.89864, -34.1771)
                scale: Qt.vector3d(0.657505, 3.17546, 9.15898)
                Node {
                    id: _gltfNode_56
                    objectName: "_gltfNode_56"
                }
                Node {
                    id: _gltfNode_57
                    objectName: "_gltfNode_57"
                }
            }
            Node {
                id: plane_036_31
                objectName: "Plane.036_31"
                position: Qt.vector3d(0, -1.89864, -34.1771)
                scale: Qt.vector3d(0.657505, 3.17546, 9.15898)
                Node {
                    id: _gltfNode_59
                    objectName: "_gltfNode_59"
                }
            }
        }
        Node {
            id: plane_031_33
            objectName: "Plane.031_33"
            Node {
                id: _gltfNode_62
                objectName: "_gltfNode_62"
            }
        }
        Node {
            id: plane_034_34
            objectName: "Plane.034_34"
            Node {
                id: _gltfNode_64
                objectName: "_gltfNode_64"
            }
        }
        Node {
            id: plane_032_35
            objectName: "Plane.032_35"
            rotation: Qt.quaternion(0.707107, 0.707107, 0, 0)
            scale: Qt.vector3d(1, 1, 1)
            Node {
                id: _gltfNode_66
                objectName: "_gltfNode_66"
            }
        }
        Node {
            id: plane_033_36
            objectName: "Plane.033_36"
            Node {
                id: _gltfNode_68
                objectName: "_gltfNode_68"
            }
        }
        Node {
            id: plane_037_37
            objectName: "Plane.037_37"
            Node {
                id: _gltfNode_70
                objectName: "_gltfNode_70"
            }
        }
        Node {
            id: plane_038_38
            objectName: "Plane.038_38"
            Node {
                id: _gltfNode_72
                objectName: "_gltfNode_72"
            }
        }
        Node {
            id: plane_039_39
            objectName: "Plane.039_39"
            scale: Qt.vector3d(1.0497, 1, 1)
            Node {
                id: _gltfNode_74
                objectName: "_gltfNode_74"
            }
        }
        Node {
            id: plane_040_40
            objectName: "Plane.040_40"
            Node {
                id: _gltfNode_76
                objectName: "_gltfNode_76"
            }
        }
        Node {
            id: plane_042_41
            objectName: "Plane.042_41"
            Node {
                id: _gltfNode_78
                objectName: "_gltfNode_78"
            }
        }
        Node {
            id: plane_041_42
            objectName: "Plane.041_42"
            Node {
                id: _gltfNode_80
                objectName: "_gltfNode_80"
            }
        }
        Node {
            id: plane_043_43
            objectName: "Plane.043_43"
            Node {
                id: _gltfNode_82
                objectName: "_gltfNode_82"
            }
            Node {
                id: _gltfNode_83
                objectName: "_gltfNode_83"
            }
        }
        Node {
            id: plane_046_44
            objectName: "Plane.046_44"
            Node {
                id: _gltfNode_85
                objectName: "_gltfNode_85"
            }
        }
        Node {
            id: cube_001_45
            objectName: "Cube.001_45"
            Node {
                id: _gltfNode_87
                objectName: "_gltfNode_87"
            }
            Node {
                id: _gltfNode_88
                objectName: "_gltfNode_88"
            }
            Node {
                id: _gltfNode_89
                objectName: "_gltfNode_89"
            }
        }
        Node {
            id: plane_044_46
            objectName: "Plane.044_46"
            position: Qt.vector3d(0.00609142, 0.0936222, -0.12038)
            Node {
                id: _gltfNode_91
                objectName: "_gltfNode_91"
            }
            Node {
                id: _gltfNode_92
                objectName: "_gltfNode_92"
            }
        }
        Node {
            id: lattice_003_48
            objectName: "Lattice.003_48"
            position: Qt.vector3d(0.998438, 1.01557, 3.19325)
            scale: Qt.vector3d(0.659051, 0.10409, 0.392388)
            Node {
                id: cube_002_47
                objectName: "Cube.002_47"
                position: Qt.vector3d(-1.51496, -9.75659, -8.13799)
                scale: Qt.vector3d(1.51733, 9.60704, 2.5485)
                Node {
                    id: _gltfNode_94
                    objectName: "_gltfNode_94"
                }
                Node {
                    id: _gltfNode_95
                    objectName: "_gltfNode_95"
                }
            }
        }
        Node {
            id: plane_045_49
            objectName: "Plane.045_49"
            Node {
                id: _gltfNode_98
                objectName: "_gltfNode_98"
            }
        }
        Node {
            id: rs6c8_taillight_L_50
            objectName: "rs6c8_taillight_L_50"
            scale: Qt.vector3d(1.50374, 1.50374, 1.50374)
            Node {
                id: _gltfNode_100
                objectName: "_gltfNode_100"
            }
            Node {
                id: _gltfNode_101
                objectName: "_gltfNode_101"
            }
            Node {
                id: _gltfNode_102
                objectName: "_gltfNode_102"
            }
        }
        Node {
            id: rs6c8_tailgate_001_51
            objectName: "rs6c8_tailgate.001_51"
            position: Qt.vector3d(0, -0.0145099, 0.309706)
            scale: Qt.vector3d(1.50374, 1.50374, 1.50374)
            Node {
                id: _gltfNode_104
                objectName: "_gltfNode_104"
            }
        }
        Node {
            id: polySurface651_001_52
            objectName: "polySurface651.001_52"
            rotation: Qt.quaternion(0.707107, 0.707107, 0, 0)
            scale: Qt.vector3d(1, 1, 1)
            Node {
                id: _gltfNode_106
                objectName: "_gltfNode_106"
            }
            Node {
                id: _gltfNode_107
                objectName: "_gltfNode_107"
            }
        }
        Node {
            id: plane_047_53
            objectName: "Plane.047_53"
            Model {
                id: _gltfNode_109
                objectName: "_gltfNode_109"
                source: "meshes/mesh_mesh115.mesh"
                materials: [
                    principledMaterial116
                ]
            }
        }
        Node {
            id: plane_048_54
            objectName: "Plane.048_54"
            Node {
                id: _gltfNode_111
                objectName: "_gltfNode_111"
            }
            Node {
                id: _gltfNode_112
                objectName: "_gltfNode_112"
            }
        }
        Node {
            id: plane_050_55
            objectName: "Plane.050_55"
            Node {
                id: _gltfNode_114
                objectName: "_gltfNode_114"
            }
        }
        Node {
            id: plane_051_56
            objectName: "Plane.051_56"
            Node {
                id: _gltfNode_116
                objectName: "_gltfNode_116"
            }
        }
        Node {
            id: plane_052_57
            objectName: "Plane.052_57"
            Node {
                id: _gltfNode_118
                objectName: "_gltfNode_118"
            }
        }
        Node {
            id: plane_053_58
            objectName: "Plane.053_58"
            Node {
                id: _gltfNode_120
                objectName: "_gltfNode_120"
            }
        }
        Node {
            id: plane_054_59
            objectName: "Plane.054_59"
            Node {
                id: _gltfNode_122
                objectName: "_gltfNode_122"
            }
        }
        Node {
            id: plane_056_60
            objectName: "Plane.056_60"
            Model {
                id: _gltfNode_124
                objectName: "_gltfNode_124"
                source: "meshes/mesh_mesh132.mesh"
                materials: [
                    principledMaterial133
                ]
            }
        }
        Node {
            id: plane_059_61
            objectName: "Plane.059_61"
            Node {
                id: _gltfNode_126
                objectName: "_gltfNode_126"
            }
        }
        Node {
            id: plane_060_62
            objectName: "Plane.060_62"
            Node {
                id: _gltfNode_128
                objectName: "_gltfNode_128"
            }
        }
        Node {
            id: plane_062_63
            objectName: "Plane.062_63"
            Node {
                id: _gltfNode_130
                objectName: "_gltfNode_130"
            }
        }
        Node {
            id: plane_067_64
            objectName: "Plane.067_64"
            Node {
                id: _gltfNode_132
                objectName: "_gltfNode_132"
            }
        }
        Node {
            id: plane_074_65
            objectName: "Plane.074_65"
            Node {
                id: _gltfNode_134
                objectName: "_gltfNode_134"
            }
        }
        Node {
            id: plane_075_66
            objectName: "Plane.075_66"
            Node {
                id: _gltfNode_136
                objectName: "_gltfNode_136"
            }
        }
        Node {
            id: plane_079_67
            objectName: "Plane.079_67"
            Model {
                id: _gltfNode_138
                objectName: "_gltfNode_138"
                source: "meshes/mesh_mesh148.mesh"
                materials: [
                    principledMaterial116
                ]
            }
        }
        Node {
            id: plane_055_68
            objectName: "Plane.055_68"
            Node {
                id: _gltfNode_140
                objectName: "_gltfNode_140"
            }
        }
        Node {
            id: plane_057_69
            objectName: "Plane.057_69"
            Node {
                id: _gltfNode_142
                objectName: "_gltfNode_142"
            }
            Node {
                id: _gltfNode_143
                objectName: "_gltfNode_143"
            }
            Node {
                id: _gltfNode_144
                objectName: "_gltfNode_144"
            }
        }
        Node {
            id: plane_058_70
            objectName: "Plane.058_70"
            Node {
                id: _gltfNode_146
                objectName: "_gltfNode_146"
            }
        }
        Node {
            id: plane_061_71
            objectName: "Plane.061_71"
            Node {
                id: _gltfNode_148
                objectName: "_gltfNode_148"
            }
        }
        Node {
            id: plane_063_72
            objectName: "Plane.063_72"
            Node {
                id: _gltfNode_150
                objectName: "_gltfNode_150"
            }
        }
        Node {
            id: plane_064_73
            objectName: "Plane.064_73"
            Node {
                id: _gltfNode_152
                objectName: "_gltfNode_152"
            }
        }
        Node {
            id: plane_065_74
            objectName: "Plane.065_74"
            Node {
                id: _gltfNode_154
                objectName: "_gltfNode_154"
            }
        }
        Node {
            id: plane_066_75
            objectName: "Plane.066_75"
            Model {
                id: _gltfNode_156
                objectName: "_gltfNode_156"
                source: "meshes/mesh_mesh167.mesh"
                materials: [
                    principledMaterial116
                ]
            }
        }
        Node {
            id: plane_068_76
            objectName: "Plane.068_76"
            position: Qt.vector3d(0, 0, -1.4077)
            Node {
                id: _gltfNode_158
                objectName: "_gltfNode_158"
            }
            Node {
                id: _gltfNode_159
                objectName: "_gltfNode_159"
            }
            Node {
                id: _gltfNode_160
                objectName: "_gltfNode_160"
            }
        }
        Node {
            id: plane_069_77
            objectName: "Plane.069_77"
            position: Qt.vector3d(0, 0, -1.4077)
            Node {
                id: _gltfNode_162
                objectName: "_gltfNode_162"
            }
        }
        Node {
            id: plane_070_78
            objectName: "Plane.070_78"
            position: Qt.vector3d(0, 0, -1.4077)
            Node {
                id: _gltfNode_164
                objectName: "_gltfNode_164"
            }
        }
        Node {
            id: plane_071_79
            objectName: "Plane.071_79"
            position: Qt.vector3d(0, 0, -1.4077)
            Node {
                id: _gltfNode_166
                objectName: "_gltfNode_166"
            }
        }
        Node {
            id: plane_072_80
            objectName: "Plane.072_80"
            position: Qt.vector3d(0, 0, -1.4077)
            Node {
                id: _gltfNode_168
                objectName: "_gltfNode_168"
            }
        }
        Node {
            id: plane_073_81
            objectName: "Plane.073_81"
            position: Qt.vector3d(0, 0, -1.4077)
            Node {
                id: _gltfNode_170
                objectName: "_gltfNode_170"
            }
        }
        Node {
            id: plane_077_82
            objectName: "Plane.077_82"
            position: Qt.vector3d(0.058139, 0.847285, -0.216388)
            scale: Qt.vector3d(0.219277, 0.219277, 0.219277)
            Node {
                id: _gltfNode_172
                objectName: "_gltfNode_172"
            }
            Node {
                id: _gltfNode_173
                objectName: "_gltfNode_173"
            }
            Model {
                id: _gltfNode_174
                objectName: "_gltfNode_174"
                source: "meshes/mesh_mesh186.mesh"
                materials: [
                    principledMaterial187
                ]
            }
            Model {
                id: _gltfNode_175
                objectName: "_gltfNode_175"
                source: "meshes/mesh_mesh191.mesh"
                materials: [
                    principledMaterial
                ]
            }
        }
        Node {
            id: plane_078_83
            objectName: "Plane.078_83"
            position: Qt.vector3d(0.058139, 0.847285, -0.216388)
            scale: Qt.vector3d(0.219277, 0.219277, 0.219277)
            Node {
                id: _gltfNode_177
                objectName: "_gltfNode_177"
            }
            Node {
                id: _gltfNode_178
                objectName: "_gltfNode_178"
            }
        }
        Node {
            id: tire_003_84
            objectName: "Tire.003_84"
            Node {
                id: mesh_80
                objectName: "mesh_80"
            }
            Node {
                id: mesh_80198
                objectName: "mesh_80"
            }
            Node {
                id: mesh_80199
                objectName: "mesh_80"
            }
            Node {
                id: mesh_80200
                objectName: "mesh_80"
            }
        }
        Node {
            id: circle_88
            objectName: "Circle_88"
            position: Qt.vector3d(0, 0.177406, 0)
            scale: Qt.vector3d(0.791045, 0.791045, 0.791045)
            Node {
                id: _gltfNode_185
                objectName: "_gltfNode_185"
            }
            Node {
                id: _gltfNode_186
                objectName: "_gltfNode_186"
            }
        }
        Node {
            id: circle_001_89
            objectName: "Circle.001_89"
            position: Qt.vector3d(0, 0.177406, 0)
            rotation: Qt.quaternion(0, 1.62921e-07, 0, 1)
            scale: Qt.vector3d(-0.637798, -0.637798, -0.637798)
            Node {
                id: _gltfNode_188
                objectName: "_gltfNode_188"
            }
        }
        Node {
            id: circle_002_90
            objectName: "Circle.002_90"
            Node {
                id: _gltfNode_190
                objectName: "_gltfNode_190"
            }
        }
        Node {
            id: circle_003_91
            objectName: "Circle.003_91"
            Node {
                id: _gltfNode_192
                objectName: "_gltfNode_192"
            }
        }
        Node {
            id: interior1_01_158_001_96
            objectName: "interior1_01_158.001_96"
            position: Qt.vector3d(0.151407, 0.699741, -0.597671)
            scale: Qt.vector3d(0.00242062, 0.00247756, 0.00247756)
            Node {
                id: interior1_01_black_m1_0_157_001_95
                objectName: "interior1_01_black_m1_0_157.001_95"
                Node {
                    id: object_245_94
                    objectName: "Object_245_94"
                    Model {
                        id: _gltfNode_194
                        objectName: "_gltfNode_194"
                        source: "meshes/mesh_mesh214.mesh"
                        materials: [
                            principledMaterial187
                        ]
                    }
                    Model {
                        id: _gltfNode_195
                        objectName: "_gltfNode_195"
                        source: "meshes/mesh_mesh216.mesh"
                        materials: [
                            principledMaterial187
                        ]
                    }
                    Model {
                        id: _gltfNode_196
                        objectName: "_gltfNode_196"
                        source: "meshes/mesh_mesh218.mesh"
                        materials: [
                            principledMaterial
                        ]
                    }
                }
            }
        }
        Node {
            id: plane_101
            objectName: "Plane_101"
            position: Qt.vector3d(0, 0, 0.358361)
            scale: Qt.vector3d(1.48776, 1.48776, 1.48776)
            Node {
                id: _gltfNode_200
                objectName: "_gltfNode_200"
            }
        }
        Node {
            id: plane_080_102
            objectName: "Plane.080_102"
            Node {
                id: _gltfNode_202
                objectName: "_gltfNode_202"
            }
        }
        Node {
            id: rs6c8_diffuser_R_b_107
            objectName: "rs6c8_diffuser_R_b_107"
            rotation: Qt.quaternion(1, 0, 0, 0)
            scale: Qt.vector3d(1.47006, 1.47006, 1.47006)
            Node {
                id: _gltfNode_204
                objectName: "_gltfNode_204"
            }
            Node {
                id: _gltfNode_205
                objectName: "_gltfNode_205"
            }
            Node {
                id: _gltfNode_206
                objectName: "_gltfNode_206"
            }
        }
        Node {
            id: wheel_disl_002_124
            objectName: "Wheel disl.002_124"
            Node {
                id: _gltfNode_208
                objectName: "_gltfNode_208"
            }
            Node {
                id: _gltfNode_209
                objectName: "_gltfNode_209"
            }
            Node {
                id: _gltfNode_210
                objectName: "_gltfNode_210"
            }
            Node {
                id: _gltfNode_211
                objectName: "_gltfNode_211"
            }
            Node {
                id: _gltfNode_212
                objectName: "_gltfNode_212"
            }
            Node {
                id: _gltfNode_213
                objectName: "_gltfNode_213"
            }
            Node {
                id: _gltfNode_214
                objectName: "_gltfNode_214"
            }
        }
        Node {
            id: plane_049_125
            objectName: "Plane.049_125"
            position: Qt.vector3d(0, -0.300169, 0)
            rotation: Qt.quaternion(-2.8213e-07, 0, 1, 0.000787245)
            Node {
                id: _gltfNode_216
                objectName: "_gltfNode_216"
            }
            Node {
                id: _gltfNode_217
                objectName: "_gltfNode_217"
            }
        }
        Node {
            id: car_seat_126
            objectName: "Car seat_126"
            position: Qt.vector3d(0.00459259, -0.210882, 0.675163)
            scale: Qt.vector3d(0.957344, 0.984588, 0.984588)
            Node {
                id: _gltfNode_219
                objectName: "_gltfNode_219"
            }
            Node {
                id: _gltfNode_220
                objectName: "_gltfNode_220"
            }
            Node {
                id: _gltfNode_221
                objectName: "_gltfNode_221"
            }
        }
        Node {
            id: car_seat_003_127
            objectName: "Car seat.003_127"
            position: Qt.vector3d(0.416888, 0.432703, 0.627754)
            scale: Qt.vector3d(0.957344, 0.984588, 0.984588)
            Node {
                id: _gltfNode_223
                objectName: "_gltfNode_223"
            }
            Node {
                id: _gltfNode_224
                objectName: "_gltfNode_224"
            }
        }
        Node {
            id: plane_003_128
            objectName: "Plane.003_128"
            position: Qt.vector3d(0.0353756, 0.131811, 0.201836)
            scale: Qt.vector3d(1.4703, 1.4281, 1.35936)
            Node {
                id: _gltfNode_226
                objectName: "_gltfNode_226"
            }
            Node {
                id: _gltfNode_227
                objectName: "_gltfNode_227"
            }
        }
        Node {
            id: plane_106_129
            objectName: "Plane.106_129"
            position: Qt.vector3d(1.23707, 3.88459, -2.5767)
            scale: Qt.vector3d(1.4703, 1.4281, 1.35936)
            Node {
                id: _gltfNode_229
                objectName: "_gltfNode_229"
            }
            Node {
                id: _gltfNode_230
                objectName: "_gltfNode_230"
            }
        }
        Node {
            id: tail_seats_001_130
            objectName: "Tail seats.001_130"
            position: Qt.vector3d(0.0353756, 0.131811, 0.201836)
            scale: Qt.vector3d(2.20434, 2.14107, 2.038)
            Node {
                id: _gltfNode_232
                objectName: "_gltfNode_232"
            }
            Node {
                id: _gltfNode_233
                objectName: "_gltfNode_233"
            }
            Node {
                id: _gltfNode_234
                objectName: "_gltfNode_234"
            }
        }
        Node {
            id: tail_seats_002_131
            objectName: "Tail seats.002_131"
            position: Qt.vector3d(0.0353756, 0.131811, 0.201836)
            scale: Qt.vector3d(2.20434, 2.14107, 2.038)
            Node {
                id: _gltfNode_236
                objectName: "_gltfNode_236"
            }
            Node {
                id: _gltfNode_237
                objectName: "_gltfNode_237"
            }
        }
        Node {
            id: tail_seats_006_132
            objectName: "Tail seats.006_132"
            position: Qt.vector3d(0.0353756, 0.774769, -1.12148)
            scale: Qt.vector3d(2.20434, 2.14107, 2.038)
            Node {
                id: _gltfNode_239
                objectName: "_gltfNode_239"
            }
            Node {
                id: _gltfNode_240
                objectName: "_gltfNode_240"
            }
        }
        Node {
            id: tail_seats_007_133
            objectName: "Tail seats.007_133"
            position: Qt.vector3d(0.0353756, 0.131811, 0.201836)
            scale: Qt.vector3d(2.20434, 2.14107, 2.038)
            Node {
                id: _gltfNode_242
                objectName: "_gltfNode_242"
            }
            Node {
                id: _gltfNode_243
                objectName: "_gltfNode_243"
            }
        }
        Node {
            id: tail_seats_008_134
            objectName: "Tail seats.008_134"
            position: Qt.vector3d(0.0353756, 0.131811, 0.201836)
            scale: Qt.vector3d(2.20434, 2.14107, 2.038)
            Node {
                id: _gltfNode_245
                objectName: "_gltfNode_245"
            }
        }
        Node {
            id: tail_seats_009_135
            objectName: "Tail seats.009_135"
            position: Qt.vector3d(0.0353756, 0.774769, -1.12148)
            scale: Qt.vector3d(2.20434, 2.14107, 2.038)
            Node {
                id: _gltfNode_247
                objectName: "_gltfNode_247"
            }
        }
        Node {
            id: tail_seats_011_136
            objectName: "Tail seats.011_136"
            position: Qt.vector3d(0.00459259, -0.210882, 0.675163)
            scale: Qt.vector3d(1.43529, 1.47613, 1.47613)
            Node {
                id: _gltfNode_249
                objectName: "_gltfNode_249"
            }
        }
        Node {
            id: tail_seats_012_137
            objectName: "Tail seats.012_137"
            position: Qt.vector3d(0.00459259, -0.210882, 0.675163)
            scale: Qt.vector3d(1.43529, 1.47613, 1.47613)
            Node {
                id: _gltfNode_251
                objectName: "_gltfNode_251"
            }
        }
    }

    // Animations:
}
