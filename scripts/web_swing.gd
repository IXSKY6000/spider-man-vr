extends Node3D
## Two independent static anchors. Forces act at the body, visuals at the hands.
## Rope constraints change velocity only: move_and_slide remains responsible
## for collisions, including when reeling towards a wall.

const MAX_REACH := 160.0
const MIN_LENGTH := 3.0
const REEL_SPEED := 10.0
const MAX_SPEED := 28.0
const SEGMENTS := 8

class Web:
	var attached := false
	var anchor := Vector3.ZERO
	var length := 0.0
	var age := 0.0
	var miss_time := 0.0
	var miss_end := Vector3.ZERO
	var candidate: Dictionary = {}
	var rope: MultiMeshInstance3D
	var marker: MeshInstance3D

var player: CharacterBody3D
var hands: Array[Web] = [Web.new(), Web.new()]
var trigger_held := [false, false]
var reeling := [false, false]
var pending_impulse := Vector3.ZERO
var aim_timer := 0.0
var obstruction_timer := 0.0

func _ready() -> void:
	# World-space visuals must not rotate or translate again with the body.
	top_level = true
	global_transform = Transform3D.IDENTITY
	var thread := StandardMaterial3D.new()
	thread.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	thread.albedo_color = Color("eeeae1")
	var tube := CylinderMesh.new()
	tube.height = 1.0
	tube.top_radius = 0.003
	tube.bottom_radius = 0.003
	tube.radial_segments = 6
	tube.rings = 1
	tube.material = thread
	var target_material := StandardMaterial3D.new()
	target_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	target_material.albedo_color = Color("b9f0f3")
	var target_mesh := SphereMesh.new()
	target_mesh.radius = 0.07
	target_mesh.height = 0.14
	target_mesh.radial_segments = 8
	target_mesh.rings = 4
	target_mesh.material = target_material
	for web in hands:
		web.rope = MultiMeshInstance3D.new()
		web.rope.multimesh = MultiMesh.new()
		web.rope.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		web.rope.multimesh.mesh = tube
		web.rope.multimesh.instance_count = SEGMENTS
		web.rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		web.rope.visible = false
		add_child(web.rope)
		web.marker = MeshInstance3D.new()
		web.marker.mesh = target_mesh
		web.marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		web.marker.visible = false
		add_child(web.marker)

func chest_position() -> Vector3:
	return player.capsule.global_position + Vector3.UP * 0.15

func muzzle(hand: int) -> Vector3:
	if player.xr_active:
		var controller: XRController3D = player.left_hand if hand == 0 else player.right_hand
		return controller.global_position - controller.global_basis.z * 0.06
	return player.camera.global_transform * Vector3(-0.23 if hand == 0 else 0.23, -0.22, -0.38)

func aim_direction(hand: int) -> Vector3:
	if player.xr_active:
		var pointer: XRController3D = player.left_aim if hand == 0 else player.right_aim
		return -pointer.global_basis.z.normalized()
	return -player.camera.global_basis.z.normalized()

func find_anchor(from: Vector3, direction: Vector3) -> Dictionary:
	if direction.length_squared() < 0.5:
		return {}
	var query := PhysicsRayQueryParameters3D.create(from, from + direction.normalized() * MAX_REACH, 1, [player.get_rid()])
	query.hit_back_faces = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or not hit.collider is StaticBody3D:
		return {}
	var point: Vector3 = hit.position
	if from.distance_to(point) < MIN_LENGTH or point.y < player.global_position.y + 1.0:
		return {}
	# Ground cannot be used as an artificial anchor; elevated roof edges can.
	if hit.normal.y > 0.7 and point.y < from.y + 2.0:
		return {}
	hit.position = point + hit.normal * 0.025
	return hit

func shoot(hand: int, from: Vector3, direction: Vector3) -> bool:
	release(hand)
	var hit := find_anchor(from, direction)
	var web := hands[hand]
	if hit.is_empty():
		web.miss_time = 0.12
		web.miss_end = from + direction.normalized() * 12.0
		_haptic(hand, 0.08)
		return false
	web.anchor = hit.position
	web.length = maxf(MIN_LENGTH, chest_position().distance_to(web.anchor))
	web.attached = true
	web.age = 0.0
	web.miss_time = 0.0
	# A small ground launch makes the first shot useful without a separate jump.
	if player.is_on_floor():
		pending_impulse += chest_position().direction_to(web.anchor) * 3.5 + Vector3.UP * 2.5
	_haptic(hand, 0.3)
	return true

func release(hand: int) -> void:
	hands[hand].attached = false
	hands[hand].miss_time = 0.0
	hands[hand].rope.visible = false
	reeling[hand] = false

func cancel_all(block_held := true) -> void:
	for hand in range(2):
		release(hand)
		hands[hand].candidate = {}
		hands[hand].marker.visible = false
		trigger_held[hand] = block_held
	pending_impulse = Vector3.ZERO

func is_attached() -> bool:
	return hands[0].attached or hands[1].attached

