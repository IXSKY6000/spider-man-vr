"""Blender 4.3+: convert an extracted scene to a textured Godot GLB.

blender --background --python tools/prepare_map.py -- --source /path/map.obj
Optional: --terrain-regex '(?i)terrain|ground' --smooth-iterations 3
No archive extraction and no execution of scripts embedded in .blend files.
"""
import argparse
import json
import math
import re
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


def smooth_terrain(obj, iterations, strength, max_step):
    """Relax height only; lock boundaries, material seams and steep edges.

    Uses world-space Z (Blender up), never moves roads/buildings unless their
    mesh was explicitly selected by the caller. Does not subdivide geometry.
    """
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    matrix = obj.matrix_world
    inverse = matrix.inverted()
    movable = []
    for vertex in bm.verts:
        if vertex.is_boundary or not vertex.link_edges:
            continue
        if len({face.material_index for face in vertex.link_faces}) > 1:
            continue
        if any(edge.is_manifold and edge.calc_face_angle(0.0) > math.radians(45)
               for edge in vertex.link_edges):
            continue
        movable.append(vertex)
    moved = set()
    for _ in range(iterations):
        updates = []
        for vertex in movable:
            point = matrix @ vertex.co
            heights = [(matrix @ edge.other_vert(vertex).co).z
                       for edge in vertex.link_edges]
            if max(abs(height - point.z) for height in heights) > max_step:
                continue
            target = sum(heights) / len(heights)
            new_height = point.z + (target - point.z) * strength
            if abs(new_height - point.z) > 1e-6:
                moved.add(vertex.index)
            updates.append((vertex, inverse @ Vector((point.x, point.y, new_height))))
        for vertex, coordinate in updates:
            vertex.co = coordinate
    bm.normal_update()
    bm.to_mesh(obj.data)
    bm.free()
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    obj.data.set_sharp_from_angle(angle=math.radians(45))
    obj.data.update()
    return len(moved)


def convert(args):
    source = Path(args.source).resolve()
    output = Path(args.output).resolve()
    if not source.is_file():
        raise ValueError(f"Missing scene: {source}")
    if source == output:
        raise ValueError("Source and output must differ")
    if output.exists() and not args.overwrite:
        raise ValueError("Output exists: use --overwrite intentionally")
    if args.scale <= 0 or not math.isfinite(args.scale):
        raise ValueError("Scale must be finite and positive")
    if not 0 <= args.smooth_iterations <= 20 or not 0 < args.strength <= 1:
        raise ValueError("Invalid smoothing parameters")
    pattern = re.compile(args.terrain_regex) if args.terrain_regex else None
    bpy.ops.wm.read_factory_settings(use_empty=True)
    suffix = source.suffix.lower()
    if suffix == ".blend":
        bpy.ops.wm.open_mainfile(filepath=str(source), use_scripts=False)
    elif suffix in {".glb", ".gltf"}:
        bpy.ops.import_scene.gltf(filepath=str(source))
    elif suffix == ".obj":
        bpy.ops.wm.obj_import(filepath=str(source))
    elif suffix == ".fbx":
        bpy.ops.import_scene.fbx(filepath=str(source), use_anim=False)
    elif suffix == ".dae":
        bpy.ops.wm.collada_import(filepath=str(source))
    else:
        raise ValueError(f"Unsupported format: {suffix}; use OBJ, FBX, GLB, glTF, DAE or BLEND")
    # Keep the source's hierarchy, multiplying all root transforms once.
    for obj in bpy.context.scene.objects:
        if obj.parent is None:
            obj.location *= args.scale
            obj.scale *= args.scale
    bpy.context.view_layer.update()
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if not meshes:
        raise ValueError("No mesh in source scene")
    selected = [obj for obj in meshes if pattern and pattern.search(obj.name)]
    if pattern and not selected:
        raise ValueError("Terrain regex matches no meshes; inspect -- report names first")
    smoothing = {}
    for obj in selected:
        # Linked meshes must not propagate edits to non-terrain instances.
        obj.data = obj.data.copy()
        smoothing[obj.name] = smooth_terrain(obj, args.smooth_iterations,
                                            args.strength, args.max_step)
    missing = [image.filepath for image in bpy.data.images
               if image.source == "FILE" and not image.packed_file
               and not Path(bpy.path.abspath(image.filepath)).is_file()]
    if missing:
        raise ValueError("Missing textures (keep their original folders): " + repr(missing[:20]))
    bounds_min = Vector((math.inf,) * 3)
    bounds_max = Vector((-math.inf,) * 3)
    triangles = 0
    for obj in meshes:
        obj.data.calc_loop_triangles()
        triangles += len(obj.data.loop_triangles)
        for corner in obj.bound_box:
            p = obj.matrix_world @ Vector(corner)
            p = Vector((p.x, p.z, -p.y))  # glTF / Godot Y-up
            for axis in range(3):
                bounds_min[axis] = min(bounds_min[axis], p[axis])
                bounds_max[axis] = max(bounds_max[axis], p[axis])
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(output), export_format="GLB",
                              export_yup=True, export_cameras=False,
                              export_lights=False, export_animations=False,
                              export_image_format="AUTO")
    report = {"source": source.name, "output": output.name, "scale": args.scale,
              "meshes": [obj.name for obj in meshes], "triangles": triangles,
              "bounds_min_godot": list(bounds_min), "bounds_max_godot": list(bounds_max),
              "terrain_vertices_moved": smoothing,
              "note": "Select spawn and water height manually in config/map.json; no automatic coastline inference."}
    output.with_suffix(".report.json").write_text(json.dumps(report, indent=2) + "\n")
    print("MAP_CONVERTED " + json.dumps(report))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True)
    parser.add_argument("--output", default="assets/maps/liberty_city.glb")
    parser.add_argument("--scale", type=float, default=1.0, help="Meters per source unit")
    parser.add_argument("--terrain-regex", default="", help="Explicit mesh names; never smooth all buildings")
    parser.add_argument("--smooth-iterations", type=int, default=3)
    parser.add_argument("--strength", type=float, default=0.35)
    parser.add_argument("--max-step", type=float, default=3.0, help="Protect cliffs higher than this many meters")
    parser.add_argument("--overwrite", action="store_true")
    convert(parser.parse_args(sys.argv[sys.argv.index("--") + 1:]))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"MAP_CONVERSION_FAILED: {error}", file=sys.stderr)
        sys.exit(1)
