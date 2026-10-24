#!/usr/bin/env python3
"""Запекание иерархии glTF: мировые трансформации → вершины.

Выход: glb с ОДНИМ узлом и одной mesh-группой (примитивы по материалам),
все координаты уже в мире — никакой иерархии масштабов, с чем бы импортёр
или balsam ни путались.
"""
import json, struct, sys
import numpy as np

GLB_MAGIC=0x46546C67; CHUNK_JSON=0x4E4F534A; CHUNK_BIN=0x004E4942
COMP={5121:np.uint8,5123:np.uint16,5125:np.uint32,5126:np.float32}
COMP_GL={np.uint8:5121,np.uint16:5123,np.uint32:5125,np.float32:5126}
NCOMP={"SCALAR":1,"VEC2":2,"VEC3":3,"VEC4":4}

def read_glb(path):
    with open(path,"rb") as f:
        magic,version,total=struct.unpack("<III",f.read(12))
        gltf=None; binary=b""
        while f.tell()<total:
            length,ctype=struct.unpack("<II",f.read(8)); data=f.read(length)
            if ctype==CHUNK_JSON: gltf=json.loads(data)
            elif ctype==CHUNK_BIN: binary=data
    return gltf,binary

def acc(gltf,binary,index):
    a=gltf["accessors"][index]; v=gltf["bufferViews"][a["bufferView"]]
    dt=COMP[a["componentType"]]; nc=NCOMP[a["type"]]
    item=np.dtype(dt).itemsize
    stride=v.get("byteStride",nc*item)
    start=v.get("byteOffset",0)+a.get("byteOffset",0)
    if stride==nc*item:
        raw=np.frombuffer(binary,dtype=dt,count=a["count"]*nc,offset=start)
        arr=raw.reshape(a["count"],nc) if nc>1 else raw
    else:
        raw=np.frombuffer(binary,dtype=np.uint8,count=(a["count"]-1)*stride+nc*item,offset=start)
        rows=np.lib.stride_tricks.as_strided(raw,shape=(a["count"],nc*item),strides=(stride,1))
        arr=rows.copy().view(dt).reshape(a["count"],nc) if nc>1 else rows.copy().view(dt).ravel()
    return np.array(arr,dtype=np.float64 if dt is np.float32 else dt)

def node_matrix(n):
    if "matrix" in n: return np.array(n["matrix"],dtype=float).reshape(4,4).T
    t=np.eye(4)
    if "translation" in n: t[:3,3]=n["translation"]
    if "rotation" in n:
        x,y,z,w=n["rotation"]
        t[:3,:3]=[[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],
                  [2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],
                  [2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]]
    if "scale" in n:
        s=np.eye(4); s[0,0],s[1,1],s[2,2]=n["scale"]; t=t@s
    return t

def tri_indices(prim,gltf,binary):
    if "indices" in prim:
        idx=acc(gltf,binary,prim["indices"]).astype(np.int64)
    else:
        idx=np.arange(gltf["accessors"][prim["attributes"]["POSITION"]]["count"],dtype=np.int64)
    mode=prim.get("mode",4)
    if mode==4: return idx.reshape(-1,3)
    if mode==5:
        a=idx[:-2]; b=idx[1:-1]; c=idx[2:]
        even=np.arange(a.size)%2==0
        return np.stack([a,np.where(even,b,c),np.where(even,c,b)],axis=1)
    if mode==6:
        return np.stack([np.full(idx.size-2,idx[0]),idx[1:-1],idx[2:]],axis=1)
    return None

