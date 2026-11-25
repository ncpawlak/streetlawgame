class_name CaptureZone
extends Node3D
## The highlighted intersection: a glowing ring, a tinted floor disc and a faint light wall so it reads from a
## distance. [method contains] is the "are you holding it" check (on foot only, checked by the driver).

@export var radius := 10.0
@export var wall_height := 3.0

var _ring_material: StandardMaterial3D
var _disc_material: StandardMaterial3D
var _wall_material: StandardMaterial3D
var _light: OmniLight3D
var _color := Color.WHITE
var _pulse := 0.0
var _pulsing := false


func _ready() -> void:
	_build()
	set_color(Color(0.85, 0.15, 0.15))


func contains(point: Vector3) -> bool:
	var offset := point - global_position
	return Vector2(offset.x, offset.z).length() <= radius and absf(offset.y) < 4.0


## The zone glows in the color of whoever is winning it; [param pulsing] while someone is capturing.
func set_color(color: Color, pulsing := false) -> void:
	_color = color
	_pulsing = pulsing
	_disc_material.albedo_color = Color(color, 0.12)
	_wall_material.albedo_color = Color(color, 0.12)
	_light.light_color = color
	_apply_ring()


func _process(delta: float) -> void:
	_pulse = fmod(_pulse + delta * 3.0, TAU) if _pulsing else 0.0
	_apply_ring()


func _apply_ring() -> void:
	var glow := 2.5 + (sin(_pulse) * 1.5 if _pulsing else 0.0)
	_ring_material.albedo_color = _color
	_ring_material.emission = _color
	_ring_material.emission_energy_multiplier = glow


func _build() -> void:
	_ring_material = StandardMaterial3D.new()
	_ring_material.emission_enabled = true
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = radius - 0.35
	ring_mesh.outer_radius = radius
	ring_mesh.rings = 96
	ring_mesh.material = _ring_material
	_add_mesh(ring_mesh, Vector3(0.0, 0.12, 0.0))

	_disc_material = _transparent_material()
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = radius
	disc_mesh.bottom_radius = radius
	disc_mesh.height = 0.02
	disc_mesh.radial_segments = 64
	disc_mesh.material = _disc_material
	_add_mesh(disc_mesh, Vector3(0.0, 0.11, 0.0))

	_wall_material = _transparent_material()
	_wall_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Fade out close to the camera so standing in the zone doesn't tint the whole screen.
	_wall_material.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	_wall_material.distance_fade_min_distance = 6.0
	_wall_material.distance_fade_max_distance = 18.0
	var wall_mesh := CylinderMesh.new()
	wall_mesh.top_radius = radius
	wall_mesh.bottom_radius = radius
	wall_mesh.height = wall_height
	wall_mesh.radial_segments = 64
	wall_mesh.cap_top = false
	wall_mesh.cap_bottom = false
	wall_mesh.material = _wall_material
	_add_mesh(wall_mesh, Vector3(0.0, wall_height * 0.5, 0.0))

	_light = OmniLight3D.new()
	_light.position = Vector3(0.0, 4.0, 0.0)
	_light.omni_range = radius * 1.6
	_light.light_energy = 0.6
	add_child(_light)


func _transparent_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _add_mesh(mesh: Mesh, offset: Vector3) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = offset
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
