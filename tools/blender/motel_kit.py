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
from mathutils import Vector, noise

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


def box(size, loc, colour, bevel=0.1, rot=(0, 0, 0), segments=3, tag=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(o, colour, bevel=min(bevel, min(size) * 0.45), segments=segments, tag=tag)


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
}
# Triangle budget per object group (prop-artist tiers, mobile-adjusted).
BUDGET = {"hero": 8000, "standard": 3000, "tree": 4000}


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


col_geo = bpy.data.collections.new("COL_Geo_Kit_" + BATCH)
scene.collection.children.link(col_geo)

manifest, report = {}, {}
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
            "tris": tris,
        }
        report[name] = validate(obj)
        for c in obj.users_collection:
            c.objects.unlink(obj)
        col_geo.objects.link(obj)
        built.append(obj)
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
print("[kit] previews done")
