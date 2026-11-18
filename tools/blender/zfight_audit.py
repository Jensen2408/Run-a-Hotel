"""
Z-fighting audit for a kit .blend (qa-review): finds faces from DIFFERENT
mesh islands (originally separate parts) that face the same way, lie within
`EPS` studs of the same plane and overlap - they flicker in game.

  blender --background --python tools/blender/zfight_audit.py -- <file.blend> [name_filter]

Prints one line per overlapping pair group: objects, colours, location
(Roblox axes, building-local) and overlap size.
"""

import sys
from collections import defaultdict

import bmesh
import bpy
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1 :]
PATH = ARGS[0]
FILTER = ARGS[1] if len(ARGS) > 1 else "SM_"
EPS = 0.04  # studs between planes that still z-fight at distance
MIN_OVERLAP = 0.03
ALL = "--all" in ARGS  # also same-colour and downward pairs

bpy.ops.wm.open_mainfile(filepath=PATH)

faces = []  # (obj, island, normal, d, lo, hi, colour, centre)
for o in bpy.data.objects:
    if o.type != "MESH" or not o.name.startswith(FILTER) or "Door" in o.name:
        continue
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.transform(o.matrix_world)
    col = bm.loops.layers.float_color.get("Col")
    # islands (connected parts) via union-find over shared vertices
    parent = list(range(len(bm.verts)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for e in bm.edges:
        a, b = find(e.verts[0].index), find(e.verts[1].index)
        if a != b:
            parent[a] = b
    for f in bm.faces:
        if f.calc_area() < 0.02:
            continue
        n = f.normal.normalized()
        c = f.calc_center_median()
        lo = Vector((min(v.co.x for v in f.verts), min(v.co.y for v in f.verts), min(v.co.z for v in f.verts)))
        hi = Vector((max(v.co.x for v in f.verts), max(v.co.y for v in f.verts), max(v.co.z for v in f.verts)))
        colour = tuple(round(x, 2) for x in f.loops[0][col][:3]) if col else (0, 0, 0)
        faces.append((o.name, find(f.verts[0].index), n, n.dot(c), lo, hi, colour, c))
    bm.free()

buckets = defaultdict(list)
for i, f in enumerate(faces):
    n = f[2]
    key = (round(n.x, 1), round(n.y, 1), round(n.z, 1), int(round(f[3] / EPS)))
    buckets[key].append(i)

pairs = {}
for key, idxs in buckets.items():
    neigh = []
    for dk in (-1, 0, 1):
        neigh += buckets.get((key[0], key[1], key[2], key[3] + dk), [])
    for i in idxs:
        fi = faces[i]
        for j in neigh:
            if j <= i:
                continue
            fj = faces[j]
            if fi[0] == fj[0] and fi[1] == fj[1]:
                continue  # same part
            if fi[2].dot(fj[2]) < 0.995 or abs(fi[3] - fj[3]) > EPS:
                continue
            if fi[6] == fj[6] and not ALL:
                continue  # same colour: no visible flicker
            if fi[2].z < -0.9 and not ALL:
                continue  # downward faces on the ground / under the roof: never seen
            ov = [min(fi[5][k], fj[5][k]) - max(fi[4][k], fj[4][k]) for k in range(3)]
            # overlap must have area in the face plane (two axes > threshold)
            if sum(1 for x in ov if x > MIN_OVERLAP) < 2 or min(ov) < -0.001:
                continue
            c = (fi[7] + fj[7]) / 2
            loc = (round(c.x, 1), round(c.z, 1), round(-c.y, 1))
            k = (fi[0], fj[0], fi[6], fj[6], (round(loc[0]), round(loc[1]), round(loc[2])))
            pairs.setdefault(k, (loc, ov, tuple(round(x, 2) for x in fi[2])))

print(f"[zfight] {len(pairs)} overlapping coplanar groups in {PATH}")
for (a, b, ca, cb, _), (loc, ov, nrm) in sorted(pairs.items(), key=lambda kv: kv[1][0]):
    same = "same colour" if ca == cb else "DIFFERENT colour"
    print(f"  {a} x {b}  at {loc}  ({same}) normal {nrm} overlap {tuple(round(x, 2) for x in ov)}")
