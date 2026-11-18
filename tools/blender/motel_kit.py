"""
Motel kit v2: premium stylized cartoon props for Run a Motel, built in
Blender per object (headless bpy, no MCP).

Run one batch:
  blender --background --factory-startup --python tools/blender/motel_kit.py -- <repo_root> <batch>

Outputs (assets/models/kit/):
  motel_kit_<batch>.fbx            every mesh of the batch (Y-up, 1 unit = 1 stud)
  motel_kit_<batch>.json           manifest per mesh: group, size, center, tint, glow,
                                   collision hint, triangles + validation report
  motel_kit_<batch>.blend          editable source (COL_ collections, SM_ meshes)
  previews/motel_kit_<batch>_*.png lookdev contact sheets (EEVEE)

Art direction (skills: blender-director, prop-artist, stylized-style,
cartoon-style, vegetation-artist):
  * Rounded "squishy" shapes, friendly circles/ovals, chunky proportions.
  * Palette from the reference: warm wood, cream, teal trim, brass, red
    accents, glowing warm lamps; saturated accents only on interactables.
  * Painted look in vertex colours ("Col"): 3 soft cartoon bands from a fixed
    key light (top-left-front), warm highlights, cool shadows, darker contact
    edges near the floor (wear hierarchy). No textures needed.
  * TINT meshes carry neutral bands so the game colours them (MeshPart.Color):
    sheet clean/dirty, door per room, AC broken, tree canopy per tree.
  * GLOW meshes (lamp glass, shades) are flat bright colour for Neon in game.
  * Budgets: hero interactables 2-6k tris, standard props 0.5-2k, tree <= 2.5k.

Coordinates: Blender X right, Z up, +Y = Roblox front (-Z), -Y = Roblox back.
Manifest sizes/centers are in Roblox axes (x, y, z) = Blender (x, z, -y).
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

ARGS = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
ROOT = ARGS[0] if ARGS else os.getcwd()
BATCH = ARGS[1] if len(ARGS) > 1 else "batch1"
OUT = os.path.join(ROOT, "assets", "models", "kit")
os.makedirs(os.path.join(OUT, "previews"), exist_ok=True)


# ======================================================================
# Colour
# ======================================================================
def srgb(r, g, b):
    def lin(c):
        c /= 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    return (lin(r), lin(g), lin(b), 1.0)


def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3)) + (1.0,)


def mul(c, k):
    return (min(1.0, c[0] * k), min(1.0, c[1] * k), min(1.0, c[2] * k), 1.0)


WOOD = srgb(184, 118, 66)
WOOD_DARK = srgb(118, 70, 40)
WOOD_LIGHT = srgb(222, 164, 102)
WOOD_PANEL = srgb(160, 98, 54)
CREAM = srgb(252, 240, 214)
LINEN = srgb(250, 248, 242)
TEAL = srgb(52, 150, 140)
TEAL_DARK = srgb(32, 104, 98)
RED = srgb(214, 66, 56)
IRON = srgb(40, 42, 50)
METAL = srgb(170, 176, 186)
BRASS = srgb(240, 190, 76)
GLOW = srgb(255, 224, 140)
GLOW_SHADE = srgb(255, 236, 190)
TERRACOTTA = srgb(214, 110, 66)
SOIL = srgb(96, 66, 46)
LEAF = srgb(70, 156, 74)
LEAF_DARK = srgb(46, 118, 62)
LEAF_LIGHT = srgb(136, 206, 96)
BARK = srgb(132, 86, 54)
BAG = srgb(46, 48, 60)
BIN = srgb(84, 150, 214)
BIN_DARK = srgb(62, 116, 180)
NEUTRAL = srgb(255, 255, 255)
PETALS = [srgb(255, 120, 160), srgb(255, 255, 255), srgb(255, 206, 80), srgb(196, 140, 255)]

KEY = Vector((-0.42, 0.38, 0.82)).normalized()  # key light, top-left-front
WARM = srgb(255, 236, 200)
COOL = srgb(120, 140, 200)


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def band(d):
    """Soft 3-band cartoon ramp: shadow 0.74, mid 0.96, light 1.10."""
    s = smoothstep(-0.05, 0.08, d)
    l = smoothstep(0.50, 0.62, d)
    return 0.74 + (0.96 - 0.74) * s + (1.10 - 0.96) * l, s, l


# ======================================================================
# Scene + mesh helpers
# ======================================================================
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


def _activate(obj):
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)


def _apply_modifiers(obj):
    _activate(obj)
    for mod in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)


def _smooth_by_angle(obj, angle_deg=42.0):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    limit = math.radians(angle_deg)
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:
        e.smooth = not (len(e.link_faces) == 2 and e.calc_face_angle(0) > limit)
    bm.to_mesh(obj.data)
    bm.free()


def finish(obj, colour, bevel=0.0, segments=3, profile=0.65, smooth_angle=42.0, tag=None):
    """Bevel (rounded), smooth-by-angle normals, store colour + tag for painting."""
    if bevel > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = segments
        mod.profile = profile
        mod.limit_method = "ANGLE"
        mod.angle_limit = math.radians(30)
        _apply_modifiers(obj)
    _smooth_by_angle(obj, smooth_angle)
    obj["base_colour"] = list(colour)
    obj["tag"] = tag or ""
    return obj


BEVEL_SEGMENTS = 3  # lowered for dense batches (asset-optimization)


def box(size, loc, colour, bevel=0.1, rot=(0, 0, 0), segments=None, tag=None):
    if segments is None:
        segments = BEVEL_SEGMENTS
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(o, colour, bevel=min(bevel, min(size) * 0.45), segments=segments, tag=tag)


def taper_box(size, loc, colour, top=(0.8, 0.8), bevel=0.1, segments=None, tag=None):
    """Box whose top face is scaled by top=(sx, sy): cabins, roofs, plinths."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0))
    o = bpy.context.active_object
    for v in o.data.vertices:
        if v.co.z > 0:
            v.co.x *= top[0]
            v.co.y *= top[1]
    o.scale = size
    o.location = loc
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=True)
    segs = BEVEL_SEGMENTS if segments is None else segments
    return finish(o, colour, bevel=min(bevel, min(size) * 0.45), segments=segs, tag=tag)


def cyl(radius, depth, loc, colour, verts=20, bevel=0.06, rot=(0, 0, 0), radius2=None, tag=None):
    if radius2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=loc, rotation=rot)
    else:
        bpy.ops.mesh.primitive_cone_add(
            vertices=verts, radius1=radius, radius2=radius2, depth=depth, location=loc, rotation=rot
        )
    o = bpy.context.active_object
    return finish(o, colour, bevel=min(bevel, radius * 0.4, depth * 0.4), segments=2, tag=tag)


def lathe(profile, loc, colour, verts=20, tag=None, smooth_angle=50.0):
    """Revolve a (radius, z) profile around Z (bottom to top). Caps closed."""
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        ring = []
        for i in range(verts):
            a = i * 2 * math.pi / verts
            ring.append(bm.verts.new((loc[0] + math.cos(a) * r, loc[1] + math.sin(a) * r, loc[2] + z)))
        rings.append(ring)
    for k in range(len(rings) - 1):
        lo, hi = rings[k], rings[k + 1]
        for i in range(verts):
            j = (i + 1) % verts
            bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
    if profile[0][0] > 1e-3:
        bm.faces.new(list(reversed(rings[0])))
    if profile[-1][0] > 1e-3:
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("lathe")
    bm.to_mesh(mesh)
    bm.free()
    o = bpy.data.objects.new("lathe", mesh)
    scene.collection.objects.link(o)
    return finish(o, colour, smooth_angle=smooth_angle, tag=tag)


