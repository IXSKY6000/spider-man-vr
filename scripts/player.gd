extends CharacterBody3D
## Feet are the origin; the collision capsule follows the headset horizontally.

const WALK_SPEED := 3.0
const RUN_SPEED := 6.0
const JUMP_SPEED := 5.0
const SNAP_ANGLE := deg_to_rad(30.0)
var xr_active := false
var xr_render_scale := 1.15
var origin: XROrigin3D
var camera: Camera3D
var left_hand: XRController3D
var right_hand: XRController3D
var capsule: CollisionShape3D
var spawn_point := Vector3(0, 2, 8)
var water_height := -2.0
var turn_latched := false
var jump_held := false
var quality_held := false
var quality_label: Label3D

func _ready() -> void:
	name = "Player"
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(48)
	_register_inputs()
	capsule = CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.24
	shape.height = 1.7
	capsule.shape = shape
	capsule.position.y = 0.85
	add_child(capsule)
	var xr := XRServer.find_interface("OpenXR") as OpenXRInterface
	xr_active = xr != null and xr.is_initialized()
	if xr_active:
		xr.set_render_target_size_multiplier(clampf(xr_render_scale, 1.0, 1.5))
		get_viewport().use_xr = true
		print("XR_RENDER_SCALE ", xr.get_render_target_size_multiplier(), " target=", xr.get_render_target_size())
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		origin = XROrigin3D.new()
		add_child(origin)
		camera = XRCamera3D.new()
		origin.add_child(camera)
		left_hand = _hand("left_hand", origin)
		right_hand = _hand("right_hand", origin)
		var hint := Label3D.new()
		hint.text = "WEB / LIBERTY\nG : marcher  ·  D : tourner\nA : sauter  ·  B : retour"
		hint.font_size = 30
		hint.pixel_size = 0.0006
		hint.position = Vector3(0, 0.10, 0)
		hint.rotation_degrees.x = -65
		left_hand.add_child(hint)
		quality_label = hint
		_refresh_quality_label()
	else:
		camera = Camera3D.new()
		camera.position.y = 1.65
		add_child(camera)
	camera.current = true
	camera.near = 0.07
	camera.far = 2200.0
	respawn()

func _hand(tracker_name: String, parent: Node3D) -> XRController3D:
	var controller := XRController3D.new()
	controller.tracker = tracker_name
	controller.pose = "grip"
	parent.add_child(controller)
	var glove := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.045
	mesh.height = 0.13
	mesh.radial_segments = 12
	mesh.rings = 6
	glove.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("c72e35")
	material.roughness = 0.65
	glove.material_override = material
	controller.add_child(glove)
	return controller

func _register_inputs() -> void:
	var keys := {
		"move_left": [KEY_A, KEY_Q, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"move_forward": [KEY_W, KEY_Z, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"jump": [KEY_SPACE], "run": [KEY_SHIFT], "respawn": [KEY_R]
	}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for code in keys[action]:
			var event := InputEventKey.new()
			event.physical_keycode = code
			InputMap.action_add_event(action, event)

func _unhandled_input(event: InputEvent) -> void:
	if xr_active:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * 0.002)
		camera.rotation.x = clampf(camera.rotation.x - event.relative.y * 0.002, -1.4, 1.4)

func _physics_process(delta: float) -> void:
	var movement := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wants_jump := Input.is_action_pressed("jump")
	var wants_run := Input.is_action_pressed("run")
	if xr_active:
		var quality_pressed := left_hand.is_button_pressed("quality")
		if quality_pressed and not quality_held:
			cycle_render_quality()
		quality_held = quality_pressed
		var stick := left_hand.get_vector2("move")
		movement = Vector2(stick.x, -stick.y)
		if movement.length() < 0.18:
			movement = Vector2.ZERO
		var turn := right_hand.get_vector2("move").x
		if absf(turn) > 0.7 and not turn_latched:
			snap_turn(-signf(turn) * SNAP_ANGLE)
			turn_latched = true
		elif absf(turn) < 0.3:
			turn_latched = false
		wants_jump = right_hand.is_button_pressed("jump")
		wants_run = left_hand.is_button_pressed("sprint")
		if right_hand.is_button_pressed("reset"):
			respawn()
		# Do not move the tracked camera; place the body capsule underneath it.
		var local_head := to_local(camera.global_position)
		capsule.position.x = local_head.x
		capsule.position.z = local_head.z
		var height := clampf(local_head.y, 0.8, 2.1)
		capsule.shape.height = height
		capsule.position.y = height * 0.5
	var forward := -camera.global_basis.z
	forward.y = 0
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP)
	var direction := (right * movement.x - forward * movement.y).limit_length(1)
	var speed := RUN_SPEED if wants_run else WALK_SPEED
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if not is_on_floor():
		velocity.y -= 12.0 * delta
	if wants_jump and not jump_held and is_on_floor():
		velocity.y = JUMP_SPEED
	jump_held = wants_jump
	move_and_slide()
	if global_position.y < water_height - 1.0 or Input.is_action_just_pressed("respawn"):
		respawn()

func snap_turn(angle: float) -> void:
	# Rotate about the headset so a room-scale offset does not cause a jump.
	var before := camera.global_position
	rotate_y(angle)
	var correction := before - camera.global_position
	global_position += Vector3(correction.x, 0, correction.z)

func respawn() -> void:
	global_position = spawn_point
	velocity = Vector3.ZERO
	if xr_active:
		var head_offset := camera.global_position - global_position
		global_position -= Vector3(head_offset.x, 0, head_offset.z)

func cycle_render_quality() -> void:
	if xr_render_scale < 1.075:
		xr_render_scale = 1.15
	elif xr_render_scale < 1.225:
		xr_render_scale = 1.3
	else:
		xr_render_scale = 1.0
	if xr_active:
		var xr := XRServer.find_interface("OpenXR") as OpenXRInterface
		xr.set_render_target_size_multiplier(xr_render_scale)
		print("XR_RENDER_SCALE ", xr_render_scale, " target=", xr.get_render_target_size())
	_refresh_quality_label()

func _refresh_quality_label() -> void:
	if is_instance_valid(quality_label):
		quality_label.text = "WEB / LIBERTY\nG : marcher · D : tourner\nA : sauter · B : retour\nY : netteté %d %%" % roundi(xr_render_scale * 100)
