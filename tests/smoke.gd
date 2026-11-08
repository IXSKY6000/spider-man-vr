extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS ", message)
	else:
		failures += 1
		push_error("FAIL " + message)

func frames(count: int) -> void:
	for i in count:
		await physics_frame

func _run() -> void:
	var demo_file := FileAccess.open("user://demo_test.json", FileAccess.WRITE)
	demo_file.store_string(JSON.stringify({"scene": "res://assets/maps/missing_for_test.glb", "water_height": -2, "water_size": 12000}))
	demo_file.close()
	var world := preload("res://scripts/world.gd").new()
	world.map_config_path = "user://demo_test.json"
	root.add_child(world)
	await frames(100)
	var player: CharacterBody3D = world.player
	check(not world.map_loaded, "Missing map selects explicitly labelled test area")
	check(player.is_on_floor(), "Player lands on solid platform")
	check(absf(player.position.y) < 0.1, "Capsule feet align with floor")
	var start := player.position
	Input.action_press("move_forward")
	await frames(60)
	Input.action_release("move_forward")
	check(player.position.z < start.z - 1.5, "Walk advances in camera direction")
	var jump_start := player.position.y
	Input.action_press("jump")
	await frames(12)
	check(player.position.y > jump_start + 0.3, "Jump leaves floor")
	Input.action_release("jump")
	await frames(100)
	check(player.is_on_floor(), "Gravity lands player again")
	player.respawn()
	world._box("TestWall", Vector3(10, 4, 1), Vector3(0, 2, 5), Color.WHITE)
	await frames(100)
	Input.action_press("move_forward")
	await frames(180)
	Input.action_release("move_forward")
	check(player.position.z > 5.7 and player.position.z < 6.1, "Walking capsule stops at wall")
	player.camera.position.x = 0.7
	var head_before: Vector3 = player.camera.global_position
	player.snap_turn(deg_to_rad(30))
	check(player.camera.global_position.distance_to(head_before) < 0.001, "Snap turn preserves headset world position")
	player.position.y = -10
	await frames(2)
	check(player.position.distance_to(player.spawn_point) < 0.1, "Falling below water respawns")
	check(world.get_node("Water").position.y == -2, "Water height comes from config")
	var water: Node3D = world.get_node("Water")
	var surface: Node3D = water.get_node("Surface")
	check(surface.get_child_count() == 5, "Ocean uses five tiles regardless of its total area")
	var area := 0.0
	for tile in surface.get_children():
		area += tile.mesh.size.x * tile.mesh.size.y
	check(absf(area - 12000.0 * 12000.0) < 1.0, "Ocean tiles cover configured area without stacked planes")
	var old_player_position := player.position
	player.position = Vector3(1400, 25, -2300)
	water._process(0.0)
	check(surface.global_position.distance_to(Vector3(1400, -2, -2300)) < 3.0, "Ocean follows player while keeping configured water altitude")
	player.position = old_player_position
	var actions := load("res://config/openxr_action_map.tres") as OpenXRActionMap
	check(actions.get_action_set(0).get_action_count() == 10, "OpenXR locomotion, web and haptic actions exist")
	check(actions.get_interaction_profile(0).get_binding_count() == 16, "Touch controller bindings include both web shooters")
	var quality_button := false
	for binding in actions.get_interaction_profile(0).bindings:
		if binding.binding_path == "/user/hand/left/input/y/click" and binding.action.resource_name == "quality":
			quality_button = true
	check(quality_button, "Left Y button controls render clarity")
	player.xr_render_scale = 1.15
	player.cycle_render_quality()
	check(is_equal_approx(player.xr_render_scale, 1.3), "Clarity can increase to 130 percent")
	player.cycle_render_quality()
	check(is_equal_approx(player.xr_render_scale, 1.0), "Clarity can return to baseline for performance")
	world.queue_free()
	await process_frame
	if ResourceLoader.exists("res://assets/maps/test_fixture.glb"):
		var fixture_config := {
			"scene": "res://assets/maps/test_fixture.glb", "scale": 1,
			"spawn": [0, 2, 0], "water_height": -3, "water_size": 100,
		}
		var file := FileAccess.open("user://test_map.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(fixture_config))
		file.close()
		var imported := preload("res://scripts/world.gd").new()
		imported.map_config_path = "user://test_map.json"
		root.add_child(imported)
		await frames(100)
		check(imported.map_loaded, "Converted GLB loads into game")
		check(imported.player.is_on_floor(), "Imported GLB collision supports player")
		check(imported.get_node("Water").position.y == -3, "Imported map applies independent water level")
		check(imported.get_node("Water/Surface").get_child_count() == 1, "Small ocean uses one patch without negative ring dimensions")
		imported.queue_free()
		await process_frame
	else:
		check(false, "Import fixture must be generated before tests")
	print("SMOKE_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