def blob(radius, loc, colour, squash=(1, 1, 1), lump=0.18, seed=0.0, segs=18, rings=12, tag=None):
    """Puffy sphere with soft noise lumps (foliage, pillows, bags)."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segs, ring_count=rings, radius=radius, location=(0, 0, 0))
    o = bpy.context.active_object
    for v in o.data.vertices:
        n = v.co.normalized()
        k = 1.0 + lump * noise.noise(n * 1.9 + Vector((seed, seed * 0.7, seed * 1.3)))
        v.co = Vector((n.x * radius * k * squash[0], n.y * radius * k * squash[1], n.z * radius * k * squash[2]))
    o.location = loc
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
    return finish(o, colour, smooth_angle=80.0, tag=tag)


def extrude_profile(points_yz, x_center, thickness, colour, bevel=0.05, tag=None):
    """Flat shape from a closed (y, z) outline, extruded along X (bench sides, arches)."""
    bm = bmesh.new()
    front = [bm.verts.new((x_center - thickness / 2, y, z)) for y, z in points_yz]
    back = [bm.verts.new((x_center + thickness / 2, y, z)) for y, z in points_yz]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    n = len(points_yz)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((front[i], back[i], back[j], front[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("profile")
    bm.to_mesh(mesh)
    bm.free()
    o = bpy.data.objects.new("profile", mesh)
    scene.collection.objects.link(o)
    return finish(o, colour, bevel=bevel, segments=2, tag=tag)


def arch_outline(width, height, rise, steps=10):
    """Rectangle with an arched top, (y, z) points for extrude_profile (y = across)."""
    pts = [(-width / 2, 0.0), (width / 2, 0.0), (width / 2, height)]
    for i in range(1, steps):
        t = i / steps
        y = width / 2 - t * width
        pts.append((y, height + rise * math.sin(math.pi * t)))
    pts.append((-width / 2, height))
    return pts


def paint(obj, kind):
    """Bake cartoon bands into a corner colour attribute.
    kind: "normal" | "tint" | "glow"."""
    mesh = obj.data
    base = tuple(obj["base_colour"])
    attr = mesh.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    normals = [cn.vector for cn in mesh.corner_normals]
    mw = obj.matrix_world
    for poly in mesh.polygons:
        for li in poly.loop_indices:
            if kind == "glow":
                attr.data[li].color = base
                continue
            n = normals[li]
            co = mw @ mesh.vertices[mesh.loops[li].vertex_index].co
            d = n.dot(KEY)
            k, s, l = band(d)
            if kind == "tint":
                c = mul(base, k * 0.93)
            else:
                c = mul(base, k)
                c = mix(c, mul(COOL, 0.6), (1 - s) * 0.18)  # cool shadows
                c = mix(c, WARM, l * 0.10)  # warm highlights
            if co.z < 0.35:  # contact edge darkening (wear / AO)
                c = mul(c, 0.82 + 0.18 * (co.z / 0.35))
            attr.data[li].color = c
    mesh.color_attributes.active_color = attr


def join(name, parts):
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    if len(parts) > 1:
        bpy.ops.object.join()
    o = bpy.context.active_object
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    o.name = name
    o.data.name = name
    return o


def build_mesh(name, parts, kind="normal"):
    """Paint every part (with its own colour) then join into one SM_ mesh."""
    for p in parts:
        paint(p, kind if kind != "mixed" else (p["tag"] or "normal"))
    return join(name, parts)


# ======================================================================
# Batch 1 objects
# ======================================================================
def bed():
    """Bed 5 x 7 (hitbox y 0.4..2.0); headboard at the back (Blender -Y)."""
    L, W = 7.0, 5.0
    frame = [
        box((W + 0.3, L + 0.2, 0.75), (0, 0, 0.72), WOOD, bevel=0.16),
        box((W + 0.42, L + 0.3, 0.14), (0, 0, 1.12), WOOD_DARK, bevel=0.05),
    ]
    head = extrude_profile(
        [(y, z) for y, z in arch_outline(W + 0.5, 2.9, 0.75)], 0, 0.42, WOOD_DARK, bevel=0.12
    )
    head.rotation_euler = (0, 0, math.pi / 2)
    head.location = (0, -(L / 2 + 0.45), 0.3)
    bpy.context.view_layer.update()
    _activate(head)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    panel = extrude_profile(
        [(y, z) for y, z in arch_outline(W - 0.7, 2.0, 0.5)], 0, 0.12, WOOD_LIGHT, bevel=0.05
    )
    panel.rotation_euler = (0, 0, math.pi / 2)
    panel.location = (0, -(L / 2 + 0.2), 1.0)
    bpy.context.view_layer.update()
    _activate(panel)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    frame += [head, panel]
    frame.append(box((W + 0.3, 0.38, 1.55), (0, L / 2 + 0.06, 0.95), WOOD_DARK, bevel=0.14))
    frame.append(box((W - 0.8, 0.1, 0.8), (0, L / 2 + 0.28, 1.0), WOOD_LIGHT, bevel=0.05))
    for x in (-W / 2 - 0.05, W / 2 + 0.05):
        for y, h in ((-(L / 2 + 0.45), 3.9), (L / 2 + 0.06, 1.9)):
            frame.append(lathe([(0.3, 0), (0.32, 0.15), (0.24, 0.3), (0.24, h - 0.45), (0.3, h - 0.3), (0.0, h - 0.05)], (x, y, 0), WOOD_DARK, verts=14))
            frame.append(blob(0.24, (x, y, h + 0.1), WOOD_DARK, lump=0.0, segs=12, rings=8))
    sheet = [box((W - 0.12, L - 0.45, 0.86), (0, -0.15, 1.6), NEUTRAL, bevel=0.34, segments=4)]
    for x in (-1.4, 0, 1.4):
        for y in (-1.6, 0.2):
            sheet.append(blob(0.09, (x, y, 2.04), mul(NEUTRAL, 0.82), squash=(1, 1, 0.5), lump=0, segs=8, rings=6))
    blanket = [
        box((W + 0.06, 3.9, 0.3), (0, L / 2 - 2.05, 2.0), NEUTRAL, bevel=0.13, segments=3),
        box((W + 0.06, 0.28, 0.95), (0, L / 2 - 0.15, 1.58), NEUTRAL, bevel=0.12, segments=3),
    ]
    linen = [
        box((W + 0.1, 0.62, 0.34), (0, L / 2 - 4.05, 2.06), LINEN, bevel=0.15),  # turned-down band
        blob(1.0, (-1.15, -(L / 2) + 1.05, 2.2), LINEN, squash=(1.05, 0.62, 0.36), lump=0.08, seed=1.0),
        blob(1.0, (1.15, -(L / 2) + 1.05, 2.2), LINEN, squash=(1.05, 0.62, 0.36), lump=0.08, seed=2.0),
    ]
    return {
        "SM_Prop_Bed_Frame": (build_mesh("SM_Prop_Bed_Frame", frame), dict(collision="Box")),
        "SM_Prop_Bed_Sheet": (build_mesh("SM_Prop_Bed_Sheet", sheet, "tint"), dict(tint=True)),
        "SM_Prop_Bed_Blanket": (build_mesh("SM_Prop_Bed_Blanket", blanket, "tint"), dict(tint=True)),
        "SM_Prop_Bed_Linen": (build_mesh("SM_Prop_Bed_Linen", linen), {}),
    }


def nightstand():
    body = [
        box((1.8, 1.7, 1.55), (0, 0, 1.12), WOOD, bevel=0.14),
        box((2.0, 1.9, 0.18), (0, 0, 1.96), WOOD_DARK, bevel=0.07),
    ]
    for z in (0.78, 1.38):
        body.append(box((1.5, 0.08, 0.5), (0, 0.86, z), WOOD_LIGHT, bevel=0.05))
        body.append(blob(0.11, (0, 0.95, z), BRASS, lump=0, segs=10, rings=7))
    for x in (-0.7, 0.7):
        for y in (-0.65, 0.65):
            body.append(cyl(0.14, 0.36, (x, y, 0.18), WOOD_DARK, verts=10, radius2=0.09))
    lamp = [
        lathe([(0.0, 0), (0.42, 0.02), (0.45, 0.1), (0.52, 0.4), (0.46, 0.7), (0.2, 0.9), (0.12, 1.0), (0.0, 1.02)], (0, 0, 2.05), TEAL, verts=18),
        cyl(0.07, 0.4, (0, 0, 3.25), BRASS, verts=8),
    ]
    shade = [lathe([(0.0, 3.3), (0.72, 3.3), (0.74, 3.36), (0.46, 4.1), (0.0, 4.12)], (0, 0, 0), GLOW_SHADE, verts=20)]
    return {
        "SM_Prop_Nightstand": (build_mesh("SM_Prop_Nightstand", body + lamp), dict(collision="Box")),
        "SM_Prop_Nightstand_Shade": (build_mesh("SM_Prop_Nightstand_Shade", shade, "glow"), dict(glow=True, collision="None")),
    }


def door():
    """Room door 3.8 x 6.8 x 0.3, centred on its frame; tinted per room."""
    w, h, t = 3.8, 6.8, 0.3
    leaf = [box((w, t, h), (0, 0, h / 2), NEUTRAL, bevel=0.07)]
    for side in (-1, 1):
        for row, (z, hh) in enumerate(((1.15, 1.6), (3.15, 1.6), (5.4, 1.9))):
            for x in (-0.85, 0.85):
                leaf.append(box((1.3, 0.12, hh), (x, side * (t / 2 + 0.04), z), mul(NEUTRAL, 0.93), bevel=0.06))
    hardware = [
        box((3.2, 0.06, 0.55), (0, t / 2 + 0.05, 0.35), BRASS, bevel=0.03),
        box((0.36, 0.06, 0.9), (w / 2 - 0.42, t / 2 + 0.05, 3.3), BRASS, bevel=0.04),
        blob(0.17, (w / 2 - 0.42, t / 2 + 0.22, 3.25), BRASS, lump=0, segs=12, rings=8),
        blob(0.17, (w / 2 - 0.42, -(t / 2 + 0.22), 3.25), BRASS, lump=0, segs=12, rings=8),
        cyl(0.36, 0.1, (0, t / 2 + 0.07, 5.0), BRASS, verts=18, rot=(math.pi / 2, 0, 0)),  # number plaque
    ]
    for z in (0.9, 3.4, 5.9):
        hardware.append(cyl(0.08, 0.5, (-w / 2 + 0.02, 0, z), METAL, verts=8))
    frame = [
        box((0.55, 0.5, 7.4), (-2.2, 0, 3.7), TEAL, bevel=0.08),
        box((0.55, 0.5, 7.4), (2.2, 0, 3.7), TEAL, bevel=0.08),
        box((5.2, 0.62, 0.55), (0, 0, 7.25), TEAL, bevel=0.08),
        box((5.6, 0.75, 0.22), (0, 0, 7.6), TEAL_DARK, bevel=0.06),
        box((0.7, 0.62, 0.6), (-2.2, 0, 0.3), TEAL_DARK, bevel=0.06),
        box((0.7, 0.62, 0.6), (2.2, 0, 0.3), TEAL_DARK, bevel=0.06),
    ]
    return {
        "SM_Prop_Door_Leaf": (build_mesh("SM_Prop_Door_Leaf", leaf, "tint"), dict(tint=True, collision="Box")),
        "SM_Prop_Door_Hardware": (build_mesh("SM_Prop_Door_Hardware", hardware), dict(collision="None")),
        "SM_Prop_Door_Frame": (build_mesh("SM_Prop_Door_Frame", frame), dict(collision="Hull")),
    }


def ac_unit():
    """Window AC 4 x 2 x 1, origin at its centre; body tinted (red when broken)."""
    body = [
        box((4.0, 1.0, 2.0), (0, 0, 0), NEUTRAL, bevel=0.2, segments=4),
        box((4.1, 0.25, 0.18), (0, 0.45, -1.0), mul(NEUTRAL, 0.85), bevel=0.06),
    ]
    face = [box((2.5, 0.08, 1.55), (-0.62, 0.5, 0.05), srgb(70, 76, 90), bevel=0.06)]
    for i in range(9):
        face.append(box((0.14, 0.12, 1.4), (-1.72 + i * 0.275, 0.55, 0.05), METAL, bevel=0.04))
    face.append(box((1.0, 0.1, 1.55), (1.32, 0.5, 0.05), CREAM, bevel=0.08))
    face.append(cyl(0.26, 0.14, (1.32, 0.58, 0.35), srgb(80, 86, 100), verts=16, rot=(math.pi / 2, 0, 0)))
    face.append(box((0.06, 0.06, 0.2), (1.32, 0.66, 0.42), CREAM, bevel=0.02))
    face.append(blob(0.08, (1.1, 0.58, -0.35), srgb(90, 230, 130), lump=0, segs=8, rings=6))
    face.append(blob(0.08, (1.32, 0.58, -0.35), srgb(255, 200, 80), lump=0, segs=8, rings=6))
    face.append(box((1.6, 0.6, 0.12), (0, -0.05, -1.12), IRON, bevel=0.04))
    return {
        "SM_Prop_AC_Body": (build_mesh("SM_Prop_AC_Body", body, "tint"), dict(tint=True, collision="Box")),
        "SM_Prop_AC_Front": (build_mesh("SM_Prop_AC_Front", face), dict(collision="None")),
    }


def trash():
    can = [
        lathe(
            [(0.0, 0), (0.92, 0), (0.96, 0.08), (1.02, 0.5), (1.0, 0.56), (1.04, 0.62), (1.08, 1.3), (1.06, 1.36),
             (1.1, 1.42), (1.14, 2.2), (1.12, 2.26), (1.16, 2.32), (1.18, 2.55), (1.24, 2.6), (1.24, 2.68), (0.0, 2.68)],
            (0, 0, 0), BIN, verts=24,
        ),
        lathe([(0.0, 2.66), (1.3, 2.66), (1.3, 2.78), (1.0, 2.95), (0.5, 3.04), (0.0, 3.06)], (0, 0, 0), BIN_DARK, verts=24),
        box((0.9, 0.24, 0.16), (0, 0, 3.12), BIN_DARK, bevel=0.07),
        box((0.6, 0.55, 0.12), (0, 1.12, 0.08), IRON, bevel=0.04),
    ]
    bag = [
        blob(0.92, (0, 0, 0.78), BAG, squash=(1.0, 0.95, 0.88), lump=0.16, seed=3.0),
        lathe([(0.32, 0), (0.18, 0.2), (0.12, 0.36), (0.14, 0.42), (0.0, 0.46)], (0, 0, 1.45), BAG, verts=12),
        blob(0.2, (0.18, 0, 1.92), BAG, squash=(1.5, 0.55, 0.7), lump=0.1, seed=4.0, segs=10, rings=7),
        blob(0.2, (-0.18, 0, 1.9), BAG, squash=(1.4, 0.55, 0.7), lump=0.1, seed=5.0, segs=10, rings=7),
    ]
    return {
        "SM_Prop_TrashBin": (build_mesh("SM_Prop_TrashBin", can), dict(collision="Hull")),
        "SM_Prop_TrashBag": (build_mesh("SM_Prop_TrashBag", bag), dict(collision="None")),
    }


def front_desk():
    """Reception counter 10 x 2 (hitbox 10 x 3 x 2); guests at the front (+Y)."""
    parts = [
        box((10.0, 1.9, 2.55), (0, -0.05, 1.42), WOOD, bevel=0.14),
        box((10.5, 0.7, 3.05), (0, 0.72, 1.62), WOOD, bevel=0.16),  # raised front fascia
        box((10.8, 0.95, 0.16), (0, 0.78, 3.2), CREAM, bevel=0.07),  # customer ledge
        box((10.4, 2.3, 0.2), (0, -0.25, 2.72), WOOD_DARK, bevel=0.08),  # work top
        box((10.6, 1.0, 0.42), (0, 0.72, 0.21), TEAL, bevel=0.1),  # base plinth
    ]
    for x in (-3.4, 0, 3.4):
        parts.append(box((3.0, 0.12, 2.0), (x, 1.08, 1.62), WOOD_DARK, bevel=0.06))
        parts.append(box((2.5, 0.14, 1.5), (x, 1.12, 1.62), WOOD_PANEL, bevel=0.08))
    parts.append(box((1.6, 0.1, 0.5), (0, 1.2, 2.62), BRASS, bevel=0.05))  # name plate
    # Open guest book + pen cup on the ledge.
    parts.append(box((1.3, 0.9, 0.12), (-3.2, 0.62, 3.34), CREAM, bevel=0.05, rot=(0, 0, 0.15)))
    parts.append(box((0.08, 0.92, 0.16), (-3.2, 0.62, 3.36), RED, bevel=0.02, rot=(0, 0, 0.15)))
    parts.append(cyl(0.2, 0.42, (3.4, 0.6, 3.48), TEAL_DARK, verts=12))
    parts.append(cyl(0.035, 0.6, (3.45, 0.62, 3.75), RED, verts=6, rot=(0.25, 0.15, 0)))
    bell = [
        cyl(0.46, 0.12, (0, 0, 0.06), IRON, verts=18),
        lathe([(0.0, 0.1), (0.42, 0.1), (0.4, 0.22), (0.3, 0.4), (0.14, 0.5), (0.0, 0.52)], (0, 0, 0), BRASS, verts=18),
        cyl(0.05, 0.12, (0, 0, 0.58), BRASS, verts=8),
        blob(0.08, (0, 0, 0.66), BRASS, lump=0, segs=8, rings=6),
    ]
    return {
        "SM_Prop_FrontDesk": (build_mesh("SM_Prop_FrontDesk", parts), dict(collision="Box")),
        "SM_Prop_DeskBell": (build_mesh("SM_Prop_DeskBell", bell), dict(collision="None")),
    }


def lamp_post():
    """Classic lantern post (like the reference), 12 studs to the top finial."""
    post = [
        lathe([(0.0, 0), (0.95, 0), (0.95, 0.35), (0.8, 0.45), (0.8, 0.75), (0.55, 0.95), (0.5, 1.3), (0.0, 1.3)], (0, 0, 0), IRON, verts=16),
        lathe([(0.32, 1.25), (0.28, 2.0), (0.26, 8.6), (0.0, 8.6)], (0, 0, 0), IRON, verts=12),
    ]
    for z in (2.0, 8.4):
        post.append(lathe([(0.0, z - 0.12), (0.42, z - 0.12), (0.44, z), (0.42, z + 0.12), (0.0, z + 0.12)], (0, 0, 0), IRON, verts=14))
    post.append(lathe([(0.0, 8.6), (0.55, 8.6), (0.62, 8.9), (0.0, 8.95)], (0, 0, 0), IRON, verts=14))  # lantern floor
    for a in range(4):
        ang = a * math.pi / 2 + math.pi / 4
        post.append(box((0.14, 0.14, 1.8), (math.cos(ang) * 0.62, math.sin(ang) * 0.62, 9.85), IRON, bevel=0.04))
    post.append(lathe([(0.0, 10.7), (0.95, 10.7), (0.9, 10.85), (0.55, 11.3), (0.25, 11.5), (0.0, 11.55)], (0, 0, 0), IRON, verts=16))
    post.append(lathe([(0.0, 11.5), (0.14, 11.55), (0.16, 11.75), (0.08, 11.95), (0.0, 12.0)], (0, 0, 0), IRON, verts=10))
    glass = [lathe([(0.0, 8.9), (0.55, 8.9), (0.68, 10.0), (0.62, 10.7), (0.0, 10.7)], (0, 0, 0), GLOW, verts=4)]
    glass[0].rotation_euler = (0, 0, math.pi / 4)
    return {
        "SM_Prop_LampPost": (build_mesh("SM_Prop_LampPost", post), dict(collision="Hull")),
        "SM_Prop_LampPost_Glass": (build_mesh("SM_Prop_LampPost_Glass", glass, "glow"), dict(glow=True, collision="None")),
    }


def bench():
    """Park bench 5 wide: wooden slats, curved back, cast-iron scroll sides."""
    parts = []
    for i in range(4):
        parts.append(box((5.0, 0.36, 0.17), (0, 0.55 - i * 0.4, 1.62 - i * 0.02), WOOD, bevel=0.08))
    for i in range(3):
        tilt = -0.18 - i * 0.03
        parts.append(box((5.0, 0.16, 0.36), (0, -0.88 - i * 0.05, 2.2 + i * 0.42), WOOD, bevel=0.07, rot=(tilt, 0, 0)))
    side = [
        (0.75, 0.0), (0.95, 0.0), (0.7, 0.8), (0.75, 1.45), (0.95, 1.55), (0.95, 1.7),
        (-0.75, 1.7), (-0.95, 1.95), (-1.1, 3.4), (-1.25, 3.45), (-1.1, 1.6), (-0.75, 0.8), (-0.95, 0.0), (-0.75, 0.0),
        (-0.55, 0.8), (-0.7, 1.45), (0.5, 1.45), (0.45, 0.8),
    ]
    for x in (-2.15, 2.15):
        parts.append(extrude_profile(side, x, 0.22, IRON, bevel=0.06))
        parts.append(box((0.32, 1.5, 0.22), (x, 0.15, 2.45), IRON, bevel=0.1))  # arm rest
        parts.append(blob(0.16, (x, 0.85, 2.45), IRON, lump=0, segs=10, rings=7))
    return {"SM_Prop_Bench": (build_mesh("SM_Prop_Bench", parts), dict(collision="Box"))}


def flowers_on(lobes, count, seed, size=0.26):
    """Flowers sitting on the upper surface of foliage lobes [(centre, radius, squash)]."""
    def inside_other(p, own):
        for k, (c, r, sq) in enumerate(lobes):
            if k != own:
                q = p - Vector(c)
                if (q.x / sq[0]) ** 2 + (q.y / sq[1]) ** 2 + (q.z / sq[2]) ** 2 < (r * 0.98) ** 2:
                    return True
        return False

    out = []
    placed = 0
    tries = 0
    while placed < count and tries < count * 12:
        tries += 1
        own = tries % len(lobes)
        c, r, sq = lobes[own]
        a = (tries * 2.39996 + seed) % (2 * math.pi)
        up = 0.2 + 0.7 * ((tries * 0.618 + seed * 0.37) % 1.0)  # upper half of the lobe
        d = Vector((math.cos(a) * math.sqrt(1 - up * up), math.sin(a) * math.sqrt(1 - up * up), up))
        p = Vector(c) + Vector((d.x * r * sq[0], d.y * r * sq[1], d.z * r * sq[2])) * 1.02
        if inside_other(p, own):
            continue
        i = placed
        placed += 1
        petal = PETALS[i % len(PETALS)]
        out.append(blob(size, tuple(p), petal, squash=(1.0, 1.0, 0.6), lump=0.3, seed=seed + i, segs=7, rings=4))
        out.append(blob(size * 0.4, (p.x, p.y, p.z + size * 0.32), srgb(255, 214, 70), lump=0, segs=5, rings=3))
    return out


def potted_plant():
    pot = [
        lathe([(0.0, 0.0), (1.05, 0.0), (1.1, 0.1), (1.05, 0.16), (0.0, 0.16)], (0, 0, 0), mul(TERRACOTTA, 0.85), verts=20),
        lathe([(0.0, 0.16), (0.68, 0.16), (0.78, 0.4), (0.95, 1.25), (1.12, 1.3), (1.14, 1.62), (1.0, 1.66), (0.0, 1.66)], (0, 0, 0), TERRACOTTA, verts=20),
        cyl(0.94, 0.08, (0, 0, 1.6), SOIL, verts=20),
    ]
    lobe_defs = [
        ((0, 0, 2.45), 0.95, LEAF, 11.0),
        ((0.62, 0.25, 2.1), 0.72, LEAF_LIGHT, 12.0),
        ((-0.58, -0.3, 2.15), 0.7, LEAF_DARK, 13.0),
        ((0.1, 0.65, 2.0), 0.62, LEAF, 14.0),
    ]
    leaves = [blob(r, c, col, lump=0.22, seed=sd, segs=14, rings=9) for c, r, col, sd in lobe_defs]
    bloom = flowers_on([(c, r, (1, 1, 1)) for c, r, _col, _sd in lobe_defs], 10, 1.7, 0.24)
    return {
        "SM_Prop_PottedPlant": (
            build_mesh("SM_Prop_PottedPlant", pot + leaves + bloom),
            dict(collision="Hull"),
        )
    }


def flower_bush():
    lobe_defs = [
        ((0, 0, 1.2), 1.55, (1, 1, 0.82), LEAF, 21.0),
        ((1.35, 0.5, 0.9), 1.15, (1, 1, 0.85), LEAF_LIGHT, 22.0),
        ((-1.3, 0.45, 0.92), 1.2, (1, 1, 0.85), LEAF_DARK, 23.0),
        ((0.3, -1.15, 0.8), 1.0, (1, 1, 0.85), LEAF, 24.0),
        ((-0.6, 1.2, 0.75), 0.9, (1, 1, 0.85), LEAF_LIGHT, 25.0),
    ]
    lobes = [blob(r, c, col, squash=sq, lump=0.2, seed=sd, segs=16, rings=10) for c, r, sq, col, sd in lobe_defs]
    bloom = flowers_on([(c, r, sq) for c, r, sq, _col, _sd in lobe_defs], 18, 2.3, 0.34)
    return {
        "SM_Prop_FlowerBush": (
            build_mesh("SM_Prop_FlowerBush", lobes + bloom),
            dict(collision="Hull"),
        )
    }


def round_tree():
    """Autumn tree ~16 studs: rooted trunk with two branches + puffy canopy (tinted)."""
    trunk = [
        lathe([(1.2, 0.0), (0.9, 0.35), (0.7, 1.2), (0.6, 4.0), (0.55, 7.0), (0.42, 9.6), (0.0, 9.7)], (0, 0, 0), BARK, verts=12),
    ]
    for a in range(4):
        ang = a * math.pi / 2 + 0.4
        # Built pointing along +X, then swung around the trunk axis.
        root = blob(0.55, (1.05, 0, 0.22), BARK, squash=(1.6, 0.7, 0.45), lump=0.1, seed=40.0 + a, segs=12, rings=8)
        root.rotation_euler = (0, 0, ang)
        trunk.append(root)
    trunk.append(cyl(0.28, 2.6, (1.0, 0.1, 7.8), BARK, verts=8, radius2=0.16, rot=(0, 0.75, 0.1)))
    trunk.append(cyl(0.26, 2.4, (-0.9, 0.3, 8.2), BARK, verts=8, radius2=0.15, rot=(0.3, -0.7, 0)))
    canopy = []
    for i, (x, y, z, r) in enumerate([
        (0.0, 0.0, 11.6, 3.5), (2.5, 0.6, 10.7, 2.7), (-2.4, 0.4, 10.9, 2.8),
        (0.5, 2.3, 10.5, 2.5), (-0.4, -2.3, 10.7, 2.6), (0.6, -0.4, 13.9, 2.5), (-1.6, -1.2, 12.9, 2.1),
    ]):
        canopy.append(blob(r, (x, y, z), NEUTRAL, lump=0.16, seed=31.0 + i * 1.7, segs=16, rings=11))
    return {
        "SM_Veg_RoundTree_Trunk": (build_mesh("SM_Veg_RoundTree_Trunk", trunk), dict(collision="Hull")),
        "SM_Veg_RoundTree_Canopy": (build_mesh("SM_Veg_RoundTree_Canopy", canopy, "tint"), dict(tint=True, collision="None")),
    }


# ======================================================================
# Batch 2 objects (kitchen, stations, shop, vehicles, yard)
# ======================================================================
STEEL = srgb(196, 202, 210)
STEEL_DARK = srgb(120, 126, 136)
MINT = srgb(150, 214, 196)
BUTTER = srgb(252, 228, 150)
GREEN_BIN = srgb(60, 140, 80)
GREEN_BIN_DARK = srgb(40, 104, 60)
ROCK = srgb(150, 150, 158)
GLASS_DARK = srgb(60, 80, 100)
FLAME_OUT = srgb(255, 140, 40)
FLAME_IN = srgb(255, 226, 110)
WATER = srgb(90, 196, 240)
SNOW = srgb(240, 250, 255)
GOODS = [srgb(250, 250, 250), srgb(110, 210, 200), srgb(240, 200, 80), srgb(230, 96, 90), srgb(150, 120, 220)]


def goods_row(x1, x2, y, z, depth, seed, front=1):
    """Small stacked goods along a shelf board (boxes, folded linen, jars)."""
    out = []
    x = x1 + 0.45
    k = 0
    while x < x2 - 0.45:
        kind = (k + seed) % 4
        c = GOODS[(k * 3 + seed) % len(GOODS)]
        if kind == 0:  # folded stack
            for s in range(3):
                out.append(box((0.9, depth * 0.7, 0.22), (x + 0.45, y, z + 0.13 + s * 0.24), c, bevel=0.08, segments=1))
            w = 0.9
        elif kind == 1:  # box
            out.append(box((0.8, depth * 0.65, 0.8), (x + 0.4, y, z + 0.42), c, bevel=0.06, segments=1))
            w = 0.8
        elif kind == 2:  # jar
            out.append(lathe([(0.0, 0), (0.26, 0), (0.3, 0.1), (0.3, 0.55), (0.2, 0.62), (0.2, 0.7), (0.0, 0.7)], (x + 0.3, y, z), c, verts=8))
            out.append(cyl(0.22, 0.08, (x + 0.3, y, z + 0.74), WOOD_DARK, verts=8, bevel=0))
            w = 0.6
        else:  # bottle
            out.append(lathe([(0.0, 0), (0.18, 0), (0.2, 0.5), (0.08, 0.72), (0.08, 0.86), (0.0, 0.86)], (x + 0.22, y, z), c, verts=6))
            w = 0.44
        x += w + 0.2
        k += 1
    return out


def stove():
    """Kitchen stove counter: 2.4 deep (X) x 9 long (Blender Y) x 3 tall, front +X.
    Burners sit at Blender y +2.5 and 0 (Roblox z -2.5, 0), prep board at y -2.5."""
    parts = [
        box((2.4, 9.0, 2.75), (0, 0, 1.38), CREAM, bevel=0.12),
        box((2.6, 9.2, 0.26), (0, 0, 2.88), STEEL, bevel=0.08),  # steel top
        box((2.5, 9.1, 0.3), (0.04, 0, 0.15), TEAL, bevel=0.08),  # kick plinth
        box((0.3, 9.2, 1.4), (-1.15, 0, 3.7), BUTTER, bevel=0.1),  # backsplash
    ]
    for y in (2.5, 0.0):  # oven fronts under the burners
        parts.append(box((0.1, 2.2, 1.6), (1.22, y, 1.35), STEEL_DARK, bevel=0.06))
        parts.append(box((0.1, 1.5, 0.8), (1.27, y, 1.35), GLASS_DARK, bevel=0.05))
        parts.append(cyl(0.07, 1.6, (1.42, y, 2.1), STEEL, verts=8, rot=(math.pi / 2, 0, 0)))
        for dy in (-0.6, -0.2, 0.2, 0.6):
            parts.append(cyl(0.13, 0.14, (1.27, y + dy, 2.55), IRON, verts=10, rot=(0, math.pi / 2, 0)))
        # Iron grate ring around the burner (the game's glowing burner sits inside).
        parts.append(lathe([(1.0, 0.0), (1.12, 0.0), (1.12, 0.1), (1.0, 0.1)], (0, y, 3.01), IRON, verts=12))
        for a in range(4):
            ang = a * math.pi / 2 + math.pi / 4
            parts.append(box((0.12, 0.5, 0.1), (math.cos(ang) * 1.1, y + math.sin(ang) * 1.1, 3.06), IRON, bevel=0.03, rot=(0, 0, ang + math.pi / 2)))
    parts.append(box((0.1, 2.4, 1.9), (1.22, -2.5, 1.35), CREAM, bevel=0.06))  # drawer bank
    for z in (0.85, 1.85):
        parts.append(box((0.1, 2.0, 0.7), (1.26, -2.5, z), BUTTER, bevel=0.05))
        parts.append(box((0.12, 0.7, 0.1), (1.33, -2.5, z), STEEL, bevel=0.03))
    return {"SM_Kitchen_Stove": (build_mesh("SM_Kitchen_Stove", parts), dict(collision="Box"))}


def fridge():
    """Retro fridge 2.6 x 7 x 2.4 (X depth, Y width), front +X."""
    parts = [
        box((2.4, 2.6, 6.9), (0, 0, 3.55), MINT, bevel=0.45, segments=4),
        box((0.08, 2.4, 0.08), (1.22, 0, 4.9), mul(MINT, 0.8), bevel=0.02),  # door split
        box((2.45, 2.65, 0.2), (0, 0, 0.1), STEEL_DARK, bevel=0.06),
    ]
    for z, hh in ((5.9, 1.2), (2.9, 2.2)):
        parts.append(box((0.2, 0.22, hh), (1.32, -0.95, z), STEEL, bevel=0.08))
    parts.append(cyl(0.32, 0.1, (1.24, 0.3, 6.3), RED, verts=16, rot=(0, math.pi / 2, 0)))  # badge
    return {"SM_Kitchen_Fridge": (build_mesh("SM_Kitchen_Fridge", parts), dict(collision="Box"))}


def sink_counter():
    """Sink counter 4 x 3 x 2, front +Y."""
    parts = [
        box((4.0, 2.0, 2.75), (0, 0, 1.38), CREAM, bevel=0.12),
        box((4.2, 2.2, 0.26), (0, 0, 2.88), STEEL, bevel=0.08),
        box((4.1, 2.1, 0.3), (0, 0.04, 0.15), TEAL, bevel=0.08),
    ]
    for x in (-1.0, 1.0):
        parts.append(box((1.8, 0.1, 2.0), (x, 1.02, 1.35), BUTTER, bevel=0.06))
        parts.append(box((0.12, 0.12, 0.6), (x + (0.6 if x < 0 else -0.6), 1.12, 1.6), STEEL, bevel=0.03))
    parts.append(box((2.2, 1.3, 0.12), (0, 0.05, 3.02), STEEL_DARK, bevel=0.05))  # basin rim
    parts.append(box((1.9, 1.0, 0.1), (0, 0.05, 2.98), srgb(110, 170, 210), bevel=0.04))  # water/basin
    neck = [(0.0, 0.0), (0.16, 0.0), (0.16, 0.12), (0.08, 0.2), (0.08, 1.1), (0.0, 1.12)]
    parts.append(lathe(neck, (0, -0.65, 3.01), STEEL, verts=10))
    parts.append(cyl(0.08, 0.7, (0, -0.35, 4.1), STEEL, verts=8, rot=(math.pi / 2, 0, 0)))
    parts.append(cyl(0.1, 0.25, (0, 0.0, 4.0), STEEL, verts=8))
    for x in (-0.45, 0.45):
        parts.append(cyl(0.12, 0.14, (x, -0.65, 3.12), RED if x < 0 else BIN, verts=10))
    return {"SM_Kitchen_Sink": (build_mesh("SM_Kitchen_Sink", parts), dict(collision="Box"))}


def pantry_shelf():
    """Open pantry shelf 5 wide x 6.4 tall x 1.6 deep, front +Y, with food goods."""
    parts = []
    for x in (-2.5, 2.5):
        parts.append(box((0.3, 1.6, 6.4), (x, 0, 3.2), WOOD_DARK, bevel=0.08))
    parts.append(box((5.3, 0.15, 6.2), (0, -0.75, 3.15), WOOD_PANEL, bevel=0.04))
    for z in (0.3, 2.4, 4.5, 6.3):
        parts.append(box((5.0, 1.6, 0.22), (0, 0, z), WOOD, bevel=0.06))
    # Level 1: veggie crate + flour sack; level 2: egg cartons + bun basket; level 3: jars.
    parts.append(box((1.8, 1.2, 0.9), (-1.2, 0.05, 0.86), WOOD_LIGHT, bevel=0.06))
    for i in range(5):
        parts.append(blob(0.3, (-1.9 + i * 0.35, 0.05, 1.42), LEAF_LIGHT if i % 2 else LEAF, lump=0.25, seed=60 + i, segs=8, rings=6))
    parts.append(blob(0.75, (1.2, 0.05, 1.18), srgb(226, 206, 160), squash=(0.85, 0.7, 1.15), lump=0.1, seed=66))
    parts.append(cyl(0.25, 0.25, (1.2, 0.05, 2.05), srgb(200, 170, 120), verts=10, radius2=0.12))
    for i in range(2):
        parts.append(box((1.3, 0.9, 0.35), (-1.6 + i * 1.4, 0.05, 2.7 + i * 0.36), srgb(232, 220, 196), bevel=0.06))
    parts.append(lathe([(0.0, 0), (0.6, 0), (0.8, 0.55), (0.0, 0.55)], (1.4, 0.05, 2.53), WOOD_LIGHT, verts=14))
    for i in range(3):
        parts.append(blob(0.32, (1.2 + i * 0.25, 0.05, 3.15), srgb(226, 160, 80), squash=(1, 1, 0.65), lump=0.06, seed=70 + i, segs=10, rings=7))
    parts += goods_row(-2.3, 2.3, 0.05, 4.62, 1.2, 3)
    return {"SM_Kitchen_Pantry": (build_mesh("SM_Kitchen_Pantry", parts), dict(collision="Box"))}


def linen_shelf():
    """Linen closet shelf 8 wide x 6 tall x 2 deep, front -Y (Roblox +Z)."""
    parts = []
    for x in (-4.0, 0.0, 4.0):
        parts.append(box((0.3, 2.0, 6.0), (x, 0, 3.0), WOOD_DARK, bevel=0.08))
    parts.append(box((8.3, 0.15, 5.8), (0, 0.95, 2.95), WOOD_PANEL, bevel=0.04))
    parts.append(box((8.5, 2.2, 0.3), (0, 0, 6.05), WOOD_DARK, bevel=0.1))
    for z in (0.25, 2.1, 4.0):
        parts.append(box((8.0, 2.0, 0.2), (0, 0, z), WOOD, bevel=0.06))
    # Folded sheet stacks (left bay) and rolled towels (right bay).
    for z in (0.35, 2.2, 4.1):
        for x in (-3.0, -1.0):
            for s in range(4):
                parts.append(box((1.6, 1.4, 0.3), (x, -0.1, z + 0.17 + s * 0.32), LINEN if s % 2 == 0 else mul(LINEN, 0.95), bevel=0.12, segments=1))
        for x in (1.0, 2.2, 3.4):
            for r in range(2):
                parts.append(cyl(0.45, 1.5, (x, -0.1, z + 0.48 + r * 0.82), TEAL if (r + int(x)) % 2 else srgb(120, 210, 200), verts=10, rot=(math.pi / 2, 0, 0)))
    for x in (-2.0, 2.2):
        parts.append(box((1.2, 0.08, 0.35), (x, -1.05, 6.05), BRASS, bevel=0.03))
    return {"SM_Station_LinenShelf": (build_mesh("SM_Station_LinenShelf", parts), dict(collision="Box"))}


def dumpster():
    """Dumpster 6 x 4 x 4 (X long), lids on top, wheels."""
    parts = [
        box((6.0, 4.0, 3.4), (0, 0, 2.0), GREEN_BIN, bevel=0.2),
        box((6.3, 4.3, 0.3), (0, 0, 3.6), GREEN_BIN_DARK, bevel=0.1),  # top rim
        box((6.1, 0.3, 0.5), (0, 2.1, 2.4), GREEN_BIN_DARK, bevel=0.1),  # front rib
        box((6.1, 0.3, 0.5), (0, 2.1, 1.1), GREEN_BIN_DARK, bevel=0.1),
    ]
    for x in (-1.5, 1.5):
        parts.append(box((2.9, 4.1, 0.25), (x, -0.25, 3.95), srgb(30, 70, 46), bevel=0.08, rot=(0.12, 0, 0)))
        parts.append(box((0.8, 0.2, 0.2), (x, 1.85, 4.05), STEEL_DARK, bevel=0.06))
    for x in (-3.05, 3.05):
        parts.append(box((0.3, 1.6, 0.4), (x, 0, 3.0), STEEL_DARK, bevel=0.08))  # lift pockets
    for x in (-2.4, 2.4):
        for y in (-1.5, 1.5):
            parts.append(cyl(0.35, 0.3, (x, y, 0.35), IRON, verts=12, rot=(0, math.pi / 2, 0)))
    parts.append(box((1.2, 0.08, 1.2), (0, 2.03, 1.75), srgb(240, 240, 240), bevel=0.04))
    parts.append(box((0.7, 0.1, 0.7), (0, 2.08, 1.75), GREEN_BIN, bevel=0.04, rot=(0, math.pi / 4, 0)))
    return {"SM_Station_Dumpster": (build_mesh("SM_Station_Dumpster", parts), dict(collision="Box"))}


def breaker_panel():
    """Breaker panel 1 deep (X) x 3 wide (Y) x 4 tall, front +X, origin at its centre."""
    parts = [
        box((0.9, 3.0, 4.0), (0, 0, 0), srgb(150, 156, 166), bevel=0.15),
        box((0.12, 2.6, 3.6), (0.5, 0, 0), srgb(176, 182, 192), bevel=0.06),
        box((0.12, 0.3, 0.6), (0.6, 1.0, 0), STEEL_DARK, bevel=0.05),  # latch
        box((0.3, 0.4, 0.9), (0.7, -0.6, 0.6), RED, bevel=0.08),  # big lever
        box((0.5, 0.25, 0.25), (0.9, -0.6, 1.0), IRON, bevel=0.06),
        cyl(0.18, 2.5, (-0.1, 0.9, 3.2), STEEL_DARK, verts=10),  # conduit up
    ]
    tri = [(-0.55, -0.45), (0.55, -0.45), (0.0, 0.5)]
    sign = extrude_profile([(y, z) for y, z in tri], 0, 0.06, srgb(255, 210, 50), bevel=0.02)
    sign.location = (0.6, 0.2, 0.7)
    sign.rotation_euler = (0, 0, 0)
    parts.append(sign)
    parts.append(box((0.08, 0.12, 0.45), (0.64, 0.22, 0.75), IRON, bevel=0.02, rot=(0.4, 0, 0)))
    return {"SM_Station_Breaker": (build_mesh("SM_Station_Breaker", parts), dict(collision="Box"))}


def shop_counter():
    """Shop counter 3 deep (X) x 9 long (Y) x 3 tall, front -X (facing the door)."""
    parts = [
        box((3.0, 9.0, 2.75), (0, 0, 1.38), MINT, bevel=0.12),
        box((3.3, 9.3, 0.25), (0, 0, 2.88), WOOD, bevel=0.08),
        box((3.1, 9.1, 0.3), (0, 0, 0.15), TEAL_DARK, bevel=0.08),
    ]
    for y in (-3.0, 0.0, 3.0):
        parts.append(box((0.1, 2.6, 1.8), (-1.52, y, 1.45), CREAM, bevel=0.06))
        parts.append(box((0.12, 2.2, 1.4), (-1.56, y, 1.45), mul(MINT, 0.85), bevel=0.06))
    register = [
        box((1.2, 1.4, 0.7), (0.3, -2.8, 3.35), srgb(70, 74, 86), bevel=0.1),
        box((0.9, 1.1, 0.2), (-0.2, -2.8, 3.62), srgb(110, 116, 130), bevel=0.05, rot=(0, 0.35, 0)),
        box((0.3, 1.0, 0.5), (0.65, -2.8, 3.95), srgb(70, 74, 86), bevel=0.06),
    ]
    screen = [box((0.08, 0.8, 0.36), (0.48, -2.8, 4.0), srgb(110, 255, 150), bevel=0.02)]
    return {
        "SM_Shop_Counter": (build_mesh("SM_Shop_Counter", parts + register), dict(collision="Box")),
        "SM_Shop_RegisterScreen": (build_mesh("SM_Shop_RegisterScreen", screen, "glow"), dict(glow=True, collision="None")),
    }


def shop_shelf():
    """Shop shelf unit 10.5 long (X) x 6.4 tall x 1.8 deep, front +Y, stocked."""
    parts = []
    for x in (-5.25, 5.25):
        parts.append(box((0.3, 1.8, 6.4), (x, 0, 3.2), WOOD_DARK, bevel=0.08))
    parts.append(box((10.8, 0.15, 6.2), (0, -0.85, 3.15), WOOD_PANEL, bevel=0.04))
    for i, z in enumerate((0.3, 2.3, 4.3, 6.3)):
        parts.append(box((10.5, 1.8, 0.22), (0, 0, z), WOOD, bevel=0.06))
        if z < 6:
            parts.append(box((10.5, 0.08, 0.3), (0, 0.92, z + 0.05), MINT, bevel=0.03))  # price strip
            parts += goods_row(-5.0, 5.0, 0.05, z + 0.11, 1.3, i)
    return {"SM_Shop_Shelf": (build_mesh("SM_Shop_Shelf", parts), dict(collision="Box"))}


def car(prefix, wagon):
    """Guest car, origin on the ground at its centre; front = Roblox -Z (Blender +Y).
    Body 4.6 wide x 9 long; old pivot height (body centre) was 1.2."""
    L, W = 9.0, 4.6
    cabin_len = 6.0 if wagon else 4.8
    cabin_y = -1.4 if wagon else -0.8  # Blender y (Roblox z +1.4 / +0.8)
    body = [
        taper_box((W, L, 1.35), (0, 0, 1.22), NEUTRAL, top=(0.94, 0.96), bevel=0.55, segments=4),
        taper_box((W - 0.35, cabin_len, 1.45), (0, cabin_y, 2.55), NEUTRAL, top=(0.8, 0.66), bevel=0.45, segments=4),
        box((W + 0.08, L - 1.2, 0.3), (0, 0, 0.85), mul(NEUTRAL, 0.85), bevel=0.12),  # lower side swell
    ]
    for y in (L / 2 - 1.75, -(L / 2 - 1.75)):  # wheel arches
        body.append(box((W + 0.1, 2.5, 0.5), (0, y, 1.55), mul(NEUTRAL, 0.92), bevel=0.22))
    # Slanted windshield / rear glass follow the tapered cabin.
    slope = math.atan2(cabin_len * 0.17, 1.45)
    glass = [
        box((W - 1.0, 0.14, 1.15), (0, cabin_y + cabin_len * 0.5 - 0.62, 2.6), GLASS_DARK, bevel=0.08, rot=(-slope, 0, 0)),
        box((W - 1.0, 0.14, 1.1), (0, cabin_y - cabin_len * 0.5 + 0.62, 2.6), GLASS_DARK, bevel=0.08, rot=(slope, 0, 0)),
    ]
    side_slope = math.atan2((W - 0.35) * 0.1, 1.45)
    for side, x in ((-1, -(W / 2 - 0.42)), (1, W / 2 - 0.42)):
        n = 3 if wagon else 2
        span = cabin_len * 0.66
        seg = span / n
        for k in range(n):
            glass.append(
                box((0.12, seg - 0.22, 0.95), (x, cabin_y - span / 2 + seg * (k + 0.5), 2.6), GLASS_DARK, bevel=0.05, rot=(0, -side * side_slope, 0))
            )
    wheels = []
    for x in (-(W / 2 - 0.1), W / 2 - 0.1):
        for y in (L / 2 - 1.75, -(L / 2 - 1.75)):
            wheels.append(cyl(0.95, 0.8, (x, y, 0.95), srgb(30, 30, 34), verts=18, rot=(0, math.pi / 2, 0), bevel=0.15))
            wheels.append(cyl(0.48, 0.86, (x, y, 0.95), srgb(206, 208, 214), verts=14, rot=(0, math.pi / 2, 0), bevel=0.08))
    trim = [
        box((W + 0.2, 0.42, 0.38), (0, L / 2 + 0.05, 0.75), STEEL, bevel=0.15),
        box((W + 0.2, 0.42, 0.38), (0, -(L / 2 + 0.05), 0.75), STEEL, bevel=0.15),
        box((1.9, 0.14, 0.45), (0, L / 2 + 0.02, 1.25), srgb(60, 60, 66), bevel=0.06),  # grille
        box((W * 0.6, cabin_len * 0.55, 0.1), (0, cabin_y, 3.3), STEEL_DARK, bevel=0.04),  # roof rack
    ]
    for x in (-(W / 2 + 0.06), W / 2 + 0.06):
        trim.append(box((0.08, L - 1.6, 0.2), (x, 0, 1.4), STEEL, bevel=0.04))
        trim.append(box((0.08, 0.3, 0.12), (x, cabin_y + 0.6, 1.85), STEEL, bevel=0.03))  # door handle
    lights = []
    for x in (-1.5, 1.5):
        lights.append(blob(0.34, (x, L / 2 - 0.05, 1.3), srgb(255, 246, 200), squash=(1.2, 0.5, 0.9), lump=0, segs=12, rings=8))
        lights.append(box((0.8, 0.12, 0.38), (x * 1.05, -(L / 2 - 0.02), 1.35), srgb(255, 70, 60), bevel=0.06))
    return {
        prefix + "_Body": (build_mesh(prefix + "_Body", body, "tint"), dict(tint=True, collision="Box")),
        prefix + "_Glass": (build_mesh(prefix + "_Glass", glass), dict(collision="None")),
        prefix + "_Wheels": (build_mesh(prefix + "_Wheels", wheels), dict(collision="None")),
        prefix + "_Trim": (build_mesh(prefix + "_Trim", trim), dict(collision="None")),
        prefix + "_Lights": (build_mesh(prefix + "_Lights", lights, "glow"), dict(glow=True, collision="None")),
    }


def car_sedan():
    return car("SM_Vehicle_Sedan", False)


def car_wagon():
    return car("SM_Vehicle_Wagon", True)


def picnic_table():
    """Picnic table: top 7 x 3 at 2.6, benches each side, A-frame legs."""
    parts = []
    for i in range(4):
        parts.append(box((7.0, 0.7, 0.22), (0, -1.1 + i * 0.73, 2.7), WOOD, bevel=0.08))
    for side in (-1, 1):
        for i in range(2):
            parts.append(box((7.0, 0.45, 0.2), (0, side * (2.0 + i * 0.5), 1.45), WOOD, bevel=0.07))
    for x in (-2.6, 2.6):
        for side in (-1, 1):
            parts.append(box((0.3, 0.3, 3.2), (x, side * 1.05, 1.35), WOOD_DARK, bevel=0.08, rot=(side * 0.6, 0, 0)))
        parts.append(box((0.3, 5.0, 0.25), (x, 0, 1.25), WOOD_DARK, bevel=0.08))
    return {"SM_Yard_PicnicTable": (build_mesh("SM_Yard_PicnicTable", parts), dict(collision="Box"))}


def parasol():
    """Striped patio umbrella, 7 wide, ~6.5 tall."""
    parts = [
        cyl(0.14, 6.2, (0, 0, 3.1), CREAM, verts=10),
        cyl(0.6, 0.25, (0, 0, 0.12), STEEL_DARK, verts=14),
        blob(0.2, (0, 0, 6.6), RED, lump=0, segs=10, rings=7),
    ]
    n = 8
    for i in range(n):
        a0 = i * 2 * math.pi / n
        a1 = (i + 1) * 2 * math.pi / n
        r, top, rim = 3.6, 6.5, 5.3
        pts = [(0, 0, top), (math.cos(a0) * r, math.sin(a0) * r, rim), (math.cos(a1) * r, math.sin(a1) * r, rim)]
        bm = bmesh.new()
        vs = [bm.verts.new(p) for p in pts]
        mid = bm.verts.new(((pts[1][0] + pts[2][0]) * 0.5 * 0.95, (pts[1][1] + pts[2][1]) * 0.5 * 0.95, rim + 0.1))
        bm.faces.new((vs[0], vs[1], mid))
        bm.faces.new((vs[0], mid, vs[2]))
        mesh = bpy.data.meshes.new("panel")
        bm.to_mesh(mesh)
        bm.free()
        o = bpy.data.objects.new("panel", mesh)
        scene.collection.objects.link(o)
        solid = o.modifiers.new("Solidify", "SOLIDIFY")  # thin sheet: visible from below too
        solid.thickness = 0.08
        _apply_modifiers(o)
        parts.append(finish(o, RED if i % 2 == 0 else CREAM, smooth_angle=30))
    for i in range(n):
        a = (i + 0.5) * 2 * math.pi / n
        parts.append(blob(0.18, (math.cos(a) * 3.45, math.sin(a) * 3.45, 5.25), RED if i % 2 else CREAM, squash=(1, 1, 0.6), lump=0, segs=8, rings=5))
    return {"SM_Yard_Parasol": (build_mesh("SM_Yard_Parasol", parts), dict(collision="None"))}


def fence():
    """Fence section 6 long (X from 0 to 6): post at x=0, two rails; plus a lone end post."""
    section = [
        box((0.8, 0.8, 4.0), (0, 0, 2.0), WOOD_DARK, bevel=0.12),
        box((1.05, 1.05, 0.32), (0, 0, 4.12), WOOD, bevel=0.1),
        blob(0.28, (0, 0, 4.42), WOOD, lump=0, segs=10, rings=7),
    ]
    for z in (1.5, 3.1):
        section.append(box((6.0, 0.35, 0.5), (3.0, 0, z), WOOD, bevel=0.1))
    post = [
        box((0.8, 0.8, 4.0), (0, 0, 2.0), WOOD_DARK, bevel=0.12),
        box((1.05, 1.05, 0.32), (0, 0, 4.12), WOOD, bevel=0.1),
        blob(0.28, (0, 0, 4.42), WOOD, lump=0, segs=10, rings=7),
    ]
    return {
        "SM_Yard_FenceSection": (build_mesh("SM_Yard_FenceSection", section), dict(collision="Box")),
        "SM_Yard_FencePost": (build_mesh("SM_Yard_FencePost", post), dict(collision="Box")),
    }


def mailbox():
    parts = [
        box((0.4, 0.4, 3.5), (0, 0, 1.75), WOOD_DARK, bevel=0.08),
        box((1.0, 1.4, 0.18), (0, 0, 3.35), WOOD, bevel=0.06),
    ]
    pts = [(0.6, 0.0)] + [(0.6 * math.cos(math.pi * t / 10), 0.55 + 0.6 * math.sin(math.pi * t / 10)) for t in range(11)] + [(-0.6, 0.0)]
    body = extrude_profile([(y, z) for y, z in pts], 0, 2.0, srgb(70, 110, 190), bevel=0.08)
    body.rotation_euler = (0, 0, math.pi / 2)
    body.location = (0, 0, 3.45)
    parts.append(body)
    parts.append(box((0.1, 0.1, 0.9), (0.68, -0.4, 4.1), IRON, bevel=0.03))
    parts.append(box((0.08, 0.5, 0.35), (0.7, -0.2, 4.4), RED, bevel=0.04))
    return {"SM_Yard_Mailbox": (build_mesh("SM_Yard_Mailbox", parts), dict(collision="Box"))}


def vending_machine():
    """Vending machine 3 x 6 x 2.4, front +Y; lit window is a glow mesh."""
    parts = [
        box((3.0, 2.4, 6.0), (0, 0, 3.0), srgb(210, 56, 56), bevel=0.2),
        box((3.1, 2.5, 0.35), (0, 0, 0.18), srgb(60, 30, 30), bevel=0.08),
        box((2.7, 0.12, 0.7), (0, 1.22, 5.4), CREAM, bevel=0.06),  # logo band
        box((0.7, 0.14, 3.0), (0.95, 1.22, 2.9), srgb(170, 40, 40), bevel=0.06),  # control column
        box((0.3, 0.1, 0.4), (0.95, 1.3, 3.6), IRON, bevel=0.03),
        box((0.5, 0.1, 0.3), (0.95, 1.3, 2.6), IRON, bevel=0.03),
        box((1.7, 0.16, 0.6), (-0.35, 1.22, 0.85), IRON, bevel=0.06),  # pickup slot
    ]
    for r in range(4):
        for c in range(4):
            parts.append(cyl(0.16, 0.55, (-1.05 + c * 0.42, 0.95, 1.85 + r * 0.82), GOODS[(r + c) % len(GOODS)], verts=6, bevel=0))
    window = [box((1.9, 0.08, 3.3), (-0.35, 1.2, 3.25), srgb(220, 240, 255), bevel=0.06)]
    return {
        "SM_Yard_Vending": (build_mesh("SM_Yard_Vending", parts), dict(collision="Box")),
        "SM_Yard_Vending_Window": (build_mesh("SM_Yard_Vending_Window", window, "glow"), dict(glow=True, collision="None")),
    }


def ice_machine():
    """Ice machine 3 x 5 x 2.4, front +Y, snowflake emblem."""
    parts = [
        box((3.0, 2.4, 5.0), (0, 0, 2.5), srgb(70, 130, 210), bevel=0.2),
        box((3.1, 2.5, 0.3), (0, 0, 0.15), srgb(40, 70, 120), bevel=0.08),
        box((2.5, 0.12, 2.6), (0, 1.22, 1.9), SNOW, bevel=0.1),  # bin door
        box((1.2, 0.18, 0.2), (0, 1.32, 3.0), STEEL, bevel=0.05),
        box((2.6, 0.12, 1.1), (0, 1.22, 4.2), srgb(220, 236, 255), bevel=0.08),
    ]
    for a in range(3):
        parts.append(box((0.14, 0.1, 0.85), (0, 1.3, 4.2), srgb(70, 130, 210), bevel=0.02, rot=(0, a * math.pi / 3, 0)))
    return {"SM_Yard_IceMachine": (build_mesh("SM_Yard_IceMachine", parts), dict(collision="Box"))}


def campfire():
    """Campfire: stone ring, crossed logs, glowing embers and flames (glow)."""
    parts = [cyl(2.4, 0.3, (0, 0, 0.15), srgb(70, 60, 56), verts=20)]
    for k in range(9):
        a = k / 9 * math.pi * 2
        parts.append(blob(0.6, (math.cos(a) * 2.5, math.sin(a) * 2.5, 0.4), ROCK, squash=(1.2, 1.0, 0.75), lump=0.3, seed=80 + k, segs=8, rings=6))
    for k in range(5):
        a = k / 5 * math.pi * 2
        # Leaning inward like a teepee: tilt around the tangent axis.
        log = cyl(0.24, 2.4, (math.cos(a) * 0.55, math.sin(a) * 0.55, 1.0), WOOD_DARK, verts=8)
        log.rotation_euler = (0, 0.75, a + math.pi)
        parts.append(log)
    fire = [blob(0.75, (0, 0, 0.75), srgb(255, 110, 40), squash=(1.2, 1.2, 0.45), lump=0.2, seed=90, segs=10, rings=7)]
    for k, (x, y, h, r) in enumerate([(0, 0, 2.6, 0.55), (0.45, 0.2, 1.8, 0.4), (-0.4, 0.3, 1.9, 0.4), (0.1, -0.45, 1.7, 0.38)]):
        fire.append(lathe([(0.0, 0), (r, 0.15), (r * 0.9, h * 0.35), (r * 0.45, h * 0.7), (0.0, h)], (x, y, 0.8), FLAME_OUT if k % 2 == 0 else FLAME_IN, verts=10))
    fire.append(lathe([(0.0, 0), (0.3, 0.1), (0.24, 0.7), (0.0, 1.4)], (0, 0, 0.85), FLAME_IN, verts=10))
    seat = [cyl(0.7, 5.0, (0, 0, 0.7), WOOD, verts=14, rot=(0, math.pi / 2, 0), bevel=0.12)]
    for x in (-2.5, 2.5):
        seat.append(cyl(0.55, 0.05, (x, 0, 0.7), WOOD_LIGHT, verts=14, rot=(0, math.pi / 2, 0)))
    return {
        "SM_Yard_Campfire": (build_mesh("SM_Yard_Campfire", parts), dict(collision="Hull")),
        "SM_Yard_Campfire_Flames": (build_mesh("SM_Yard_Campfire_Flames", fire, "glow"), dict(glow=True, collision="None")),
        "SM_Yard_LogSeat": (build_mesh("SM_Yard_LogSeat", seat), dict(collision="Box")),
    }


def fountain():
    """Fountain: basin 10 wide, column, top bowl; water surfaces as a separate mesh."""
    stone = srgb(222, 214, 200)
    parts = [
        lathe([(0.0, 0.0), (5.0, 0.0), (5.05, 0.9), (5.3, 1.05), (5.3, 1.3), (4.6, 1.3), (4.5, 0.4), (0.0, 0.4)], (0, 0, 0), stone, verts=28),
        lathe([(0.0, 0.4), (0.75, 0.4), (0.6, 1.2), (0.65, 2.6), (0.5, 3.4), (0.0, 3.4)], (0, 0, 0), stone, verts=16),
        lathe([(0.0, 3.4), (0.4, 3.4), (1.6, 3.85), (1.7, 4.15), (1.45, 4.2), (0.3, 3.9), (0.0, 3.9)], (0, 0, 0), stone, verts=20),
        lathe([(0.0, 4.0), (0.22, 4.0), (0.18, 4.6), (0.0, 4.7)], (0, 0, 0), stone, verts=10),
    ]
    parts.append(lathe([(5.32, 1.0), (5.36, 1.0), (5.36, 1.18), (5.32, 1.18)], (0, 0, 0), srgb(70, 160, 190), verts=28))  # tile band
    for k in range(8):
        a = k / 8 * math.pi * 2
        parts.append(blob(0.35, (math.cos(a) * 5.0, math.sin(a) * 5.0, 1.42), stone, squash=(1, 1, 0.5), lump=0, segs=10, rings=6))
    water = [
        cyl(4.55, 0.15, (0, 0, 1.0), WATER, verts=28),
        cyl(1.4, 0.1, (0, 0, 4.05), WATER, verts=18),
        lathe([(0.0, 4.6), (0.16, 4.62), (0.1, 5.4), (0.0, 5.5)], (0, 0, 0), srgb(170, 225, 250), verts=10),  # spout jet
        lathe([(1.5, 1.05), (1.62, 1.05), (1.72, 2.5), (1.6, 4.1), (1.48, 4.1), (1.58, 2.5)], (0, 0, 0), srgb(150, 215, 245), verts=20),  # falling sheet
    ]
    return {
        "SM_Yard_Fountain": (build_mesh("SM_Yard_Fountain", parts), dict(collision="Hull")),
        "SM_Yard_Fountain_Water": (build_mesh("SM_Yard_Fountain_Water", water), dict(collision="None")),
    }


# ======================================================================
# Batch 3: buildings (environment-artist + stylized/cartoon style)
#   * Shells on the exact gameplay footprints of MapDecor/MapBuilder
#     (walls 1 stud thick centred on the same lines, same door gaps and
#     heights), so the gameplay hitboxes, prompts and waypoints stay valid.
#   * Each building is built in its world orientation with the local origin
#     at the footprint centre on the floor; info["place"] lists the scale-1
#     Roblox world positions of that origin (several for instanced rooms).
#   * One mesh per role: Walls (cream shell, gables, ceiling), Trim (teal
#     frames, base, shutters, posts), Roof, Glass (transparent in game),
#     Awning (stripes), Sign (board) and Glow (3D letters, bulbs, lamps).
# ======================================================================
WALL_CREAM = srgb(246, 230, 200)
WALL_LINE = srgb(220, 198, 162)
MINT_LINE = srgb(118, 186, 168)
BUTTER_LINE = srgb(232, 200, 116)
ROOF_RED = srgb(212, 74, 58)
ROOF_LINE = srgb(178, 56, 46)
ROOF_DARK = srgb(126, 44, 40)
BRICK = srgb(180, 96, 72)
GLASS_BLUE = srgb(164, 216, 242)
CEILING = srgb(248, 242, 228)
SIGN_RED = srgb(156, 44, 44)
SIGN_TEAL = srgb(40, 96, 90)
SIGN_NAVY = srgb(34, 60, 76)
CONCRETE = srgb(190, 184, 172)
LETTER = srgb(255, 230, 130)
LETTER_PINK = srgb(255, 120, 196)
LETTER_WHITE = srgb(255, 252, 244)
BULB = srgb(255, 238, 170)
DOOR_TOP = 9.0
ROOM_SHIFT = 18  # MapDecor.ROOM_SHIFT: rooms are moved north (+Z) by this


def _along(axis, p, c, out, u=0.0, v=0.0, z=0.0):
    """Point on a wall: axis "x" = wall along X at y=c, "y" = along Y at x=c.
    u runs along the wall, v outward (out = +1/-1)."""
    if axis == "x":
        return (p + u, c + out * v, z)
    return (c + out * v, p + u, z)


def _size(axis, su, sv, sz):
    return (su, sv, sz) if axis == "x" else (sv, su, sz)


def wall(axis, a, b, c, height, colour, openings=(), t=1.0, bevel=0.05):
    """Wall run a..b with rectangular openings (o1, o2, bottom, top)."""
    parts = []

    def piece(p1, p2, z1, z2):
        if p2 - p1 < 0.05 or z2 - z1 < 0.05:
            return
        parts.append(
            box(_size(axis, p2 - p1, t, z2 - z1), _along(axis, (p1 + p2) / 2, c, 1, z=(z1 + z2) / 2), colour, bevel=bevel, segments=1)
        )

    cursor = a
    for o1, o2, zb, zt in sorted(openings):
        piece(cursor, o1, 0, height)
        piece(o1, o2, 0, zb)
        piece(o1, o2, zt, height)
        cursor = o2
    piece(cursor, b, 0, height)
    return parts


def _free_spans(a, b, openings, z, margin=0.15):
    """Free stretches of a wall run at height z; `margin` keeps trims clear
    of the frames around openings (frames stick out past the hole)."""
    spans, cursor = [], a
    for o1, o2, zb, zt in sorted(openings):
        if zb - max(0.2, margin) <= z <= zt + max(0.2, margin):
            spans.append((cursor, o1 - margin))
            cursor = o2 + margin
    spans.append((cursor, b))
    return [(s1, s2) for s1, s2 in spans if s2 - s1 > 0.4]


def siding(axis, a, b, c, out, height, colour, openings=(), step=2.0, margin=0.15):
    """Clapboard lines on the outside face (cartoon horizontal siding)."""
    parts, z = [], 2.2
    while z < height - 0.8:
        for s1, s2 in _free_spans(a, b, openings, z, margin):
            parts.append(box(_size(axis, s2 - s1, 0.14, 0.16), _along(axis, (s1 + s2) / 2, c, out, v=0.56, z=z), colour, bevel=0.0))
        z += step
    return parts


def base_trim(axis, a, b, c, out, colour, openings=(), h=0.9):
    return [
        box(_size(axis, s2 - s1, 0.32, h), _along(axis, (s1 + s2) / 2, c, out, v=0.6, z=h / 2), colour, bevel=0.08, segments=1)
        for s1, s2 in _free_spans(a, b, openings, 0.3)
    ]


def corner_boards(x1, x2, y1, y2, height, colour):
    h = height - 0.05  # top just under the wall top: no shared plane (z-fighting)
    return [
        box((0.75, 0.75, h), (x, y, h / 2), colour, bevel=0.1, segments=1)
        for x in (x1 - 0.42, x2 + 0.42)
        for y in (y1 - 0.42, y2 + 0.42)
    ]


def window(axis, p, c, out, w, h, zc, shutters=True, flowers=False, seed=0, glass_colour=None, flower_step=1.0, mullion=None, sill=True):
    """Framed window through a wall: glass pane (own mesh), frame, cross
    mullion, sill, shutters and an optional flower box."""
    trim, glass = [], []
    pane_colour = glass_colour or GLASS_BLUE
    glass = []
    glass.append(box(_size(axis, w, 0.12, h), _along(axis, p, c, out, z=zc), pane_colour, bevel=0.02, segments=1))
    for s in (-1, 1):
        # Frame inset 0.03 into the hole so it never shares the wall's reveal plane.
        trim.append(box(_size(axis, 0.4, 1.3, h + 0.8), _along(axis, p, c, out, u=s * (w / 2 + 0.17), z=zc), TEAL, bevel=0.1, segments=1))
        trim.append(box(_size(axis, w + 0.8, 1.3, 0.4), _along(axis, p, c, out, z=zc + s * (h / 2 + 0.17)), TEAL, bevel=0.1, segments=1))
    bar = mullion or CREAM
    trim.append(box(_size(axis, 0.2, 0.26, h - 0.04), _along(axis, p, c, out, z=zc), bar, bevel=0.0))
    trim.append(box(_size(axis, w - 0.04, 0.26, 0.2), _along(axis, p, c, out, z=zc), bar, bevel=0.0))
    if sill:  # (a flower box below the window replaces the sill)
        trim.append(box(_size(axis, w + 1.3, 0.7, 0.28), _along(axis, p, c, out, v=0.75, z=zc - h / 2 - 0.42), CREAM, bevel=0.08, segments=1))
    if shutters:
        sw = max(0.9, w * 0.42)
        for s in (-1, 1):
            u = s * (w / 2 + 0.45 + sw / 2)
            trim.append(box(_size(axis, sw, 0.18, h + 0.4), _along(axis, p, c, out, u=u, v=0.62, z=zc), TEAL_DARK, bevel=0.06, segments=1))
            for k in (-1, 1):
                trim.append(box(_size(axis, sw - 0.3, 0.08, 0.14), _along(axis, p, c, out, u=u, v=0.74, z=zc + k * h * 0.28), TEAL, bevel=0.0))
    if flowers:
        zb = zc - h / 2 - 1.0
        trim.append(box(_size(axis, w + 0.6, 0.9, 0.75), _along(axis, p, c, out, v=1.05, z=zb), WOOD, bevel=0.12, segments=1))
        n = max(3, int(w / flower_step))
        for i in range(n):
            u = -w / 2 + (i + 0.5) * w / n
            leaf_segs, leaf_rings = (6, 4) if flower_step <= 1.0 else (5, 3)
            trim.append(blob(0.34, _along(axis, p, c, out, u=u, v=1.05, z=zb + 0.45), LEAF, lump=0.2, seed=seed + i, segs=leaf_segs, rings=leaf_rings))
            petal = 0.2 if flower_step <= 1.0 else 0.3
            trim.append(blob(petal, _along(axis, p, c, out, u=u + 0.1, v=1.3, z=zb + 0.75), PETALS[(i + seed) % len(PETALS)], lump=0, segs=6, rings=4))
    return trim, glass


def awning(axis, p, c, out, w, ztop, depth=2.6, angle=24.0, scallops=True):
    """Striped awning sloping out and down from a wall, scalloped valance."""
    parts = []
    a = math.radians(angle)
    n = max(3, int(round(w / 0.85)))
    sw = w / n
    rot = (-a * out, 0, 0) if axis == "x" else (0, a * out, 0)
    for i in range(n):
        u = -w / 2 + (i + 0.5) * sw
        col = RED if i % 2 == 0 else CREAM
        centre = _along(axis, p, c, out, u=u, v=0.5 + depth * math.cos(a) / 2, z=ztop - depth * math.sin(a) / 2)
        parts.append(box(_size(axis, sw, depth, 0.18), centre, col, bevel=0.0, rot=rot))  # abutting, not overlapping
        if scallops:
            edge = _along(axis, p, c, out, u=u, v=0.5 + depth * math.cos(a), z=ztop - depth * math.sin(a) - 0.25)
            parts.append(blob(sw * 0.5, edge, col, squash=(1, 0.35, 0.7) if axis == "x" else (0.35, 1, 0.7), lump=0, segs=6, rings=3))
    # Side cheeks and a wall batten.
    parts.append(box(_size(axis, w + 0.3, 0.3, 0.35), _along(axis, p, c, out, v=0.6, z=ztop + 0.05), RED, bevel=0.08, segments=1))
    return parts


def door_frame(axis, p1, p2, c, top, colour=TEAL):
    return [
        # Inset 0.03 into the opening: no face shares the wall's reveal plane (z-fighting).
        box(_size(axis, 0.7, 1.4, top), _along(axis, p1 - 0.32, c, 1, z=top / 2), colour, bevel=0.1, segments=1),
        box(_size(axis, 0.7, 1.4, top), _along(axis, p2 + 0.32, c, 1, z=top / 2), colour, bevel=0.1, segments=1),
        box(_size(axis, p2 - p1 + 1.6, 1.5, 0.6), _along(axis, (p1 + p2) / 2, c, 1, z=top + 0.27), colour, bevel=0.1, segments=1),
    ]


def gable_roof(x1, x2, y1, y2, base, rise, th=0.7, colour=ROOF_RED, line=ROOF_LINE):
    """Gable roof, ridge along X, covering x1..x2 / y1..y2 (overhang
    included), eaves at `base`. Shingle lips, ridge roll, fascia and
    cream barge boards."""
    roof, trim = [], []
    yc, d = (y1 + y2) / 2, (y2 - y1) / 2
    a = math.atan2(rise, d)
    L = math.hypot(d, rise)
    xc, length = (x1 + x2) / 2, x2 - x1
    for side in (1, -1):
        rot = (-a * side, 0, 0)
        n = Vector((0, side * math.sin(a), math.cos(a)))
        mid = Vector((xc, yc + side * d / 2, base + rise / 2)) + n * (th / 2)
        roof.append(box((length, L + 0.5, th), mid, colour, bevel=0.14, rot=rot))
        k = max(3, int(L / 1.45))
        for i in range(1, k):
            t = i / k
            p = Vector((xc, yc + side * d * t, base + rise * (1 - t))) + n * (th + 0.05)
            roof.append(box((length + 0.05, 0.55, 0.18), p, line, bevel=0.0, rot=rot))
        eave = Vector((xc, y1 if side < 0 else y2, base)) + n * (th / 2) - Vector((0, 0, 0.25))
        roof.append(box((length + 0.5, 0.55, 0.7), eave, ROOF_DARK, bevel=0.12, segments=1))
        for x in (x1 - 0.12, x2 + 0.12):
            trim.append(box((0.32, L + 0.6, 1.0), mid + Vector((x - xc, 0, 0)) - n * 0.1, CREAM, bevel=0.08, segments=1, rot=rot))
    roof.append(cyl(0.6, length + 0.6, (xc, yc, base + rise + th * 0.75), ROOF_DARK, verts=12, rot=(0, math.pi / 2, 0)))
    return roof, trim


def gable_infill(x, ya, yb, yc, d, base, rise, colour, vent=True):
    """Wall triangle under the roof at a gable end (follows the slab underside)."""
    def under(y):
        return base + rise * (1 - abs(y - yc) / d) - 0.05

    pts = [(ya, base), (yb, base), (yb, under(yb))]
    if ya < yc < yb:
        pts.append((yc, under(yc)))
    pts.append((ya, under(ya)))
    parts = [extrude_profile(pts, x, 1.0, colour, bevel=0.0)]
    trim = []
    if vent and ya < yc < yb:
        zc = base + (under(yc) - base) * 0.42
        for s in (-1, 1):
            trim.append(cyl(0.85, 0.3, (x + s * 0.55, yc, zc), TEAL, verts=16, rot=(0, math.pi / 2, 0)))
            for k in (-1, 0, 1):
                trim.append(box((0.12, 1.2, 0.12), (x + s * 0.72, yc, zc + k * 0.35), TEAL_DARK, bevel=0.0))
    return parts, trim


def chimney(x, y, z0, h, colour=BRICK):
    return [
        box((2.6, 2.6, h), (x, y, z0 + h / 2), colour, bevel=0.12, segments=1),
        box((3.2, 3.2, 0.5), (x, y, z0 + h + 0.25), mul(colour, 0.7), bevel=0.12, segments=1),
        box((2.0, 2.0, 0.3), (x, y, z0 + h + 0.6), IRON, bevel=0.06, segments=1),
    ]


def ceiling(x1, x2, y1, y2, h):
    return [box((x2 - x1, y2 - y1, 0.3), ((x1 + x2) / 2, (y1 + y2) / 2, h + 0.05), CEILING, bevel=0.0)]


TEXT_ROT = {"+y": (math.pi / 2, 0, math.pi), "-x": (math.pi / 2, 0, -math.pi / 2), "+x": (math.pi / 2, 0, math.pi / 2)}


def text3d(body, size, loc, facing, colour, depth=0.14, bold=0.035):
    """Chunky 3D letters (built-in font), standing up and facing `facing`."""
    cu = bpy.data.curves.new("txt", "FONT")
    cu.body = body
    cu.size = size
    cu.extrude = depth / 2
    cu.offset = size * bold  # bolder strokes (bigger = outline layer)
    cu.resolution_u = 3
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    o = bpy.data.objects.new("txt", cu)
    scene.collection.objects.link(o)
    o.location = loc
    o.rotation_euler = TEXT_ROT[facing]
    _activate(o)
    bpy.ops.object.convert(target="MESH")
    o = bpy.context.active_object
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return finish(o, colour, smooth_angle=30)


def bulb(loc, r=0.26, colour=BULB):
    return blob(r, loc, colour, lump=0, segs=6, rings=4)


def bulb_line(a, b, n, sag=0.0, r=0.24):
    """Bulbs from a to b (sagging string lights when sag > 0) + their wire."""
    a, b = Vector(a), Vector(b)
    glow, wire, pts = [], [], []
    for i in range(n):
        t = (i + 0.5) / n
        p = a.lerp(b, t) - Vector((0, 0, sag * 4 * t * (1 - t)))
        pts.append(p)
        glow.append(bulb(p - Vector((0, 0, r * 0.9)), r))
    chain = [a] + pts + [b]
    for p, q in zip(chain, chain[1:]):
        seg = q - p
        if seg.length < 1e-3:
            continue
        o = cyl(0.04, seg.length, (p + q) / 2, IRON, verts=4, bevel=0.0)
        o.rotation_euler = seg.to_track_quat("Z", "Y").to_euler()
        wire.append(o)
    return glow, wire


def marquee(board_centre, w, h, front, facing, step=1.0, r=0.22):
    """Bulbs around the edge of a sign board (front = offset to the face)."""
    cx, cy, cz = board_centre
    glow = []
    nx = max(2, int(w / step))
    nz = max(1, int(h / step))
    for i in range(nx + 1):
        u = -w / 2 + i * w / nx
        for z in (cz + h / 2 - 0.3, cz - h / 2 + 0.3):
            glow.append(bulb(_sign_point(facing, cx, cy, u, front, z), r))
    for k in range(1, nz):
        z = cz - h / 2 + 0.3 + k * (h - 0.6) / nz
        for u in (-w / 2, w / 2):
            glow.append(bulb(_sign_point(facing, cx, cy, u, front, z), r))
    return glow


def _sign_point(facing, cx, cy, u, front, z):
    if facing == "+y":
        return (cx + u, cy + front, z)
    if facing == "-x":
        return (cx - front, cy + u, z)
    return (cx + front, cy + u, z)


def sign_board(facing, cx, cy, cz, w, h, colour, border=CREAM, t=0.6):
    """Board + raised border, w along the face."""
    parts = []
    s = (lambda a, b, c: (a, b, c)) if facing == "+y" else (lambda a, b, c: (b, a, c))
    parts.append(box(s(w, t, h), (cx, cy, cz), colour, bevel=0.12, segments=1))
    off = t / 2 + 0.06
    p = (lambda u, z: _sign_point(facing, cx, cy, u, off, z))
    for zz in (cz + h / 2 - 0.15, cz - h / 2 + 0.15):
        parts.append(box(s(w, 0.16, 0.3), p(0, zz), border, bevel=0.05, segments=1))
    for u in (-w / 2 + 0.15, w / 2 - 0.15):
        parts.append(box(s(0.3, 0.16, h), p(u, cz), border, bevel=0.05, segments=1))
    return parts


def out(parts_by_role, prefix, collisions=None, extra=None):
    """Build the role meshes of one building."""
    collisions = collisions or {}
    res = {}
    for role, parts in parts_by_role.items():
        if not parts:
            continue
        name = f"SM_Bld_{prefix}_{role}"
        info = dict(collision=collisions.get(role, "None"))
        if role in ("Glow", "Windows"):
            info["glow"] = True
            res[name] = (build_mesh(name, parts, "glow"), info)
            continue
        if role == "Glass":
            info["glass"] = True
        info.update(extra or {})
        res[name] = (build_mesh(name, parts), info)
    for name in res:
        res[name][1].update(extra or {})
    return res


# ---------------------------------------------------------------- office
def office():
    """Office/lobby: world x 4..40, z -32..-6 (centre 22, -19), walls 14.
    Front (+Y here) = Roblox -Z, the parking side. Gaps: front door 14 wide,
    hall door north, side door east (same as MapDecor.buildLobby)."""
    H = 14
    X1, X2, Y1, Y2 = -18.0, 18.0, -13.0, 13.0
    W, T, G, R, A, S, L = [], [], [], [], [], [], []
    front_open = [(-3.0, 11.0, 0, DOOR_TOP), (-15.0, -9.0, 2.8, 6.8), (12.0, 17.0, 2.8, 6.8)]
    back_open = [(-12.0, 0.0, 0, DOOR_TOP)]
    east_open = [(-5.0, 5.0, 0, DOOR_TOP)]
    west_open = [(1.5, 6.5, 3.4, 7.4)]
    W += wall("x", X1 - 0.5, X2 + 0.5, Y2, H, WALL_CREAM, front_open)
    W += wall("x", X1 - 0.5, X2 + 0.5, Y1, H, WALL_CREAM, back_open)
    W += wall("y", Y1 + 0.5, Y2 - 0.5, X1, H, WALL_CREAM, west_open)
    W += wall("y", Y1 + 0.5, Y2 - 0.5, X2, H, WALL_CREAM, east_open)
    W += siding("x", X1, X2, Y2, 1, H, WALL_LINE, front_open)
    W += siding("x", X1, X2, Y1, -1, H, WALL_LINE, back_open)
    W += siding("y", Y1, Y2, X1, -1, H, WALL_LINE, west_open)
    W += siding("y", Y1, Y2, X2, 1, H, WALL_LINE, east_open)
    W += ceiling(X1 + 0.5, X2 - 0.5, Y1 + 0.5, Y2 - 0.5, H)
    T += base_trim("x", X1, X2, Y2, 1, TEAL, front_open)
    T += base_trim("x", X1, X2, Y1, -1, TEAL, back_open)
    T += base_trim("y", Y1, Y2, X1, -1, TEAL, west_open)
    T += base_trim("y", Y1, Y2, X2, 1, TEAL, east_open)
    T += corner_boards(X1, X2, Y1, Y2, H, CREAM)
    T += door_frame("x", -3.0, 11.0, Y2, DOOR_TOP)
    T += door_frame("x", -12.0, 0.0, Y1, DOOR_TOP)
    T += door_frame("y", -5.0, 5.0, X2, DOOR_TOP)
    for cx, w, seed in ((-12.0, 6.0, 1), (14.5, 5.0, 4)):
        t, g = window("x", cx, Y2, 1, w, 4.0, 4.8, flowers=True, seed=seed)
        T += t
        G += g
        A += awning("x", cx, Y2, 1, w + 1.4, 8.6)
    t, g = window("y", 4.0, X1, -1, 5.0, 4.0, 5.4)
    T += t
    G += g
    A += awning("y", 4.0, X1, -1, 6.4, 9.2)
    # Roof, gables, chimney.
    r, t = gable_roof(-19.5, 19.5, -14.5, 14.5, H, 7.0)
    R += r
    T += t
    for x in (X1, X2):
        w_, t_ = gable_infill(x, Y1 - 0.5, Y2 + 0.5, 0.0, 14.5, H, 7.0, WALL_CREAM)
        W += w_
        T += t_
    R += chimney(12.0, -7.0, 16.0, 7.5)
    # Entrance canopy with posts and string lights (Roblox: 16 x 6 at y 10).
    A.append(box((16.0, 6.0, 0.6), (4.0, 16.0, 10.0), RED, bevel=0.15))
    A.append(box((16.4, 0.4, 0.5), (4.0, 19.05, 9.75), CREAM, bevel=0.1, segments=1))
    for i in range(8):
        A.append(blob(1.0, (-3.0 + i * 2, 19.1, 9.25), RED if i % 2 == 0 else CREAM, squash=(1, 0.18, 0.45), lump=0, segs=8, rings=4))
    for x in (-3.2, 11.2):
        T.append(cyl(0.38, 9.7, (x, 18.5, 4.85), CREAM, verts=12))
        T.append(box((1.0, 1.0, 0.6), (x, 18.5, 0.3), TEAL, bevel=0.12, segments=1))
        T.append(box((0.9, 0.9, 0.4), (x, 18.5, 9.5), TEAL, bevel=0.1, segments=1))
    g, wire = bulb_line((-3.2, 19.3, 9.3), (11.2, 19.3, 9.3), 10, sag=0.5)
    L += g
    T += wire
    # OFFICE sign standing on the front slope (Roblox: 14 x 3.4 at y 16.4).
    S += sign_board("+y", 4.0, 13.0, 16.6, 14.0, 3.4, SIGN_RED)
    for x in (-1.5, 9.5):
        S.append(box((0.5, 0.5, 2.4), (x, 12.6, 15.2), IRON, bevel=0.06, segments=1))
    L.append(text3d("OFFICE", 2.7, (4.0, 13.42, 16.5), "+y", LETTER))
    L += marquee((4.0, 13.0, 16.6), 14.0, 3.4, 0.45, "+y", step=1.4)
    # Porch lamps either side of the door.
    for x in (-4.6, 12.6):
        T.append(box((0.5, 0.4, 0.8), (x, Y2 + 0.7, 7.0), IRON, bevel=0.06, segments=1))
        L.append(blob(0.4, (x, Y2 + 1.0, 6.5), GLOW, squash=(1, 1, 1.25), lump=0, segs=10, rings=6))
    return out(
        {"Walls": W, "Trim": T, "Roof": R, "Glass": G, "Awning": A, "Sign": S, "Glow": L},
        "Office",
        {"Walls": "Precise", "Roof": "Hull"},
        dict(place=[[22, 0, -19]]),
    )


# ---------------------------------------------------------------- rooms
def room_unit():
    """One guest room shell, 14 x 16, walls 12 (MapBuilder Room walls).
    Front (+Y) = Roblox -Z walkway side; door gap 4 x 7.6 in the middle.
    Placed three times (rooms 1-3)."""
    H = 12
    X1, X2, Y1, Y2 = -7.0, 7.0, -8.0, 8.0
    W, T, G, L = [], [], [], []
    front_open = [(-6.0, -3.0, 3.3, 6.3), (-2.0, 2.0, 0, 7.6)]
    back_open = [(1.0, 5.0, 5.2, 8.0)]
    W += wall("x", X1 - 0.5, X2 + 0.5, Y2, H, WALL_CREAM, front_open)
    W += wall("x", X1 - 0.5, X2 + 0.5, Y1, H, WALL_CREAM, back_open)
    W += wall("y", Y1 + 0.5, Y2 - 0.5, X1, H, WALL_CREAM)
    W += wall("y", Y1 + 0.5, Y2 - 0.5, X2, H, WALL_CREAM)
    W += siding("x", X1, X2, Y2, 1, H, WALL_LINE, front_open)
    W += siding("x", X1, X2, Y1, -1, H, WALL_LINE, back_open)
    W += siding("y", Y1, Y2, X1, -1, H, WALL_LINE)
    W += siding("y", Y1, Y2, X2, 1, H, WALL_LINE)
    W += ceiling(X1 + 0.5, X2 - 0.5, Y1 + 0.5, Y2 - 0.5, H)
    T += base_trim("x", X1, X2, Y2, 1, TEAL, front_open)
    T += base_trim("x", X1, X2, Y1, -1, TEAL, back_open)
    T += base_trim("y", Y1, Y2, X1, -1, TEAL)
    T += base_trim("y", Y1, Y2, X2, 1, TEAL)
    T += corner_boards(X1, X2, Y1, Y2, H, CREAM)
    t, g = window("x", -4.5, Y2, 1, 3.0, 3.0, 4.8, shutters=False, flowers=True, seed=2)
    T += t
    G += g
    t, g = window("x", 3.0, Y1, -1, 4.0, 2.8, 6.6, shutters=False)
    T += t
    G += g
    # Brass number plaque (the game writes the number) and a porch lamp.
    T.append(box((1.5, 0.25, 1.5), (3.4, Y2 + 0.62, 6.0), BRASS, bevel=0.1, segments=1))
    T.append(box((0.45, 0.4, 0.75), (-2.95, Y2 + 0.7, 6.6), IRON, bevel=0.06, segments=1))
    L.append(blob(0.36, (-2.95, Y2 + 1.0, 6.15), GLOW, squash=(1, 1, 1.25), lump=0, segs=10, rings=6))
    places = [[cx, 0, 12 + ROOM_SHIFT] for cx in (2, 20, 38)]
    return out({"Walls": W, "Trim": T, "Glass": G, "Glow": L}, "Room", {"Walls": "Precise"}, dict(place=places))


def room_roof():
    """Long roof over the three rooms + walkway (world x -7..46, z -1..21
    before ROOM_SHIFT), walkway posts, beam, string lights, chimneys."""
    W, T, R, L = [], [], [], []
    r, t = gable_roof(-26.5, 26.5, -11.0, 11.0, 12.0, 6.0)
    R += r
    T += t
    # Gable ends on the outer room walls (room 1 west wall, room 3 east wall).
    for x in (-24.5, 25.5):
        w_, t_ = gable_infill(x, -10.5, 6.5, 0.0, 11.0, 12.0, 6.0, WALL_CREAM)
        W += w_
        T += t_
    # Fill the roof space between the rooms so the eave reads as one block.
    # Lintels across the gaps between rooms (front and back) under the eave.
    for x1, x2 in ((-10.5, -6.5), (7.5, 11.5)):
        for y in (6.0, -10.0):
            W.append(box((x2 - x1 + 1.0, 1.0, 1.8), ((x1 + x2) / 2, y, 11.1), WALL_CREAM, bevel=0.05, segments=1))
    posts = (-25.5, -8.5, 9.5, 25.5)
    for x in posts:
        T.append(cyl(0.42, 11.3, (x, 10.6, 5.65), CREAM, verts=12))  # top inside the teal cap
        T.append(box((1.0, 1.0, 0.6), (x, 10.6, 0.3), TEAL, bevel=0.12, segments=1))
        T.append(box((1.1, 1.1, 0.4), (x, 10.6, 11.2), TEAL, bevel=0.1, segments=1))
    T.append(box((52.4, 0.6, 0.6), (0.0, 10.6, 11.7), TEAL, bevel=0.12, segments=1))
    for a, b in zip(posts, posts[1:]):
        g, wire = bulb_line((a, 10.95, 11.25), (b, 10.95, 11.25), 12, sag=0.55, r=0.22)
        L += g
        T += wire
    R += chimney(-15.5, -5.0, 14.6, 4.6)
    R += chimney(16.5, -5.0, 14.6, 4.6)
    return out({"Walls": W, "Trim": T, "Roof": R, "Glow": L}, "RoomRoof", {"Roof": "Hull"}, dict(place=[[19.5, 0, 10 + ROOM_SHIFT]]))


# ---------------------------------------------------------------- linen shed
def linen_shed():
    """Laundry / linen shed: world x 53..67, z -23.5..-8.5 (centre 60, -16),
    walls 12, door in the west wall (-X here), LAUNDRY sign over it."""
    H = 12
    X1, X2, Y1, Y2 = -7.0, 7.0, -7.5, 7.5
    W, T, G, R, A, S, L = [], [], [], [], [], [], []
    west_open = [(-4.0, 4.0, 0, DOOR_TOP)]
    south_open = [(-5.0, -2.0, 4.0, 7.0), (2.0, 5.0, 4.0, 7.0)]
    W += wall("x", X1 - 0.5, X2 + 0.5, Y2, H, WALL_CREAM, south_open)
    W += wall("x", X1 - 0.5, X2 + 0.5, Y1, H, WALL_CREAM)
    W += wall("y", Y1 + 0.5, Y2 - 0.5, X1, H, WALL_CREAM, west_open)
    W += wall("y", Y1 + 0.5, Y2 - 0.5, X2, H, WALL_CREAM)
    W += siding("x", X1, X2, Y2, 1, H, WALL_LINE, south_open)
    W += siding("x", X1, X2, Y1, -1, H, WALL_LINE)
    W += siding("y", Y1, Y2, X1, -1, H, WALL_LINE, west_open)
    W += siding("y", Y1, Y2, X2, 1, H, WALL_LINE)
    W += ceiling(X1 + 0.5, X2 - 0.5, Y1 + 0.5, Y2 - 0.5, H)
    T += base_trim("x", X1, X2, Y2, 1, TEAL, south_open)
    T += base_trim("x", X1, X2, Y1, -1, TEAL)
    T += base_trim("y", Y1, Y2, X1, -1, TEAL, west_open)
    T += base_trim("y", Y1, Y2, X2, 1, TEAL)
    T += corner_boards(X1, X2, Y1, Y2, H, CREAM)
    T += door_frame("y", -4.0, 4.0, X1, DOOR_TOP)
    for cx in (-3.5, 3.5):
        t, g = window("x", cx, Y2, 1, 3.0, 3.0, 5.5, seed=int(cx))
        T += t
        G += g
    A += awning("y", 0.0, X1, -1, 9.6, 9.8)
    # Dryer vent on the east wall.
    T.append(cyl(0.55, 1.2, (X2 + 0.9, 3.0, 8.0), STEEL, verts=12, rot=(0, math.pi / 2, 0)))
    T.append(box((0.3, 1.6, 1.6), (X2 + 1.5, 3.0, 8.0), STEEL_DARK, bevel=0.08, segments=1))
    r, t = gable_roof(-8.0, 8.0, -8.5, 8.5, H, 4.5)
    R += r
    T += t
    for x in (X1, X2):
        w_, t_ = gable_infill(x, Y1 - 0.5, Y2 + 0.5, 0.0, 8.5, H, 4.5, WALL_CREAM, vent=x > 0)
        W += w_
        T += t_
    S += sign_board("-x", X1 - 0.9, 0.0, 11.0, 7.4, 2.0, SIGN_TEAL)
    L.append(text3d("LAUNDRY", 1.3, (X1 - 1.32, 0.0, 10.95), "-x", LETTER_WHITE))
    L += marquee((X1 - 0.9, 0.0, 11.0), 7.4, 2.0, 0.42, "-x", step=1.05, r=0.18)
    return out(
        {"Walls": W, "Trim": T, "Roof": R, "Glass": G, "Awning": A, "Sign": S, "Glow": L},
        "LinenShed",
        {"Walls": "Precise", "Roof": "Hull"},
        dict(place=[[60, 0, -16]]),
    )


# ---------------------------------------------------------------- shop
def shop():
    """Supply shop: 20 x 16 centred at world (100, -36), walls 12, mint.
    Door + windows in the west wall (-X here) facing the motel."""
    H = 12
    X1, X2, Y1, Y2 = -10.0, 10.0, -8.0, 8.0
    W, T, G, R, A, S, L = [], [], [], [], [], [], []
    west_open = [(-7.3, -4.9, 2.4, 6.8), (-4.0, 4.0, 0, DOOR_TOP), (4.9, 7.3, 2.4, 6.8)]
    side_open = [(-4.0, 4.0, 6.6, 9.4)]
    W += wall("x", X1 - 0.5, X2 + 0.5, Y2, H, MINT, side_open)
    W += wall("x", X1 - 0.5, X2 + 0.5, Y1, H, MINT, side_open)
    W += wall("y", Y1 + 0.5, Y2 - 0.5, X1, H, MINT, west_open)
    W += wall("y", Y1 + 0.5, Y2 - 0.5, X2, H, MINT)
    W += siding("x", X1, X2, Y2, 1, H, MINT_LINE, side_open)
    W += siding("x", X1, X2, Y1, -1, H, MINT_LINE, side_open)
    W += siding("y", Y1, Y2, X1, -1, H, MINT_LINE, west_open)
    W += siding("y", Y1, Y2, X2, 1, H, MINT_LINE)
    W += ceiling(X1 + 0.5, X2 - 0.5, Y1 + 0.5, Y2 - 0.5, H)
    T += base_trim("x", X1, X2, Y2, 1, CREAM)
    T += base_trim("x", X1, X2, Y1, -1, CREAM)
    T += base_trim("y", Y1, Y2, X1, -1, CREAM, west_open)
    T += base_trim("y", Y1, Y2, X2, 1, CREAM)
    T += corner_boards(X1, X2, Y1, Y2, H, CREAM)
    T += door_frame("y", -4.0, 4.0, X1, DOOR_TOP, colour=TEAL_DARK)
    for cy in (-6.1, 6.1):
        t, g = window("y", cy, X1, -1, 2.4, 4.4, 4.6, shutters=False)
        T += t
        G += g
    for y in (Y1, Y2):
        t, g = window("x", 0.0, y, 1 if y > 0 else -1, 8.0, 2.8, 8.0, shutters=False)
        T += t
        G += g
    A += awning("y", 0.0, X1, -1, 10.0, 9.7, depth=3.0)
    r, t = gable_roof(-11.5, 11.5, -9.5, 9.5, H, 5.0)
    R += r
    T += t
    for x in (X1, X2):
        w_, t_ = gable_infill(x, Y1 - 0.5, Y2 + 0.5, 0.0, 9.5, H, 5.0, MINT, vent=x > 0)
        W += w_
        T += t_
    S += sign_board("-x", X1 - 0.95, 0.0, 11.6, 12.4, 2.6, SIGN_TEAL)
    L.append(text3d("SUPPLY SHOP", 1.55, (X1 - 1.38, 0.0, 11.55), "-x", LETTER))
    L += marquee((X1 - 0.95, 0.0, 11.6), 12.4, 2.6, 0.45, "-x", step=1.05, r=0.2)
    # OPEN sign hanging in the north window (Roblox z -29.8): own glow mesh
    # so the game can blink it.
    open_parts = [box((0.2, 2.4, 1.2), (X1 - 0.85, -6.1, 5.3), srgb(255, 72, 96), bevel=0.08, segments=1)]
    open_parts.append(text3d("OPEN", 0.75, (X1 - 0.98, -6.1, 5.25), "-x", LETTER_WHITE, depth=0.08))
    res = out(
        {"Walls": W, "Trim": T, "Roof": R, "Glass": G, "Awning": A, "Sign": S, "Glow": L},
        "Shop",
        {"Walls": "Precise", "Roof": "Hull"},
        dict(place=[[100, 0, -36]]),
    )
    res["SM_Bld_Shop_OpenSign"] = (build_mesh("SM_Bld_Shop_OpenSign", open_parts, "glow"), dict(glow=True, collision="None", place=[[100, 0, -36]]))
    return res


# ---------------------------------------------------------------- kitchen
def kitchen():
    """Diner-style kitchen: world x -8..6, z -4..10 (centre -1, 3), walls 10,
    butter yellow with a red diner stripe; door east (+X), windows south."""
    H = 10
    X1, X2, Y1, Y2 = -7.0, 7.0, -7.0, 7.0
    W, T, G, R, A, S, L = [], [], [], [], [], [], []
    east_open = [(-2.0, 2.0, 0, DOOR_TOP)]
    south_open = [(-4.5, -1.5, 3.3, 6.7), (1.5, 4.5, 3.3, 6.7)]
    W += wall("x", X1 - 0.5, X2 + 0.5, Y2, H, BUTTER, south_open)
    W += wall("x", X1 - 0.5, X2 + 0.5, Y1, H, BUTTER)
    W += wall("y", Y1 + 0.5, Y2 - 0.5, X1, H, BUTTER)
    W += wall("y", Y1 + 0.5, Y2 - 0.5, X2, H, BUTTER, east_open)
    W += siding("x", X1, X2, Y2, 1, H, BUTTER_LINE, south_open)
    W += siding("x", X1, X2, Y1, -1, H, BUTTER_LINE)
    W += siding("y", Y1, Y2, X1, -1, H, BUTTER_LINE)
    W += siding("y", Y1, Y2, X2, 1, H, BUTTER_LINE, east_open)
    W += ceiling(X1 + 0.5, X2 - 0.5, Y1 + 0.5, Y2 - 0.5, H)
    T += base_trim("x", X1, X2, Y2, 1, RED, south_open)
    T += base_trim("x", X1, X2, Y1, -1, RED)
    T += base_trim("y", Y1, Y2, X1, -1, RED)
    T += base_trim("y", Y1, Y2, X2, 1, RED, east_open)
    # Diner stripe band just under the eaves.
    for axis, a, b, c, o, op in (
        ("x", X1, X2, Y2, 1, ()),
        ("x", X1, X2, Y1, -1, ()),
        ("y", Y1, Y2, X1, -1, ()),
        ("y", Y1, Y2, X2, 1, ()),
    ):
        T.append(box(_size(axis, b - a + 1.0, 0.3, 0.7), _along(axis, (a + b) / 2, c, o, v=0.6, z=H - 0.7), RED, bevel=0.08, segments=1))
        T.append(box(_size(axis, b - a + 1.0, 0.32, 0.22), _along(axis, (a + b) / 2, c, o, v=0.62, z=H - 1.25), CREAM, bevel=0.0))
    T += corner_boards(X1, X2, Y1, Y2, H, CREAM)
    T += door_frame("y", -2.0, 2.0, X2, DOOR_TOP, colour=RED)
    for cx in (-3.0, 3.0):
        t, g = window("x", cx, Y2, 1, 3.0, 3.4, 5.0, shutters=False, flowers=True, seed=int(cx) + 5)
        T += t
        G += g
    A += awning("y", 0.0, X2, 1, 5.6, 9.6)
    r, t = gable_roof(-8.2, 8.2, -8.2, 8.2, H, 4.0)
    R += r
    T += t
    for x in (X1, X2):
        w_, t_ = gable_infill(x, Y1 - 0.5, Y2 + 0.5, 0.0, 8.2, H, 4.0, BUTTER, vent=False)
        W += w_
        T += t_
    # Stainless kitchen exhaust instead of a brick chimney.
    R.append(cyl(0.75, 6.0, (-5.0, -4.0, 14.0), STEEL, verts=14))
    R.append(cyl(1.2, 0.5, (-5.0, -4.0, 17.2), STEEL_DARK, verts=14, radius2=0.5))
    R.append(cyl(1.05, 0.4, (-5.0, -4.0, 11.6), STEEL_DARK, verts=14))
    S += sign_board("+x", X2 + 0.95, 0.0, 11.3, 8.6, 2.2, SIGN_RED)
    L.append(text3d("KITCHEN", 1.5, (X2 + 1.38, 0.0, 11.25), "+x", LETTER))
    L += marquee((X2 + 0.95, 0.0, 11.3), 8.6, 2.2, 0.45, "+x", step=1.05, r=0.18)
    return out(
        {"Walls": W, "Trim": T, "Roof": R, "Glass": G, "Awning": A, "Sign": S, "Glow": L},
        "Kitchen",
        {"Walls": "Precise", "Roof": "Hull"},
        dict(place=[[-1, 0, 3]]),
    )


# ---------------------------------------------------------------- pylon sign
def motel_sign():
    """Roadside "RUN A MOTEL" pylon at world (-46, -50): pole 30, board 16 x 7,
    arrow and a blank VACANCY board (the game keeps its text label)."""
    S, T, L = [], [], []
    T.append(cyl(0.8, 30.0, (0, 0, 15.0), srgb(70, 76, 88), verts=16))
    T.append(box((4.0, 4.0, 1.0), (0, 0, 0.5), CONCRETE, bevel=0.15))
    T.append(cyl(1.1, 0.8, (0, 0, 1.4), srgb(70, 76, 88), verts=16))
    S += sign_board("+y", 0, 1.0, 25.0, 16.0, 7.0, SIGN_NAVY, border=TEAL, t=1.0)
    L.append(text3d("RUN A", 1.6, (0, 1.6, 27.0), "+y", LETTER))
    L.append(text3d("MOTEL", 3.9, (0, 1.6, 24.0), "+y", LETTER_PINK, depth=0.2))
    L += marquee((0, 1.0, 25.0), 16.0, 7.0, 0.65, "+y", step=1.0, r=0.26)
    # Arrow pointing at the lot.
    S.append(box((12.0, 0.8, 1.6), (4.0, 1.0, 18.5), SIGN_NAVY, bevel=0.15))
    head = extrude_profile([(-1.6, -1.6), (1.6, -1.6), (0.0, 1.8)], 0, 0.8, SIGN_NAVY, bevel=0.1)
    # profile (y across, z tip) -> board plane: tip along +X, across along Z.
    head.matrix_world = Matrix(((0, 0, 1, 11.0), (1, 0, 0, 1.0), (0, 1, 0, 18.5), (0, 0, 0, 1)))
    _activate(head)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    S.append(head)
    for k in range(10):
        L.append(bulb((-1.0 + k * 1.1, 1.55, 18.5), 0.24, srgb(255, 200, 70)))
    L.append(bulb((11.6, 1.55, 18.5), 0.3, srgb(255, 200, 70)))
    S += sign_board("+y", 0, 1.0, 15.2, 11.0, 2.6, srgb(28, 28, 34), border=TEAL, t=0.8)
    T.append(box((0.4, 0.4, 3.0), (-1.0, 1.0, 17.0), IRON, bevel=0.05, segments=1))
    T.append(box((0.4, 0.4, 3.0), (3.0, 1.0, 17.0), IRON, bevel=0.05, segments=1))
    return out({"Sign": S, "Trim": T, "Glow": L}, "MotelSign", {"Trim": "Hull"}, dict(place=[[-46, 0, -50]]))


# ======================================================================
# Office v2 (batch "office"): matches the 4-view reference art
# (front / left / right / back). Same gameplay footprint as batch 3's
# office (36 x 26, walls 14), but narrower real doorways, and every door
# leaf is its own mesh group with the origin ON THE HINGE so it can swing
# in Roblox (manifest: hinge position + swing angle).
#
# Blender local frame: office centre on the floor, +Y = front (Roblox -Z).
# ======================================================================
GLASS_WARM = srgb(255, 190, 84)
MORTAR = srgb(150, 80, 62)
BRICK_LIGHT = srgb(214, 116, 80)
STONE = srgb(214, 204, 186)
POT = srgb(206, 104, 62)
TOPIARY = srgb(92, 168, 70)
WELCOME = srgb(204, 52, 46)
EMBLEM_SNOW = srgb(246, 248, 252)
EMBLEM_ROCK = srgb(150, 160, 176)
EMBLEM_PINE = srgb(58, 140, 74)
LAUREL = srgb(210, 186, 96)
STRING_COLOURS = [srgb(255, 92, 92), srgb(255, 212, 84), srgb(110, 230, 140), srgb(110, 180, 255), srgb(250, 130, 220)]
DOOR_TOP_V2 = 8.4  # visible doorway height (the gameplay lintel collider stays at 9)

# Door hinges (Blender local) and canonical turn: a leaf is built extending
# +X from its hinge; `turn` rotates it into place. `swing` = Roblox degrees
# about +Y that open it inward.
OFFICE_DOORS = {
    "OfficeDoorFL": dict(hinge=(-2.95, 12.75, 0.0), turn=0.0, width=2.9, glass=True, swing=-95),
    "OfficeDoorFR": dict(hinge=(2.95, 12.75, 0.0), turn=math.pi, width=2.9, glass=True, swing=95),
    "OfficeDoorSide": dict(hinge=(17.75, -1.05, 0.0), turn=-math.pi / 2, width=3.9, glass=False, swing=-95),
    "OfficeDoorBack": dict(hinge=(-7.95, -12.75, 0.0), turn=0.0, width=3.9, glass=False, swing=95),
}


def extrude_xz(points_uz, cx, cy, thickness, colour, bevel=0.05):
    """Flat shape from a closed (u, z) outline in the XZ plane (u along X),
    extruded along Y and centred on (cx, cy): upright signs facing +Y."""
    bm = bmesh.new()
    front = [bm.verts.new((cx + u, cy + thickness / 2, z)) for u, z in points_uz]
    back = [bm.verts.new((cx + u, cy - thickness / 2, z)) for u, z in points_uz]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    n = len(points_uz)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((front[i], back[i], back[j], front[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("xz")
    bm.to_mesh(mesh)
    bm.free()
    o = bpy.data.objects.new("xz", mesh)
    scene.collection.objects.link(o)
    return finish(o, colour, bevel=bevel, segments=2)


def segment(a, b, r, colour, verts=8):
    """Round bar from point a to point b."""
    a, b = Vector(a), Vector(b)
    seg = b - a
    o = cyl(r, seg.length, (a + b) / 2, colour, verts=verts, bevel=0.0)
    o.rotation_euler = seg.to_track_quat("Z", "Y").to_euler()
    return o


def gooseneck(base, height, reach, direction, glow_parts, trim_parts, shade_colour=IRON, size=1.0):
    """Gooseneck lamp: post up from `base`, curved arm reaching `reach`
    along `direction` (unit XY), cone shade pointing down, glowing bulb."""
    bx, by, bz = base
    dx, dy = direction
    top = Vector((bx, by, bz + height))
    k = size
    trim_parts.append(segment((bx, by, bz), top, 0.09 * k, shade_colour, verts=6))
    pts = [top]
    for i in range(1, 4):
        t = i / 3
        ang = t * math.pi / 2
        pts.append(top + Vector((dx * reach * math.sin(ang), dy * reach * math.sin(ang), (0.55 * math.sin(ang * 2) - 0.25 * t) * k)))
    for p, q in zip(pts, pts[1:]):
        trim_parts.append(segment(p, q, 0.08 * k, shade_colour, verts=6))
    end = pts[-1]
    trim_parts.append(cyl(0.12 * k, 0.25 * k, end + Vector((0, 0, -0.05 * k)), shade_colour, verts=8))
    trim_parts.append(cyl(0.5 * k, 0.42 * k, end + Vector((0, 0, -0.35 * k)), shade_colour, verts=10, radius2=0.16 * k))
    glow_parts.append(blob(0.24 * k, end + Vector((0, 0, -0.55 * k)), GLOW, lump=0, segs=10, rings=6))


def lantern(pos, glow_parts, trim_parts, facing=(0, 1)):
    """Wall lantern: bracket, cage posts, pyramid cap, glowing core."""
    x, y, z = pos
    fx, fy = facing
    trim_parts.append(box((0.3 if fy else 0.6, 0.6 if fy else 0.3, 0.9), (x - fx * 0.15, y - fy * 0.15, z + 0.35), IRON, bevel=0.05, segments=1))
    trim_parts.append(segment((x, y, z + 0.6), (x + fx * 0.55, y + fy * 0.55, z + 0.6), 0.06, IRON))
    cx, cy = x + fx * 0.7, y + fy * 0.7
    trim_parts.append(cyl(0.38, 0.14, (cx, cy, z - 0.55), IRON, verts=4, rot=(0, 0, math.pi / 4)))
    for a in range(4):
        ang = a * math.pi / 2 + math.pi / 4
        trim_parts.append(box((0.07, 0.07, 1.0), (cx + math.cos(ang) * 0.3, cy + math.sin(ang) * 0.3, z - 0.02), IRON, bevel=0.0))
    trim_parts.append(cyl(0.48, 0.45, (cx, cy, z + 0.66), IRON, verts=4, radius2=0.05, rot=(0, 0, math.pi / 4)))
    glow_parts.append(box((0.42, 0.42, 0.85), (cx, cy, z - 0.02), GLOW, bevel=0.06, segments=1))


def topiary(pos, trim_parts, seed):
    x, y, z = pos
    trim_parts.append(lathe([(0.0, 0), (0.55, 0), (0.6, 0.1), (0.78, 1.15), (0.86, 1.2), (0.86, 1.38), (0.0, 1.38)], (x, y, z), POT, verts=16))
    trim_parts.append(cyl(0.7, 0.12, (x, y, z + 1.34), SOIL, verts=14))
    trim_parts.append(blob(0.95, (x, y, z + 2.25), TOPIARY, squash=(1, 1, 1.05), lump=0.14, seed=seed, segs=10, rings=7))


def mortar_lines(x, y, z0, h, w, trim_parts, step=0.62):
    z = z0 + 0.45
    while z < z0 + h - 0.2:
        trim_parts.append(box((w + 0.04, w + 0.04, 0.07), (x, y, z), MORTAR, bevel=0.0))
        z += step


def gable_siding(x, out, base, rise, d, half_wall, trim_parts, step=1.2):
    """Siding lines on a gable triangle (wall plane at x, facing out)."""
    z = base + 0.8
    while z < base + rise - 0.8:
        half = min(half_wall, d * (1 - (z - base) / rise)) - 0.25
        if half > 0.4:
            trim_parts.append(box((0.14, half * 2, 0.16), (x + out * 0.56, 0, z), WALL_LINE, bevel=0.0))
        z += step


def office_door_leaf(name, spec):
    """One door leaf, hinge at the origin (built extending +X, then turned).
    Glass doors: wooden frame, lower panel, 2 x 3 warm panes (glow mesh),
    brass bar handle and kick plate. Solid doors: 4 raised panels, knob."""
    w, h, t = spec["width"], 7.9, 0.28
    z0 = 0.42
    wood, glow = [], []
    if spec["glass"]:
        wood.append(box((0.42, t, h), (0.21, 0, z0 + h / 2), WOOD, bevel=0.06, segments=1))
        wood.append(box((0.42, t, h), (w - 0.21, 0, z0 + h / 2), WOOD, bevel=0.06, segments=1))
        for zc, hh in ((z0 + 0.25, 0.5), (z0 + 2.6, 0.36), (z0 + h - 0.22, 0.44)):
            wood.append(box((w, t, hh), (w / 2, 0, zc), WOOD, bevel=0.05, segments=1))
        wood.append(box((w - 0.84, t * 0.7, 1.9), (w / 2, 0, z0 + 1.45), WOOD_PANEL, bevel=0.08, segments=1))
        for side in (-1, 1):
            wood.append(box((w - 1.2, 0.06, 1.4), (w / 2, side * (t * 0.35 + 0.02), z0 + 1.45), WOOD_LIGHT, bevel=0.04, segments=1))
        gx0, gz0, gz1 = 0.42, z0 + 2.8, z0 + h - 0.45
        pw, ph = (w - 0.84) / 2, (gz1 - gz0) / 3
        for i in range(2):
            for j in range(3):
                glow.append(box((pw - 0.12, 0.08, ph - 0.12), (gx0 + pw * (i + 0.5), 0, gz0 + ph * (j + 0.5)), GLASS_BLUE, bevel=0.0))
        wood.append(box((0.1, t * 0.9, gz1 - gz0), (w / 2, 0, (gz0 + gz1) / 2), WOOD, bevel=0.0))
        for j in (1, 2):
            wood.append(box((w - 0.84, t * 0.9, 0.1), (w / 2, 0, gz0 + ph * j), WOOD, bevel=0.0))
        for side in (-1, 1):
            wood.append(cyl(0.06, 1.6, (w - 0.45, side * (t / 2 + 0.16), z0 + 3.6), BRASS, verts=8))
            for dz in (-0.7, 0.7):
                wood.append(segment((w - 0.45, side * t / 2, z0 + 3.6 + dz), (w - 0.45, side * (t / 2 + 0.17), z0 + 3.6 + dz), 0.05, BRASS, verts=6))
            wood.append(box((w - 0.4, 0.04, 0.42), (w / 2, side * (t / 2 + 0.02), z0 + 0.3), BRASS, bevel=0.02, segments=1))
    else:
        wood.append(box((w, t, h), (w / 2, 0, z0 + h / 2), WOOD, bevel=0.08, segments=1))
        pw = (w - 0.9) / 2
        for side in (-1, 1):
            for i in range(2):
                for zc, hh in ((z0 + 1.9, 2.6), (z0 + 5.6, 3.2)):
                    u = 0.3 + pw * (i + 0.5) + 0.15 * i
                    wood.append(box((pw - 0.1, 0.1, hh), (u, side * (t / 2 + 0.03), zc), WOOD_LIGHT, bevel=0.07, segments=1))
                    wood.append(box((pw - 0.5, 0.06, hh - 0.4), (u, side * (t / 2 + 0.09), zc), WOOD_PANEL, bevel=0.05, segments=1))
            wood.append(blob(0.17, (w - 0.42, side * (t / 2 + 0.2), z0 + 3.6), BRASS, lump=0, segs=10, rings=7))
            wood.append(box((0.32, 0.06, 0.62), (w - 0.42, side * (t / 2 + 0.04), z0 + 3.6), BRASS, bevel=0.03, segments=1))
    for x in (0.0,):
        for zc in (z0 + 0.9, z0 + h - 0.9):
            wood.append(cyl(0.09, 0.6, (x + 0.02, 0, zc), METAL, verts=8))
    parts = {"wood": wood, "glow": glow}
    # Turn into place around the hinge (origin).
    for group in parts.values():
        for o in group:
            o.matrix_world = Matrix.Rotation(spec["turn"], 4, "Z") @ o.matrix_world
            _activate(o)
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    hx, hy, hz = spec["hinge"]
    info = dict(collision="None", hinge=[hx, hz, -hy], swing=spec["swing"], place=[[22, 0, -19]])
    res = {f"SM_Bld_OfficeV2_{name[6:]}": (build_mesh(f"SM_Bld_OfficeV2_{name[6:]}", wood), dict(info))}
    if glow:
        gname = f"SM_Bld_OfficeV2_{name[6:]}_Glass"
        res[gname] = (build_mesh(gname, glow), dict(info, glass=True))  # clear glass (transparent in game)
    return res


def office_door_fl():
    return office_door_leaf("OfficeDoorFL", OFFICE_DOORS["OfficeDoorFL"])


def office_door_fr():
    return office_door_leaf("OfficeDoorFR", OFFICE_DOORS["OfficeDoorFR"])


def office_door_side():
    return office_door_leaf("OfficeDoorSide", OFFICE_DOORS["OfficeDoorSide"])


def office_door_back():
    return office_door_leaf("OfficeDoorBack", OFFICE_DOORS["OfficeDoorBack"])


def office_v2():
    """Office shell v3, matched to the painted 4-view reference (gap list of
    the visual-match pass): symmetric facade with the double door centred,
    saturated palette, chunky rounded clay-tile roof, glowing warm windows
    (own glow mesh), lush flower boxes, light porch on slim posts, arched
    wooden OFFICE sign with crest emblem, gold border, outlined letters,
    marquee bulbs and three short lamps on top."""
    return with_palette(V3_PALETTE, _office_v3)


V3_PALETTE = {  # cartoon-style: limited palette, bold accents (reference swatches)
    "WALL_CREAM": srgb(252, 238, 208),
    "WALL_LINE": srgb(208, 178, 136),
    "TEAL": srgb(22, 146, 140),
    "TEAL_DARK": srgb(12, 104, 102),
    "CREAM": srgb(255, 247, 228),
    "RED": srgb(232, 50, 42),
    "ROOF_DARK": srgb(120, 26, 24),
}
ROOF_V3 = srgb(214, 42, 32)
ROOF_V3_EDGE = srgb(168, 28, 24)
WINDOW_GLOW = srgb(255, 178, 62)
SIGN_WOOD = srgb(134, 70, 34)
SIGN_GOLD = srgb(238, 186, 86)
LETTER_EDGE = srgb(72, 36, 18)
FOLIAGE = srgb(76, 156, 66)
FOLIAGE_DARK = srgb(46, 118, 54)
BLOOMS = [srgb(255, 150, 190), srgb(255, 255, 255), srgb(255, 112, 168), srgb(255, 232, 244)]
BOX_WOOD = srgb(178, 94, 50)


def with_palette(palette, fn):
    """Run fn with some module colours swapped (helpers read them at call time)."""
    g = globals()
    saved = {k: g[k] for k in palette}
    g.update(palette)
    try:
        return fn()
    finally:
        g.update(saved)


def tile_roof(x1, x2, y1, y2, base, rise, th=0.5):
    """Clay-tile gable roof, ridge along X: dark deck, chunky rounded tile
    rows (grooves between rows), thick rounded eave edges, red barge edges
    over cream boards, ridge roll."""
    roof, trim = [], []
    yc, d = (y1 + y2) / 2, (y2 - y1) / 2
    a = math.atan2(rise, d)
    L = math.hypot(d, rise)
    xc, length = (x1 + x2) / 2, x2 - x1
    for side in (1, -1):
        rot = (-a * side, 0, 0)
        n = Vector((0, side * math.sin(a), math.cos(a)))
        down = Vector((0, side * math.cos(a), -math.sin(a)))
        top = Vector((xc, yc, base + rise))
        mid = top + down * (L / 2) + n * (th / 2)
        roof.append(box((length, L + 0.3, th), mid, ROOF_DARK, bevel=0.05, segments=1, rot=rot))
        rows = max(4, int(L / 1.3))
        step = L / rows
        tilt = 0.11  # rows flatter than the deck: lower lips cast a shadow line
        row_rot = (-(a - tilt) * side, 0, 0)
        for i in range(rows):
            centre = top + down * (step * (i + 0.5)) + n * (th + 0.22 + step * 0.5 * math.sin(tilt))
            roof.append(box((length + 0.1, step + 0.05, 0.42), centre, ROOF_V3, bevel=0.2, segments=2, rot=row_rot))
        eave = top + down * (L + 0.05) + n * (th * 0.5)
        roof.append(box((length + 0.6, 0.8, 0.95), eave, ROOF_V3_EDGE, bevel=0.28, segments=2, rot=rot))
        for x in (x1 - 0.2, x2 + 0.2):
            roof.append(box((0.6, L + 0.5, 1.0), mid + Vector((x - xc, 0, 0)) + n * 0.3, ROOF_V3_EDGE, bevel=0.2, segments=2, rot=rot))
            trim.append(box((0.42, L + 0.3, 0.55), mid + Vector((x - xc, 0, 0)) - n * 0.5, CREAM, bevel=0.08, segments=1, rot=rot))
    roof.append(cyl(0.66, length + 0.8, (xc, yc, base + rise + th + 0.32), ROOF_V3_EDGE, verts=12, rot=(0, math.pi / 2, 0)))
    return roof, trim


def sign_outline(w, h, rise, crest, crest_w, steps=26):
    """Arched sign outline with a raised crest in the middle, (u, z) points."""
    pts = [(-w / 2, 0.0), (w / 2, 0.0), (w / 2, h)]
    for i in range(1, steps):
        t = i / steps
        u = w / 2 - t * w
        pts.append((u, h + rise * math.sin(math.pi * t) + crest * math.exp(-((u / crest_w) ** 2))))
    pts.append((-w / 2, h))
    return pts


def sign_top(u, w, h, rise, crest, crest_w):
    t = (w / 2 - u) / w
    return h + rise * math.sin(math.pi * t) + crest * math.exp(-((u / crest_w) ** 2))


def flower_box(axis, p, c, out, w, zb, seed, parts):
    """Lush window box: wooden box with a rim, two rows of foliage, pink
    and white blooms spilling over the top (reference)."""
    parts.append(box(_size(axis, w + 0.7, 1.0, 0.8), _along(axis, p, c, out, v=1.1, z=zb), BOX_WOOD, bevel=0.14, segments=1))
    parts.append(box(_size(axis, w + 0.9, 1.15, 0.16), _along(axis, p, c, out, v=1.1, z=zb + 0.42), mul(BOX_WOOD, 0.82), bevel=0.05, segments=1))
    n = max(4, int(w / 0.9))
    for row, (v, dz, r) in enumerate(((0.95, 0.62, 0.48), (1.4, 0.55, 0.4))):
        for i in range(n):
            u = -w / 2 + (i + 0.5 + 0.5 * row) * w / (n + 0.5 * row)
            col = FOLIAGE if (i + row) % 2 else FOLIAGE_DARK
            parts.append(blob(r, _along(axis, p, c, out, u=u, v=v, z=zb + dz), col, lump=0.24, seed=seed * 7 + i + row * 13, segs=6, rings=4))
    m = max(5, int(w / 0.6))
    for i in range(m):
        u = -w / 2 + 0.25 + (i + 0.5) * (w - 0.5) / m
        dz = 0.95 + 0.2 * ((i * 37 + seed) % 3)
        v = 1.3 + 0.3 * ((i + seed) % 2)
        parts.append(blob(0.22, _along(axis, p, c, out, u=u, v=v, z=zb + dz), BLOOMS[(i + seed) % len(BLOOMS)], lump=0, segs=5, rings=3))


def _office_v3():
    H = 14
    X1, X2, Y1, Y2 = -18.0, 18.0, -13.0, 13.0
    RISE, D = 8.0, 15.2
    W, T, R, A, S, L, P, F, WIN = [], [], [], [], [], [], [], [], []
    dt = DOOR_TOP_V2
    front_open = [(-3.0, 3.0, 0, dt), (-15.5, -9.5, 2.9, 8.3), (9.5, 15.5, 2.9, 8.3)]
    back_open = [(-15.1, -10.9, 3.2, 7.2), (-8.0, -4.0, 0, dt), (-1.1, 3.1, 3.2, 7.2)]
    east_open = [(-5.0, -1.0, 0, dt), (3.0, 8.0, 3.2, 7.2)]
    west_open = [(-2.5, 2.5, 3.2, 7.2)]
    W += wall("x", X1 - 0.5, X2 + 0.5, Y2, H, WALL_CREAM, front_open, bevel=0.0)
    W += wall("x", X1 - 0.5, X2 + 0.5, Y1, H, WALL_CREAM, back_open, bevel=0.0)
    W += wall("y", Y1 + 0.5, Y2 - 0.5, X1, H, WALL_CREAM, west_open, bevel=0.0)
    W += wall("y", Y1 + 0.5, Y2 - 0.5, X2, H, WALL_CREAM, east_open, bevel=0.0)
    W += siding("x", X1, X2, Y2, 1, H, WALL_LINE, front_open, step=1.3, margin=0.8)
    W += siding("x", X1, X2, Y1, -1, H, WALL_LINE, back_open, step=1.3, margin=0.8)
    W += siding("y", Y1, Y2, X1, -1, H, WALL_LINE, west_open, step=1.3, margin=0.8)
    W += siding("y", Y1, Y2, X2, 1, H, WALL_LINE, east_open, step=1.3, margin=0.8)
    W += ceiling(X1 + 0.5, X2 - 0.5, Y1 + 0.5, Y2 - 0.5, H)
    # Teal base band, cream pilasters with teal plinths and capitals.
    T += base_trim("x", X1, X2, Y2, 1, TEAL, front_open, h=1.1)
    T += base_trim("x", X1, X2, Y1, -1, TEAL, back_open, h=1.1)
    T += base_trim("y", Y1, Y2, X1, -1, TEAL, west_open, h=1.1)
    T += base_trim("y", Y1, Y2, X2, 1, TEAL, east_open, h=1.1)
    T += corner_boards(X1, X2, Y1, Y2, H, CREAM)
    for x in (X1 - 0.42, X2 + 0.42):
        for y in (Y1 - 0.42, Y2 + 0.42):
            T.append(box((1.4, 1.4, 1.5), (x, y, 0.75), TEAL_DARK, bevel=0.14, segments=2))
            T.append(box((1.15, 1.15, 0.55), (x, y, H - 0.6), TEAL, bevel=0.1, segments=1))
    for y, o in ((Y2, 1), (Y1, -1)):
        T.append(box((X2 - X1 - 0.2, 0.45, 0.75), (0, y + o * 0.72, H - 0.42), CREAM, bevel=0.08, segments=1))
    # Door frames and gold thresholds.
    T += door_frame("x", -3.0, 3.0, Y2, dt, colour=TEAL)
    T += door_frame("x", -8.0, -4.0, Y1, dt, colour=TEAL)
    T += door_frame("y", -5.0, -1.0, X2, dt, colour=TEAL)
    for axis, a_, b_, c_ in (("x", -3.0, 3.0, Y2), ("x", -8.0, -4.0, Y1), ("y", -5.0, -1.0, X2)):
        T.append(box(_size(axis, b_ - a_, 1.2, 0.12), _along(axis, (a_ + b_) / 2, c_, 1, z=0.06), BRASS, bevel=0.03, segments=1))
    # Windows: teal frame + mullions, glowing warm panes, awnings, flower boxes.
    wins = [
        ("x", -12.5, Y2, 1, 6.0, 5.4, 5.6, 1, True),
        ("x", 12.5, Y2, 1, 6.0, 5.4, 5.6, 2, True),
        ("x", -13.0, Y1, -1, 4.2, 4.0, 5.2, 3, False),
        ("x", 1.0, Y1, -1, 4.2, 4.0, 5.2, 4, False),
        ("y", 5.5, X2, 1, 5.0, 4.0, 5.2, 5, True),
        ("y", 0.0, X1, -1, 5.0, 4.0, 5.2, 6, True),
    ]
    for axis, p_, c_, o, w, h, zc, seed, has_awning in wins:
        t_, g_ = window(axis, p_, c_, o, w, h, zc, shutters=False, flowers=False, glass_colour=GLASS_BLUE, mullion=TEAL, sill=False)
        T += t_
        WIN += g_
        flower_box(axis, p_, c_, o, w, zc - h / 2 - 0.95, seed, F)
        if has_awning:
            A += awning(axis, p_, c_, o, w + 1.2, zc + h / 2 + 1.2, depth=2.2)
    # Roof, gables, brick chimney (left) and metal vent (right).
    r, t = tile_roof(-19.8, 19.8, -D, D, H, RISE)
    R += r
    T += t
    for x, o in ((X1, -1), (X2, 1)):
        w_, t_ = gable_infill(x, Y1 - 0.5, Y2 + 0.5, 0.0, D, H, RISE, WALL_CREAM, vent=False)
        W += w_
        gable_siding(x, o, H, RISE, D, 13.0, T)
    R += chimney(11.5, -6.5, 18.0, 7.2, colour=BRICK_LIGHT)
    mortar_lines(11.5, -6.5, 18.0, 7.2, 2.6, R)
    R.append(cyl(0.62, 3.0, (-11.5, -4.5, 21.0), STEEL, verts=16))
    R.append(cyl(0.78, 0.25, (-11.5, -4.5, 22.55), STEEL_DARK, verts=16))
    R.append(cyl(0.95, 0.5, (-11.5, -4.5, 22.95), STEEL, verts=16, radius2=0.35))
    for x in (-16.0, -10.0, 10.0, 16.0):
        L.append(cyl(0.27, 0.12, (x, Y2 + 0.74, H - 0.86), GLOW, verts=8))
    for x in (-13.0, -6.0, 1.0):
        L.append(cyl(0.27, 0.12, (x, Y1 - 0.74, H - 0.86), GLOW, verts=8))
    gooseneck((X2 + 0.55, 8.5, 11.3), 1.0, 1.2, (1, 0), L, T)
    gooseneck((X1 - 0.55, 8.5, 11.3), 1.0, 1.2, (-1, 0), L, T)
    # ------------------------------------------------------------ porch
    P.append(box((14.4, 5.6, 0.34), (0.0, 15.9, 0.17), STONE, bevel=0.1))
    P.append(box((4.6, 1.8, 0.06), (0.0, 14.4, 0.37), WELCOME, bevel=0.02, segments=1))
    P.append(box((4.0, 1.3, 0.07), (0.0, 14.4, 0.38), srgb(236, 82, 60), bevel=0.02, segments=1))
    for x in (-6.6, 6.6):
        P.append(cyl(0.32, 8.9, (x, 18.1, 4.9), CREAM, verts=12))
        P.append(box((1.0, 1.0, 0.9), (x, 18.1, 0.79), TEAL_DARK, bevel=0.12, segments=1))
        P.append(box((0.9, 0.9, 0.36), (x, 18.1, 9.4), TEAL, bevel=0.1, segments=1))
    pa = math.atan2(0.85, 5.2)
    prot = (-pa, 0, 0)
    pdown = Vector((0, math.cos(pa), -math.sin(pa)))
    pn = Vector((0, math.sin(pa), math.cos(pa)))
    ptop = Vector((0.0, 13.45, 10.62))
    P.append(box((14.8, 5.4, 0.34), ptop + pdown * 2.7 + pn * 0.17, ROOF_DARK, bevel=0.08, segments=1, rot=prot))
    for i in range(4):
        P.append(box((14.9, 5.4 / 4 - 0.06, 0.32), ptop + pdown * (5.4 / 4 * (i + 0.5)) + pn * 0.45, ROOF_V3, bevel=0.14, segments=2, rot=prot))
    P.append(box((15.2, 0.32, 0.6), (0.0, 18.82, 9.55), ROOF_V3_EDGE, bevel=0.12, segments=1))
    P.append(box((15.2, 0.34, 0.16), (0.0, 18.84, 9.2), CREAM, bevel=0.04, segments=1))
    for i in range(11):
        tt = (i + 0.5) / 11
        L.append(bulb((-6.5 + 13.0 * tt, 18.95, 8.9 - 0.4 * 4 * tt * (1 - tt)), 0.2, STRING_COLOURS[i % len(STRING_COLOURS)]))
    for i in range(11):
        u0, u1 = i / 11, (i + 1) / 11
        T.append(
            segment(
                (-6.5 + 13.0 * u0, 18.95, 9.1 - 0.4 * 4 * u0 * (1 - u0)),
                (-6.5 + 13.0 * u1, 18.95, 9.1 - 0.4 * 4 * u1 * (1 - u1)),
                0.03,
                IRON,
                verts=4,
            )
        )
    lantern((-4.3, Y2 + 0.5, 5.8), L, T)
    lantern((4.3, Y2 + 0.5, 5.8), L, T)
    topiary((-5.2, 15.6, 0.34), P, 1.0)
    topiary((5.2, 15.6, 0.34), P, 2.0)
    # ------------------------------------------------------------ sign
    sx, sy, sz = 0.0, 15.75, 14.45
    bw, bh, br, bc, bcw = 19.8, 4.55, 1.3, 1.75, 2.27  # gold border (1.3x: reference proportion)
    iw, ih, ir, ic, icw = 18.5, 3.9, 1.1, 1.5, 2.0  # wooden board
    S.append(extrude_xz([(u, sz - 0.3 + z) for u, z in sign_outline(bw, bh, br, bc, bcw)], sx, sy - 0.08, 0.5, SIGN_GOLD, bevel=0.1))
    S.append(extrude_xz([(u, sz + z) for u, z in sign_outline(iw, ih, ir, ic, icw)], sx, sy + 0.08, 0.5, SIGN_WOOD, bevel=0.1))
    for x in (-6.0, 6.0):
        S.append(segment((x, sy - 0.3, sz + 1.6), (x, 13.6, 14.3), 0.18, IRON, verts=6))
    # Marquee bulbs riding on the gold border.
    ring = [(u, sz - 0.2 + z) for u, z in sign_outline(19.2, 4.26, 1.2, 1.62, 2.15)]
    ring.append(ring[0])
    for p0, p1 in zip(ring, ring[1:]):
        seglen = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
        n = max(1, int(seglen / 1.3))
        for k in range(n):
            tt = k / n
            L.append(bulb((sx + p0[0] + (p1[0] - p0[0]) * tt, sy + 0.28, p0[1] + (p1[1] - p0[1]) * tt), 0.16))
    # Crest emblem: snowy peaks between two pines.
    ez = sz + 4.2
    for dx, hgt, r_ in ((-0.65, 1.3, 0.78), (0.6, 1.6, 0.9)):
        S.append(cyl(r_, hgt, (sx + dx, sy + 0.3, ez + hgt / 2), EMBLEM_ROCK, verts=4, radius2=0.0))
        # Snow cap a little fatter than the peak's slope so it sits proud (no shared planes).
        S.append(cyl(r_ * 0.56, hgt * 0.44, (sx + dx, sy + 0.3, ez + hgt * 0.78 + 0.02), EMBLEM_SNOW, verts=4, radius2=0.0))
    for dx in (-1.7, 1.7):
        S.append(cyl(0.38, 1.25, (sx + dx, sy + 0.6, ez + 0.55), EMBLEM_PINE, verts=6, radius2=0.0))
    # Gold laurel sprigs either side of the word.
    for side in (-1, 1):
        cxl, czl, rad = sx + side * 6.3, sz + 2.0, 1.35
        stem = [(cxl + side * rad * math.cos(math.radians(-80 + k * 30)), czl + rad * math.sin(math.radians(-80 + k * 30))) for k in range(6)]
        for (x0, z0), (x1, z1) in zip(stem, stem[1:]):
            S.append(segment((x0, sy + 0.38, z0), (x1, sy + 0.38, z1), 0.05, SIGN_GOLD, verts=5))
        for k, (x0, z0) in enumerate(stem[1:]):
            ang = math.radians(-80 + (k + 1) * 30)
            nx, nz = side * math.cos(ang), math.sin(ang)
            for sgn in (-1, 1):
                S.append(blob(0.28, (x0 + nx * 0.28 * sgn - nz * 0.1, sy + 0.4, z0 + nz * 0.28 * sgn + nx * 0.1), SIGN_GOLD, squash=(0.75, 0.25, 0.75), lump=0, segs=6, rings=4))
    # OFFICE: cream letters with a dark outline behind them.
    S.append(text3d("OFFICE", 3.0, (sx, sy + 0.3, sz + 2.0), "+y", LETTER_EDGE, depth=0.1, bold=0.11))
    L.append(text3d("OFFICE", 3.0, (sx, sy + 0.4, sz + 2.0), "+y", LETTER_WHITE, depth=0.16, bold=0.035))
    # Three short gooseneck lamps standing on the sign's top edge.
    for u in (-6.2, 0.0, 6.2):
        zb = sz - 0.3 + sign_top(u, bw, bh, br, bc, bcw)
        gooseneck((sx + u, sy - 0.1, zb - 0.1), 1.0, 1.1, (0, 1), L, T, size=0.95)
    return out(
        {"Walls": W, "Trim": T, "Roof": R, "Awning": A, "Porch": P, "Flowers": F, "Sign": S, "Glass": WIN, "Glow": L},
        "OfficeV2",
        {"Walls": "Precise", "Roof": "Hull"},
        dict(place=[[22, 0, -19]]),
    )


# ======================================================================
# Batch "rooms": guest room block restyled to match office v3 (same
# palette, clay-tile roof, teal plinths / capitals, cream eave band,
# teal-framed windows with flower boxes, wall lanterns, colourful string
# lights). Same footprints as RoomUnit / RoomRoof, so gameplay walls,
# doors and NPC routes stay.
# ======================================================================
def room_v2():
    """Guest room shell in the office v3 style (14 x 16, walls 12)."""
    return with_palette(V3_PALETTE, _room_v3)


def room_roof_v2():
    """Long clay-tile roof over the three rooms + walkway (office v3 style)."""
    return with_palette(V3_PALETTE, _room_roof_v3)


def _room_v3():
    H = 12
    X1, X2, Y1, Y2 = -7.0, 7.0, -8.0, 8.0
    W, T, A, F, WIN, L = [], [], [], [], [], []
    front_open = [(-6.0, -3.0, 3.3, 6.3), (-2.0, 2.0, 0, 7.6)]
    back_open = [(1.0, 5.0, 5.2, 8.0)]
    W += wall("x", X1 - 0.5, X2 + 0.5, Y2, H, WALL_CREAM, front_open, bevel=0.0)
    W += wall("x", X1 - 0.5, X2 + 0.5, Y1, H, WALL_CREAM, back_open, bevel=0.0)
    W += wall("y", Y1 + 0.5, Y2 - 0.5, X1, H, WALL_CREAM, bevel=0.0)
    W += wall("y", Y1 + 0.5, Y2 - 0.5, X2, H, WALL_CREAM, bevel=0.0)
    W += siding("x", X1, X2, Y2, 1, H, WALL_LINE, front_open, step=1.3, margin=0.8)
    W += siding("x", X1, X2, Y1, -1, H, WALL_LINE, back_open, step=1.3, margin=0.8)
    W += siding("y", Y1, Y2, X1, -1, H, WALL_LINE, step=1.3, margin=0.8)
    W += siding("y", Y1, Y2, X2, 1, H, WALL_LINE, step=1.3, margin=0.8)
    W += ceiling(X1 + 0.5, X2 - 0.5, Y1 + 0.5, Y2 - 0.5, H)
    # Teal base band, cream corner boards on teal plinths, teal capitals,
    # cream eave band front and back (as the office).
    T += base_trim("x", X1, X2, Y2, 1, TEAL, front_open, h=1.1)
    T += base_trim("x", X1, X2, Y1, -1, TEAL, back_open, h=1.1)
    T += base_trim("y", Y1, Y2, X1, -1, TEAL, h=1.1)
    T += base_trim("y", Y1, Y2, X2, 1, TEAL, h=1.1)
    T += corner_boards(X1, X2, Y1, Y2, H, CREAM)
    for x in (X1 - 0.42, X2 + 0.42):
        for y in (Y1 - 0.42, Y2 + 0.42):
            T.append(box((1.4, 1.4, 1.5), (x, y, 0.75), TEAL_DARK, bevel=0.14, segments=2))
            T.append(box((1.15, 1.15, 0.55), (x, y, H - 0.6), TEAL, bevel=0.1, segments=1))
    for y, o in ((Y2, 1), (Y1, -1)):
        T.append(box((X2 - X1 - 0.2, 0.45, 0.75), (0, y + o * 0.72, H - 0.42), CREAM, bevel=0.08, segments=1))
    # Teal door frame with a brass threshold (the tinted door leaf is the
    # gameplay RoomDoor mesh, placed by MapBuilder).
    T += door_frame("x", -2.0, 2.0, Y2, 7.6, colour=TEAL)
    T.append(box(_size("x", 4.0, 1.2, 0.12), _along("x", 0.0, Y2, 1, z=0.06), BRASS, bevel=0.03, segments=1))
    # Front window: teal mullions, clear glass, flower box, striped awning.
    t_, g_ = window("x", -4.5, Y2, 1, 3.0, 3.0, 4.8, shutters=False, glass_colour=GLASS_BLUE, mullion=TEAL, sill=False)
    T += t_
    WIN += g_
    flower_box("x", -4.5, Y2, 1, 2.8, 4.8 - 1.5 - 0.95, 3, F)
    A += awning("x", -4.5, Y2, 1, 3.8, 4.8 + 1.5 + 1.2, depth=2.0)
    # Back window (bathroom side) with a flower box.
    t_, g_ = window("x", 3.0, Y1, -1, 4.0, 2.8, 6.6, shutters=False, glass_colour=GLASS_BLUE, mullion=TEAL, sill=False)
    T += t_
    WIN += g_
    flower_box("x", 3.0, Y1, -1, 4.0, 6.6 - 1.4 - 0.95, 5, F)
    # Wall lantern beside the door, brass number plaque, eave downlights.
    lantern((3.4, Y2 + 0.5, 5.6), L, T)
    T.append(box((1.5, 0.25, 1.5), (5.3, Y2 + 0.62, 6.0), BRASS, bevel=0.1, segments=1))
    T.append(box((1.2, 0.12, 1.2), (5.3, Y2 + 0.78, 6.0), TEAL_DARK, bevel=0.06, segments=1))
    for x in (-4.5, 4.5):
        L.append(cyl(0.27, 0.12, (x, Y2 + 0.74, H - 0.86), GLOW, verts=8))
    places = [[cx, 0, 12 + ROOM_SHIFT] for cx in (2, 20, 38)]
    return out(
        {"Walls": W, "Trim": T, "Awning": A, "Flowers": F, "Glass": WIN, "Glow": L},
        "RoomV2",
        {"Walls": "Precise"},
        dict(place=places),
    )


def _room_roof_v3():
    W, T, R, L = [], [], [], []
    BASE, RISE, D = 12.0, 6.0, 11.6
    r, t = tile_roof(-26.3, 27.3, -D, D, BASE, RISE)
    R += r
    T += t
    # Gable ends on the outer room walls, with siding lines (wall span is
    # y -10.5..6.5 under a roof centred on y 0).
    for x, o in ((-24.5, -1), (25.5, 1)):
        w_, t_ = gable_infill(x, -10.5, 6.5, 0.0, D, BASE, RISE, WALL_CREAM, vent=False)
        W += w_
        z = BASE + 0.8
        while z < BASE + RISE - 0.8:
            half = D * (1 - (z - BASE) / RISE) - 0.25
            ya, yb = max(-10.5 + 0.25, -half), min(6.5 - 0.25, half)
            if yb - ya > 0.8:
                T.append(box((0.14, yb - ya, 0.16), (x + o * 0.56, (ya + yb) / 2, z), WALL_LINE, bevel=0.0))
            z += 1.2
        lantern((x + o * 0.5, -2.0, 15.0), L, T, facing=(o, 0))
    # Lintels across the gaps between rooms (front and back) under the eave.
    for x1, x2 in ((-10.5, -6.5), (7.5, 11.5)):
        for y in (6.0, -10.0):
            W.append(box((x2 - x1 + 1.0, 1.0, 1.8), ((x1 + x2) / 2, y, 11.1), WALL_CREAM, bevel=0.05, segments=1))
            T.append(box((x2 - x1 + 1.0, 1.15, 0.5), ((x1 + x2) / 2, y, 10.05), TEAL, bevel=0.08, segments=1))
    # Walkway: slim cream posts on teal plinths, teal beam, string lights.
    posts = (-25.5, -8.5, 9.5, 25.5)
    for x in posts:
        T.append(cyl(0.34, 11.0, (x, 10.6, 5.75), CREAM, verts=12))
        T.append(box((1.0, 1.0, 0.9), (x, 10.6, 0.45), TEAL_DARK, bevel=0.12, segments=1))
        T.append(box((0.9, 0.9, 0.4), (x, 10.6, 11.2), TEAL, bevel=0.1, segments=1))
    T.append(box((52.4, 0.6, 0.6), (0.0, 10.6, 11.7), TEAL, bevel=0.12, segments=1))
    T.append(box((52.6, 0.62, 0.16), (0.0, 10.62, 11.33), CREAM, bevel=0.04, segments=1))
    k = 0
    for a, b in zip(posts, posts[1:]):
        n = 12
        pts = []
        for i in range(n + 1):
            tt = i / n
            pts.append((a + (b - a) * tt, 10.98, 11.05 - 0.55 * 4 * tt * (1 - tt)))
        for p0, p1 in zip(pts, pts[1:]):
            T.append(segment(p0, p1, 0.03, IRON, verts=4))
        for i in range(n):
            tt = (i + 0.5) / n
            L.append(bulb((a + (b - a) * tt, 10.98, 10.85 - 0.55 * 4 * tt * (1 - tt)), 0.2, STRING_COLOURS[k % len(STRING_COLOURS)]))
            k += 1
    # Brick chimney (left) and metal vent (right), as on the office.
    R += chimney(-15.5, -5.0, 14.6, 4.6, colour=BRICK_LIGHT)
    mortar_lines(-15.5, -5.0, 14.6, 4.6, 2.6, R)
    R.append(cyl(0.62, 3.0, (16.5, -5.0, 16.7), STEEL, verts=16))
    R.append(cyl(0.78, 0.25, (16.5, -5.0, 18.25), STEEL_DARK, verts=16))
    R.append(cyl(0.95, 0.5, (16.5, -5.0, 18.65), STEEL, verts=16, radius2=0.35))
    return out(
        {"Walls": W, "Trim": T, "Roof": R, "Glow": L},
        "RoomRoofV2",
        {"Roof": "Hull"},
        dict(place=[[19.5, 0, 10 + ROOM_SHIFT]]),
    )


# ======================================================================
# Batch "annex": linen shed, supply shop and kitchen restyled to match
# office v3 (cream siding, teal base band / plinths / capitals, cream eave
# band, clay-tile roof, teal-framed windows with flower boxes and striped
# awnings, lanterns, arched wooden signs with a gold border and marquee
# bulbs). Same footprints, wall heights and door gaps as LinenShed / Shop /
# Kitchen, so gameplay walls, prompts and NPC routes stay.
# ======================================================================
def extrude_yz(points_uz, cx, cy, thickness, colour, bevel=0.05):
    """Flat shape from a closed (u, z) outline in the YZ plane (u along Y),
    extruded along X and centred on (cx, cy): upright signs facing +-X."""
    bm = bmesh.new()
    front = [bm.verts.new((cx + thickness / 2, cy + u, z)) for u, z in points_uz]
    back = [bm.verts.new((cx - thickness / 2, cy + u, z)) for u, z in points_uz]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    n = len(points_uz)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((front[i], back[i], back[j], front[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("yz")
    bm.to_mesh(mesh)
    bm.free()
    o = bpy.data.objects.new("yz", mesh)
    scene.collection.objects.link(o)
    return finish(o, colour, bevel=bevel, segments=2)


def v3_shell(X1, X2, Y1, Y2, H, opens, W, T):
    """Office-v3 walls on a footprint: siding, teal base band, cream corner
    boards on teal plinths with teal capitals, cream eave band on the long
    (+-Y) walls. opens: {"+y"/"-y"/"+x"/"-x": [(o1, o2, bottom, top)]}."""
    sides = {
        "+y": ("x", X1, X2, Y2, 1),
        "-y": ("x", X1, X2, Y1, -1),
        "-x": ("y", Y1, Y2, X1, -1),
        "+x": ("y", Y1, Y2, X2, 1),
    }
    for key, (axis, a, b, c, o) in sides.items():
        op = opens.get(key, [])
        if axis == "x":
            W += wall("x", a - 0.5, b + 0.5, c, H, WALL_CREAM, op, bevel=0.0)
        else:
            W += wall("y", a + 0.5, b - 0.5, c, H, WALL_CREAM, op, bevel=0.0)
        W += siding(axis, a, b, c, o, H, WALL_LINE, op, step=1.3, margin=0.8)
        T += base_trim(axis, a, b, c, o, TEAL, op, h=1.1)
    W += ceiling(X1 + 0.5, X2 - 0.5, Y1 + 0.5, Y2 - 0.5, H)
    T += corner_boards(X1, X2, Y1, Y2, H, CREAM)
    for x in (X1 - 0.42, X2 + 0.42):
        for y in (Y1 - 0.42, Y2 + 0.42):
            T.append(box((1.4, 1.4, 1.5), (x, y, 0.75), TEAL_DARK, bevel=0.14, segments=2))
            T.append(box((1.15, 1.15, 0.55), (x, y, H - 0.6), TEAL, bevel=0.1, segments=1))
    for y, o in ((Y2, 1), (Y1, -1)):
        T.append(box((X2 - X1 - 0.2, 0.45, 0.75), (0, y + o * 0.72, H - 0.42), CREAM, bevel=0.08, segments=1))


def v3_door(axis, p1, p2, c, top, T):
    """Teal door frame with a brass threshold (open doorway)."""
    T += door_frame(axis, p1, p2, c, top, colour=TEAL)
    T.append(box(_size(axis, p2 - p1, 1.2, 0.12), _along(axis, (p1 + p2) / 2, c, 1, z=0.06), BRASS, bevel=0.03, segments=1))


def v3_window(axis, p, c, o, w, h, zc, seed, T, WIN, F, A, awn=True):
    """Teal-framed window, clear glass, flower box, optional striped awning."""
    t_, g_ = window(axis, p, c, o, w, h, zc, shutters=False, glass_colour=GLASS_BLUE, mullion=TEAL, sill=False)
    T += t_
    WIN += g_
    flower_box(axis, p, c, o, w, zc - h / 2 - 0.95, seed, F)
    if awn:
        A += awning(axis, p, c, o, w + 1.2, zc + h / 2 + 1.2, depth=2.0)


def v3_roof(X1, X2, Y1, Y2, H, rise, d, over, W, T, R):
    """Clay-tile roof (ridge along X) with sided gable ends at x = X1 / X2."""
    r, t = tile_roof(X1 - over, X2 + over, -d, d, H, rise)
    R += r
    T += t
    for x, o in ((X1, -1), (X2, 1)):
        w_, t_ = gable_infill(x, Y1 - 0.5, Y2 + 0.5, 0.0, d, H, rise, WALL_CREAM, vent=False)
        W += w_
        gable_siding(x, o, H, rise, d, (Y2 - Y1) / 2, T)


def roof_deck(H, rise, d, y):
    """Height of the roof deck line above y (for chimneys and vents)."""
    return H + rise * (1 - abs(y) / d)


def arch_sign(facing, xw, z0, iw, ih, word, size, S, L, T, crest=1.0):
    """Arched wooden sign (office style) on the wall at x = xw facing +-X:
    gold border, wooden board, outlined cream letters, marquee bulbs on the
    border, gold badge on the crest, iron brackets to the wall. z0 = bottom
    of the gold border."""
    o = 1 if facing == "+x" else -1
    sx = xw + o * 1.15
    ir, ic, icw = ih * 0.28 * crest, ih * 0.38 * crest, iw * 0.11
    bw, bh, br, bc, bcw = iw + 0.9, ih + 0.5, ir + 0.15, ic + 0.2, icw + 0.15
    S.append(extrude_yz([(u, z0 + z) for u, z in sign_outline(bw, bh, br, bc, bcw)], sx - o * 0.08, 0.0, 0.4, SIGN_GOLD, bevel=0.08))
    S.append(extrude_yz([(u, z0 + 0.25 + z) for u, z in sign_outline(iw, ih, ir, ic, icw)], sx + o * 0.06, 0.0, 0.4, SIGN_WOOD, bevel=0.08))
    for y in (-iw * 0.3, iw * 0.3):
        S.append(segment((xw + o * 0.45, y, z0 + ih * 0.55), (sx - o * 0.26, y, z0 + ih * 0.55), 0.14, IRON, verts=6))
    ring = [(u, z0 + 0.12 + z) for u, z in sign_outline(bw - 0.45, bh - 0.22, br, bc, bcw)]
    ring.append(ring[0])
    for p0, p1 in zip(ring, ring[1:]):
        seglen = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
        n = max(1, int(seglen / 1.1))
        for k in range(n):
            tt = k / n
            L.append(bulb((sx + o * 0.2, p0[0] + (p1[0] - p0[0]) * tt, p0[1] + (p1[1] - p0[1]) * tt), 0.13))
    zt = z0 + 0.25 + ih / 2
    S.append(text3d(word, size, (sx + o * 0.28, 0.0, zt), facing, LETTER_EDGE, depth=0.1, bold=0.11))
    L.append(text3d(word, size, (sx + o * 0.36, 0.0, zt), facing, LETTER_WHITE, depth=0.16, bold=0.035))
    zc = z0 + 0.25 + ih + ir + ic * 0.55
    S.append(cyl(ic * 0.62, 0.14, (sx + o * 0.3, 0.0, zc), SIGN_GOLD, verts=16, rot=(0, math.pi / 2, 0)))
    S.append(cyl(ic * 0.42, 0.14, (sx + o * 0.36, 0.0, zc), EMBLEM_SNOW, verts=16, rot=(0, math.pi / 2, 0)))


def linen_shed_v2():
    """Laundry / linen shed in the office v3 style (footprint of LinenShed)."""
    return with_palette(V3_PALETTE, _linen_shed_v3)


def shop_v2():
    """Supply shop in the office v3 style (footprint of Shop)."""
    return with_palette(V3_PALETTE, _shop_v3)


def kitchen_v2():
    """Kitchen in the office v3 style (footprint of Kitchen)."""
    return with_palette(V3_PALETTE, _kitchen_v3)


def _linen_shed_v3():
    H = 12
    X1, X2, Y1, Y2 = -7.0, 7.0, -7.5, 7.5
    RISE, D = 5.0, 9.1
    W, T, R, A, F, S, WIN, L = [], [], [], [], [], [], [], []
    opens = {"-x": [(-4.0, 4.0, 0, DOOR_TOP)], "+y": [(-5.0, -2.0, 4.0, 7.0), (2.0, 5.0, 4.0, 7.0)]}
    v3_shell(X1, X2, Y1, Y2, H, opens, W, T)
    v3_door("y", -4.0, 4.0, X1, DOOR_TOP, T)
    for cx, seed in ((-3.5, 11), (3.5, 12)):
        v3_window("x", cx, Y2, 1, 3.0, 3.0, 5.5, seed, T, WIN, F, A)
    A += awning("y", 0.0, X1, -1, 9.4, 9.8, depth=2.6)
    for y in (-5.4, 5.4):
        lantern((X1 - 0.5, y, 6.4), L, T, facing=(-1, 0))
    for x in (-4.0, 4.0):
        L.append(cyl(0.27, 0.12, (x, Y2 + 0.74, H - 0.86), GLOW, verts=8))
        L.append(cyl(0.27, 0.12, (x, Y1 - 0.74, H - 0.86), GLOW, verts=8))
    # Dryer vent on the east wall, steel roof vent.
    T.append(cyl(0.55, 1.2, (X2 + 0.9, 3.0, 8.0), STEEL, verts=12, rot=(0, math.pi / 2, 0)))
    T.append(box((0.3, 1.6, 1.6), (X2 + 1.5, 3.0, 8.0), STEEL_DARK, bevel=0.08, segments=1))
    v3_roof(X1, X2, Y1, Y2, H, RISE, D, 1.6, W, T, R)
    vz = roof_deck(H, RISE, D, -3.8)
    R.append(cyl(0.55, 2.6, (3.5, -3.8, vz + 1.1), STEEL, verts=16))
    R.append(cyl(0.7, 0.22, (3.5, -3.8, vz + 2.45), STEEL_DARK, verts=16))
    R.append(cyl(0.85, 0.45, (3.5, -3.8, vz + 2.8), STEEL, verts=16, radius2=0.3))
    arch_sign("-x", X1, 10.1, 9.0, 2.0, "LAUNDRY", 1.35, S, L, T)
    return out(
        {"Walls": W, "Trim": T, "Roof": R, "Awning": A, "Flowers": F, "Sign": S, "Glass": WIN, "Glow": L},
        "LinenShedV2",
        {"Walls": "Precise", "Roof": "Hull"},
        dict(place=[[60, 0, -16]]),
    )


def _shop_v3():
    H = 12
    X1, X2, Y1, Y2 = -10.0, 10.0, -8.0, 8.0
    RISE, D = 6.0, 9.8
    W, T, R, A, F, S, WIN, L = [], [], [], [], [], [], [], []
    side = [(-4.0, 4.0, 6.6, 9.4)]
    opens = {"-x": [(-7.3, -4.9, 2.4, 6.8), (-4.0, 4.0, 0, DOOR_TOP), (4.9, 7.3, 2.4, 6.8)], "+y": side, "-y": side}
    v3_shell(X1, X2, Y1, Y2, H, opens, W, T)
    v3_door("y", -4.0, 4.0, X1, DOOR_TOP, T)
    for cy, seed in ((-6.1, 21), (6.1, 22)):
        v3_window("y", cy, X1, -1, 2.4, 4.4, 4.6, seed, T, WIN, F, A, awn=False)
    for y, o, seed in ((Y1, -1, 23), (Y2, 1, 24)):
        v3_window("x", 0.0, y, o, 8.0, 2.8, 8.0, seed, T, WIN, F, A, awn=False)
    A += awning("y", 0.0, X1, -1, 10.0, 9.7, depth=3.0)
    for x in (-7.0, 7.0):
        L.append(cyl(0.27, 0.12, (x, Y2 + 0.74, H - 0.86), GLOW, verts=8))
        L.append(cyl(0.27, 0.12, (x, Y1 - 0.74, H - 0.86), GLOW, verts=8))
    for y in (-6.1, 6.1):
        gooseneck((X1 - 0.55, y, 8.2), 0.8, 1.0, (-1, 0), L, T, size=0.85)
    v3_roof(X1, X2, Y1, Y2, H, RISE, D, 1.7, W, T, R)
    cz = roof_deck(H, RISE, D, 4.0 + 1.3)
    R += chimney(5.5, -4.0, cz, H + RISE + 1.6 - cz, colour=BRICK_LIGHT)
    mortar_lines(5.5, -4.0, cz, H + RISE + 1.6 - cz, 2.6, R)
    arch_sign("-x", X1, 10.0, 12.6, 2.2, "SUPPLY SHOP", 1.45, S, L, T)
    # OPEN sign hanging in the north window (Roblox z -29.8): own glow mesh
    # so the game can blink it.
    open_parts = [box((0.2, 2.4, 1.2), (X1 - 0.85, -6.1, 5.3), srgb(255, 72, 96), bevel=0.08, segments=1)]
    open_parts.append(text3d("OPEN", 0.75, (X1 - 0.98, -6.1, 5.25), "-x", LETTER_WHITE, depth=0.08))
    res = out(
        {"Walls": W, "Trim": T, "Roof": R, "Awning": A, "Flowers": F, "Sign": S, "Glass": WIN, "Glow": L},
        "ShopV2",
        {"Walls": "Precise", "Roof": "Hull"},
        dict(place=[[100, 0, -36]]),
    )
    res["SM_Bld_ShopV2_OpenSign"] = (build_mesh("SM_Bld_ShopV2_OpenSign", open_parts, "glow"), dict(glow=True, collision="None", place=[[100, 0, -36]]))
    return res


def _kitchen_v3():
    H = 10
    X1, X2, Y1, Y2 = -7.0, 7.0, -7.0, 7.0
    RISE, D = 4.6, 8.8
    W, T, R, A, F, S, WIN, L = [], [], [], [], [], [], [], []
    opens = {"+x": [(-2.0, 2.0, 0, DOOR_TOP)], "+y": [(-4.5, -1.5, 3.3, 6.7), (1.5, 4.5, 3.3, 6.7)]}
    v3_shell(X1, X2, Y1, Y2, H, opens, W, T)
    v3_door("y", -2.0, 2.0, X2, DOOR_TOP, T)
    for cx, seed in ((-3.0, 31), (3.0, 32)):
        v3_window("x", cx, Y2, 1, 3.0, 3.4, 5.0, seed, T, WIN, F, A)
    A += awning("y", 0.0, X2, 1, 5.4, 9.6)
    for y in (-3.4, 3.4):
        lantern((X2 + 0.5, y, 6.2), L, T, facing=(1, 0))
    for x in (-4.0, 4.0):
        L.append(cyl(0.27, 0.12, (x, Y2 + 0.74, H - 0.86), GLOW, verts=8))
        L.append(cyl(0.27, 0.12, (x, Y1 - 0.74, H - 0.86), GLOW, verts=8))
    v3_roof(X1, X2, Y1, Y2, H, RISE, D, 1.6, W, T, R)
    # Stainless kitchen exhaust (as before) through the back slope.
    ez = roof_deck(H, RISE, D, -4.0)
    R.append(cyl(0.75, 5.0, (-4.5, -4.0, ez + 2.0), STEEL, verts=14))
    R.append(cyl(1.2, 0.5, (-4.5, -4.0, ez + 4.7), STEEL_DARK, verts=14, radius2=0.5))
    R.append(cyl(1.05, 0.4, (-4.5, -4.0, ez + 0.1), STEEL_DARK, verts=14))
    arch_sign("+x", X2, 9.8, 6.6, 1.5, "KITCHEN", 1.02, S, L, T, crest=0.7)
    return out(
        {"Walls": W, "Trim": T, "Roof": R, "Awning": A, "Flowers": F, "Sign": S, "Glass": WIN, "Glow": L},
        "KitchenV2",
        {"Walls": "Precise", "Roof": "Hull"},
        dict(place=[[-1, 0, 5]]),
    )


# ======================================================================
# Batch "lobby": the lobby hall (LobbyBuilder) restyled to match office v3
# (cartoon-style). Footprint 82 x 56, walls 16, wide front opening 34 x 10
# (Roblox -Z = Blender +Y), four room doors on the back wall inside, boards
# on the side walls. The game keeps its primitive parts as invisible
# colliders and SurfaceGui hosts; these meshes are the visuals.
#   LobbyHall     shell, siding, clay-tile roof, front windows, pillars,
#                 lanterns, WELCOME arch sign, wainscot + plank floor,
#                 ceiling beams
#   LobbyTitle    "RUN A MOTEL" arch sign with marquee bulbs (back wall)
#   LobbyDoor     double door (tinted per room), teal frame, glowing transom
#   LobbyPad      wooden pad base with a brass ring and rim bulbs
#   LobbyBoardL/M/W  wooden board frames with gold bead and gooseneck lamps
# ======================================================================
FLOOR_A = srgb(206, 160, 108)
FLOOR_B = srgb(188, 140, 94)
WAINSCOT = srgb(150, 92, 54)


def turn_parts(parts, angle, offset):
    """Rotate parts about Z through the origin, then move them (baked)."""
    m = Matrix.Translation(Vector(offset)) @ Matrix.Rotation(angle, 4, "Z")
    for o in parts:
        o.matrix_world = m @ o.matrix_world
    bpy.context.view_layer.update()
    for o in parts:
        _activate(o)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def arch_sign_y(facing, yw, xc, z0, iw, ih, word, size, S, L, crest=1.0):
    """arch_sign on a wall at y = yw facing +-Y, centred on x = xc."""
    s_, l_, t_ = [], [], []
    arch_sign("+x", 0.0, z0, iw, ih, word, size, s_, l_, t_, crest=crest)
    turn_parts(s_ + l_ + t_, math.pi / 2 if facing == "+y" else -math.pi / 2, (xc, yw, 0))
    S += s_ + t_
    L += l_


def lobby_hall():
    return with_palette(V3_PALETTE, _lobby_hall)


def _lobby_hall():
    H = 16
    X1, X2, Y1, Y2 = -41.0, 41.0, -28.0, 28.0
    RISE, D = 9.0, 29.8
    W, T, R, A, F, S, WIN, L, P = [], [], [], [], [], [], [], [], []
    front = [(-17.0, 17.0, 0, 10.0), (-32.0, -26.0, 3.2, 7.6), (26.0, 32.0, 3.2, 7.6)]
    v3_shell(X1, X2, Y1, Y2, H, {"+y": front}, W, T)
    v3_door("x", -17.0, 17.0, Y2, 10.0, T)
    for cx, seed in ((-29.0, 41), (29.0, 42)):
        v3_window("x", cx, Y2, 1, 6.0, 4.4, 5.4, seed, T, WIN, F, A)
    # Pillars flanking the opening.
    for x in (-16.2, 16.2):
        T.append(cyl(0.75, 9.0, (x, Y2 + 1.0, 5.0), CREAM, verts=16))
        T.append(box((2.0, 2.0, 1.2), (x, Y2 + 1.0, 0.6), TEAL_DARK, bevel=0.16, segments=2))
        T.append(box((1.9, 1.9, 0.7), (x, Y2 + 1.0, 9.75), TEAL, bevel=0.12, segments=2))
    for x in (-19.6, 19.6):
        lantern((x, Y2 + 0.5, 7.2), L, T, facing=(0, 1))
    for x in (-34.0, -22.0, 22.0, 34.0):
        L.append(cyl(0.27, 0.12, (x, Y2 + 0.74, H - 0.86), GLOW, verts=8))
    for x in (-30.0, -10.0, 10.0, 30.0):
        L.append(cyl(0.27, 0.12, (x, Y1 - 0.74, H - 0.86), GLOW, verts=8))
    arch_sign_y("+y", Y2 + 0.5, 0.0, 10.6, 13.0, 2.4, "WELCOME", 1.7, S, L, crest=0.8)
    v3_roof(X1, X2, Y1, Y2, H, RISE, D, 1.8, W, T, R)
    cz = roof_deck(H, RISE, D, -14.0 + 1.3)
    R += chimney(28.0, -14.0, cz, H + RISE + 1.6 - cz, colour=BRICK_LIGHT)
    mortar_lines(28.0, -14.0, cz, H + RISE + 1.6 - cz, 2.6, R)
    # Interior: wainscot (teal base, wood panels with battens, cream rail).
    # Side runs stop short of the front / back runs (no overlapping corners).
    runs = [
        ("x", X1 + 0.5, X2 - 0.5, Y1 + 0.5, 1),
        ("x", X1 + 0.5, -17.8, Y2 - 0.5, -1),
        ("x", 17.8, X2 - 0.5, Y2 - 0.5, -1),
        ("y", Y1 + 0.95, Y2 - 0.95, X1 + 0.5, 1),
        ("y", Y1 + 0.95, Y2 - 0.95, X2 - 0.5, -1),
    ]
    for axis, a, b, c, o in runs:
        mid, length = (a + b) / 2, b - a
        P.append(box(_size(axis, length, 0.22, 3.0), _along(axis, mid, c, o, v=0.11, z=1.9), WAINSCOT, bevel=0.04, segments=1))
        P.append(box(_size(axis, length, 0.3, 0.55), _along(axis, mid, c, o, v=0.18, z=0.68), TEAL, bevel=0.06, segments=1))
        P.append(box(_size(axis, length, 0.36, 0.3), _along(axis, mid, c, o, v=0.2, z=3.5), CREAM, bevel=0.08, segments=1))
        n = max(1, int(length / 3.2))
        for k in range(1, n):
            u = a + length * k / n
            P.append(box(_size(axis, 0.22, 0.3, 2.3), _along(axis, u, c, o, v=0.2, z=2.1), WOOD_DARK, bevel=0.03, segments=1))
    # Plank floor (top at 0.4), staggered joints.
    rows = 28
    fy1, fy2, fx1, fx2 = Y1 + 0.5, Y2 + 0.5, X1 + 0.5, X2 - 0.5  # front row runs out of the opening
    for r in range(rows):
        y = fy1 + (r + 0.5) * (fy2 - fy1) / rows
        cut = X1 + 18.0 + (r % 3) * 16.0
        for xa, xb, k in ((fx1, cut, 0), (cut, fx2, 1)):
            colour = FLOOR_A if (r + k) % 2 == 0 else FLOOR_B
            P.append(box((xb - xa - 0.06, (fy2 - fy1) / rows - 0.08, 0.4), ((xa + xb) / 2, y, 0.2), colour, bevel=0.05, segments=1))
    # Ceiling beams (the lamps hang under them).
    for x in (-30.0, -15.0, 0.0, 15.0, 30.0):
        P.append(box((1.1, Y2 - Y1 - 1.0, 0.9), (x, 0.0, H - 0.45), WOOD_DARK, bevel=0.1, segments=1))
    return out(
        {"Walls": W, "Trim": T, "Roof": R, "Awning": A, "Flowers": F, "Sign": S, "Glass": WIN, "Glow": L, "Interior": P},
        "LobbyHall",
        None,
        dict(place=[[0, 0, 0]]),
    )


def lobby_title():
    return with_palette(V3_PALETTE, _lobby_title)


def _lobby_title():
    S, L = [], []
    arch_sign_y("+y", -27.5, 0.0, 10.5, 26.0, 3.4, "RUN A MOTEL", 2.5, S, L, crest=0.45)
    return out({"Sign": S, "Glow": L}, "LobbyTitle", None, dict(place=[[0, 0, 0]]))


def lobby_door():
    return with_palette(V3_PALETTE, _lobby_door)


def _lobby_door():
    """Double door on the wall plane y = 0 facing +Y, floor at z = 0.
    Opening 6.4 x 8.8; the leaves are tinted per room."""
    w, h, t = 3.1, 8.6, 0.35
    leaf, hw, frame, glow = [], [], [], []
    for side in (-1, 1):
        cx = side * (w / 2 + 0.05)
        leaf.append(box((w, t, h), (cx, 0.3, h / 2), NEUTRAL, bevel=0.08))
        for z, hh in ((1.6, 2.4), (4.6, 2.4)):
            leaf.append(box((w - 1.0, 0.12, hh), (cx, 0.3 + t / 2 + 0.04, z), mul(NEUTRAL, 0.92), bevel=0.07))
        # Round porthole window.
        leaf.append(cyl(0.72, 0.14, (cx, 0.3 + t / 2 + 0.05, 7.0), mul(NEUTRAL, 0.88), verts=14, rot=(math.pi / 2, 0, 0)))
        glow.append(cyl(0.55, 0.16, (cx, 0.3 + t / 2 + 0.07, 7.0), GLOW, verts=14, rot=(math.pi / 2, 0, 0)))
        hw.append(box((0.32, 0.08, 1.4), (side * 0.45, 0.3 + t / 2 + 0.06, 4.0), BRASS, bevel=0.04, segments=1))
        hw.append(box((w - 0.3, 0.06, 0.6), (cx, 0.3 + t / 2 + 0.05, 0.4), BRASS, bevel=0.03, segments=1))
    # Teal frame, cream keystone header, glowing transom with mullions.
    for x in (-3.55, 3.55):
        frame.append(box((0.75, 0.8, 9.4), (x, 0.3, 4.7), TEAL, bevel=0.1))
        frame.append(box((1.0, 0.95, 0.8), (x, 0.32, 0.4), TEAL_DARK, bevel=0.08))
    frame.append(box((7.9, 0.85, 0.7), (0.0, 0.32, 9.0), TEAL, bevel=0.1))
    frame.append(box((7.9, 0.85, 0.5), (0.0, 0.32, 10.0), TEAL_DARK, bevel=0.1))
    frame.append(box((8.4, 1.0, 0.25), (0.0, 0.36, 10.3), TEAL, bevel=0.06))
    frame.append(box((1.0, 1.0, 1.1), (0.0, 0.4, 9.75), CREAM, bevel=0.12, segments=2))
    glow.append(box((6.4, 0.12, 0.55), (0.0, 0.2, 9.55), GLOW, bevel=0.03, segments=1))
    for x in (-2.0, 2.0):
        frame.append(box((0.16, 0.3, 0.6), (x, 0.32, 9.55), TEAL_DARK, bevel=0.02, segments=1))
    return {
        "SM_Bld_LobbyDoor_Leaf": (build_mesh("SM_Bld_LobbyDoor_Leaf", leaf, "tint"), dict(tint=True, collision="None", place=[[0, 0, 0]])),
        "SM_Bld_LobbyDoor_Hardware": (build_mesh("SM_Bld_LobbyDoor_Hardware", hw), dict(collision="None", place=[[0, 0, 0]])),
        "SM_Bld_LobbyDoor_Frame": (build_mesh("SM_Bld_LobbyDoor_Frame", frame), dict(collision="None", place=[[0, 0, 0]])),
        "SM_Bld_LobbyDoor_Glow": (build_mesh("SM_Bld_LobbyDoor_Glow", glow, "glow"), dict(glow=True, collision="None", place=[[0, 0, 0]])),
    }


def lobby_pad():
    """Pad base: wooden disc (r 5.4) with a brass ring and rim bulbs; the
    game's tinted neon pad (r 4.5) sits on top. Floor at z = 0."""
    base, glow = [], []
    base.append(cyl(5.4, 0.22, (0, 0, 0.11), WOOD_DARK, verts=40, bevel=0.06))
    base.append(cyl(5.05, 0.1, (0, 0, 0.25), BRASS, verts=40, bevel=0.03))
    base.append(cyl(4.7, 0.1, (0, 0, 0.28), WOOD, verts=40, bevel=0.03))
    for k in range(12):
        a = k * math.pi * 2 / 12
        glow.append(blob(0.2, (math.cos(a) * 5.1, math.sin(a) * 5.1, 0.36), GLOW, lump=0, segs=8, rings=5))
    return {
        "SM_Prop_LobbyPad_Base": (build_mesh("SM_Prop_LobbyPad_Base", base), dict(collision="None", place=[[0, 0, 0]])),
        "SM_Prop_LobbyPad_Glow": (build_mesh("SM_Prop_LobbyPad_Glow", glow, "glow"), dict(glow=True, collision="None", place=[[0, 0, 0]])),
    }