func update_controls(delta: float) -> void:
	aim_timer -= delta
	var refresh_aim := aim_timer <= 0.0
	if refresh_aim: aim_timer = 0.067
	for hand in range(2):
		var held := false
		var reel := false
		var tracked := true
		if player.xr_active:
			var controller: XRController3D = player.left_hand if hand == 0 else player.right_hand
			var pointer: XRController3D = player.left_aim if hand == 0 else player.right_aim
			tracked = controller.get_has_tracking_data() and pointer.get_has_tracking_data()
			var trigger := controller.get_float("web_fire")
			held = tracked and trigger >= (0.25 if trigger_held[hand] else 0.65)
			reel = controller.get_float("web_reel") > 0.55
		else:
			tracked = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			held = tracked and Input.is_action_pressed("web_left" if hand == 0 else "web_right")
			reel = tracked and Input.is_action_pressed("web_reel")
		if held and not trigger_held[hand]:
			shoot(hand, muzzle(hand), aim_direction(hand))
		elif not held and trigger_held[hand]:
			release(hand)
		trigger_held[hand] = held
		reeling[hand] = held and reel
		if refresh_aim:
			hands[hand].candidate = find_anchor(muzzle(hand), aim_direction(hand)) if tracked else {}
		if not tracked:
			release(hand)
			# A returning tracked hand must release its trigger before a new shot.
			trigger_held[hand] = true

func apply_constraints(delta: float) -> void:
	player.velocity += pending_impulse
	pending_impulse = Vector3.ZERO
	var chest := chest_position()
	for hand in range(2):
		var web := hands[hand]
		if not web.attached: continue
		web.age += delta
		if chest.distance_to(web.anchor) > MAX_REACH + 20.0:
			release(hand)
			continue
		if reeling[hand]:
			var minimum := MIN_LENGTH
			var other := hands[1 - hand]
			if other.attached:
				minimum = maxf(minimum, web.anchor.distance_to(other.anchor) - other.length + 0.1)
			web.length = maxf(minimum, web.length - REEL_SPEED * delta)
	# Two iterations let simultaneous ropes share their radial constraints.
	for iteration in range(2):
		for web in hands:
			if not web.attached: continue
			var offset := chest - web.anchor
			var distance := offset.length()
			if distance < 0.001: continue
			var outward := offset / distance
			var allowed_speed := maxf((web.length - distance) / delta, -REEL_SPEED * 1.2)
			var excess := player.velocity.dot(outward) - allowed_speed
			if excess > 0.0:
				player.velocity -= outward * excess
	player.velocity = player.velocity.limit_length(MAX_SPEED)
	obstruction_timer -= delta
	if obstruction_timer <= 0.0:
		obstruction_timer = 0.12
		for hand in range(2):
			var web := hands[hand]
			if not web.attached or web.age < 0.12: continue
			var query := PhysicsRayQueryParameters3D.create(chest, web.anchor, 1, [player.get_rid()])
			query.hit_back_faces = true
			var hit := get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty() and hit.position.distance_to(web.anchor) > 0.5:
				release(hand)

func _haptic(hand: int, strength: float) -> void:
	if player.xr_active:
		var controller: XRController3D = player.left_hand if hand == 0 else player.right_hand
		controller.trigger_haptic_pulse("haptic", 0.0, strength, 0.04, 0.0)

func _process(delta: float) -> void:
	for hand in range(2):
		var web := hands[hand]
		web.miss_time = maxf(0.0, web.miss_time - delta)
		web.rope.visible = web.attached or web.miss_time > 0.0
		web.marker.visible = web.attached or not web.candidate.is_empty()
		if web.marker.visible:
			web.marker.position = web.anchor if web.attached else web.candidate.position
			web.marker.scale = Vector3.ONE * clampf(player.camera.global_position.distance_to(web.marker.position) * 0.05, 1.0, 6.0)
		if not web.rope.visible: continue
		var start := muzzle(hand)
		var finish := web.anchor if web.attached else web.miss_end
		if web.attached:
			finish = start.lerp(finish, clampf(web.age / 0.09, 0.0, 1.0))
		var slack := minf(1.5, maxf(0.0, web.length - chest_position().distance_to(finish)) * 0.15) if web.attached else 0.0
		for segment in range(SEGMENTS):
			var t0 := float(segment) / SEGMENTS
			var t1 := float(segment + 1) / SEGMENTS
			var a := start.lerp(finish, t0) - Vector3.UP * sin(t0 * PI) * slack
			var b := start.lerp(finish, t1) - Vector3.UP * sin(t1 * PI) * slack
			web.rope.multimesh.set_instance_transform(segment, segment_transform(a, b))

func segment_transform(a: Vector3, b: Vector3) -> Transform3D:
	var direction := b - a
	var length := maxf(direction.length(), 0.0001)
	var y := direction / length
	if y.length_squared() < 0.5: y = Vector3.UP
	var x := y.cross(Vector3.FORWARD if absf(y.y) > 0.95 else Vector3.UP).normalized()
	# Keep a fine thread near the hand and a readable subpixel width far away.
	var radius := maxf(1.0, player.camera.global_position.distance_to((a + b) * 0.5) * 0.1)
	# Scale the local cylinder axes, not the world axes of the rotated basis.
	return Transform3D(Basis(x * radius, y * length, x.cross(y) * radius), (a + b) * 0.5)
