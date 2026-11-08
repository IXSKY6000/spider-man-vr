extends Node
## The city stays resident; rendering is distance-culled by chunk. Physics shapes
## are generated around the player only, one chunk per frame after priming spawn.

const ATLAS_SHADER = preload("res://shaders/city_atlas.gdshader")
var target: Node3D
var chunks: Array[MeshInstance3D] = []
var active: Dictionary = {}
var materials: Dictionary = {}
var visual_distance := 900.0
var shadow_manifest: Dictionary = {}
var shadow_manifest_path := "res://assets/shadows/sun.json"
var shadow_textures: Array[Texture2D] = []
var lighting_exposure := 1.0
var legacy_water: Array[MeshInstance3D] = []
const PHYSICS_DISTANCE := 240.0
const RELEASE_DISTANCE := 400.0

func prepare(city: Node) -> void:
	shadow_manifest = JSON.parse_string(FileAccess.get_file_as_string(shadow_manifest_path))
	for path in shadow_manifest.files:
		shadow_textures.append(load(path) as Texture2D)
	_collect(city)
	print("CITY_CHUNKS_READY ", chunks.size())

func _collect(node: Node) -> void:
	if node is MeshInstance3D:
		if node.name.begins_with("LegacyWater_"):
			legacy_water.append(node)
			var water := ShaderMaterial.new()
			water.shader = preload("res://shaders/water.gdshader")
			water.set_shader_parameter("ripple_normal", preload("res://assets/water/ripples.tres"))
			water.set_shader_parameter("displace_vertices", false)
			water.set_shader_parameter("wind_strength", 0.3)
			water.set_shader_parameter("surface_roughness", 0.12)
			node.material_override = water
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			return
		chunks.append(node)
		node.visibility_range_end = visual_distance
		node.visibility_range_end_margin = 30.0
		node.lod_bias = 1.1
		for i in node.mesh.get_surface_count():
			var original := node.mesh.surface_get_material(i) as StandardMaterial3D
			if original and original.resource_name.begins_with("LibertyAtlas_"):
				var key := str(original.albedo_texture.get_rid())
				if not materials.has(key):
					var material := ShaderMaterial.new()
					material.shader = ATLAS_SHADER
					material.set_shader_parameter("atlas", original.albedo_texture)
					material.set_shader_parameter("lighting_exposure", lighting_exposure)
					material.set_shader_parameter("fade_distance", visual_distance)
					_configure_sun(material)
					materials[key] = material
				node.set_surface_override_material(i, materials[key])
	for child in node.get_children():
		_collect(child)

func _configure_sun(material: ShaderMaterial) -> void:
	for index in range(4):
		material.set_shader_parameter("shadow_%d" % index, shadow_textures[mini(index, shadow_textures.size() - 1)])
	for key in ["sun_direction", "right", "up"]:
		var v: Array = shadow_manifest[key]
		material.set_shader_parameter(key if key == "sun_direction" else "shadow_" + key, Vector3(v[0], v[1], v[2]))
	var minimum: Array = shadow_manifest.minimum
	material.set_shader_parameter("shadow_minimum", Vector2(minimum[0], minimum[1]))
	material.set_shader_parameter("shadow_span", float(shadow_manifest.span))
	material.set_shader_parameter("depth_min", float(shadow_manifest.depth_min))
	material.set_shader_parameter("depth_span", float(shadow_manifest.depth_span))
	material.set_shader_parameter("shadow_grid", float(shadow_manifest.grid))
	material.set_shader_parameter("shadow_resolution", float(shadow_manifest.resolution))

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
	# The ripped city includes single-sided bridge decks and walls. Collision
	# must work from either side, just as the visible and shadow geometry does.
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(chunk.mesh.get_faces())
	collision.shape = shape
	body.add_child(collision)
	chunk.add_child(body)
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
