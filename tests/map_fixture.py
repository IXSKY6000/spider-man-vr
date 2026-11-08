"""Run with Blender: exercises terrain conversion without GTA assets."""
import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from prepare_map import smooth_terrain

bpy.ops.wm.read_factory_settings(use_empty=True)
# 5x5 plane: boundary must stay fixed, centre is a bump to relax.
vertices = [(x - 2, y - 2, 0.6 if x == 2 and y == 2 else 0)
            for y in range(5) for x in range(5)]
faces = [(y * 5 + x, y * 5 + x + 1, (y + 1) * 5 + x + 1, (y + 1) * 5 + x)
         for y in range(4) for x in range(4)]
mesh = bpy.data.meshes.new("GroundMesh")
mesh.from_pydata(vertices, [], faces)
ground = bpy.data.objects.new("TerrainTest", mesh)
bpy.context.collection.objects.link(ground)
before = [v.co.copy() for v in mesh.vertices]
moved = smooth_terrain(ground, 3, 0.35, 3.0)
assert moved > 0, "No smoothing occurred"
assert mesh.vertices[12].co.z < 0.6, "Centre should be lower"
for i, vertex in enumerate(mesh.vertices):
    assert vertex.co.x == before[i].x and vertex.co.y == before[i].y
    if i // 5 in (0, 4) or i % 5 in (0, 4):
        assert vertex.co == before[i], "Boundary moved"
# Add a large solid flat floor for the actual runtime collision test.
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, -0.5))
floor = bpy.context.object
floor.name = "CollisionFloor"
floor.scale = (30, 30, 1)
source = Path("/tmp/liberty-test-source.glb")
bpy.ops.export_scene.gltf(filepath=str(source), export_format="GLB")
print("FIXTURE_PASS height_relaxation boundary_lock xy_lock source=" + str(source))
