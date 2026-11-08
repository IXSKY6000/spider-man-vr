extends Node3D
## Detailed patch and four distant tiles; world-space phase remains stationary.
## Five draw calls, no reflection viewport or per-eye screen-space copy.

const WATER_SHADER = preload("res://shaders/water.gdshader")
const PATCH_SIZE := 192.0
const SEGMENTS := 96
var water_size := 12000.0
var wind_strength := 0.75
var surface_roughness := 0.13
var target: Node3D
var surface: Node3D
var patch_size: float

func _ready() -> void:
	name = "Water"
	water_size = maxf(water_size, 8.0)
	patch_size = minf(PATCH_SIZE, water_size)
	surface = Node3D.new()
	surface.name = "Surface"
	add_child(surface)
	var near_material := ShaderMaterial.new()
	near_material.shader = WATER_SHADER
	near_material.set_shader_parameter("ripple_normal", preload("res://assets/water/ripples.tres"))
	near_material.set_shader_parameter("patch_half_size", patch_size * 0.5)
	near_material.set_shader_parameter("wind_strength", wind_strength)
	near_material.set_shader_parameter("surface_roughness", surface_roughness)
	_tile("NearWater", Vector2(patch_size, patch_size), Vector2.ZERO, SEGMENTS - 1, near_material)
	if water_size > patch_size:
		var far_material := near_material.duplicate() as ShaderMaterial
		far_material.set_shader_parameter("displace_vertices", false)
		var strip := (water_size - patch_size) * 0.5
		var offset := patch_size * 0.5 + strip * 0.5
		for side in [-1.0, 1.0]:
			_tile("FarNorthSouth", Vector2(water_size, strip), Vector2(0, side * offset), 0, far_material)
			_tile("FarEastWest", Vector2(strip, patch_size), Vector2(side * offset, 0), 0, far_material)

func _tile(label: String, size: Vector2, center: Vector2, subdivisions: int, material: ShaderMaterial) -> void:
	var instance := MeshInstance3D.new()
	instance.name = label
	var plane := PlaneMesh.new()
	plane.size = size
	plane.subdivide_width = subdivisions
	plane.subdivide_depth = subdivisions
	instance.mesh = plane
	instance.position = Vector3(center.x, 0, center.y)
	instance.material_override = material
	instance.extra_cull_margin = 0.6
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	surface.add_child(instance)

func _process(_delta: float) -> void:
	if is_instance_valid(target):
		var local_target := to_local(target.global_position)
		var cell_size := patch_size / SEGMENTS
		surface.position.x = snappedf(local_target.x, cell_size)
		surface.position.z = snappedf(local_target.z, cell_size)
