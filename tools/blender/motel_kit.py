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


def wall(axis, a, b, c, height, colour, openings=(), t=1.0):
    """Wall run a..b with rectangular openings (o1, o2, bottom, top)."""
    parts = []

    def piece(p1, p2, z1, z2):
        if p2 - p1 < 0.05 or z2 - z1 < 0.05:
            return
        parts.append(
            box(_size(axis, p2 - p1, t, z2 - z1), _along(axis, (p1 + p2) / 2, c, 1, z=(z1 + z2) / 2), colour, bevel=0.05, segments=1)
        )

    cursor = a
    for o1, o2, zb, zt in sorted(openings):
        piece(cursor, o1, 0, height)
        piece(o1, o2, 0, zb)
        piece(o1, o2, zt, height)
        cursor = o2
    piece(cursor, b, 0, height)
    return parts


def _free_spans(a, b, openings, z):
    spans, cursor = [], a
    for o1, o2, zb, zt in sorted(openings):
        if zb - 0.2 <= z <= zt + 0.2:
            spans.append((cursor, o1 - 0.15))
            cursor = o2 + 0.15
    spans.append((cursor, b))
    return [(s1, s2) for s1, s2 in spans if s2 - s1 > 0.4]


def siding(axis, a, b, c, out, height, colour, openings=(), step=2.0):
    """Clapboard lines on the outside face (cartoon horizontal siding)."""
    parts, z = [], 2.2
    while z < height - 0.8:
        for s1, s2 in _free_spans(a, b, openings, z):
            parts.append(box(_size(axis, s2 - s1, 0.14, 0.16), _along(axis, (s1 + s2) / 2, c, out, v=0.56, z=z), colour, bevel=0.0))
        z += step
    return parts


def base_trim(axis, a, b, c, out, colour, openings=(), h=0.9):
    return [
        box(_size(axis, s2 - s1, 0.32, h), _along(axis, (s1 + s2) / 2, c, out, v=0.6, z=h / 2), colour, bevel=0.08, segments=1)
        for s1, s2 in _free_spans(a, b, openings, 0.3)
    ]


def corner_boards(x1, x2, y1, y2, height, colour):
    return [
        box((0.75, 0.75, height), (x, y, height / 2), colour, bevel=0.1, segments=1)
        for x in (x1 - 0.42, x2 + 0.42)
        for y in (y1 - 0.42, y2 + 0.42)
    ]


def window(axis, p, c, out, w, h, zc, shutters=True, flowers=False, seed=0):
    """Framed window through a wall: glass pane (own mesh), frame, cross
    mullion, sill, shutters and an optional flower box."""
    trim, glass = [], []
    glass.append(box(_size(axis, w, 0.12, h), _along(axis, p, c, out, z=zc), GLASS_BLUE, bevel=0.02, segments=1))
    for s in (-1, 1):
        trim.append(box(_size(axis, 0.4, 1.3, h + 0.8), _along(axis, p, c, out, u=s * (w / 2 + 0.2), z=zc), TEAL, bevel=0.1, segments=1))
        trim.append(box(_size(axis, w + 0.8, 1.3, 0.4), _along(axis, p, c, out, z=zc + s * (h / 2 + 0.2)), TEAL, bevel=0.1, segments=1))
    trim.append(box(_size(axis, 0.16, 0.24, h), _along(axis, p, c, out, z=zc), CREAM, bevel=0.0))
    trim.append(box(_size(axis, w, 0.24, 0.16), _along(axis, p, c, out, z=zc), CREAM, bevel=0.0))
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
        n = max(3, int(w / 1.0))
        for i in range(n):
            u = -w / 2 + (i + 0.5) * w / n
            trim.append(blob(0.34, _along(axis, p, c, out, u=u, v=1.05, z=zb + 0.45), LEAF, lump=0.2, seed=seed + i, segs=6, rings=4))
            trim.append(blob(0.2, _along(axis, p, c, out, u=u + 0.1, v=1.3, z=zb + 0.75), PETALS[(i + seed) % len(PETALS)], lump=0, segs=6, rings=4))
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
        parts.append(box(_size(axis, sw + 0.01, depth, 0.18), centre, col, bevel=0.05, segments=1, rot=rot))
        if scallops:
            edge = _along(axis, p, c, out, u=u, v=0.5 + depth * math.cos(a), z=ztop - depth * math.sin(a) - 0.25)
            parts.append(blob(sw * 0.5, edge, col, squash=(1, 0.35, 0.7) if axis == "x" else (0.35, 1, 0.7), lump=0, segs=8, rings=4))
    # Side cheeks and a wall batten.
    parts.append(box(_size(axis, w + 0.3, 0.3, 0.35), _along(axis, p, c, out, v=0.6, z=ztop + 0.05), RED, bevel=0.08, segments=1))
    return parts


def door_frame(axis, p1, p2, c, top, colour=TEAL):
    return [
        box(_size(axis, 0.7, 1.4, top), _along(axis, p1 - 0.35, c, 1, z=top / 2), colour, bevel=0.1, segments=1),
        box(_size(axis, 0.7, 1.4, top), _along(axis, p2 + 0.35, c, 1, z=top / 2), colour, bevel=0.1, segments=1),
        box(_size(axis, p2 - p1 + 1.6, 1.5, 0.6), _along(axis, (p1 + p2) / 2, c, 1, z=top + 0.3), colour, bevel=0.1, segments=1),
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


def text3d(body, size, loc, facing, colour, depth=0.14):
    """Chunky 3D letters (built-in font), standing up and facing `facing`."""
    cu = bpy.data.curves.new("txt", "FONT")
    cu.body = body
    cu.size = size
    cu.extrude = depth / 2
    cu.offset = size * 0.035  # bolder strokes
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
        if role == "Glow":
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
        T.append(cyl(0.42, 11.4, (x, 10.6, 5.7), CREAM, verts=12))
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
}
# Triangle budget per object group (prop-artist tiers, mobile-adjusted).
BUDGET = {"hero": 8000, "standard": 3000, "tree": 4000, "vehicle": 8000, "building": 12000, "sign": 8000}


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
for k, sheet in enumerate(sheets):
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
print("[kit] previews done")
