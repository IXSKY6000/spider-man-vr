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
	check(world.city_stream.materials.size() == 3, "All atlas materials use repeating-UV city shader")
	check(world.city_stream.active.size() >= 4 and world.city_stream.active.size() < 129, "Physics is loaded around spawn only")
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
