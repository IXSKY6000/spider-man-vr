extends SceneTree
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	print("PASS " if condition else "FAIL ", message)
	if not condition:
		failures += 1

func frames(count: int) -> void:
	for i in count:
		await physics_frame

func _run() -> void:
	var world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await frames(160)
	check(world.map_loaded, "Actual Liberty City asset loaded")
	check(world.has_node("LibertyCity") and not world.has_node("TestPlatform"), "Real city replaces placeholder")
	check(world.city_stream.chunks.size() == 129, "All converted city chunks present")
	var albedos := {}
	for material in world.city_stream.materials.values():
		var atlas: Texture2D = material.get_shader_parameter("atlas")
		if atlas: albedos[atlas.get_rid()] = true
	check(albedos.size() == 3, "All baked chunks retain the three original texture atlases")
	check(world.city_stream.shadow_textures.size() == 4 and world.city_stream.shadow_textures[0].get_width() == 4096, "Four precalculated 4K solar depth maps are loaded")
	check(world.city_stream.legacy_water.size() > 0, "Old GTA water surfaces use new water shader")
	var water_triangles := 0
	var water_non_solid := true
	for water in world.city_stream.legacy_water:
		water_non_solid = water_non_solid and water.get_child_count() == 0
		for surface in water.mesh.get_surface_count():
			var arrays: Array = water.mesh.surface_get_arrays(surface)
			water_triangles += arrays[Mesh.ARRAY_INDEX].size() / 3
	check(water_non_solid, "Replaced water remains non-solid")
	check(water_triangles == 290, "All selected legacy-water triangles are replaced")
	var has_lods := false
	for chunk in world.city_stream.chunks:
		for surface in chunk.mesh.get_surface_count():
			if RenderingServer.mesh_get_surface(chunk.mesh.get_rid(), surface).get("lods", []).size() > 0:
				has_lods = true
	check(has_lods, "Renderer receives generated mesh LOD index buffers")
	check(is_equal_approx(world.get_viewport().mesh_lod_threshold, 0.75), "LOD screen error stays below one pixel")
	check(is_equal_approx(world.player.xr_render_scale, 1.15), "Default XR render target scale is 115 percent")
	check(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d") == Viewport.MSAA_4X, "4x MSAA is configured")
	var sun: DirectionalLight3D = world.get_node("Sun")
	check(not sun.shadow_enabled, "Static city uses baked shadows instead of dynamic shadow maps")
	var environment_nodes = world.find_children("*", "WorldEnvironment", true, false)
	var sky_material = environment_nodes[0].environment.sky.sky_material
	check(sky_material is ShaderMaterial and sky_material.shader == load("res://shaders/day_sky.gdshader"), "Day sky renders its own visible solar disc")
	var sun_direction := sun.global_basis.z.normalized()
	var sky_direction: Vector3 = sky_material.get_shader_parameter("sun_direction")
	var shader_direction: Vector3 = world.city_stream.materials.values()[0].get_shader_parameter("sun_direction")
	check(sky_direction.dot(sun_direction) > 0.99999 and shader_direction.dot(sun_direction) > 0.99999, "Sky sun, water light and static city shadows share the same direction")
	check(rad_to_deg(asin(sun_direction.y)) >= 60.0 and rad_to_deg(asin(sun_direction.y)) <= 80.0, "Daytime sun is high overhead")
	check(environment_nodes[0].environment.fog_sky_affect < 0.1, "Distance haze preserves the sun in the sky")
	check(world.city_stream.active.size() >= 4 and world.city_stream.active.size() < 129, "Physics is loaded around spawn only")
	check(_solar_depth_matches_geometry(world, Vector3(-105, -0.0498, -480)), "Baked bridge shadow depth agrees with an independent physics ray")
	check(_solar_depth_matches_geometry(world, Vector3(-95, -0.0498, -465)), "Baked sunlit street depth agrees with an independent physics ray")
	check(world.player.is_on_floor(), "Player lands on actual city ground")
	check(absf(world.player.position.y - (-0.0498)) < 0.2, "Spawn matches measured street elevation")
	var previous: Vector3 = world.player.position
	Input.action_press("move_forward")
	await frames(25)
	Input.action_release("move_forward")
	check(world.player.position.distance_to(previous) > 0.3, "Walking works in real city")
	var jump_height: float = world.player.position.y
	Input.action_press("jump")
	await frames(12)
	Input.action_release("jump")
	check(world.player.position.y > jump_height + 0.3, "Jump works on city ground")
	await frames(120)
	check(world.player.is_on_floor(), "Player lands again in city")
	world.player.position.y = world.player.water_height - 5
	await frames(2)
	check(world.player.position.distance_to(world.player.spawn_point) < 0.15, "City water fall returns to selected street")
	check(world.get_node("Water").position.y == world.config.water_height, "Real city water uses selected sea level")
	world.queue_free()
	await process_frame
	print("CITY_SMOKE_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _solar_depth_matches_geometry(world: Node3D, point: Vector3) -> bool:
	var stream = world.city_stream
	var manifest: Dictionary = stream.shadow_manifest
	var resolution := int(manifest.resolution)
	var grid := int(manifest.grid)
	var sun := _vector(manifest.sun_direction)
	var right := _vector(manifest.right)
	var up := _vector(manifest.up)
	var minimum := Vector2(manifest.minimum[0], manifest.minimum[1])
	var uv := (Vector2(point.dot(right), point.dot(up)) - minimum) / float(manifest.span)
	var pixel := Vector2i((uv * (resolution * grid)).floor())
	var tile := Vector2i(pixel.x / resolution, pixel.y / resolution)
	var texture: Texture2D = stream.shadow_textures[tile.y * grid + tile.x]
	var image := texture.get_image()
	if image == null: return false
	var encoded := image.get_pixel(pixel.x % resolution, resolution - 1 - pixel.y % resolution)
	var packed := roundf(encoded.r * 255) + roundf(encoded.g * 255) * 256 + roundf(encoded.b * 255) * 65536
	var baked_height := packed / 16777215.0 * float(manifest.depth_span) + float(manifest.depth_min)
	# Reconstruct the exact pixel centre on the receiver plane, avoiding any
	# nearest-texel slope error in this independent CPU/GPU comparison.
	var xy := minimum + (Vector2(pixel) + Vector2.ONE * 0.5) / (resolution * grid) * float(manifest.span)
	var receiver := right * xy.x + up * xy.y + sun * ((point.y - up.y * xy.y) / sun.y)
	var query := PhysicsRayQueryParameters3D.create(receiver + sun * 200, receiver - sun * 10)
	query.hit_back_faces = true
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and absf(baked_height - hit.position.dot(sun)) < 0.01

func _vector(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])
