"""
Motel kit: cartoon 3D props for Run a Motel, built in Blender per object.

Run headless (one batch at a time):
  blender --background --factory-startup --python tools/blender/motel_kit.py -- <repo_root> <batch>

Outputs (assets/models/kit/):
  motel_kit_<batch>.fbx        every object of the batch as its own mesh (Y-up)
  motel_kit_<batch>.json       manifest: per mesh, size and centre offset in studs
  previews/motel_kit_<batch>.png  contact sheet of the batch

Conventions
  * 1 Blender unit = 1 stud. Sizes match the parts the map uses today
    (scale-1 numbers from MapBuilder / MapDecor).
  * Each object's origin is its placement point: ground/base centre unless
    noted. Roblox: +Y up, the object's "front" faces -Z (Blender +Y).
  * Colours live in a corner colour attribute "Col" with baked cartoon
    shading (top faces lighter, undersides darker).
  * TINT meshes use light neutral shading instead, so the game can colour
    them with MeshPart.Color (bed sheet dirty/clean, door colours, autumn
    canopies, broken AC...). Their manifest entry has "tint": true.
  * The manifest "center" is the mesh bounding-box centre relative to the
    origin, in Roblox axes, so code can place the MeshPart (whose pivot is
    its box centre) exactly where the old parts were.
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

ARGS = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
ROOT = ARGS[0] if ARGS else os.getcwd()
BATCH = ARGS[1] if len(ARGS) > 1 else "batch1"
OUT = os.path.join(ROOT, "assets", "models", "kit")
os.makedirs(os.path.join(OUT, "previews"), exist_ok=True)


# ---------------------------------------------------------------- colour helpers
def srgb(r, g, b):
    def lin(c):
        c /= 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    return (lin(r), lin(g), lin(b), 1.0)


def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(4))


def scale_col(c, k):
    return (min(1.0, c[0] * k), min(1.0, c[1] * k), min(1.0, c[2] * k), 1.0)


# Palette (from the reference art).
WOOD = srgb(176, 116, 70)
WOOD_DARK = srgb(116, 72, 44)
WOOD_LIGHT = srgb(214, 160, 104)
CREAM = srgb(250, 242, 222)
WHITE = srgb(245, 245, 240)
TEAL = srgb(56, 140, 132)
RED = srgb(206, 64, 52)
METAL_DARK = srgb(46, 50, 58)
METAL = srgb(150, 156, 166)
BRASS = srgb(230, 184, 80)
LAMP_GLOW = srgb(255, 226, 150)
TERRACOTTA = srgb(206, 112, 70)
LEAF = srgb(72, 150, 72)
LEAF_LIGHT = srgb(126, 196, 92)
BARK = srgb(124, 82, 52)
BLACK_BAG = srgb(44, 44, 50)
NEUTRAL = srgb(255, 255, 255)  # TINT meshes: tinted in game
FLOWERS = [srgb(255, 110, 140), srgb(255, 214, 80), srgb(250, 250, 250), srgb(190, 130, 255)]

# ---------------------------------------------------------------- scene
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
collection = scene.collection


def _apply_all(obj):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    for mod in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.select_set(False)


def _finish(obj, colour, bevel=0.0, segments=2, smooth=True, tint=False):
    """Bevel, colour fill with baked shading, smooth shading."""
    if bevel > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = segments
        mod.limit_method = "ANGLE"
        mod.harden_normals = False
        _apply_all(obj)
    mesh = obj.data
    attr = mesh.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    for poly in mesh.polygons:
        up = poly.normal.z
        if tint:
            k = 0.86 + 0.14 * max(0.0, up) if up > -0.3 else 0.72
        else:
            k = 0.88 + 0.22 * max(0.0, up) if up > -0.3 else 0.68
        c = scale_col(colour, k)
        for li in poly.loop_indices:
            attr.data[li].color = c
        poly.use_smooth = smooth
    return obj


def box(size, loc, colour, bevel=0.08, rot=(0, 0, 0), tint=False, segments=2):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    obj = bpy.context.active_object
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return _finish(obj, colour, bevel=min(bevel, min(size) * 0.45), segments=segments, smooth=False, tint=tint)


def cyl(radius, depth, loc, colour, verts=16, bevel=0.06, rot=(0, 0, 0), tint=False, radius2=None):
    if radius2 is not None:
        bpy.ops.mesh.primitive_cone_add(
            vertices=verts, radius1=radius, radius2=radius2, depth=depth, location=loc, rotation=rot
        )
    else:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=loc, rotation=rot)
    obj = bpy.context.active_object
    return _finish(obj, colour, bevel=min(bevel, radius * 0.4, depth * 0.4), smooth=True, tint=tint)


def ball(radius, loc, colour, squash=(1, 1, 1), segs=14, rings=9, tint=False):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segs, ring_count=rings, radius=radius, location=loc)
    obj = bpy.context.active_object
    obj.scale = squash
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return _finish(obj, colour, smooth=True, tint=tint)


def join(name, parts):
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    if len(parts) > 1:
        bpy.ops.object.join()
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name
    obj.select_set(False)
    return obj


# ---------------------------------------------------------------- objects
# Each builder returns { meshName: (object, tint) } built around the origin.
# Blender axes: X right, -Y = Roblox +Z (back), +Y = Roblox -Z (front), Z up.


def build_bed():
    """Bed 5 x 1.6 x 7 (hitbox y 0.4..2.0), headboard at the back (Roblox +Z)."""
    L, W = 7.0, 5.0
    frame = [
        box((W + 0.2, L + 0.2, 0.7), (0, 0, 0.75), WOOD, bevel=0.15),
        box((W + 0.6, 0.45, 3.4), (0, -(L / 2 + 0.55), 1.9), WOOD_DARK, bevel=0.2),  # headboard
        box((W + 0.2, 0.35, 1.3), (0, L / 2 + 0.05, 0.85), WOOD_DARK, bevel=0.12),  # footboard
    ]
    for x in (-W / 2 + 0.25, W / 2 - 0.25):
        for y in (-L / 2 + 0.25, L / 2 - 0.25):
            frame.append(cyl(0.22, 0.6, (x, y, 0.3), WOOD_DARK, verts=10))
    sheet = box((W - 0.1, L - 0.3, 0.8), (0, -0.1, 1.45), NEUTRAL, bevel=0.3, segments=3, tint=True)
    blanket = box((W + 0.05, 3.7, 0.28), (0, L / 2 - 2.0, 1.95), NEUTRAL, bevel=0.12, tint=True)
    pillows = [
        ball(1.0, (x, -(L / 2) + 1.0, 2.0), WHITE, squash=(1.0, 0.6, 0.32), segs=16, rings=8) for x in (-1.2, 1.2)
    ]
    return {
        "BedFrame": (join("BedFrame", frame), False),
        "BedSheet": (join("BedSheet", [sheet]), True),
        "BedBlanket": (join("BedBlanket", [blanket]), True),
        "BedPillows": (join("BedPillows", pillows), False),
    }


def build_nightstand():
    parts = [
        box((1.8, 1.8, 1.9), (0, 0, 1.0), WOOD, bevel=0.15),
        box((1.5, 0.08, 0.6), (0, 0.92, 1.25), WOOD_LIGHT, bevel=0.03),
        ball(0.12, (0, 0.98, 1.25), BRASS, segs=8, rings=6),
    ]
    for x in (-0.7, 0.7):
        for y in (-0.7, 0.7):
            parts.append(cyl(0.12, 0.1, (x, y, 0.05), WOOD_DARK, verts=8))
    lamp = [
        cyl(0.35, 0.2, (0, 0, 2.05), BRASS, verts=14),
        cyl(0.08, 0.8, (0, 0, 2.5), BRASS, verts=8),
        cyl(0.6, 0.75, (0, 0, 3.15), LAMP_GLOW, verts=16, radius2=0.38),
    ]
    return {"Nightstand": (join("Nightstand", parts), False), "BedsideLamp": (join("BedsideLamp", lamp), False)}


def build_door():
    """Room door 3.8 wide x 6.8 tall x 0.3 (hinge side at origin x = -1.9), tinted per room."""
    w, h, t = 3.8, 6.8, 0.3
    door = [box((w, t, h), (0, 0, h / 2), NEUTRAL, bevel=0.06, tint=True)]
    for z in (h * 0.3, h * 0.72):
        for side in (-1, 1):
            door.append(box((w * 0.7, 0.06, h * 0.32), (0, side * (t / 2 + 0.02), z), NEUTRAL, bevel=0.03, tint=True))
    knob = [ball(0.16, (w / 2 - 0.4, s * 0.25, h * 0.48), BRASS, segs=10, rings=7) for s in (-1, 1)]
    frame = [
        box((0.5, 0.45, 7.4), (-2.2, 0, 3.7), TEAL, bevel=0.06),
        box((0.5, 0.45, 7.4), (2.2, 0, 3.7), TEAL, bevel=0.06),
        box((4.9, 0.45, 0.5), (0, 0, 7.2), TEAL, bevel=0.06),
    ]
    return {
        "RoomDoor": (join("RoomDoor", door), True),
        "DoorKnobs": (join("DoorKnobs", knob), False),
        "DoorFrame": (join("DoorFrame", frame), False),
    }


def build_ac():
    """Window AC 4 x 2 x 1, centred (origin at its centre); body tinted (red when broken)."""
    body = [box((4.0, 1.0, 2.0), (0, 0, 0), NEUTRAL, bevel=0.15, tint=True)]
    grille = []
    for i in range(6):
        grille.append(box((2.2, 0.08, 0.12), (-0.7, 0.52, -0.65 + i * 0.26), METAL_DARK, bevel=0.02))
    grille.append(cyl(0.5, 0.08, (1.2, 0.52, 0.1), METAL, verts=16, rot=(math.pi / 2, 0, 0)))
    grille.append(box((0.6, 0.08, 0.25), (1.2, 0.52, -0.65), srgb(80, 200, 120), bevel=0.03))
    return {"ACUnit": (join("ACUnit", body), True), "ACGrille": (join("ACGrille", grille), False)}


def build_trash():
    bin_parts = [
        cyl(1.05, 2.6, (0, 0, 1.3), srgb(90, 150, 210), verts=18, radius2=1.15),
        cyl(1.22, 0.3, (0, 0, 2.7), srgb(70, 120, 180), verts=18),
        box((0.9, 0.3, 0.18), (0, 0, 2.95), srgb(70, 120, 180), bevel=0.06),
        box((0.5, 0.5, 0.1), (0, 1.1, 0.08), METAL_DARK, bevel=0.03),
    ]
    bag = [
        ball(0.9, (0, 0, 0.75), BLACK_BAG, squash=(1.0, 1.0, 0.9), segs=14, rings=9),
        cyl(0.25, 0.4, (0, 0, 1.55), BLACK_BAG, verts=10, radius2=0.12),
        ball(0.18, (0.12, 0, 1.78), BLACK_BAG, squash=(1.4, 0.6, 0.6), segs=8, rings=6),
    ]
    return {"TrashBin": (join("TrashBin", bin_parts), False), "TrashBag": (join("TrashBag", bag), False)}


def build_desk():
    """Front desk 10 x 3 x 2 (origin at floor centre); guests stand at the front (Roblox -Z)."""
    parts = [
        box((10.0, 2.0, 2.6), (0, 0, 1.3), WOOD, bevel=0.12),
        box((10.6, 2.5, 0.35), (0, 0.1, 2.75), WOOD_DARK, bevel=0.1),  # counter top overhang
        box((10.0, 0.25, 0.4), (0, 1.05, 0.2), WOOD_DARK, bevel=0.06),  # kick plate
    ]
    for x in (-3.5, 0, 3.5):
        parts.append(box((2.8, 0.1, 1.6), (x, 1.04, 1.35), WOOD_LIGHT, bevel=0.06))
    bell = [
        cyl(0.42, 0.12, (0, 0, 0.06), METAL_DARK, verts=14),
        ball(0.36, (0, 0, 0.14), BRASS, squash=(1, 1, 0.75), segs=14, rings=8),
        ball(0.08, (0, 0, 0.45), BRASS, segs=8, rings=6),
    ]
    return {"FrontDesk": (join("FrontDesk", parts), False), "DeskBell": (join("DeskBell", bell), False)}


def build_lamp_post():
    """Street lamp, 12 tall, arm reaching toward Roblox +Z (Blender -Y) like the old one."""
    h = 12.0
    pole = [
        cyl(0.75, 1.0, (0, 0, 0.5), METAL_DARK, verts=14, radius2=0.5),
        cyl(0.3, h - 1.0, (0, 0, (h + 1.0) / 2), METAL_DARK, verts=12),
        ball(0.4, (0, 0, h), METAL_DARK, segs=10, rings=7),
        box((0.32, 2.4, 0.32), (0, -1.1, h - 0.2), METAL_DARK, bevel=0.08),
        cyl(1.05, 0.7, (0, -2.3, h - 0.3), METAL_DARK, verts=16, radius2=0.45),
    ]
    glass = [ball(0.62, (0, -2.3, h - 0.75), LAMP_GLOW, squash=(1, 1, 0.75), segs=14, rings=8)]
    return {"LampPost": (join("LampPost", pole), False), "LampPostGlass": (join("LampPostGlass", glass), False)}


def build_bench():
    parts = []
    for i in range(3):
        parts.append(box((5.0, 0.42, 0.18), (0, -0.55 + i * 0.5, 1.62), WOOD, bevel=0.06))
    for i in range(2):
        parts.append(box((5.0, 0.16, 0.4), (0, -0.78, 2.15 + i * 0.55), WOOD, bevel=0.05))
    for x in (-2.1, 2.1):
        parts.append(box((0.22, 1.5, 0.22), (x, 0, 0.8), METAL_DARK, bevel=0.06))
        parts.append(box((0.22, 0.22, 1.6), (x, -0.78, 1.9), METAL_DARK, bevel=0.06))
        parts.append(box((0.22, 1.5, 0.22), (x, 0, 1.45), METAL_DARK, bevel=0.06))
        for y in (-0.65, 0.65):
            parts.append(box((0.22, 0.22, 1.45), (x, y, 0.72), METAL_DARK, bevel=0.06))
    return {"Bench": (join("Bench", parts), False)}


def build_potted_plant():
    pot = [
        cyl(0.95, 1.5, (0, 0, 0.75), TERRACOTTA, verts=16, radius2=0.7),
        cyl(1.05, 0.25, (0, 0, 1.5), scale_col(TERRACOTTA, 0.85), verts=16),
    ]
    leaves = []
    for i, (x, y, z, r) in enumerate([(0, 0, 2.3, 0.95), (0.55, 0.3, 2.0, 0.7), (-0.5, -0.35, 2.05, 0.7)]):
        leaves.append(ball(r, (x, y, z), mix(LEAF, LEAF_LIGHT, i * 0.3), segs=12, rings=8))
    for i, (x, y, z) in enumerate([(0.3, 0.6, 2.7), (-0.6, 0.2, 2.5), (0.6, -0.5, 2.4), (-0.1, -0.6, 2.9)]):
        leaves.append(ball(0.2, (x, y, z), FLOWERS[i % len(FLOWERS)], segs=8, rings=6))
    return {"PottedPlant": (join("PottedPlant", pot + leaves), False)}


def build_flower_bush():
    parts = []
    for i, (x, y, r) in enumerate([(0, 0, 1.5), (1.2, 0.5, 1.1), (-1.1, 0.4, 1.15), (0.2, -1.0, 1.0)]):
        parts.append(ball(r, (x, y, r * 0.75), mix(LEAF, LEAF_LIGHT, 0.15 + i * 0.15), squash=(1, 1, 0.85)))
    flowers = [(0.4, 0.8, 2.1), (-0.7, 0.9, 1.7), (1.4, 0.2, 1.6), (-1.3, -0.3, 1.5), (0.1, -0.9, 1.7), (0.9, -0.5, 2.0)]
    for i, (x, y, z) in enumerate(flowers):
        parts.append(ball(0.26, (x, y, z), FLOWERS[i % len(FLOWERS)], segs=8, rings=6))
    return {"FlowerBush": (join("FlowerBush", parts), False)}


def build_round_tree():
    """Autumn tree ~16 tall: trunk + puffy canopy (canopy tinted per tree: orange/red/yellow)."""
    trunk = [
        cyl(0.75, 9.0, (0, 0, 4.5), BARK, verts=12, radius2=0.5),
        cyl(1.1, 0.8, (0, 0, 0.4), BARK, verts=12, radius2=0.75),
        box((0.35, 0.35, 2.4), (0.9, 0, 7.6), BARK, bevel=0.1, rot=(0, 0.6, 0)),
        box((0.35, 0.35, 2.2), (-0.8, 0.3, 8.0), BARK, bevel=0.1, rot=(0.3, -0.6, 0)),
    ]
    canopy = []
    for x, y, z, r in [
        (0, 0, 11.5, 3.6),
        (2.4, 0.6, 10.6, 2.7),
        (-2.3, 0.4, 10.8, 2.8),
        (0.4, 2.2, 10.4, 2.5),
        (-0.3, -2.3, 10.6, 2.6),
        (0.6, -0.4, 13.8, 2.6),
    ]:
        canopy.append(ball(r, (x, y, z), NEUTRAL, segs=14, rings=10, tint=True))
    return {
        "RoundTreeTrunk": (join("RoundTreeTrunk", trunk), False),
        "RoundTreeCanopy": (join("RoundTreeCanopy", canopy), True),
    }


BATCHES = {
    "batch1": [
        ("Bed", build_bed),
        ("Nightstand", build_nightstand),
        ("RoomDoor", build_door),
        ("ACUnit", build_ac),
        ("Trash", build_trash),
        ("FrontDesk", build_desk),
        ("LampPost", build_lamp_post),
        ("Bench", build_bench),
        ("PottedPlant", build_potted_plant),
        ("FlowerBush", build_flower_bush),
        ("RoundTree", build_round_tree),
    ],
}


# ---------------------------------------------------------------- build + layout
def bbox(obj):
    pts = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


manifest = {}
spacing_x = 0.0
row_objects = []
for group, builder in BATCHES[BATCH]:
    meshes = builder()
    # Group footprint for the contact sheet / FBX layout.
    lo_all = Vector((1e9, 1e9, 1e9))
    hi_all = Vector((-1e9, -1e9, -1e9))
    for name, (obj, tint) in meshes.items():
        lo, hi = bbox(obj)
        lo_all = Vector((min(lo_all.x, lo.x), min(lo_all.y, lo.y), min(lo_all.z, lo.z)))
        hi_all = Vector((max(hi_all.x, hi.x), max(hi_all.y, hi.y), max(hi_all.z, hi.z)))
        size = hi - lo
        centre = (lo + hi) / 2
        tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
        # Blender (x, y, z) -> Roblox (x, z, -y)
        manifest[name] = {
            "group": group,
            "size": [round(size.x, 3), round(size.z, 3), round(size.y, 3)],
            "center": [round(centre.x, 3), round(centre.z, 3), round(-centre.y, 3)],
            "tint": tint,
            "tris": tris,
        }
    offset = spacing_x - lo_all.x
    for name, (obj, _tint) in meshes.items():
        obj.location.x += offset
        row_objects.append(obj)
    spacing_x += (hi_all.x - lo_all.x) + 4.0

total = sum(m["tris"] for m in manifest.values())
print(f"[kit] {BATCH}: {len(manifest)} meshes, {total} triangles")

# Material reading the colour attribute (so viewers and importers see colours).
mat = bpy.data.materials.new("KitVertexColour")
mat.use_nodes = True
bsdf = mat.node_tree.nodes.get("Principled BSDF")
bsdf.inputs["Roughness"].default_value = 0.85
vc = mat.node_tree.nodes.new("ShaderNodeVertexColor")
vc.layer_name = "Col"
mat.node_tree.links.new(vc.outputs["Color"], bsdf.inputs["Base Color"])
for obj in row_objects:
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    obj.data.color_attributes.active_color = obj.data.color_attributes["Col"]

# ---------------------------------------------------------------- export
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, f"motel_kit_{BATCH}.blend"))
bpy.ops.object.select_all(action="DESELECT")
for obj in row_objects:
    obj.select_set(True)
bpy.ops.export_scene.fbx(
    filepath=os.path.join(OUT, f"motel_kit_{BATCH}.fbx"),
    use_selection=True,
    object_types={"MESH"},
    apply_unit_scale=True,
    apply_scale_options="FBX_SCALE_UNITS",
    axis_forward="-Z",
    axis_up="Y",
    mesh_smooth_type="FACE",
    colors_type="SRGB",
    add_leaf_bones=False,
)
with open(os.path.join(OUT, f"motel_kit_{BATCH}.json"), "w", encoding="utf-8") as f:
    json.dump({"batch": BATCH, "units": "studs", "meshes": manifest}, f, indent=2)
print("[kit] exported", BATCH)

# ---------------------------------------------------------------- preview
# Example colours for TINT meshes (preview only; the game colours them).
PREVIEW_TINT = {
    "BedSheet": srgb(250, 250, 246),
    "BedBlanket": srgb(90, 150, 220),
    "RoomDoor": srgb(206, 80, 70),
    "ACUnit": srgb(225, 228, 232),
    "RoundTreeCanopy": srgb(246, 150, 60),
}
for obj in row_objects:
    tint = PREVIEW_TINT.get(obj.name)
    if tint:
        attr = obj.data.color_attributes["Col"]
        for d in attr.data:
            d.color = tuple(d.color[i] * tint[i] for i in range(3)) + (1.0,)

world = bpy.data.worlds.new("Sky")
world.color = (0.62, 0.82, 0.95)
scene.world = world
scene.render.engine = "BLENDER_WORKBENCH"
sh = scene.display.shading
sh.light = "STUDIO"
sh.color_type = "VERTEX"
sh.show_object_outline = True
sh.object_outline_color = (0.18, 0.12, 0.08)
sh.show_shadows = True
sh.shadow_intensity = 0.3
sh.show_cavity = True
sh.cavity_type = "WORLD"
sh.background_type = "WORLD"
scene.render.resolution_x = 1600
scene.render.resolution_y = 800

bpy.ops.mesh.primitive_plane_add(size=1, location=(spacing_x / 2, 0, 0))
ground = bpy.context.active_object
ground.scale = (spacing_x + 20, 40, 1)
_finish(ground, srgb(150, 196, 110), smooth=False)

cam_data = bpy.data.cameras.new("Cam")
cam_data.type = "ORTHO"
cam = bpy.data.objects.new("Cam", cam_data)
collection.objects.link(cam)
scene.camera = cam
half = spacing_x / 2
for k, (x0, x1) in enumerate(((0, half), (half, spacing_x))):
    cx = (x0 + x1) / 2
    cam_data.ortho_scale = (x1 - x0) + 4
    cam.location = (cx, 34, 16)
    direction = Vector((cx, 0, 5)) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = os.path.join(OUT, "previews", f"motel_kit_{BATCH}_{k + 1}.png")
    bpy.ops.render.render(write_still=True)
