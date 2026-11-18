"""
Stylized cartoon pine tree for Run a Motel (Roblox).

Run headless:
  blender --background --factory-startup --python tools/blender/pine_tree.py -- <repo_root>

Outputs (under <repo_root>/assets/models/):
  pine_tree.fbx            game mesh (Y-up, units = studs, pivot at the trunk base)
  pine_tree.blend          editable source
  previews/pine_tree.png   preview render

Look: stacked "skirt" tiers with drooping rounded lobes, dark green at the
bottom to light green at the top, baked cartoon shading in vertex colours
(top faces lighter, the underside of the lobes darker), brown flared trunk.
Low poly (~1k tris), two meshes so Roblox can colour them separately even
if vertex colours are not imported: PineTrunk and PineLeaves.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

ROOT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else os.getcwd()
OUT = os.path.join(ROOT, "assets", "models")
os.makedirs(os.path.join(OUT, "previews"), exist_ok=True)


def srgb(r, g, b):
    """0-255 sRGB -> linear floats (Blender colour attributes are linear)."""

    def lin(c):
        c /= 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    return (lin(r), lin(g), lin(b), 1.0)


def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(4))


# Palette (sRGB), close to the reference art.
LEAF_DARK = srgb(52, 140, 76)
LEAF_MID = srgb(92, 184, 88)
LEAF_LIGHT = srgb(170, 228, 110)
LEAF_SHADE = srgb(30, 92, 60)
BARK = srgb(150, 96, 58)
BARK_DARK = srgb(98, 60, 38)

# ---------------------------------------------------------------- scene
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


def new_object(name, bm):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    return obj


def ring(bm, n, radius_fn, z_fn, phase=0.0):
    verts = []
    for i in range(n):
        a = phase + i * 2 * math.pi / n
        r = radius_fn(i)
        verts.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, z_fn(i))))
    return verts


def bridge(bm, lower, upper):
    n = len(lower)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((lower[i], lower[j], upper[j], upper[i]))


def fan(bm, center, loop, flip=False):
    n = len(loop)
    for i in range(n):
        j = (i + 1) % n
        if flip:
            bm.faces.new((center, loop[j], loop[i]))
        else:
            bm.faces.new((center, loop[i], loop[j]))


# ---------------------------------------------------------------- foliage
SEG_PER_LOBE = 4


def scallop(theta, lobes, phase):
    """0 at the notches, 1 at the round bottom of each lobe (soft U shape)."""
    x = abs(math.sin((theta - phase) * lobes / 2))
    return x**0.55


def add_tier(bm, base_z, radius, height, lobes, droop, phase):
    """One puffy skirt: soft tip -> rounded shoulders -> belly -> scalloped rim -> underside."""
    n = lobes * SEG_PER_LOBE

    def theta(i):
        return i * 2 * math.pi / n

    def s(i):
        return scallop(theta(i), lobes, phase)

    top = bm.verts.new((0, 0, base_z + height))
    shoulder = ring(bm, n, lambda i: radius * (0.30 + 0.05 * s(i)), lambda i: base_z + height * 0.72)
    upper = ring(bm, n, lambda i: radius * (0.58 + 0.08 * s(i)), lambda i: base_z + height * 0.48)
    belly = ring(bm, n, lambda i: radius * (0.80 + 0.12 * s(i)), lambda i: base_z + height * 0.22)
    rim = ring(
        bm,
        n,
        lambda i: radius * (0.82 + 0.18 * s(i)),
        lambda i: base_z - droop * s(i) + droop * 0.25,
    )
    lip = ring(bm, n, lambda i: radius * (0.76 + 0.16 * s(i)), lambda i: base_z - droop * s(i) + droop * 0.05)
    under = ring(bm, n, lambda i: radius * 0.52, lambda i: base_z + height * 0.10)
    bottom = bm.verts.new((0, 0, base_z + height * 0.18))
    fan(bm, top, shoulder, flip=True)
    bridge(bm, upper, shoulder)
    bridge(bm, belly, upper)
    bridge(bm, rim, belly)
    bridge(bm, lip, rim)
    bridge(bm, under, lip)
    fan(bm, bottom, under)


leaves_bm = bmesh.new()
# (base z, radius, height, lobes, droop)
TIERS = [
    (5.0, 7.2, 6.4, 11, 0.9),
    (8.7, 6.1, 6.0, 10, 0.8),
    (12.1, 5.0, 5.6, 9, 0.7),
    (15.2, 3.9, 5.2, 8, 0.6),
    (17.9, 2.7, 6.0, 7, 0.5),
]
for k, (z, r, h, lobes, droop) in enumerate(TIERS):
    add_tier(leaves_bm, z, r, h, lobes, droop, phase=(math.pi / lobes) * (k % 2))
bmesh.ops.recalc_face_normals(leaves_bm, faces=leaves_bm.faces)
leaves = new_object("PineLeaves", leaves_bm)

# ---------------------------------------------------------------- trunk
trunk_bm = bmesh.new()
SEG = 10
roots = ring(trunk_bm, SEG * 2, lambda i: 1.55 if i % 4 == 0 else 1.1, lambda i: 0.0)
base = ring(trunk_bm, SEG * 2, lambda i: 1.0, lambda i: 0.9)
mid = ring(trunk_bm, SEG * 2, lambda i: 0.82, lambda i: 3.0)
top_ring = ring(trunk_bm, SEG * 2, lambda i: 0.72, lambda i: 6.4)
bridge(trunk_bm, roots, base)
bridge(trunk_bm, base, mid)
bridge(trunk_bm, mid, top_ring)
fan(trunk_bm, trunk_bm.verts.new((0, 0, 6.4)), top_ring, flip=True)
fan(trunk_bm, trunk_bm.verts.new((0, 0, 0.0)), roots)
bmesh.ops.recalc_face_normals(trunk_bm, faces=trunk_bm.faces)
trunk = new_object("PineTrunk", trunk_bm)


# ---------------------------------------------------------------- shading
def shade_smooth(obj):
    for poly in obj.data.polygons:
        poly.use_smooth = True


def paint(obj, colour_fn):
    """Per-corner colour attribute from a function of (position, normal)."""
    mesh = obj.data
    attr = mesh.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    mesh.calc_loop_triangles()
    for poly in mesh.polygons:
        for li in poly.loop_indices:
            v = mesh.vertices[mesh.loops[li].vertex_index]
            attr.data[li].color = colour_fn(v.co, poly.normal)
    mesh.color_attributes.active_color = attr


top_z = TIERS[-1][0] + TIERS[-1][2]
bottom_z = TIERS[0][0] - TIERS[0][4]


def leaf_colour(co, normal):
    height = (co.z - bottom_z) / (top_z - bottom_z)
    base = mix(LEAF_DARK, LEAF_MID, height * 1.6) if height < 0.62 else mix(LEAF_MID, LEAF_LIGHT, (height - 0.62) / 0.38)
    up = normal.z
    radial = Vector((co.x, co.y, 0)).length
    if up < -0.15:
        return mix(base, LEAF_SHADE, 0.7)  # underside of the skirt
    # Top-facing surfaces catch the light (cartoon highlight band).
    lit = mix(base, LEAF_LIGHT, max(0.0, up) ** 1.5 * 0.55)
    return mix(lit, LEAF_SHADE, 0.15) if radial < 0.8 else lit


def bark_colour(co, normal):
    return mix(BARK_DARK, BARK, min(1.0, co.z / 3.5))


for obj, fn in ((leaves, leaf_colour), (trunk, bark_colour)):
    shade_smooth(obj)
    paint(obj, fn)


# Materials (base colour so the importer gets a sensible tint too).
def material(name, colour):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = colour
    bsdf.inputs["Roughness"].default_value = 0.9
    attr = m.node_tree.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    m.node_tree.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    return m


leaves.data.materials.append(material("PineLeaves", LEAF_MID))
trunk.data.materials.append(material("PineTrunk", BARK))

tris = sum(len(p.vertices) - 2 for o in (leaves, trunk) for p in o.data.polygons)
print(f"[pine] triangles: {tris}")

# ---------------------------------------------------------------- preview render
world = bpy.data.worlds.new("Sky")
world.color = (0.62, 0.82, 0.95)
scene.world = world
scene.render.engine = "BLENDER_WORKBENCH"
shading = scene.display.shading
shading.light = "STUDIO"
shading.color_type = "VERTEX"
shading.show_object_outline = True
shading.object_outline_color = (0.18, 0.12, 0.08)
shading.show_shadows = True
shading.shadow_intensity = 0.35
shading.show_cavity = True
shading.cavity_type = "WORLD"
shading.background_type = "WORLD"
scene.render.resolution_x = 900
scene.render.resolution_y = 1100
scene.render.film_transparent = False

ground_bm = bmesh.new()
gr = ring(ground_bm, 32, lambda i: 11.0, lambda i: 0.0)
fan(ground_bm, ground_bm.verts.new((0, 0, 0)), gr)
ground = new_object("PreviewGround", ground_bm)
paint(ground, lambda co, n: srgb(128, 186, 92))

cam_data = bpy.data.cameras.new("Cam")
cam_data.lens = 55
cam = bpy.data.objects.new("Cam", cam_data)
scene.collection.objects.link(cam)
cam.location = (30, -30, 16)
direction = Vector((0, 0, 11)) - cam.location
cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
scene.camera = cam
scene.render.filepath = os.path.join(OUT, "previews", "pine_tree.png")
bpy.ops.render.render(write_still=True)

# ---------------------------------------------------------------- export (game meshes only)
bpy.data.objects.remove(ground, do_unlink=True)
bpy.data.objects.remove(cam, do_unlink=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "pine_tree.blend"))
bpy.ops.object.select_all(action="DESELECT")
for obj in (leaves, trunk):
    obj.select_set(True)
bpy.ops.export_scene.fbx(
    filepath=os.path.join(OUT, "pine_tree.fbx"),
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
print("[pine] exported", os.path.join(OUT, "pine_tree.fbx"))
