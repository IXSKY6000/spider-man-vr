extends Node
## The city stays resident; rendering is distance-culled by chunk. Physics shapes
## are generated around the player only, one chunk per frame after priming spawn.

const ATLAS_SHADER = preload("res://shaders/city_atlas.gdshader")
var target: Node3D
var chunks: Array[MeshInstance3D] = []
var active: Dictionary = {}
var materials: Dictionary = {}
var visual_distance := 900.0
const PHYSICS_DISTANCE := 240.0
const RELEASE_DISTANCE := 400.0

func prepare(city: Node) -> void:
	_collect(city)
	print("CITY_CHUNKS_READY ", chunks.size())

func _collect(node: Node) -> void:
	if node is MeshInstance3D:
		chunks.append(node)
		node.visibility_range_end = visual_distance
		node.visibility_range_end_margin = 30.0
		for i in node.mesh.get_surface_count():
			var original := node.mesh.surface_get_material(i) as StandardMaterial3D
			if original and original.resource_name.begins_with("LibertyAtlas_"):
				var key := original.resource_name
				if not materials.has(key):
					var material := ShaderMaterial.new()
					material.shader = ATLAS_SHADER
					material.set_shader_parameter("atlas", original.albedo_texture)
					materials[key] = material
				node.set_surface_override_material(i, materials[key])
	for child in node.get_children():
		_collect(child)

func _distance_squared(chunk: MeshInstance3D) -> float:
	var center := chunk.global_transform * chunk.get_aabb().get_center()
	return Vector2(center.x - target.global_position.x, center.z - target.global_position.z).length_squared()

func prime() -> void:
	chunks.sort_custom(func(a: MeshInstance3D, b: MeshInstance3D) -> bool: return _distance_squared(a) < _distance_squared(b))
	for chunk in chunks.slice(0, 4):
		_activate(chunk)

func _activate(chunk: MeshInstance3D) -> void:
	if active.has(chunk):
		return
	chunk.create_trimesh_collision()
	active[chunk] = true

func _process(_delta: float) -> void:
	if not is_instance_valid(target):
		return
	var pending: MeshInstance3D
	var nearest := PHYSICS_DISTANCE * PHYSICS_DISTANCE
	for chunk in chunks:
		var distance := _distance_squared(chunk)
		if active.has(chunk) and distance > RELEASE_DISTANCE * RELEASE_DISTANCE:
			for child in chunk.get_children():
				if child is StaticBody3D:
					child.queue_free()
			active.erase(chunk)
		elif not active.has(chunk) and distance < nearest:
			pending = chunk
			nearest = distance
	if pending:
		_activate(pending)