def board_frame(prefix, bw, bh):
    """Wooden frame around a bw x bh board (board plane y = 0, facing +Y,
    origin at the board centre): chunky wood bars, gold bead, brass corner
    caps, header crest and two gooseneck lamps over the top."""
    T, L = [], []
    fw = 0.9
    for z in (bh / 2 + fw / 2, -(bh / 2 + fw / 2)):
        T.append(box((bw + fw * 2, 0.7, fw), (0, 0.2, z), WOOD_DARK, bevel=0.14, segments=2))
    for x in (bw / 2 + fw / 2, -(bw / 2 + fw / 2)):
        T.append(box((fw, 0.7, bh), (x, 0.2, 0), WOOD_DARK, bevel=0.14, segments=2))
    for z in (bh / 2 + 0.06, -(bh / 2 + 0.06)):
        T.append(box((bw + 0.2, 0.3, 0.16), (0, 0.42, z), SIGN_GOLD, bevel=0.05, segments=1))
    for x in (bw / 2 + 0.06, -(bw / 2 + 0.06)):
        T.append(box((0.16, 0.3, bh + 0.2), (x, 0.42, 0), SIGN_GOLD, bevel=0.05, segments=1))
    for x in (bw / 2 + fw / 2, -(bw / 2 + fw / 2)):
        for z in (bh / 2 + fw / 2, -(bh / 2 + fw / 2)):
            T.append(box((1.2, 0.85, 1.2), (x, 0.25, z), SIGN_GOLD, bevel=0.2, segments=2))
    crest_w = min(bw * 0.4, 7.0)
    T.append(box((crest_w, 0.6, 0.9), (0, 0.15, bh / 2 + fw + 0.4), WOOD, bevel=0.2, segments=2))
    T.append(cyl(0.55, 0.3, (0, 0.5, bh / 2 + fw + 0.45), SIGN_GOLD, verts=16, rot=(math.pi / 2, 0, 0)))
    for x in (-bw * 0.28, bw * 0.28):
        gooseneck((x, 0.05, bh / 2 + fw), 0.6, 1.1, (0, 1), L, T, size=0.85)
    return {
        f"SM_Prop_{prefix}_Frame": (build_mesh(f"SM_Prop_{prefix}_Frame", T), dict(collision="None", place=[[0, 0, 0]])),
        f"SM_Prop_{prefix}_Glow": (build_mesh(f"SM_Prop_{prefix}_Glow", L, "glow"), dict(glow=True, collision="None", place=[[0, 0, 0]])),
    }


