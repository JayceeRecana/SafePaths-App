"""Build the original SafePaths low-poly sedan, without third-party assets.

glTF coordinates: X right, Y up, -Z forward. Dimensions in metres.
Run from the repository root; writes a self-contained GLB (no textures/URLs).
"""
import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
materials = [
    ('SafePaths blue', [0.004, 0.18, 0.55, 1], 0.18, 0.36),
    ('Roof blue', [0.012, 0.28, 0.72, 1], 0.12, 0.38),
    ('Dark blue glass', [0.022, 0.065, 0.12, 1], 0.25, 0.22),
    ('Tyres', [0.018, 0.023, 0.033, 1], 0, 0.9),
    ('Silver trim', [0.55, 0.63, 0.72, 1], 0.65, 0.3),
    ('Headlights', [0.92, 0.97, 1, 1], 0, 0.4),
    ('Tail lights', [0.9, 0.025, 0.025, 1], 0, 0.45),
]
faces = [[] for _ in materials]


def face(points, mat):
    a, b, c = points[:3]
    u = [b[i] - a[i] for i in range(3)]
    v = [c[i] - a[i] for i in range(3)]
    n = [u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0]]
    size = math.sqrt(sum(x*x for x in n))
    n = [x/size for x in n]
    for j in range(1, len(points)-1):
        for p in [points[0], points[j], points[j+1]]:
            faces[mat].append((p, n))


def box(x0, x1, y0, y1, z0, z1, mat):
    face([(x0,y0,z0),(x0,y0,z1),(x0,y1,z1),(x0,y1,z0)], mat)
    face([(x1,y0,z1),(x1,y0,z0),(x1,y1,z0),(x1,y1,z1)], mat)
    face([(x0,y0,z1),(x0,y0,z0),(x1,y0,z0),(x1,y0,z1)], mat)
    face([(x0,y1,z0),(x0,y1,z1),(x1,y1,z1),(x1,y1,z0)], mat)
    face([(x1,y0,z0),(x0,y0,z0),(x0,y1,z0),(x1,y1,z0)], mat)
    face([(x0,y0,z1),(x1,y0,z1),(x1,y1,z1),(x0,y1,z1)], mat)


def wheel(x0, x1, z, radius, mat):
    # Axis along X, twelve-sided cylinders; outward winding on both ends.
    ring = [(0.36 + radius*math.cos(i*math.tau/12), z + radius*math.sin(i*math.tau/12)) for i in range(12)]
    face([(x0,y,zz) for y,zz in reversed(ring)], mat)
    face([(x1,y,zz) for y,zz in ring], mat)
    for i in range(12):
        a,b = ring[i], ring[(i+1)%12]
        face([(x0,*a),(x0,*b),(x1,*b),(x1,*a)], mat)


# A compact sedan with long bonnet and clearly distinguishable front/rear.
box(-0.86,0.86,0.33,0.72,-2.05,2.05,0)
box(-0.84,0.84,0.72,0.87,-1.93,1.92,1)
# Cabin: trapezoidal cross-section with sloped windscreen and rear window.
lf=(-0.8,0.87,-0.92); rf=(0.8,0.87,-0.92)
lr=(-0.8,0.87,1.25); rr=(0.8,0.87,1.25)
tlf=(-0.65,1.48,-0.42); trf=(0.65,1.48,-0.42)
tlr=(-0.65,1.48,0.72); trr=(0.65,1.48,0.72)
face([lf,tlf,trf,rf],2)
face([lr,rr,trr,tlr],2)
face([lf,lr,tlr,tlf],2)
face([rf,trf,trr,rr],2)
face([tlf,tlr,trr,trf],1)
# Window pillars, body belt, mirrors, bumpers and lamps.
box(-0.815,-0.775,0.87,1.43,0.12,0.21,0)
box(0.775,0.815,0.87,1.43,0.12,0.21,0)
box(-1.01,-0.80,0.93,1.07,-0.63,-0.38,0)
box(0.80,1.01,0.93,1.07,-0.63,-0.38,0)
box(-0.79,0.79,0.39,0.51,-2.09,-2.05,4)
box(-0.79,0.79,0.39,0.51,2.05,2.09,4)
for x0,x1 in [(-0.77,-0.38),(0.38,0.77)]:
    box(x0,x1,0.61,0.76,-2.075,-2.055,5)
    box(x0,x1,0.60,0.76,2.055,2.075,6)
for z in [-1.28,1.28]:
    wheel(-0.96,-0.78,z,0.34,3)
    wheel(0.78,0.96,z,0.34,3)
    wheel(-0.969,-0.961,z,0.18,4)
    wheel(0.961,0.969,z,0.18,4)

binary = bytearray()
views = []
accessors = []
primitives = []


def attribute(values, minimum=None, maximum=None):
    offset = len(binary)
    for v in values:
        binary.extend(struct.pack('<3f', *v))
    view = len(views)
    views.append({'buffer':0,'byteOffset':offset,'byteLength':len(binary)-offset,'target':34962})
    result = {'bufferView':view,'componentType':5126,'count':len(values),'type':'VEC3'}
    if minimum is not None:
        result.update(min=minimum,max=maximum)
    accessors.append(result)
    return len(accessors)-1


for mat, vertices in enumerate(faces):
    positions = [p for p,n in vertices]
    normals = [n for p,n in vertices]
    low = [min(p[i] for p in positions) for i in range(3)]
    high = [max(p[i] for p in positions) for i in range(3)]
    primitives.append({'attributes':{'POSITION':attribute(positions,low,high),'NORMAL':attribute(normals)},'material':mat,'mode':4})

gltf = {
    'asset':{'version':'2.0','generator':'SafePaths original procedural sedan v1',
             'copyright':'SafePaths project original asset; no third-party model content'},
    'scene':0,'scenes':[{'nodes':[0]}],
    'nodes':[{'mesh':0,'name':'SafePaths sedan - front negative Z'}],
    'meshes':[{'primitives':primitives}],
    'materials':[{'name':name,'pbrMetallicRoughness':{'baseColorFactor':color,'metallicFactor':metal,'roughnessFactor':rough}} for name,color,metal,rough in materials],
    'buffers':[{'byteLength':len(binary)}], 'bufferViews':views,'accessors':accessors,
}
encoded = json.dumps(gltf,separators=(',',':')).encode()
encoded += b' ' * (-len(encoded)%4)
binary += b'\0' * (-len(binary)%4)
data = struct.pack('<III',0x46546C67,2,12+8+len(encoded)+8+len(binary))
data += struct.pack('<II',len(encoded),0x4E4F534A)+encoded
data += struct.pack('<II',len(binary),0x004E4942)+binary
out = ROOT/'assets/navigation/safepaths-sedan-v1.glb'
out.parent.mkdir(parents=True,exist_ok=True)
out.write_bytes(data)
print(f'{out.name}: {len(data)} bytes; {sum(len(v)//3 for v in faces)} triangles')
