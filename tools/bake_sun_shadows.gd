extends SceneTree
## Render fixed orthographic RGB24 depth maps. No frame-to-frame shadow rendering.
const OUTPUT := "res://assets/shadows/"
const SUN_ELEVATION := 68.0
const SUN_AZIMUTH := -35.0
var pilot := false

func _initialize() -> void:
	pilot = "--pilot" in OS.get_cmdline_user_args()
	call_deferred("bake")

func bake() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var viewport := SubViewport.new()
	var resolution := 2048 if pilot else 4096
	viewport.size = Vector2i(resolution, resolution)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.mesh_lod_threshold = 0.0
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	var stage := Node3D.new(); viewport.add_child(stage)
	var city = load("res://assets/maps/liberty_city.glb").instantiate()
	stage.add_child(city)
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/map.json"))
	city.scale = Vector3.ONE * float(config.get("scale", 1.0))
	var translation: Array = config.get("position", [0, 0, 0])
	var orientation: Array = config.get("rotation_degrees", [0, 0, 0])
	city.position = Vector3(translation[0], translation[1], translation[2])
	city.rotation_degrees = Vector3(orientation[0], orientation[1], orientation[2])
	var elevation := float(config.get("sun_elevation_degrees", SUN_ELEVATION))
	var azimuth := float(config.get("sun_azimuth_degrees", SUN_AZIMUTH))
	var rotation := Basis.from_euler(Vector3(deg_to_rad(-elevation), deg_to_rad(azimuth), 0))
	var sun := rotation.z.normalized()
	var right := Vector3.UP.cross(sun).normalized()
	var up := sun.cross(right).normalized()
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	var meshes: Array[MeshInstance3D] = []
	for node in city.find_children("*", "MeshInstance3D", true, false):
		if node.name.begins_with("LegacyWater_"):
			node.visible = false
			continue
		meshes.append(node)
		var box: AABB = node.get_aabb()
		for index in range(8):
			var point: Vector3 = node.global_transform * box.get_endpoint(index)
			var projected := Vector3(right.dot(point), up.dot(point), sun.dot(point))
			low = low.min(projected); high = high.max(projected)
	var span := ceilf(maxf(high.x - low.x, high.y - low.y) + 32.0)
	var center_xy := Vector2(low.x + high.x, low.y + high.y) * 0.5
	var minimum := center_xy - Vector2.ONE * span * 0.5
	if pilot:
		span = 256.0
		var focus := Vector3(-105, 0, -465)
		minimum = Vector2(right.dot(focus), up.dot(focus)) - Vector2.ONE * span * 0.5
	var depth_min := low.z - 20.0
	var depth_span := high.z - low.z + 40.0
	for mesh in meshes:
		mesh.visibility_range_end = 0
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for surface in mesh.mesh.get_surface_count():
			var original = mesh.mesh.surface_get_material(surface)
			var material := ShaderMaterial.new()
			material.shader = load("res://shaders/shadow_bake.gdshader")
			material.set_shader_parameter("atlas", original.albedo_texture)
			material.set_shader_parameter("sun_direction", sun)
			material.set_shader_parameter("depth_min", depth_min)
			material.set_shader_parameter("depth_span", depth_span)
			mesh.set_surface_override_material(surface, material)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	stage.add_child(environment)
	var camera := Camera3D.new(); stage.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.1; camera.far = depth_span + 200.0
	camera.current = true
	var grid := 1 if pilot else 2
	var tile_span := span / grid
	camera.size = tile_span
	var files := []
	for y in range(grid):
		for x in range(grid):
			var xy := minimum + Vector2(x + 0.5, y + 0.5) * tile_span
			camera.global_transform = Transform3D(Basis(right, up, sun), right * xy.x + up * xy.y + sun * (high.z + 50.0))
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			await process_frame
			await RenderingServer.frame_post_draw
			var name := "pilot.png" if pilot else "sun_%d_%d.png" % [x, y]
			var image := viewport.get_texture().get_image()
			var result := image.save_png(OUTPUT + name)
			if result != OK:
				push_error("Shadow map save failed"); quit(1); return
			files.append(OUTPUT + name)
			print("SUN_SHADOW_BAKED ", name, " ", resolution)
	var metadata := {
		"method": "static orthographic RGB24 solar depth, PCF at runtime",
		"geometry_sha256": FileAccess.get_sha256("res://assets/maps/liberty_city.glb"),
		"sun_elevation": elevation, "sun_azimuth": azimuth,
		"sun_direction": [sun.x, sun.y, sun.z], "right": [right.x, right.y, right.z],
		"up": [up.x, up.y, up.z], "minimum": [minimum.x, minimum.y],
		"span": span, "depth_min": depth_min, "depth_span": depth_span,
		"grid": grid, "resolution": resolution, "files": files
	}
	var file := FileAccess.open(OUTPUT + ("pilot.json" if pilot else "sun.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(metadata, "  ")); file.close()
	viewport.queue_free()
	await process_frame
	quit()