def lobby_board_l():
    return board_frame("LobbyBoardL", 24.0, 14.0)


def lobby_board_m():
    return board_frame("LobbyBoardM", 15.0, 11.0)


def lobby_board_w():
    return board_frame("LobbyBoardW", 22.0, 13.0)


# ======================================================================
# Batch 4: interior furniture, lamps, pool / yard / road props
# (prop-artist + cartoon-style). Sizes follow the part-built decor they
# replace (MapDecor / MapBuilder); front = +Y (Roblox -Z), origin noted
# per builder (floor contact unless "wall" or "ceiling").
# ======================================================================
FABRIC_BLUE = srgb(70, 134, 168)
FABRIC_DARK = srgb(50, 104, 138)
RUG_RED = srgb(178, 58, 60)
RUG_GOLD = srgb(234, 190, 92)
RUG_CREAM = srgb(244, 226, 190)
COPPER = srgb(208, 122, 74)
CANVAS = srgb(150, 162, 178)
RECYCLE_BLUE = srgb(62, 128, 208)
STOP_YELLOW = srgb(246, 206, 72)
POOL_WHITE = srgb(246, 248, 250)
FLOATIE_PINK = srgb(255, 118, 170)
CYAN_GLOW = srgb(130, 226, 255)
POLE_WOOD = srgb(122, 84, 56)
SCREEN_GLOW = srgb(110, 170, 230)
PAPER = srgb(250, 246, 232)
INK = srgb(70, 70, 80)
SKY = srgb(150, 210, 245)
HILL = srgb(110, 180, 90)
HILL_DARK = srgb(80, 150, 80)
SUN = srgb(255, 214, 90)
FLOWER_MIX = [srgb(255, 110, 150), srgb(255, 212, 80), srgb(190, 130, 255), srgb(255, 255, 255), srgb(255, 150, 90)]


