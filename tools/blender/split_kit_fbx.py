"""
Export one FBX per model (group) from a built kit batch, same settings as
motel_kit.py:

  blender --background --factory-startup --python tools/blender/split_kit_fbx.py -- <repo_root> <batch>

Reads   assets/models/kit/<batch>/motel_kit_<batch>.blend + .json
Writes  assets/models/kit/<batch>/<Group>/fbx/<Group>.fbx
(motel_kit.py already does this for new builds; this is for batches built
before the per-model folders existed.)
"""

import json
import os
import sys

import bpy

ARGS = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
ROOT, BATCH = ARGS[0], ARGS[1]
OUT = os.path.join(ROOT, "assets", "models", "kit", BATCH)
manifest = json.load(open(os.path.join(OUT, f"motel_kit_{BATCH}.json"), encoding="utf-8"))["meshes"]
bpy.ops.wm.open_mainfile(filepath=os.path.join(OUT, f"motel_kit_{BATCH}.blend"))

groups = {}
for name, m in manifest.items():
    groups.setdefault(m["group"], []).append(name)
for group, names in groups.items():
    bpy.ops.object.select_all(action="DESELECT")
    objs = [bpy.data.objects[n] for n in names if n in bpy.data.objects]
    if len(objs) != len(names):
        print(f"[split] {group}: missing {set(names) - {o.name for o in objs}}")
    for o in objs:
        o.select_set(True)
    if not objs:
        continue
    d = os.path.join(OUT, group, "fbx")
    os.makedirs(d, exist_ok=True)
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(d, f"{group}.fbx"),
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
    print(f"[split] {BATCH}/{group}: {len(objs)} meshes")
