"""Prepare the supplied LCG3 OBJ rip for Godot (run with Blender 4.3+).

blender --background --python tools/import_liberty_city.py -- --source-dir PATH
Preserves sources. Atlases retain original texture resolution and repeating UVs.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from prepare_map import smooth_terrain

ATLAS_SIZE = 4096
PADDING = 8
CELL_SIZE = 128.0
# Visually inspected grass/soil textures, never facades, roofs or foliage cards.
TERRAIN_MATERIALS = {138, 236, 226, 1559, 224}


def run(source, output):
    source = source.resolve()
    output.mkdir(parents=True, exist_ok=True)
    working = output / "source" / "prepared"
    working.mkdir(parents=True, exist_ok=True)
    (output / "source" / ".gdignore").touch()
    atlas_dir = output / "source" / "atlases"
    atlas_dir.mkdir(exist_ok=True)
    # Replace the repeated author-machine paths in a derived copy only.
    with (source / "LCG3.obj").open() as src, (working / "LCG3.obj").open("w") as dst:
        dst.write("mtllib LCG3.mtl\n")
        for line in src:
            if not line.startswith("mtllib "):
                dst.write(line)
    (working / "LCG3.mtl").write_text((source / "LCG3.mtl").read_text())
    for image in source.iterdir():
        if image.suffix.lower() not in {".dds", ".png"}:
            continue
        dest = working / image.name
        if not dest.exists():
            dest.symlink_to(image)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.obj_import(filepath=str(working / "LCG3.obj"))
    obj = next(o for o in bpy.context.scene.objects if o.type == "MESH")
    mesh = obj.data
    mesh.calc_loop_triangles()
    assert all(len(p.vertices) == 3 for p in mesh.polygons), "Expected triangulated source"
    materials = list(mesh.materials)
    print("SOURCE", len(mesh.vertices), "vertices", len(mesh.polygons), "triangles", flush=True)

    # Deduplicate identical source images by bytes, independently of their names.
    image_keys, unique = {}, {}
    for mat in materials:
        image = next(n.image for n in mat.node_tree.nodes if n.type == "TEX_IMAGE" and n.image)
        path = Path(bpy.path.abspath(image.filepath))
        key = hashlib.sha256(path.read_bytes()).hexdigest()
        unique.setdefault(key, image)
        image_keys[mat.name] = key

    # Shelf packing, no downscaling. Original power-of-two dimensions are retained.
    packing, atlas_count = {}, 1
    x = y = row_height = 0
    for key, image in sorted(unique.items(), key=lambda pair: (-pair[1].size[1], -pair[1].size[0], pair[0])):
        width, height = image.size
        if x + width + 2 * PADDING > ATLAS_SIZE:
            x = 0
            y += row_height
            row_height = 0
        if y + height + 2 * PADDING > ATLAS_SIZE:
            atlas_count += 1
            x = y = row_height = 0
        packing[key] = (atlas_count - 1, x + PADDING, y + PADDING, width, height)
        x += width + 2 * PADDING
        row_height = max(row_height, height + 2 * PADDING)
    atlas_materials = []
    for index in range(atlas_count):
        pixels = np.zeros((ATLAS_SIZE, ATLAS_SIZE, 4), dtype=np.float32)
        for key, image in unique.items():
            page, px, py, width, height = packing[key]
            if page != index:
                continue
            data = np.empty(width * height * 4, dtype=np.float32)
            image.pixels.foreach_get(data)
            data = data.reshape(height, width, 4)
            pixels[py-PADDING:py+height+PADDING, px-PADDING:px+width+PADDING] = np.pad(data, ((PADDING, PADDING), (PADDING, PADDING), (0, 0)), mode="wrap")
        atlas = bpy.data.images.new(f"LibertyAtlas{index}", ATLAS_SIZE, ATLAS_SIZE, alpha=True)
        atlas.pixels.foreach_set(pixels.ravel())
        atlas.filepath_raw = str(atlas_dir / f"liberty_atlas_{index}.png")
        atlas.file_format = "PNG"
        atlas.save()
        material = bpy.data.materials.new(f"LibertyAtlas_{index}")
        material.use_nodes = True
        bsdf = material.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Roughness"].default_value = 0.9
        texture = material.node_tree.nodes.new("ShaderNodeTexImage")
        texture.image = atlas
        material.node_tree.links.new(texture.outputs["Color"], bsdf.inputs["Base Color"])
        atlas_materials.append(material)
        print("ATLAS", index, flush=True)

    verts = np.empty(len(mesh.vertices) * 3, dtype=np.float32)
    mesh.vertices.foreach_get("co", verts)
    verts = verts.reshape(-1, 3)
    matrix = np.array(obj.matrix_world, dtype=np.float32)
    verts = verts @ matrix[:3, :3].T + matrix[:3, 3]
    loops = np.empty(len(mesh.loops), dtype=np.int32)
    mesh.loops.foreach_get("vertex_index", loops)
    positions = verts[loops].copy()
    uv = np.empty(len(mesh.loops) * 2, dtype=np.float32)
    mesh.uv_layers.active.data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 2)
    normals = np.empty(len(mesh.loops) * 3, dtype=np.float32)
    mesh.corner_normals.foreach_get("vector", normals)
    normals = normals.reshape(-1, 3) @ matrix[:3, :3].T
    mat_ids = np.empty(len(mesh.polygons), dtype=np.int32)
    mesh.polygons.foreach_get("material_index", mat_ids)

    terrain_ids = [i for i, material in enumerate(materials)
                   if int(material.name.replace("Model001_Material", "").split(".")[0]) in TERRAIN_MATERIALS]
    terrain_faces = np.flatnonzero(np.isin(mat_ids, terrain_ids))
    terrain_loops = (terrain_faces[:, None] * 3 + np.arange(3)).ravel()
    coordinates, inverse = np.unique(np.round(positions[terrain_loops], 4), axis=0, return_inverse=True)
    terrain_mesh = bpy.data.meshes.new("SelectedTerrain")
    terrain_mesh.from_pydata(coordinates.tolist(), [], inverse.reshape(-1, 3).tolist())
    terrain_obj = bpy.data.objects.new("SelectedTerrain", terrain_mesh)
    bpy.context.collection.objects.link(terrain_obj)
    moved = smooth_terrain(terrain_obj, 3, 0.35, 3.0)
    updated = np.empty(len(terrain_mesh.vertices) * 3, dtype=np.float32)
    terrain_mesh.vertices.foreach_get("co", updated)
    positions[terrain_loops] = updated.reshape(-1, 3)[inverse]
    updated_normals = np.empty(len(terrain_mesh.loops) * 3, dtype=np.float32)
    terrain_mesh.corner_normals.foreach_get("vector", updated_normals)
    normals[terrain_loops] = updated_normals.reshape(-1, 3)
    bpy.data.objects.remove(terrain_obj, do_unlink=True)
    print("TERRAIN", len(terrain_faces), "faces", moved, "vertices relaxed", flush=True)

    # Carry atlas origins in UV2, texture dimensions as quantization-safe log2 COLOR.
    rects = np.array([packing[image_keys[m.name]] for m in materials], dtype=np.float32)
    rect_per_loop = rects[np.repeat(mat_ids, 3)]
    atlas_uv = rect_per_loop[:, 1:3].copy() / ATLAS_SIZE
    atlas_uv[:, 1] += rect_per_loop[:, 4] / ATLAS_SIZE  # glTF flips UV2 V on export
    color = np.ones((len(loops), 4), dtype=np.float32)
    color[:, :2] = np.log2(rect_per_loop[:, 3:5]) / 8.0
    pages = rects[mat_ids, 0].astype(np.int32)
    centroids = positions.reshape(-1, 3, 3).mean(axis=1)
    cells = np.floor(centroids[:, :2] / CELL_SIZE).astype(np.int32)
    unique_cells, assignments = np.unique(cells, axis=0, return_inverse=True)
    bpy.data.objects.remove(obj, do_unlink=True)
    chunk_stats = []
    for chunk_id, cell in enumerate(unique_cells):
        face_ids = np.flatnonzero(assignments == chunk_id)
        corner_ids = (face_ids[:, None] * 3 + np.arange(3)).ravel()
        points, indices = np.unique(positions[corner_ids], axis=0, return_inverse=True)
        chunk_mesh = bpy.data.meshes.new(f"City_{cell[0]}_{cell[1]}")
        chunk_mesh.from_pydata(points.tolist(), [], indices.reshape(-1, 3).tolist())
        chunk = bpy.data.objects.new(chunk_mesh.name, chunk_mesh)
        bpy.context.collection.objects.link(chunk)
        for material in atlas_materials:
            chunk_mesh.materials.append(material)
        chunk_mesh.polygons.foreach_set("material_index", pages[face_ids])
        chunk_mesh.polygons.foreach_set("use_smooth", np.ones(len(face_ids), dtype=bool))
        chunk_mesh.uv_layers.new(name="UVMap").data.foreach_set("uv", uv[corner_ids].ravel())
        chunk_mesh.uv_layers.new(name="AtlasOrigin").data.foreach_set("uv", atlas_uv[corner_ids].ravel())
        colors = chunk_mesh.color_attributes.new(name="AtlasDimensions", type="FLOAT_COLOR", domain="CORNER")
        colors.data.foreach_set("color", color[corner_ids].ravel())
        chunk_mesh.color_attributes.active_color = colors
        chunk_mesh.normals_split_custom_set(normals[corner_ids].tolist())
        chunk_stats.append({"name":chunk.name, "triangles":len(face_ids)})
    print("CHUNKS", len(chunk_stats), flush=True)
    bpy.ops.export_scene.gltf(filepath=str(output / "liberty_city.glb"), export_format="GLB",
                              export_yup=True, export_cameras=False, export_lights=False,
                              export_animations=False, export_vertex_color="ACTIVE", export_all_vertex_colors=False)
    report = {"source": "LCG3.obj", "triangles": int(len(mat_ids)), "chunks": chunk_stats,
              "atlas_count": atlas_count, "unique_textures": len(unique),
              "terrain_materials": sorted(TERRAIN_MATERIALS), "terrain_faces": len(terrain_faces),
              "terrain_vertices_relaxed": moved, "chunk_size_m": CELL_SIZE}
    (output / "liberty_city.report.json").write_text(json.dumps(report, indent=2) + "\n")
    print("CITY_EXPORT_DONE", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", required=True, type=Path)
    parser.add_argument("--output-dir", type=Path, default=Path("assets/maps"))
    arguments = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    run(arguments.source_dir, arguments.output_dir.resolve())
