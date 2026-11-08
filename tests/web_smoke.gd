extends SceneTree
## Real physics queries and CharacterBody sweeps against independent fixtures.
var failures := 0
var checks := 0
const DT := 1.0 / 72.0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	print("PASS " if condition else "FAIL ", message)
	if not condition: failures += 1

func box(parent: Node3D, size: Vector3, position: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	parent.add_child(body)
	body.position = position
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body

func step(player: CharacterBody3D, count: int) -> void:
	for frame in range(count):
		await physics_frame
		player.velocity.y -= 12.0 * DT
		player.webs.apply_constraints(DT)
		player.move_and_slide()

func place(player: CharacterBody3D, position: Vector3) -> void:
	player.webs.cancel_all(false)
	player.global_position = position
	player.velocity = Vector3.ZERO
	player.move_and_slide()

func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	box(stage, Vector3(400, 1, 400), Vector3(0, -0.5, 0))
	box(stage, Vector3(14, 40, 2), Vector3(-12, 20, -30))
	box(stage, Vector3(14, 40, 2), Vector3(12, 20, -30))
	box(stage, Vector3(12, 60, 2), Vector3(0, 30, -220))
	var player = preload("res://scripts/player.gd").new()
	player.spawn_point = Vector3(0, 2, 0)
	stage.add_child(player)
	player.set_physics_process(false)
	await step(player, 100)
	check(player.is_on_floor(), "Web fixture starts on real solid ground")
	var webs = player.webs
	var from: Vector3 = webs.muzzle(0)
	check(not webs.shoot(0, from, Vector3.UP) and not webs.is_attached(), "Shooting empty sky does not create a floating anchor")
	check(not webs.shoot(0, from, Vector3.DOWN), "Ground is rejected as a web anchor")
	check(not webs.shoot(0, from, from.direction_to(Vector3(0, 35, -219))), "Targets beyond 160 metres are rejected")
	check(webs.shoot(0, from, from.direction_to(Vector3(-12, 22, -29))), "Left web attaches to an aimed building face")
	check(webs.hands[0].anchor.distance_to(Vector3(-12, 22, -28.975)) < 0.05, "Attachment is the actual ray impact, not an invented point")
	from = webs.muzzle(1)
	check(webs.shoot(1, from, from.direction_to(Vector3(12, 22, -29))) and webs.hands[0].attached, "Both hands can hold separate building anchors")
	await step(player, 4)
	check(webs.hands[0].rope.visible and webs.hands[1].rope.visible, "Both web threads become visible")
	var continuous := true
	# The headless renderer does not retain MultiMesh transforms. Verify the
	# same geometry transform by its independent cylinder endpoint invariant.
	for direction in [Vector3(-12, 22, -29), Vector3(12, 25, -29), Vector3(0, 10, 0)]:
		var start := Vector3(-0.23, 1.43, -0.38)
		var transform: Transform3D = webs.segment_transform(start, direction)
		continuous = continuous and (transform * Vector3(0, -0.5, 0)).distance_to(start) < 0.001
		continuous = continuous and (transform * Vector3(0, 0.5, 0)).distance_to(direction) < 0.001
	check(continuous, "Rendered tube segments join into continuous web threads")
	webs.release(0)
	check(not webs.hands[0].attached and webs.hands[1].attached, "Releasing one hand keeps the other attached")
	place(player, Vector3(0, 12, 0))
	from = webs.muzzle(1)
	webs.shoot(1, from, from.direction_to(Vector3(12, 25, -29)))
	var initial_length: float = webs.hands[1].length
	webs.reeling[1] = true
	await step(player, 100)
	check(webs.hands[1].attached and webs.hands[1].length < initial_length - 10.0, "Grip reeling shortens the rope while staying attached")
	check(webs.chest_position().distance_to(webs.hands[1].anchor) < webs.hands[1].length + 0.2, "Reeling pulls the body towards its real anchor")
	check(player.global_position.z > -28.7, "Web pull respects the building collision")
	# A taut pendulum should retain tangential velocity and stay within its rope.
	place(player, Vector3(0, 12, 0))
	from = webs.muzzle(1)
	webs.shoot(1, from, from.direction_to(Vector3(12, 25, -29)))
	player.velocity = Vector3(10, 0, 0)
	await step(player, 70)
	check(webs.hands[1].attached and player.global_position.x > 3.0, "A sideways impulse produces a pendulum arc")
	check(webs.chest_position().distance_to(webs.hands[1].anchor) < webs.hands[1].length + 0.2, "Swinging remains inside the rope length")
	var previous_velocity: Vector3 = player.velocity
	webs.release(1)
	check(player.velocity.distance_to(previous_velocity) < 0.001, "Releasing the trigger preserves velocity")
	# Exercise the real player integration after release, not a copy of its math.
	place(player, Vector3(0, 12, 0))
	player.velocity = Vector3(10, 0, 0)
	for frame in range(36):
		await physics_frame
		player._physics_process(DT)
	check(player.global_position.x > 4.0 and player.velocity.x > 9.0, "Player keeps airborne momentum after release without stick input")
	place(player, Vector3(0, 12, 0))
	from = webs.muzzle(1)
	webs.shoot(1, from, from.direction_to(Vector3(12, 25, -29)))
	var middle: Vector3 = webs.chest_position().lerp(webs.hands[1].anchor, 0.5)
	var obstacle := box(stage, Vector3(30, 30, 1), middle)
	await step(player, 25)
	check(not webs.is_attached(), "An intervening wall cuts the rope instead of pulling through it")
	obstacle.queue_free()
	await physics_frame
	place(player, Vector3(0, 12, 0))
	from = webs.muzzle(0)
	webs.shoot(0, from, from.direction_to(Vector3(-12, 22, -29)))
	player.respawn()
	check(not webs.is_attached() and player.velocity == Vector3.ZERO, "Respawn clears both anchors and their momentum")
	var actions: OpenXRActionMap = load("res://config/openxr_action_map.tres")
	var bindings := {}
	for binding in actions.get_interaction_profile(0).bindings:
		bindings[binding.binding_path] = binding.action.resource_name
	var correct := true
	for side in ["left", "right"]:
		correct = correct and bindings.get("/user/hand/%s/input/trigger/value" % side) == "web_fire"
		correct = correct and bindings.get("/user/hand/%s/input/squeeze/value" % side) == "web_reel"
		correct = correct and bindings.get("/user/hand/%s/input/aim/pose" % side) == "aim"
		correct = correct and bindings.get("/user/hand/%s/output/haptic" % side) == "haptic"
	check(correct, "Both Touch hands bind triggers, grips, aim poses and haptics")
	stage.queue_free()
	await process_frame
	print("WEB_SMOKE_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