def extrude_up(points_xy, z0, h, colour, bevel=0.0):
    """Closed (x, y) outline extruded straight up from z0 by h (curtains)."""
    bm = bmesh.new()
    bot = [bm.verts.new((x, y, z0)) for x, y in points_xy]
    top = [bm.verts.new((x, y, z0 + h)) for x, y in points_xy]
    bm.faces.new(list(reversed(bot)))
    bm.faces.new(top)
    n = len(points_xy)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((bot[i], bot[j], top[j], top[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("up")
    bm.to_mesh(mesh)
    bm.free()
    o = bpy.data.objects.new("up", mesh)
    scene.collection.objects.link(o)
    return finish(o, colour, bevel=bevel, segments=1, smooth_angle=60)


def torus_arc(R, r, a0, a1, loc, colour, segs=4, rsegs=8):
    """Section of a torus (axis Z) from angle a0 to a1: striped rings."""
    bm = bmesh.new()
    rings = []
    for i in range(segs + 1):
        a = a0 + (a1 - a0) * i / segs
        cx, cy = math.cos(a), math.sin(a)
        ring = []
        for k in range(rsegs):
            b = k * 2 * math.pi / rsegs
            rr = R + r * math.cos(b)
            ring.append(bm.verts.new((loc[0] + cx * rr, loc[1] + cy * rr, loc[2] + r * math.sin(b))))
        rings.append(ring)
    for i in range(segs):
        for k in range(rsegs):
            kk = (k + 1) % rsegs
            bm.faces.new((rings[i][k], rings[i + 1][k], rings[i + 1][kk], rings[i][kk]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("torus")
    bm.to_mesh(mesh)
    bm.free()
    o = bpy.data.objects.new("torus", mesh)
    scene.collection.objects.link(o)
    return finish(o, colour, smooth_angle=70)


def wave_panel(x0, x1, y, depth, z0, h, folds, colour):
    """Curtain panel: wavy cross-section (folds) between x0 and x1."""
    n = folds * 4
    front = [(x0 + (x1 - x0) * i / n, y + depth * 0.5 * math.sin(i / n * folds * 2 * math.pi)) for i in range(n + 1)]
    back = [(x, yy + 0.08) for x, yy in reversed(front)]
    return extrude_up(front + back, z0, h, colour)


# ---------------------------------------------------------------- lobby
def couch():
    """Lobby sofa 7 wide x 3.2 deep (old seat 2.6 x 7 + back), seat ~1.5.
    Origin floor, back at -Y. Placed facing +X (yaw -90)."""
    W, D = 7.0, 3.2
    frame = [
        box((W, D, 0.9), (0, 0, 0.75), FABRIC_DARK, bevel=0.25),
        box((W, 0.9, 2.2), (0, -D / 2 + 0.45, 1.75), FABRIC_DARK, bevel=0.35),
    ]
    for s in (-1, 1):
        frame.append(box((0.8, D + 0.1, 1.5), (s * (W / 2 - 0.4), 0, 1.15), FABRIC_DARK, bevel=0.32))  # arms stand proud of the base
        frame.append(cyl(0.42, D + 0.1, (s * (W / 2 - 0.4), 0, 1.9), FABRIC_DARK, verts=12, rot=(math.pi / 2, 0, 0)))
    cushions = []
    for x in (-1.45, 1.45):
        cushions.append(box((2.8, D - 1.1, 0.55), (x, 0.4, 1.45), FABRIC_BLUE, bevel=0.24, segments=2))
        cushions.append(box((2.7, 0.6, 1.5), (x, -D / 2 + 1.05, 2.25), FABRIC_BLUE, bevel=0.26, segments=2, rot=(-0.12, 0, 0)))
    cushions.append(blob(0.5, (-2.6, 0.0, 2.0), RUG_GOLD, squash=(0.7, 0.4, 0.75), lump=0.05))
    cushions.append(blob(0.5, (2.6, 0.0, 2.0), RUG_RED, squash=(0.7, 0.4, 0.75), lump=0.05))
    legs = [cyl(0.14, 0.32, (x, y, 0.16), WOOD_DARK, verts=10, radius2=0.1) for x in (-3.1, 3.1) for y in (-1.3, 1.3)]
    return {"SM_Prop_Couch": (build_mesh("SM_Prop_Couch", frame + cushions + legs), dict(collision="Box"))}


def coffee_table():
    """Coffee table 3.6 x 2.4, top at 1.0 above the floor, magazine and mug."""
    parts = [
        box((3.6, 2.4, 0.22), (0, 0, 0.9), WOOD, bevel=0.1),
        box((3.3, 2.1, 0.1), (0, 0, 0.35), WOOD_DARK, bevel=0.04),
    ]
    for x in (-1.55, 1.55):
        for y in (-0.95, 0.95):
            parts.append(cyl(0.13, 0.82, (x, y, 0.4), WOOD_DARK, verts=10, radius2=0.1))
    parts += [
        box((1.0, 1.4, 0.08), (0.4, -0.3, 1.05), RED, bevel=0.03, rot=(0, 0, 0.2)),
        box((0.9, 1.3, 0.08), (0.45, -0.25, 1.13), TEAL, bevel=0.03, rot=(0, 0, -0.1)),
        lathe([(0.0, 0), (0.2, 0), (0.22, 0.32), (0.18, 0.34), (0.0, 0.34)], (-0.9, 0.4, 1.01), CREAM, verts=12),
        cyl(0.08, 0.2, (-0.66, 0.4, 1.18), CREAM, verts=8, rot=(math.pi / 2, 0, 0)),
    ]
    return {"SM_Prop_CoffeeTable": (build_mesh("SM_Prop_CoffeeTable", parts), dict(collision="Box"))}


def lobby_rug():
    """Lobby runner 6 x 12 (old rug + border): gold border, red field, cream motifs."""
    parts = [
        box((6.6, 12.6, 0.05), (0, 0, 0.025), RUG_GOLD, bevel=0.02, segments=1),
        box((5.8, 11.8, 0.06), (0, 0, 0.035), RUG_RED, bevel=0.02, segments=1),
    ]
    for y in (-4.0, 0.0, 4.0):
        parts.append(box((1.6, 1.6, 0.04), (0, y, 0.07), RUG_CREAM, bevel=0.0, rot=(0, 0, math.pi / 4)))
        parts.append(box((0.8, 0.8, 0.04), (0, y, 0.08), RUG_GOLD, bevel=0.0, rot=(0, 0, math.pi / 4)))
    for x in (-2.5, 2.5):
        parts.append(box((0.18, 11.2, 0.04), (x, 0, 0.07), RUG_CREAM, bevel=0.0))
    for y in (-6.45, 6.45):
        for k in range(12):
            parts.append(box((0.12, 0.35, 0.03), (-3.0 + k * 0.55, y + (0.12 if y > 0 else -0.12), 0.02), RUG_CREAM, bevel=0.0))
    return {"SM_Prop_LobbyRug": (build_mesh("SM_Prop_LobbyRug", parts), dict(collision="None"))}


def key_rack():
    """Wall key rack 6 x 3 (origin board centre), six hooks with tagged keys."""
    parts = [
        box((6.0, 0.3, 3.0), (0, 0, 0), WOOD_DARK, bevel=0.1),
        box((5.4, 0.12, 2.4), (0, 0.18, 0), WOOD, bevel=0.06, segments=1),
        box((2.2, 0.1, 0.5), (0, 0.26, 1.0), BRASS, bevel=0.04, segments=1),
    ]
    tags = [TEAL, RED, RUG_GOLD, TEAL, RED, RUG_GOLD]
    for k in range(6):
        x = -2.5 + k
        parts.append(segment((x, 0.24, 0.35), (x, 0.55, 0.45), 0.05, BRASS, verts=6))
        parts.append(cyl(0.12, 0.06, (x, 0.5, 0.15), BRASS, verts=10, rot=(math.pi / 2, 0, 0)))
        parts.append(box((0.08, 0.04, 0.45), (x, 0.5, -0.17), BRASS, bevel=0.0))
        parts.append(box((0.32, 0.06, 0.5), (x, 0.42, -0.62), tags[k], bevel=0.05, segments=1))
    return {"SM_Prop_KeyRack": (build_mesh("SM_Prop_KeyRack", parts), dict(collision="None"))}


def wall_clock():
    """Wall clock, 2 across (origin face centre at the wall)."""
    parts = [
        cyl(1.0, 0.24, (0, 0.12, 0), TEAL, verts=24, rot=(math.pi / 2, 0, 0)),
        cyl(0.86, 0.06, (0, 0.27, 0), PAPER, verts=24, rot=(math.pi / 2, 0, 0)),
        cyl(0.09, 0.08, (0, 0.33, 0), IRON, verts=10, rot=(math.pi / 2, 0, 0)),
        box((0.1, 0.04, 0.55), (0, 0.33, 0.25), IRON, bevel=0.0),
        box((0.38, 0.04, 0.08), (0.17, 0.34, 0.0), IRON, bevel=0.0, rot=(0, -0.5, 0)),
    ]
    for k in range(12):
        a = k * math.pi / 6
        long = k % 3 == 0
        parts.append(box((0.06, 0.03, 0.2 if long else 0.1), (math.sin(a) * 0.72, 0.31, math.cos(a) * 0.72), INK, bevel=0.0, rot=(0, -a, 0)))
    return {"SM_Prop_WallClock": (build_mesh("SM_Prop_WallClock", parts), dict(collision="None"))}


def coffee_bar():
    """Coffee counter 3.6 wide x 2 deep x 3 tall + machine, cups, jar."""
    parts = [
        box((3.6, 2.0, 2.7), (0, 0, 1.35), WOOD, bevel=0.12),
        box((3.8, 2.2, 0.2), (0, 0, 2.8), CREAM, bevel=0.07),
        box((3.4, 0.08, 1.8), (0, 1.02, 1.3), WOOD_PANEL, bevel=0.05, segments=1),
        box((3.7, 0.25, 0.3), (0, 0.95, 0.15), TEAL, bevel=0.06, segments=1),
        box((1.2, 1.1, 1.4), (-0.6, -0.3, 3.6), IRON, bevel=0.15),
        box((1.0, 0.1, 0.5), (-0.6, 0.27, 4.0), RED, bevel=0.04, segments=1),
        cyl(0.18, 0.4, (-0.6, 0.15, 3.25), METAL, verts=10),
        lathe([(0.0, 0), (0.28, 0), (0.32, 0.5), (0.2, 0.62), (0.08, 0.7), (0.0, 0.7)], (0.4, -0.4, 2.9), srgb(120, 200, 230), verts=14),
    ]
    for x in (0.9, 1.3):
        parts.append(lathe([(0.0, 0), (0.15, 0), (0.18, 0.28), (0.0, 0.28)], (x, 0.4, 2.9), PAPER, verts=10))
    return {"SM_Prop_CoffeeBar": (build_mesh("SM_Prop_CoffeeBar", parts), dict(collision="Box"))}


def wall_sconce():
    """Wall sconce (origin at the wall plate centre), brass arm, glowing shade."""
    metal = [
        box((0.5, 0.12, 0.9), (0, 0.06, 0), BRASS, bevel=0.06, segments=1),
        segment((0, 0.1, -0.1), (0, 0.55, 0.15), 0.06, BRASS, verts=8),
        cyl(0.18, 0.12, (0, 0.6, 0.2), BRASS, verts=12),
    ]
    shade = [lathe([(0.12, 0.25), (0.34, 0.3), (0.38, 0.75), (0.2, 0.85), (0.0, 0.86)], (0, 0.6, 0), GLOW_SHADE, verts=16)]
    return {
        "SM_Prop_WallSconce": (build_mesh("SM_Prop_WallSconce", metal), dict(collision="None")),
        "SM_Prop_WallSconce_Shade": (build_mesh("SM_Prop_WallSconce_Shade", shade, "glow"), dict(glow=True, collision="None")),
    }


# ---------------------------------------------------------------- rooms
def dresser_tv():
    """Dresser 4 wide x 1.4 deep x 2.4 tall with a retro TV (glowing screen)."""
    body = [
        box((4.0, 1.4, 2.2), (0, 0, 1.25), WOOD, bevel=0.1),
        box((4.2, 1.55, 0.18), (0, 0, 2.42), WOOD_DARK, bevel=0.06),
    ]
    for s in (-1, 1):
        for y in (-0.55, 0.55):
            body.append(cyl(0.1, 0.18, (s * 1.8, y, 0.09), WOOD_DARK, verts=8, radius2=0.07))
    for row, z in enumerate((0.75, 1.45)):
        for x in (-0.98, 0.98):
            body.append(box((1.85, 0.08, 0.6), (x, 0.72, z), WOOD_LIGHT, bevel=0.05, segments=1))
            body.append(blob(0.08, (x, 0.82, z), BRASS, lump=0, segs=8, rings=6))
    tv = [
        box((2.6, 1.5, 1.8), (0, -0.05, 3.5), srgb(66, 58, 70), bevel=0.3, segments=3),
        box((2.2, 0.08, 1.45), (0, 0.72, 3.5), IRON, bevel=0.1, segments=2),
        box((1.2, 0.8, 0.12), (0, 0, 2.57), IRON, bevel=0.04, segments=1),
        cyl(0.07, 0.6, (0.6, 0.1, 4.6), METAL, verts=6, rot=(0, 0.5, 0)),
        cyl(0.07, 0.6, (-0.6, 0.1, 4.6), METAL, verts=6, rot=(0, -0.5, 0)),
        blob(0.09, (0.95, 0.73, 2.95), BRASS, lump=0, segs=8, rings=6),
    ]
    screen = [box((1.9, 0.06, 1.2), (0, 0.77, 3.52), SCREEN_GLOW, bevel=0.12, segments=2)]
    return {
        "SM_Prop_Dresser": (build_mesh("SM_Prop_Dresser", body + tv), dict(collision="Box")),
        "SM_Prop_Dresser_Screen": (build_mesh("SM_Prop_Dresser_Screen", screen, "glow"), dict(glow=True, collision="None")),
    }


def painting():
    """Framed landscape 3.8 x 2.8 (origin back centre on the wall)."""
    parts = [
        box((3.8, 0.16, 2.8), (0, 0.08, 0), RUG_GOLD, bevel=0.08),
        box((3.3, 0.06, 2.3), (0, 0.18, 0), SKY, bevel=0.0),
        cyl(0.35, 0.04, (1.0, 0.22, 0.55), SUN, verts=16, rot=(math.pi / 2, 0, 0)),
    ]
    for cx, r, col in ((-0.9, 1.3, HILL_DARK), (0.8, 1.6, HILL)):
        parts.append(cyl(r, 0.05, (cx, 0.2 + (0.01 if col == HILL else 0), -1.15), col, verts=14, rot=(math.pi / 2, 0, 0)))
    parts.append(box((3.3, 0.07, 0.45), (0, 0.24, -0.92), HILL, bevel=0.0))
    for x in (-1.2, -0.7, 0.3):
        parts.append(cyl(0.18, 0.55, (x, 0.27, -0.45), EMBLEM_PINE, verts=6, radius2=0.0, rot=(0, 0, 0)))
    return {"SM_Prop_Painting": (build_mesh("SM_Prop_Painting", parts), dict(collision="None"))}


def room_rug():
    """Oval room rug 4 x 3."""
    parts = [
        cyl(1.0, 0.04, (0, 0, 0.02), RUG_GOLD, verts=28),
        cyl(0.86, 0.05, (0, 0, 0.03), RUG_CREAM, verts=28),
        cyl(0.55, 0.06, (0, 0, 0.035), RUG_RED, verts=24),
    ]
    for o in parts:
        o.scale = (2.0, 1.5, 1.0)
        _activate(o)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return {"SM_Prop_RoomRug": (build_mesh("SM_Prop_RoomRug", parts), dict(collision="None"))}


def curtains():
    """Window curtains for a 3-wide window: rod, two folded panels, tie-backs.
    Origin = window centre on the inner wall face; panels hang toward +Y."""
    parts = [cyl(0.06, 3.9, (0, 0.3, 1.85), BRASS, verts=8, rot=(0, math.pi / 2, 0))]
    for s in (-1, 1):
        parts.append(blob(0.11, (s * 1.98, 0.3, 1.85), BRASS, lump=0, segs=8, rings=6))
        parts.append(wave_panel(s * 1.85, s * 0.95, 0.3, 0.16, -1.8, 3.55, 3, srgb(240, 214, 140)))
        parts.append(box((0.9, 0.2, 0.14), (s * 1.55, 0.36, -0.3), RED, bevel=0.05, segments=1))
    return {"SM_Prop_Curtains": (build_mesh("SM_Prop_Curtains", parts), dict(collision="None"))}


# ---------------------------------------------------------------- kitchen
def pot_rack():
    """Pot rail 7 long (origin rail centre), wall brackets at -Y, 3 pots."""
    parts = [cyl(0.1, 7.0, (0, 0, 0), STEEL_DARK, verts=10, rot=(0, math.pi / 2, 0))]
    for x in (-3.2, 3.2):
        parts.append(box((0.2, 0.7, 0.2), (x, -0.35, 0), STEEL_DARK, bevel=0.05, segments=1))
    for k, x in enumerate((-2.2, 0.0, 2.2)):
        parts.append(segment((x, 0, -0.05), (x, 0, -0.45), 0.04, STEEL, verts=6))
        if k == 1:
            parts.append(cyl(0.65, 0.12, (x, 0, -1.2), COPPER, verts=18, rot=(math.pi / 2, 0, 0)))
            parts.append(box((0.12, 0.08, 0.7), (x, 0, -0.5), IRON, bevel=0.03, segments=1))
        else:
            parts.append(lathe([(0.0, 0), (0.5, 0), (0.58, 0.15), (0.6, 0.75), (0.66, 0.8), (0.0, 0.8)], (x, 0, -1.35), COPPER, verts=16))
            parts.append(segment((x - 0.6, 0, -0.6), (x + 0.6, 0, -0.6), 0.04, IRON, verts=6))
    return {"SM_Prop_PotRack": (build_mesh("SM_Prop_PotRack", parts), dict(collision="None"))}


def ticket_rail():
    """Order ticket rail 6 long (origin rail centre) with three tickets."""
    parts = [box((6.0, 0.3, 0.3), (0, 0, 0), STEEL, bevel=0.08)]
    for k, x in enumerate((-1.8, -0.2, 1.4)):
        parts.append(box((0.8, 0.05, 1.05), (x, 0.18, -0.55), PAPER, bevel=0.0, rot=(0, (k - 1) * 0.08, 0)))
        for j in range(4):
            parts.append(box((0.55, 0.02, 0.05), (x, 0.21, -0.25 - j * 0.2), INK, bevel=0.0))
    return {"SM_Prop_TicketRail": (build_mesh("SM_Prop_TicketRail", parts), dict(collision="None"))}


# ---------------------------------------------------------------- lamps
def ceiling_lamp():
    """Flush ceiling lamp 2 across (origin at the ceiling, hangs to -Z)."""
    metal = [
        cyl(0.55, 0.12, (0, 0, -0.06), BRASS, verts=18),
        cyl(0.08, 0.3, (0, 0, -0.25), BRASS, verts=8),
        lathe([(0.0, -0.4), (1.0, -0.4), (1.05, -0.46), (0.0, -0.46)], (0, 0, 0), BRASS, verts=24),
    ]
    dome = [lathe([(1.0, -0.46), (0.92, -0.75), (0.62, -1.0), (0.0, -1.08)], (0, 0, 0), GLOW_SHADE, verts=24)]
    return {
        "SM_Prop_CeilingLamp": (build_mesh("SM_Prop_CeilingLamp", metal), dict(collision="None")),
        "SM_Prop_CeilingLamp_Glow": (build_mesh("SM_Prop_CeilingLamp_Glow", dome, "glow"), dict(glow=True, collision="None")),
    }


def desk_lamp():
    """Banker's desk lamp: brass base and stem, green shade, glowing bulb."""
    metal = [
        cyl(0.4, 0.12, (0, 0, 0.06), BRASS, verts=16),
        cyl(0.06, 0.8, (0, 0, 0.5), BRASS, verts=8),
        segment((0, 0, 0.9), (0, 0.25, 1.0), 0.05, BRASS, verts=6),
    ]
    shade = [box((1.0, 0.5, 0.18), (0, 0.32, 1.08), srgb(40, 130, 90), bevel=0.08, rot=(0.25, 0, 0))]
    glow = [box((0.8, 0.36, 0.06), (0, 0.33, 0.97), GLOW, bevel=0.02, rot=(0.25, 0, 0))]
    return {
        "SM_Prop_DeskLamp": (build_mesh("SM_Prop_DeskLamp", metal + shade), dict(collision="None")),
        "SM_Prop_DeskLamp_Glow": (build_mesh("SM_Prop_DeskLamp_Glow", glow, "glow"), dict(glow=True, collision="None")),
    }


# ---------------------------------------------------------------- laundry
def washer():
    """Front-loading washer 3 x 3 x 3.4, door at the front (+Y)."""
    body = [
        box((3.0, 3.0, 3.4), (0, 0, 1.7), POOL_WHITE, bevel=0.25, segments=3),
        box((2.9, 0.7, 0.55), (0, -1.0, 3.6), POOL_WHITE, bevel=0.15),
        box((1.0, 0.08, 0.3), (0.6, -0.63, 3.62), INK, bevel=0.04, segments=1),
        cyl(1.05, 0.14, (0, 1.5, 1.7), METAL, verts=24, rot=(math.pi / 2, 0, 0)),
        box((0.25, 0.2, 0.5), (0.95, 1.55, 1.7), METAL, bevel=0.06, segments=1),
    ]
    for x in (-0.9, -0.5):
        body.append(cyl(0.14, 0.15, (x, -0.62, 3.62), TEAL, verts=10, rot=(math.pi / 2, 0, 0)))
    glass = [cyl(0.82, 0.08, (0, 1.58, 1.7), srgb(150, 205, 240), verts=24, rot=(math.pi / 2, 0, 0))]
    return {
        "SM_Prop_Washer": (build_mesh("SM_Prop_Washer", body), dict(collision="Box")),
        "SM_Prop_Washer_Glass": (build_mesh("SM_Prop_Washer_Glass", glass), dict(glass=True, collision="None")),
    }


def laundry_cart():
    """Laundry cart 2.4 x 3.4 x 2: wheeled frame, canvas bin, folded towels."""
    parts = [
        box((2.4, 3.4, 1.2), (0, 0, 1.15), CANVAS, bevel=0.2),
        box((2.5, 3.5, 0.14), (0, 0, 1.78), STEEL, bevel=0.05, segments=1),
        box((2.2, 3.2, 0.1), (0, 0, 0.5), STEEL_DARK, bevel=0.03, segments=1),
    ]
    for x in (-1.0, 1.0):
        for y in (-1.5, 1.5):
            parts.append(cyl(0.18, 0.16, (x, y, 0.2), IRON, verts=10, rot=(0, math.pi / 2, 0)))
            parts.append(box((0.08, 0.08, 0.3), (x, y, 0.42), STEEL, bevel=0.0))
    for k, (y, col) in enumerate(((-0.8, LINEN), (0.2, srgb(110, 210, 200)), (1.1, LINEN))):
        for j in range(2):
            parts.append(box((1.5, 0.8, 0.22), (0, y, 1.95 + j * 0.24), col, bevel=0.08, segments=2))
    return {"SM_Prop_LaundryCart": (build_mesh("SM_Prop_LaundryCart", parts), dict(collision="Box"))}


# ---------------------------------------------------------------- shop yard
def crate():
    """Wooden crate 2 x 2 x 2 with slats and an X brace."""
    parts = [box((1.9, 1.9, 1.9), (0, 0, 0.95), WOOD_PANEL, bevel=0.06)]
    for s in (-1, 1):
        for axis in ("x", "y"):
            for z in (0.12, 1.78):
                size = (2.0, 0.14, 0.24) if axis == "x" else (0.14, 2.0, 0.24)
                pos = (0, s * 1.0, z) if axis == "x" else (s * 1.0, 0, z)
                parts.append(box(size, pos, WOOD, bevel=0.04, segments=1))
            r = (0, 0.785, 0) if axis == "x" else (0.785, 0, 0)
            size = (2.3, 0.12, 0.22) if axis == "x" else (0.12, 2.3, 0.22)
            pos = (0, s * 1.0, 0.95) if axis == "x" else (s * 1.0, 0, 0.95)
            parts.append(box(size, pos, WOOD, bevel=0.03, segments=1, rot=r if axis == "x" else (-0.785, 0, 0)))
    return {"SM_Prop_Crate": (build_mesh("SM_Prop_Crate", parts), dict(collision="Box"))}


def barrel():
    """Wooden barrel 2 across x 2.6 tall with iron hoops."""
    parts = [lathe([(0.0, 0), (0.85, 0), (0.95, 0.3), (1.0, 1.3), (0.95, 2.3), (0.85, 2.6), (0.0, 2.6)], (0, 0, 0), WOOD, verts=16)]
    for z, r in ((0.35, 0.97), (0.85, 1.0), (1.75, 1.0), (2.25, 0.97)):
        parts.append(cyl(r + 0.08, 0.14, (0, 0, z), IRON, verts=16, bevel=0.0))  # hoops clear of the staves
    parts.append(cyl(0.8, 0.06, (0, 0, 2.6), WOOD_DARK, verts=16))
    return {"SM_Prop_Barrel": (build_mesh("SM_Prop_Barrel", parts), dict(collision="Hull"))}


# ---------------------------------------------------------------- pool
def diving_board():
    """Diving board: stand at the origin, board reaching 4.6 toward +Y (over the water)."""
    stand = [
        box((1.4, 1.2, 0.9), (0, 0, 0.45), STEEL, bevel=0.15),
        box((1.7, 0.4, 0.12), (0, 0, 0.95), STEEL_DARK, bevel=0.04, segments=1),
    ]
    for s in (-1, 1):
        stand.append(segment((s * 0.75, -0.4, 0.0), (s * 0.75, -0.4, 2.0), 0.06, METAL, verts=8))
        stand.append(segment((s * 0.75, -0.4, 2.0), (s * 0.75, 0.6, 2.0), 0.06, METAL, verts=8))
        stand.append(segment((s * 0.75, 0.6, 2.0), (s * 0.75, 0.6, 1.0), 0.06, METAL, verts=8))
    board = [box((1.6, 5.0, 0.25), (0, 2.1, 1.03), POOL_WHITE, bevel=0.1), box((1.4, 3.6, 0.04), (0, 2.6, 1.17), TEAL, bevel=0.0)]
    return {"SM_Prop_DivingBoard": (build_mesh("SM_Prop_DivingBoard", stand + board), dict(collision="Box"))}


def floatie():
    """Pool ring 2.6 across, pink and white stripes (origin centre)."""
    parts = [torus_arc(1.0, 0.3, i * math.pi / 4, (i + 1) * math.pi / 4, (0, 0, 0), FLOATIE_PINK if i % 2 == 0 else POOL_WHITE) for i in range(8)]
    return {"SM_Prop_Floatie": (build_mesh("SM_Prop_Floatie", parts), dict(collision="None"))}


def lounger():
    """Pool lounger 2.4 x 5: white frame, tinted cushion (per lounger),
    raised back at -Y (Roblox +Z), rolled towel."""
    frame = [
        box((2.4, 5.0, 0.18), (0, 0.2, 0.62), POOL_WHITE, bevel=0.07),
        box((2.3, 2.2, 0.18), (0, -1.84, 1.41), POOL_WHITE, bevel=0.07, rot=(-0.7, 0, 0)),  # back rest rising toward -Y
    ]
    for x in (-1.0, 1.0):
        for y in (-1.9, 2.3):
            frame.append(cyl(0.09, 0.6, (x, y, 0.3), METAL, verts=8))
        frame.append(cyl(0.16, 0.12, (x, 2.5, 0.16), IRON, verts=10, rot=(0, math.pi / 2, 0)))
    cushion = [
        box((2.2, 3.2, 0.24), (0, 0.9, 0.82), NEUTRAL, bevel=0.1, segments=3),
        box((2.1, 1.9, 0.24), (0, -1.71, 1.56), NEUTRAL, bevel=0.1, segments=3, rot=(-0.7, 0, 0)),
    ]
    towel = [cyl(0.24, 1.8, (0, -0.55, 1.12), PAPER, verts=12, rot=(0, math.pi / 2, 0))]
    return {
        "SM_Prop_Lounger": (build_mesh("SM_Prop_Lounger", frame + towel), dict(collision="Box")),
        "SM_Prop_Lounger_Cushion": (build_mesh("SM_Prop_Lounger_Cushion", cushion, "tint"), dict(tint=True, collision="None")),
    }


def pool_light():
    """Underwater light: chrome ring and glowing lens, 1 across (origin centre)."""
    ring = [cyl(0.55, 0.1, (0, 0, 0), METAL, verts=18)]
    lens = [cyl(0.42, 0.12, (0, 0, 0.02), CYAN_GLOW, verts=18)]
    return {
        "SM_Prop_PoolLight": (build_mesh("SM_Prop_PoolLight", ring), dict(collision="None")),
        "SM_Prop_PoolLight_Glow": (build_mesh("SM_Prop_PoolLight_Glow", lens, "glow"), dict(glow=True, collision="None")),
    }


# ---------------------------------------------------------------- yard / road
def recycle_bin():
    """Recycle bin 1.8 across x 2.6 tall, lid, white recycle triangle."""
    parts = [
        lathe([(0.0, 0), (0.8, 0), (0.9, 2.3), (0.95, 2.35), (0.0, 2.35)], (0, 0, 0), RECYCLE_BLUE, verts=20),
        lathe([(0.0, 2.32), (1.0, 2.32), (0.95, 2.5), (0.5, 2.6), (0.0, 2.62)], (0, 0, 0), mul(RECYCLE_BLUE, 0.8), verts=20),
    ]
    for k in range(3):
        a = k * 2 * math.pi / 3
        parts.append(box((0.5, 0.06, 0.12), (math.sin(a) * 0.22, 0.87, 1.3 + math.cos(a) * 0.22), POOL_WHITE, bevel=0.0, rot=(0, a + math.pi / 2, 0)))
    return {"SM_Prop_RecycleBin": (build_mesh("SM_Prop_RecycleBin", parts), dict(collision="Hull"))}


def wheel_stop():
    """Parking wheel stop 3.6 x 0.7, rounded top, yellow with bolts."""
    parts = [taper_box((3.6, 0.7, 0.35), (0, 0, 0.175), STOP_YELLOW, top=(0.96, 0.7), bevel=0.08)]
    for x in (-1.3, 1.3):
        parts.append(cyl(0.09, 0.06, (x, 0, 0.36), IRON, verts=8))
    return {"SM_Prop_WheelStop": (build_mesh("SM_Prop_WheelStop", parts), dict(collision="Box"))}


def guard_rail():
    """Road guard rail section 8 long: post at x 0, W-beam toward +X (at +Y)."""
    parts = [box((0.4, 0.4, 2.0), (0, 0, 1.0), STEEL_DARK, bevel=0.05, segments=1)]
    parts.append(box((8.0, 0.18, 0.32), (4.0, 0.26, 1.85), STEEL, bevel=0.04, segments=1))
    parts.append(box((8.0, 0.22, 0.22), (4.0, 0.3, 1.55), METAL, bevel=0.04, segments=1))
    parts.append(box((8.0, 0.18, 0.32), (4.0, 0.26, 1.25), STEEL, bevel=0.04, segments=1))
    parts.append(box((0.14, 0.06, 0.3), (0, 0.42, 1.55), RUG_GOLD, bevel=0.0))
    return {"SM_Road_GuardRail": (build_mesh("SM_Road_GuardRail", parts), dict(collision="Box"))}


def light_pole():
    """String-light pole 7.2 tall: wooden pole, cross arm, cap, hook."""
    parts = [
        cyl(0.26, 7.2, (0, 0, 3.6), POLE_WOOD, verts=10),
        box((1.6, 0.25, 0.25), (0, 0, 6.6), POLE_WOOD, bevel=0.05, segments=1),
        cyl(0.32, 0.2, (0, 0, 7.3), IRON, verts=10, radius2=0.12),
        cyl(0.4, 0.4, (0, 0, 0.2), CONCRETE, verts=10, radius2=0.3),
    ]
    for x in (-0.7, 0.7):
        parts.append(segment((x, 0, 6.48), (x, 0, 6.15), 0.04, IRON, verts=6))
    return {"SM_Yard_LightPole": (build_mesh("SM_Yard_LightPole", parts), dict(collision="Hull"))}


def flower_bed():
    """Courtyard flower bed 2 x 12 (long along Y): wooden border, soil,
    foliage and mixed blooms."""
    parts = [box((2.0, 12.0, 0.6), (0, 0, 0.3), WOOD_DARK, bevel=0.1), box((1.7, 11.7, 0.1), (0, 0, 0.62), SOIL, bevel=0.0)]
    n = 13
    for i in range(n):
        y = -5.5 + i * 11.0 / (n - 1)
        parts.append(blob(0.48, (0.25 * (1 if i % 2 else -1), y, 0.95), FOLIAGE if i % 2 else FOLIAGE_DARK, lump=0.24, seed=i * 3.1, segs=6, rings=4))
    for i in range(16):
        y = -5.6 + i * 11.2 / 15
        x = 0.45 * math.sin(i * 1.7)
        parts.append(blob(0.26, (x, y, 1.3 + 0.12 * (i % 3)), FLOWER_MIX[i % len(FLOWER_MIX)], lump=0, segs=6, rings=4))
    return {"SM_Yard_FlowerBed": (build_mesh("SM_Yard_FlowerBed", parts), dict(collision="Box"))}


# ======================================================================
# Batch 5: nature (vegetation-artist + environment-artist): rocks, wild
# flowers, grass, distant mountains and hills. Unit-ish sizes, ground
# pivot; the game scales / turns / tints every instance.
# ======================================================================
ROCK_LIGHT = srgb(178, 176, 170)
ROCK_DARK = srgb(124, 124, 132)
MOSS = srgb(110, 160, 80)
STEM = srgb(70, 136, 62)
PETAL_CENTRE = srgb(255, 206, 70)
MTN_ROCK = srgb(110, 130, 156)
MTN_DARK = srgb(84, 100, 128)
MTN_SNOW = srgb(246, 248, 252)
HILL_GREEN = srgb(96, 150, 80)


def lumpy_rock(seed, size=(1.0, 0.7, 0.9)):
    """Faceted cartoon rock (~1 x 0.7 x 0.9), flat underside, mossy top."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.5, location=(0, 0, 0))
    o = bpy.context.active_object
    for v in o.data.vertices:
        n = v.co.normalized()
        k = 1.0 + 0.22 * noise.noise(n * 2.3 + Vector((seed, seed * 1.7, seed * 0.3)))
        p = n * 0.5 * k
        v.co = Vector((p.x * size[0] * 2, p.y * size[2] * 2, max(-0.05, p.z) * size[1] * 2 + 0.05))
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
    finish(o, ROCK_LIGHT, smooth_angle=25)
    moss = blob(0.36, (0.05, 0.0, size[1] * 0.98), MOSS, squash=(1.0, 0.85, 0.22), lump=0.25, seed=seed, segs=8, rings=5)
    return [o, moss]


def rock_variant(name, seed, size):
    parts = lumpy_rock(seed, size)
    return {name: (build_mesh(name, parts), dict(collision="Hull"))}


def rock_a():
    return rock_variant("SM_Veg_RockA", 1.3, (1.0, 0.7, 0.9))


def rock_b():
    return rock_variant("SM_Veg_RockB", 4.7, (1.1, 0.55, 0.8))


def rock_c():
    return rock_variant("SM_Veg_RockC", 8.1, (0.8, 0.9, 0.8))


def flower_clump():
    """Six daisies on stems in a 5-wide clump; petals tinted per patch."""
    import random

    rnd = random.Random(5)
    stems, petals = [], []
    for i in range(6):
        a = i / 6 * math.pi * 2 + rnd.uniform(-0.3, 0.3)
        r = rnd.uniform(0.6, 2.2)
        x, y = math.cos(a) * r, math.sin(a) * r
        h = rnd.uniform(0.9, 1.3)
        stems.append(cyl(0.06, h, (x, y, h / 2), STEM, verts=6, bevel=0.0))
        stems.append(blob(0.22, (x + 0.15, y, h * 0.4), STEM, squash=(1.0, 0.45, 0.25), lump=0, segs=5, rings=3))
        stems.append(blob(0.13, (x, y, h + 0.05), PETAL_CENTRE, squash=(1, 1, 0.6), lump=0, segs=5, rings=3))
        for k in range(4):
            b = k / 4 * math.pi * 2 + i
            petals.append(blob(0.18, (x + math.cos(b) * 0.25, y + math.sin(b) * 0.25, h), NEUTRAL, squash=(1.25, 0.8, 0.35), lump=0, segs=5, rings=3))
    return {
        "SM_Veg_Flowers": (build_mesh("SM_Veg_Flowers", stems), dict(collision="None")),
        "SM_Veg_Flowers_Petals": (build_mesh("SM_Veg_Flowers_Petals", petals, "tint"), dict(tint=True, collision="None")),
    }


def grass_tuft():
    """Grass tuft ~1.6 wide x 1.1 tall: a fan of tapered blades (tinted)."""
    import random

    rnd = random.Random(9)
    blades = []
    for i in range(9):
        a = i / 9 * math.pi * 2 + rnd.uniform(-0.2, 0.2)
        r = rnd.uniform(0.1, 0.45)
        h = rnd.uniform(0.7, 1.1)
        o = cyl(0.14, h, (0, 0, h / 2), NEUTRAL, verts=4, radius2=0.0, bevel=0.0)
        o.rotation_euler = (rnd.uniform(0.15, 0.4), 0, a)
        o.location = (math.cos(a) * r, math.sin(a) * r, 0)
        bpy.context.view_layer.update()
        _activate(o)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=False)
        blades.append(o)
    return {"SM_Veg_GrassTuft": (build_mesh("SM_Veg_GrassTuft", blades, "tint"), dict(tint=True, collision="None"))}


def grass_patch():
    """Organic flat grass patch, radius ~1 (scaled to the patch size), tinted."""
    bm = bmesh.new()
    n = 20
    centre = bm.verts.new((0, 0, 0.08))
    ring = []
    for i in range(n):
        a = i / n * math.pi * 2
        r = 1.0 + 0.12 * math.sin(a * 3 + 0.7) + 0.06 * math.sin(a * 7)
        ring.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, 0.0)))
    for i in range(n):
        bm.faces.new((centre, ring[i], ring[(i + 1) % n]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("patch")
    bm.to_mesh(mesh)
    bm.free()
    o = bpy.data.objects.new("patch", mesh)
    scene.collection.objects.link(o)
    finish(o, NEUTRAL, smooth_angle=80)
    return {"SM_Veg_GrassPatch": (build_mesh("SM_Veg_GrassPatch", [o], "tint"), dict(tint=True, collision="None"))}


def mountain_mesh(name, height, seed):
    """Faceted cartoon mountain, base width 10, with snow above 68%."""
    bm = bmesh.new()
    segs = 9
    rings = [(5.0, 0.0), (3.9, 0.3), (2.6, 0.58), (1.3, 0.82)]
    verts = []
    for ri, (r, t) in enumerate(rings):
        ring = []
        for i in range(segs):
            a = i / segs * math.pi * 2 + ri * 0.3
            rr = r * (1 + 0.16 * noise.noise(Vector((math.cos(a) * 2 + seed, math.sin(a) * 2, ri))))
            ring.append(bm.verts.new((math.cos(a) * rr, math.sin(a) * rr, height * t)))
        verts.append(ring)
    apex = bm.verts.new((0.2, -0.1, height))
    for ri in range(len(verts) - 1):
        lo, hi = verts[ri], verts[ri + 1]
        for i in range(segs):
            j = (i + 1) % segs
            bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
    for i in range(segs):
        bm.faces.new((verts[-1][i], verts[-1][(i + 1) % segs], apex))
    bm.faces.new(list(reversed(verts[0])))
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    o = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(o)
    finish(o, MTN_ROCK, smooth_angle=15)
    # Height-banded colours (rock, darker base, snow cap) painted per corner.
    o.data.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    attr = o.data.color_attributes["Col"]
    normals = [cn.vector for cn in o.data.corner_normals]
    for poly in o.data.polygons:
        zc = sum(o.data.vertices[v].co.z for v in poly.vertices) / len(poly.vertices)
        base = MTN_SNOW if zc > height * 0.68 else (MTN_DARK if zc < height * 0.2 else MTN_ROCK)
        for li in poly.loop_indices:
            k, s, l = band(normals[li].dot(KEY))
            attr.data[li].color = mix(mul(base, k), mul(COOL, 0.6), (1 - s) * 0.15)
    o.data.color_attributes.active_color = attr
    o["prepainted"] = True
    return o


def mountain_tall():
    o = mountain_mesh("SM_Env_MountainTall", 8.0, 2.0)
    return {"SM_Env_MountainTall": (o, dict(collision="None"))}


def mountain_wide():
    o = mountain_mesh("SM_Env_MountainWide", 5.0, 6.0)
    return {"SM_Env_MountainWide": (o, dict(collision="None"))}


def hill():
    """Rolling green hill, base 10 wide x 2.2 tall (tinted per hill)."""
    parts = [blob(5.0, (0, 0, -1.4), NEUTRAL, squash=(1.0, 0.8, 0.72), lump=0.12, seed=3.0, segs=16, rings=10)]
    for v in parts[0].data.vertices:  # flatten the buried half just under the ground
        v.co.z = max(v.co.z, -0.3)
    return {"SM_Env_Hill": (build_mesh("SM_Env_Hill", parts, "tint"), dict(tint=True, collision="None"))}


BATCHES = {
    "batch1": [
        ("Bed", bed, "hero"),
        ("Nightstand", nightstand, "standard"),
        ("RoomDoor", door, "hero"),
        ("ACUnit", ac_unit, "hero"),
        ("Trash", trash, "hero"),
        ("FrontDesk", front_desk, "hero"),
        ("LampPost", lamp_post, "standard"),
        ("Bench", bench, "standard"),
        ("PottedPlant", potted_plant, "standard"),
        ("FlowerBush", flower_bush, "standard"),
        ("RoundTree", round_tree, "tree"),
    ],
    "batch2": [
        ("Stove", stove, "hero"),
        ("Fridge", fridge, "standard"),
        ("Sink", sink_counter, "standard"),
        ("Pantry", pantry_shelf, "standard"),
        ("LinenShelf", linen_shelf, "hero"),
        ("Dumpster", dumpster, "hero"),
        ("Breaker", breaker_panel, "standard"),
        ("ShopCounter", shop_counter, "standard"),
        ("ShopShelf", shop_shelf, "hero"),
        ("CarSedan", car_sedan, "vehicle"),
        ("CarWagon", car_wagon, "vehicle"),
        ("PicnicTable", picnic_table, "standard"),
        ("Parasol", parasol, "standard"),
        ("Fence", fence, "standard"),
        ("Mailbox", mailbox, "standard"),
        ("Vending", vending_machine, "standard"),
        ("IceMachine", ice_machine, "standard"),
        ("Campfire", campfire, "standard"),
        ("Fountain", fountain, "standard"),
    ],
    "batch3": [
        ("Office", office, "building"),
        ("RoomUnit", room_unit, "building"),
        ("RoomRoof", room_roof, "building"),
        ("LinenShed", linen_shed, "building"),
        ("Shop", shop, "building"),
        ("Kitchen", kitchen, "building"),
        ("MotelSign", motel_sign, "sign"),
    ],
    "office": [
        ("OfficeV2", office_v2, "hero_building"),
        ("OfficeDoorFL", office_door_fl, "door"),
        ("OfficeDoorFR", office_door_fr, "door"),
        ("OfficeDoorSide", office_door_side, "door"),
        ("OfficeDoorBack", office_door_back, "door"),
    ],
    "rooms": [
        ("RoomV2", room_v2, "building"),
        ("RoomRoofV2", room_roof_v2, "hero_building"),
    ],
    "annex": [
        ("LinenShedV2", linen_shed_v2, "hero_building"),
        ("ShopV2", shop_v2, "hero_building"),
        ("KitchenV2", kitchen_v2, "hero_building"),
    ],
    "lobby": [
        ("LobbyHall", lobby_hall, "lobby_hall"),
        ("LobbyTitle", lobby_title, "sign"),
        ("LobbyDoor", lobby_door, "door"),
        ("LobbyPad", lobby_pad, "standard"),
        ("LobbyBoardL", lobby_board_l, "standard"),
        ("LobbyBoardM", lobby_board_m, "standard"),
        ("LobbyBoardW", lobby_board_w, "standard"),
    ],
    "batch4": [
        ("Couch", couch, "hero"),  # main lobby furniture, seen up close
        ("CoffeeTable", coffee_table, "standard"),
        ("LobbyRug", lobby_rug, "background"),
        ("KeyRack", key_rack, "standard"),
        ("WallClock", wall_clock, "background"),
        ("CoffeeBar", coffee_bar, "standard"),
        ("WallSconce", wall_sconce, "background"),
        ("Dresser", dresser_tv, "standard"),
        ("Painting", painting, "background"),
        ("RoomRug", room_rug, "background"),
        ("Curtains", curtains, "standard"),
        ("PotRack", pot_rack, "standard"),
        ("TicketRail", ticket_rail, "background"),
        ("CeilingLamp", ceiling_lamp, "background"),
        ("DeskLamp", desk_lamp, "background"),
        ("Washer", washer, "standard"),
        ("LaundryCart", laundry_cart, "standard"),
        ("Crate", crate, "background"),
        ("Barrel", barrel, "background"),
        ("DivingBoard", diving_board, "standard"),
        ("Floatie", floatie, "background"),
        ("Lounger", lounger, "standard"),
        ("PoolLight", pool_light, "background"),
        ("RecycleBin", recycle_bin, "background"),
        ("WheelStop", wheel_stop, "background"),
        ("GuardRail", guard_rail, "background"),
        ("LightPole", light_pole, "background"),
        ("FlowerBed", flower_bed, "standard"),
    ],
    "batch5": [
        ("RockA", rock_a, "background"),
        ("RockB", rock_b, "background"),
        ("RockC", rock_c, "background"),
        ("FlowerClump", flower_clump, "background"),
        ("GrassTuft", grass_tuft, "background"),
        ("GrassPatch", grass_patch, "background"),
        ("MountainTall", mountain_tall, "background"),
        ("MountainWide", mountain_wide, "background"),
        ("Hill", hill, "background"),
    ],
}
# Triangle budget per object group (prop-artist tiers, mobile-adjusted).
BUDGET = {"hero": 8000, "standard": 3000, "tree": 4000, "vehicle": 8000, "building": 12000, "sign": 8000, "hero_building": 28000, "lobby_hall": 60000, "door": 2500, "background": 1000}


# ======================================================================
# Build, validate, organise
# ======================================================================
def bbox(obj):
    pts = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


def validate(obj):
    """Loose verts/edges, non-manifold edges, zero-area faces, scale applied."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    loose_v = sum(1 for v in bm.verts if not v.link_edges)
    loose_e = sum(1 for e in bm.edges if not e.link_faces)
    zero = sum(1 for f in bm.faces if f.calc_area() < 1e-7)
    nonmanifold = sum(1 for e in bm.edges if not e.is_manifold and e.link_faces)
    bm.free()
    return {
        "loose_verts": loose_v,
        "loose_edges": loose_e,
        "zero_area_faces": zero,
        "non_manifold_edges": nonmanifold,
        "scale_applied": tuple(round(s, 4) for s in obj.scale) == (1.0, 1.0, 1.0),
    }


if BATCH != "batch1":
    BEVEL_SEGMENTS = 2
col_geo = bpy.data.collections.new("COL_Geo_Kit_" + BATCH)
scene.collection.children.link(col_geo)

manifest, report = {}, {}
orig_matrix = {}
cursor_x = 0.0
built = []
for group, builder, tier in BATCHES[BATCH]:
    meshes = builder()
    lo_all = Vector((1e9, 1e9, 1e9))
    hi_all = Vector((-1e9, -1e9, -1e9))
    group_tris = 0
    for name, (obj, info) in meshes.items():
        # Clean-up pass (asset-optimization): merge doubles, drop loose geo, triangulate later in FBX.
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
        loose = [v for v in bm.verts if not v.link_edges]
        if loose:
            bmesh.ops.delete(bm, geom=loose, context="VERTS")
        bm.to_mesh(obj.data)
        bm.free()
        lo, hi = bbox(obj)
        lo_all = Vector((min(lo_all.x, lo.x), min(lo_all.y, lo.y), min(lo_all.z, lo.z)))
        hi_all = Vector((max(hi_all.x, hi.x), max(hi_all.y, hi.y), max(hi_all.z, hi.z)))
        size, centre = hi - lo, (lo + hi) / 2
        tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
        group_tris += tris
        manifest[name] = {
            "group": group,
            "size": [round(size.x, 3), round(size.z, 3), round(size.y, 3)],
            "center": [round(centre.x, 3), round(centre.z, 3), round(-centre.y, 3)],
            "tint": bool(info.get("tint")),
            "glow": bool(info.get("glow")),
            "collision": info.get("collision", "Box"),
            "glass": bool(info.get("glass")),
            "place": info.get("place"),
            "hinge": info.get("hinge"),
            "swing": info.get("swing"),
            "tris": tris,
        }
        report[name] = validate(obj)
        for c in obj.users_collection:
            c.objects.unlink(obj)
        col_geo.objects.link(obj)
        built.append(obj)
        orig_matrix[name] = obj.matrix_world.copy()
    budget = BUDGET[tier]
    status = "OK" if group_tris <= budget else "OVER"
    print(f"[kit] {group:12s} {group_tris:6d} tris (budget {budget}) {status}")
    report["_group_" + group] = {"tris": group_tris, "budget": budget, "status": status}
    offset = cursor_x - lo_all.x
    for name in meshes:
        meshes[name][0].location.x += offset
    cursor_x += (hi_all.x - lo_all.x) + 5.0

total = sum(m["tris"] for m in manifest.values())
issues = {k: v for k, v in report.items() if not k.startswith("_") and (v["loose_verts"] or v["loose_edges"] or v["zero_area_faces"] or not v["scale_applied"])}
print(f"[kit] {BATCH}: {len(manifest)} meshes, {total} triangles, meshes with issues: {len(issues)}")
for k, v in issues.items():
    print("   issue", k, v)

# Materials: one vertex-colour material, one emissive for glow meshes (MAT_ names).
def make_material(name, emissive):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 0.8
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Col"
    nt.links.new(vc.outputs["Color"], bsdf.inputs["Base Color"])
    if emissive:
        nt.links.new(vc.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 3.0
    return m


MAT_VC = make_material("MAT_Kit_VertexColour", False)
MAT_GLOW = make_material("MAT_Kit_Emissive", True)
for obj in built:
    obj.data.materials.clear()
    obj.data.materials.append(MAT_GLOW if manifest[obj.name]["glow"] else MAT_VC)

# ======================================================================
# Export (before preview tints)
# ======================================================================
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, f"motel_kit_{BATCH}.blend"))
bpy.ops.object.select_all(action="DESELECT")
for obj in built:
    obj.select_set(True)
bpy.ops.export_scene.fbx(
    filepath=os.path.join(OUT, f"motel_kit_{BATCH}.fbx"),
    use_selection=True,
    object_types={"MESH"},
    apply_unit_scale=True,
    apply_scale_options="FBX_SCALE_UNITS",
    axis_forward="-Z",
    axis_up="Y",
    mesh_smooth_type="OFF",
    use_triangles=True,
    colors_type="SRGB",
    add_leaf_bones=False,
)
with open(os.path.join(OUT, f"motel_kit_{BATCH}.json"), "w", encoding="utf-8") as f:
    json.dump({"batch": BATCH, "units": "studs", "axes": "roblox", "meshes": manifest, "validation": report}, f, indent=2)
print("[kit] exported", BATCH)

# ======================================================================
# Lookdev preview (EEVEE), with example tints
# ======================================================================
PREVIEW_TINT = {
    "SM_Prop_Bed_Sheet": srgb(250, 250, 246),
    "SM_Prop_Bed_Blanket": srgb(86, 150, 226),
    "SM_Prop_Door_Leaf": srgb(214, 84, 70),
    "SM_Prop_AC_Body": srgb(232, 234, 238),
    "SM_Veg_RoundTree_Canopy": srgb(250, 150, 54),
    "SM_Vehicle_Sedan_Body": srgb(236, 120, 110),
    "SM_Vehicle_Wagon_Body": srgb(120, 190, 220),
}
for obj in built:
    t = PREVIEW_TINT.get(obj.name)
    if t:
        for d in obj.data.color_attributes["Col"].data:
            d.color = (d.color[0] * t[0], d.color[1] * t[1], d.color[2] * t[2], 1.0)

for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
    try:
        scene.render.engine = engine
        break
    except TypeError:
        continue
world = bpy.data.worlds.new("WRL_Sky")
world.use_nodes = True
bg = world.node_tree.nodes.get("Background")
bg.inputs["Color"].default_value = (0.55, 0.75, 0.95, 1)
bg.inputs["Strength"].default_value = 0.9
scene.world = world
scene.view_settings.view_transform = "AgX"
try:
    scene.view_settings.look = "AgX - Punchy"
except TypeError:
    pass
sun_data = bpy.data.lights.new("LGT_Key_Sun", "SUN")
sun_data.energy = 3.2
sun_data.angle = math.radians(8)
sun = bpy.data.objects.new("LGT_Key_Sun", sun_data)
scene.collection.objects.link(sun)
sun.rotation_euler = (math.radians(50), 0, math.radians(-35))

bpy.ops.mesh.primitive_plane_add(size=1, location=(cursor_x / 2, 0, 0))
ground = bpy.context.active_object
ground.scale = (cursor_x + 30, 50, 1)
gm = bpy.data.materials.new("MAT_Preview_Grass")
gm.use_nodes = True
gm.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = srgb(126, 186, 96)
ground.data.materials.append(gm)

cam_data = bpy.data.cameras.new("CAM_Preview")
cam_data.lens = 50
cam = bpy.data.objects.new("CAM_Preview", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
scene.render.resolution_x = 1600
scene.render.resolution_y = 900

# Preview layout only (already exported): groups on a grid, small props in
# front, tall ones behind; one 3/4 camera per sheet.
def group_objects(group):
    return [o for o in built if manifest[o.name]["group"] == group]


def group_box(objs):
    lo = Vector((min(bbox(o)[0].x for o in objs), min(bbox(o)[0].y for o in objs), min(bbox(o)[0].z for o in objs)))
    hi = Vector((max(bbox(o)[1].x for o in objs), max(bbox(o)[1].y for o in objs), max(bbox(o)[1].z for o in objs)))
    return lo, hi


# Groups whose front is not +Y are turned toward the camera (preview only).
PREVIEW_YAW = {
    "LinenShelf": math.pi,
    "Stove": math.pi / 2,
    "Fridge": math.pi / 2,
    "Breaker": math.pi / 2,
    "ShopCounter": -math.pi / 2,
    "LinenShed": -math.pi / 2,
    "Shop": -math.pi / 2,
    "Kitchen": math.pi / 2,
    "LinenShedV2": -math.pi / 2,
    "ShopV2": -math.pi / 2,
    "KitchenV2": math.pi / 2,
}
from mathutils import Matrix

for g, yaw in PREVIEW_YAW.items():
    objs = group_objects(g)
    if objs:
        lo, hi = group_box(objs)
        pivot = Matrix.Translation(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, 0))
        rot = pivot @ Matrix.Rotation(yaw, 4, "Z") @ pivot.inverted()
        for o in objs:
            o.matrix_world = rot @ o.matrix_world
bpy.context.view_layer.update()
names = [g for g, _b, _t in BATCHES[BATCH]]
sheets = [names[i : i + 6] for i in range(0, len(names), 6)]
for k, sheet in enumerate(sheets if BATCH not in ("office", "rooms") else []):
    # Hide everything, then lay this sheet out in two rows of three.
    for o in built:
        o.hide_render = True
    cell = 0.0
    for g in sheet:
        lo, hi = group_box(group_objects(g))
        cell = max(cell, hi.x - lo.x, hi.y - lo.y)
    cell += 3.0
    for idx, g in enumerate(sheet):
        objs = group_objects(g)
        lo, hi = group_box(objs)
        col, row = idx % 3, idx // 3
        target = Vector((col * cell, -row * cell, 0))
        shift = target - Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, 0))
        for o in objs:
            o.location += shift
            o.hide_render = False
    bpy.context.view_layer.update()
    lo, hi = group_box([o for o in built if not o.hide_render])
    centre = (lo + hi) / 2
    ground.location = (centre.x, centre.y, 0)
    # Distance from the horizontal field of view so the whole sheet fits.
    fov = 2 * math.atan(cam_data.sensor_width / (2 * cam_data.lens))
    aspect = scene.render.resolution_x / scene.render.resolution_y
    vfov = 2 * math.atan(math.tan(fov / 2) / aspect)
    elev = math.radians(28)
    width = max(hi.x - lo.x, (hi.y - lo.y) * 0.8) * 1.15
    height = (hi.z * math.cos(elev) + (hi.y - lo.y) * math.sin(elev)) * 1.2
    dist = max((width / 2) / math.tan(fov / 2), (height / 2) / math.tan(vfov / 2))
    look = Vector((centre.x, centre.y, hi.z * 0.45))
    cam.location = look + Vector((0, math.cos(elev), math.sin(elev))) * dist
    cam.rotation_euler = (look - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = os.path.join(OUT, "previews", f"motel_kit_{BATCH}_{k + 1}.png")
    bpy.ops.render.render(write_still=True)
# Batch 3: assembly view, every building at its scale-1 world place
# (Roblox (x, y, z) -> Blender (x, -z, y)); rooms instanced three times.
if BATCH == "batch3":
    shown = []
    for o in built:
        places = manifest[o.name]["place"] or [[0, 0, 0]]
        for i, (px, py, pz) in enumerate(places):
            inst = o if i == 0 else o.copy()
            if i > 0:
                col_geo.objects.link(inst)
            inst.matrix_world = Matrix.Translation((px, -pz, py)) @ orig_matrix[o.name]
            inst.hide_render = False
            shown.append(inst)
    bpy.context.view_layer.update()
    lo, hi = group_box(shown)
    centre = (lo + hi) / 2
    ground.location = (centre.x, centre.y, 0)
    ground.scale = (400, 400, 1)
    fov = 2 * math.atan(cam_data.sensor_width / (2 * cam_data.lens))
    elev = math.radians(38)
    dist = ((hi.x - lo.x) * 0.62) / math.tan(fov / 2)
    look = Vector((centre.x, centre.y, 4.0))
    yaw = math.radians(-18)
    cam.location = look + Vector((math.sin(yaw) * math.cos(elev), math.cos(yaw) * math.cos(elev), math.sin(elev))) * dist
    cam.rotation_euler = (look - cam.location).to_track_quat("-Z", "Y").to_euler()
    sun.rotation_euler = (math.radians(48), 0, math.radians(-30))
    scene.render.filepath = os.path.join(OUT, "previews", f"motel_kit_{BATCH}_layout.png")
    bpy.ops.render.render(write_still=True)
# Office: assembled with the doors on their hinges (front pair half open),
# rendered from the same four sides as the reference art.
if BATCH == "office":
    for o in built:
        o.hide_render = False
        o.matrix_world = orig_matrix[o.name]
        g = manifest[o.name]["group"]
        if g in OFFICE_DOORS:
            spec = OFFICE_DOORS[g]
            ajar = 0.0
            o.matrix_world = (
                Matrix.Translation(spec["hinge"]) @ Matrix.Rotation(math.radians(spec["swing"]) * ajar, 4, "Z") @ orig_matrix[o.name]
            )
    bpy.context.view_layer.update()
    ground.location = (0, 0, 0)
    ground.scale = (300, 300, 1)
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    bg.inputs["Color"].default_value = (0.32, 0.46, 0.72, 1)
    bg.inputs["Strength"].default_value = 0.75
    sun_data.energy = 2.4
    sun_data.color = (1.0, 0.92, 0.8)
    fov = 2 * math.atan(cam_data.sensor_width / (2 * cam_data.lens))
    views = {"front": (0, 1), "left": (1, 0), "right": (-1, 0), "back": (0, -1)}
    for name, (vx, vy) in views.items():
        elev = math.radians(12)
        span = 64.0 if vy else 60.0
        dist = (span / 2) / math.tan(fov / 2)
        look = Vector((0, 0, 9.6))
        cam.location = look + Vector((vx * math.cos(elev), vy * math.cos(elev), math.sin(elev))) * dist
        cam.rotation_euler = (look - cam.location).to_track_quat("-Z", "Y").to_euler()
        sun.rotation_euler = (math.radians(-50), 0, math.atan2(-vx, vy) + math.radians(-28))
        scene.render.filepath = os.path.join(OUT, "previews", f"motel_kit_office_{name}.png")
        bpy.ops.render.render(write_still=True)
# Rooms: the block assembled (roof + three rooms at their places, relative
# to the roof), front 3/4, back and close-up views.
if BATCH == "rooms":
    roof_place = manifest["SM_Bld_RoomRoofV2_Roof"]["place"][0]
    for o in list(built):
        for i, (px, py, pz) in enumerate(manifest[o.name]["place"]):
            inst = o if i == 0 else o.copy()
            if i > 0:
                col_geo.objects.link(inst)
            dx, dz = px - roof_place[0], pz - roof_place[2]
            inst.matrix_world = Matrix.Translation((dx, -dz, 0)) @ orig_matrix[o.name]
            inst.hide_render = False
    bpy.context.view_layer.update()
    ground.location = (0, 0, 0)
    ground.scale = (300, 300, 1)
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    bg.inputs["Color"].default_value = (0.32, 0.46, 0.72, 1)
    bg.inputs["Strength"].default_value = 0.75
    sun_data.energy = 2.4
    sun_data.color = (1.0, 0.92, 0.8)
    fov = 2 * math.atan(cam_data.sensor_width / (2 * cam_data.lens))
    views = {"front": (0.35, 1, 14, 70.0), "back": (-0.3, -1, 14, 70.0), "close": (0.2, 1, 8, 26.0)}
    for name, (vx, vy, elev, span) in views.items():
        e = math.radians(elev)
        dist = (span / 2) / math.tan(fov / 2)
        look = Vector((0, 0, 7.5)) if name != "close" else Vector((0.5, 6.0, 5.5))
        d = Vector((vx, vy, 0)).normalized()
        cam.location = look + Vector((d.x * math.cos(e), d.y * math.cos(e), math.sin(e))) * dist
        cam.rotation_euler = (look - cam.location).to_track_quat("-Z", "Y").to_euler()
        sun.rotation_euler = (math.radians(-50), 0, math.atan2(-d.x, d.y) + math.radians(-28))
        scene.render.filepath = os.path.join(OUT, "previews", f"motel_kit_rooms_{name}.png")
        bpy.ops.render.render(write_still=True)
# Annex: each building on its own, door side 3/4 and back 3/4 (the sheet
# above already turned the doors toward +Y).
if BATCH in ("annex", "lobby"):
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    bg.inputs["Color"].default_value = (0.32, 0.46, 0.72, 1)
    bg.inputs["Strength"].default_value = 0.75
    sun_data.energy = 2.4
    sun_data.color = (1.0, 0.92, 0.8)
    fov = 2 * math.atan(cam_data.sensor_width / (2 * cam_data.lens))
    for g, _b, _t in BATCHES[BATCH]:
        objs = group_objects(g)
        for o in built:
            o.hide_render = o not in objs
        lo, hi = group_box(objs)
        centre = (lo + hi) / 2
        ground.location = (centre.x, centre.y, 0)
        span = max(hi.x - lo.x, hi.y - lo.y) * 2.1
        for name, (vx, vy, elev) in {"front": (0.45, 1, 14), "back": (-0.5, -1, 16)}.items():
            e = math.radians(elev)
            dist = (span / 2) / math.tan(fov / 2)
            look = Vector((centre.x, centre.y, hi.z * 0.5))
            d = Vector((vx, vy, 0)).normalized()
            cam.location = look + Vector((d.x * math.cos(e), d.y * math.cos(e), math.sin(e))) * dist
            cam.rotation_euler = (look - cam.location).to_track_quat("-Z", "Y").to_euler()
            sun.rotation_euler = (math.radians(-50), 0, math.atan2(-d.x, d.y) + math.radians(-28))
            scene.render.filepath = os.path.join(OUT, "previews", f"motel_kit_{BATCH}_{g}_{name}.png")
            bpy.ops.render.render(write_still=True)
print("[kit] previews done")