def main(src,dst):
    gltf,binary=read_glb(src)
    # собираем мировые вершины по материалам
    per_mat={}   # mat_idx -> list of (pos,nrm,uv,tris)
    def walk(ni,M):
        n=gltf["nodes"][ni]; M=M@node_matrix(n)
        if "mesh" in n:
            for p in gltf["meshes"][n["mesh"]]["primitives"]:
                tris=tri_indices(p,gltf,binary)
                if tris is None or tris.size==0: continue
                pos=acc(gltf,binary,p["attributes"]["POSITION"]).astype(np.float64)
                w=(M@np.c_[pos,np.ones(len(pos))].T).T[:,:3]
                nrm=None
                if "NORMAL" in p["attributes"]:
                    nr=acc(gltf,binary,p["attributes"]["NORMAL"]).astype(np.float64)
                    # нормали вращаются матрицей (без учёта неравномерного масштаба — ок для дисплея)
                    nrm=(M[:3,:3]@nr.T).T
                    l=np.linalg.norm(nrm,axis=1,keepdims=True); l[l==0]=1; nrm/=l
                uv=acc(gltf,binary,p["attributes"]["TEXCOORD_0"]).astype(np.float32) if "TEXCOORD_0" in p["attributes"] else None
                mat=p.get("material",-1)
                per_mat.setdefault(mat,[]).append((w,nrm,uv,tris))
        for c in n.get("children",[]): walk(c,M)
    for r in gltf["scenes"][gltf.get("scene",0)]["nodes"]: walk(r,np.eye(4))

    new_bin=bytearray(); views=[]; accessors=[]
    def add_view(data):
        while len(new_bin)%4: new_bin.append(0)
        off=len(new_bin); new_bin.extend(data)
        views.append({"buffer":0,"byteOffset":off,"byteLength":len(data)})
        return len(views)-1
    def add_acc(arr,tn,bounds=False):
        v=add_view(np.asarray(arr).tobytes())
        a={"bufferView":v,"componentType":COMP_GL[arr.dtype.type],"count":int(arr.shape[0]),"type":tn}
        if bounds: a["min"]=arr.min(axis=0).tolist(); a["max"]=arr.max(axis=0).tolist()
        accessors.append(a); return len(accessors)-1

    # выравниваем tiling по индексам: каждая примитива — свой буфер вершин
    prims_out=[]
    for mat,parts in per_mat.items():
        pos=np.concatenate([p[0] for p in parts]).astype(np.float32)
        uv=np.concatenate([p[2] for p in parts]).astype(np.float32) if all(p[2] is not None for p in parts) else None
        base=0; idxs=[]
        for (pw,pn,pu,pt) in parts:
            idxs.append(pt+base); base+=len(pw)
        flat=np.concatenate(idxs).reshape(-1)
        out={"attributes":{"POSITION":add_acc(pos,"VEC3",True)},"mode":4}
        if uv is not None: out["attributes"]["TEXCOORD_0"]=add_acc(uv,"VEC2")
        nrm=np.concatenate([p[1] for p in parts]).astype(np.float32) if all(p[1] is not None for p in parts) else None
        if nrm is not None: out["attributes"]["NORMAL"]=add_acc(nrm,"VEC3")
        if mat>=0: out["material"]=mat
        out["indices"]=add_acc(flat.astype(np.uint32),"SCALAR")
        prims_out.append(out)

    out={"asset":{"version":"2.0","generator":"dash-bake"},"scene":0,"scenes":[{"nodes":[0]}],
         "nodes":[{"mesh":0}],
         "meshes":[{"primitives":prims_out}],
         "materials":gltf.get("materials",[]),
         "accessors":accessors,"bufferViews":views}
    # Изображения переписываем на новые bufferView: старые индексы в новом
    # файле указывают на чужие данные, и текстура получается мусором
    # (проверено: balsam выгружал float-данные вместо WebP → плоская машина).
    if "images" in gltf:
        images=[]
        for image in gltf["images"]:
            view=gltf["bufferViews"][image["bufferView"]]
            start=view.get("byteOffset",0)
            data=binary[start:start+view["byteLength"]]
            image=dict(image)
            image["bufferView"]=add_view(bytes(data))
            images.append(image)
        out["images"]=images
    if "textures" in gltf: out["textures"]=gltf["textures"]
    if "samplers" in gltf: out["samplers"]=gltf["samplers"]
    while len(new_bin)%4: new_bin.append(0)
    out["buffers"]=[{"byteLength":len(new_bin)}]
    jsonb=json.dumps(out,separators=(",",":")).encode()
    while len(jsonb)%4: jsonb+=b" "
    total=12+8+len(jsonb)+8+len(new_bin)
    with open(dst,"wb") as f:
        f.write(struct.pack("<III",GLB_MAGIC,2,total))
        f.write(struct.pack("<II",len(jsonb),CHUNK_JSON)); f.write(jsonb)
        f.write(struct.pack("<II",len(new_bin),CHUNK_BIN)); f.write(bytes(new_bin))
    print("baked ->", dst)

if __name__=="__main__":
    main(sys.argv[1],sys.argv[2])
