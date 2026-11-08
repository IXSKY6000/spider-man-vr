extends Node3D

const Player = preload("res://scripts/player.gd")
const Water = preload("res://scripts/water.gd")
const CityStream = preload("res://scripts/city_stream.gd")
@export_file("*.json") var map_config_path := "res://config/map.json"
var player: CharacterBody3D
var map_loaded := false
var config: Dictionary
var city_stream: Node

func _ready() -> void:
	config = JSON.parse_string(FileAccess.get_file_as_string(map_config_path))
	_lighting()
	_water()
	var scene_path := str(config.get("scene", ""))
	if not scene_path.is_empty() and ResourceLoader.exists(scene_path):
		var packed := load(scene_path) as PackedScene
		if packed:
			var city := packed.instantiate() as Node3D
			city.name = "LibertyCity"
			city.scale = Vector3.ONE * float(config.get("scale", 1.0))
			city.position = _vec(config.get("position", [0, 0, 0]))
			city.rotation_degrees = _vec(config.get("rotation_degrees", [0, 0, 0]))
			add_child(city)
			if config.get("stream_city", false):
				city_stream = CityStream.new()
				city_stream.visual_distance = float(config.get("city_view_distance", 900.0))
				add_child(city_stream)
				city_stream.prepare(city)
			else:
				_add_collisions(city)
			map_loaded = true
	if not map_loaded:
		_test_area()
	player = Player.new()
	player.spawn_point = _vec(config.get("spawn", [0, 2, 8])) if map_loaded else Vector3(0, 2, 8)
	player.water_height = float(config.get("water_height", -2))
	add_child(player)
	if city_stream:
		city_stream.target = player.camera
		city_stream.prime()
	get_node("Water").target = player.camera
	player.camera.far = float(config.get("far_clip", 2200))
	if not player.xr_active:
		_desktop_overlay()
	print("WORLD_READY map=", map_loaded, " xr=", player.xr_active)

func _vec(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

func _lighting() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("397da3")
	sky_material.sky_horizon_color = Color("c3d5da")
	sky_material.ground_horizon_color = Color("b5c6cd")
	sky_material.ground_bottom_color = Color("46575f")
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("a8c3d3")
	environment.ambient_light_energy = 0.25
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("b7cdd5")
	environment.fog_density = float(config.get("fog_density", 0.00035))
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-38, -32, 0)
	sun.light_color = Color("fff1d5")
	sun.light_energy = 0.7
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 65
	add_child(sun)

func _water() -> void:
	var ocean := Water.new()
	ocean.name = "Water"
	ocean.water_size = float(config.get("water_size", 12000))
	ocean.wind_strength = float(config.get("water_wind", 0.75))
	ocean.surface_roughness = float(config.get("water_roughness", 0.13))
	ocean.position.y = float(config.get("water_height", -2))
	add_child(ocean)

func _add_collisions(node: Node) -> void:
	# Imported GLBs can already contain authored collision bodies.
	if node is StaticBody3D:
		return
	if node is MeshInstance3D and node.mesh:
		var has_collision := false
		for child in node.get_children():
			if child is StaticBody3D:
				has_collision = true
		if not has_collision:
			node.create_trimesh_collision()
	for child in node.get_children():
		_add_collisions(child)

func _box(label: String, size: Vector3, pos: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.position = pos
	add_child(body)
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = size
	mesh.mesh = cube
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	mesh.material_override = material
	body.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)

func _test_area() -> void:
	# Explicit fallback for testing locomotion while the supplied archive is unavailable.
	_box("TestPlatform", Vector3(42, 1, 42), Vector3(0, -0.5, 0), Color("66777e"))
	_box("Walkway", Vector3(5, 0.04, 36), Vector3(0, 0.025, 0), Color("b0bab8"))
	_box("JumpBlock", Vector3(2, 0.4, 2), Vector3(3, 0.2, 0), Color("be4a43"))
	for side in [-1, 1]:
		for i in range(4):
			var height := 8.0 + i * 4.0
			_box("TestTower", Vector3(6, height, 6), Vector3(side * 14, height / 2, -15 + i * 10), Color("384f62"))
			_box("TowerCornice", Vector3(6.2, 0.25, 6.2), Vector3(side * 14, height, -15 + i * 10), Color("b2bbbc"))
	var sign_label := Label3D.new()
	sign_label.text = "WEB / LIBERTY\nZONE DE TEST\nCarte GTA III en attente d'import"
	sign_label.position = Vector3(0, 3.5, -10)
	sign_label.font_size = 70
	sign_label.pixel_size = 0.009
	sign_label.modulate = Color("f1e7cf")
	add_child(sign_label)

func _desktop_overlay() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 24)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.06, 0.09, 0.90)
	style.border_width_left = 4
	style.border_color = Color("df4848")
	style.content_margin_left = 20
	style.content_margin_right = 24
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	var label := Label.new()
	var status := "LIBERTY CITY IMPORTÉE" if map_loaded else "ZONE DE TEST · CARTE GTA III NON IMPORTÉE"
	label.text = "WEB / LIBERTY   —   PROTOTYPE VR\n\n%s\n\nZQSD / WASD : marcher   ·   Maj : courir\nEspace : sauter   ·   R : retour au départ\nClic : caméra souris   ·   Échap : libérer la souris\n\nQuest 3 : stick G / stick D · A : saut · B : retour" % status
	label.add_theme_font_size_override("font_size", 17)
	panel.add_child(label)
