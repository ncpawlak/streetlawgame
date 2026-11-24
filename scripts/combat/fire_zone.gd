class_name FireZone
extends Area3D
## Patch of fire (molotovs, burning wrecks) that hurts anyone standing in it, including vehicles.

const TICK := 0.25

var radius := 3.0
var duration := 6.0
var damage_per_second := 15.0
var source: Node

var _tick_left := 0.0
var _light: OmniLight3D


static func spawn(context: Node, at: Vector3, fire_radius: float, lifetime: float, dps: float, fire_source: Node) -> FireZone:
	var fire := FireZone.new()
	fire.radius = fire_radius
	fire.duration = lifetime
	fire.damage_per_second = dps
	fire.source = fire_source
	fire.position = at
	var scene := context.get_tree().current_scene
	(scene if scene else context.get_tree().root).add_child(fire)
	return fire


func _ready() -> void:
	add_to_group("fires")
	collision_layer = 0
	collision_mask = Explosion.DAMAGEABLE_LAYERS
	monitorable = false
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = 2.5
	var shape := CollisionShape3D.new()
	shape.shape = cylinder
	shape.position.y = 1.0
	add_child(shape)
	_build_visual()
	get_tree().create_timer(duration, false).timeout.connect(queue_free)


func _physics_process(delta: float) -> void:
	_tick_left -= delta
	if _light:
		_light.light_energy = randf_range(1.5, 3.0)
	if _tick_left > 0.0:
		return
	_tick_left = TICK
	for body in get_overlapping_bodies():
		if body.has_method("take_damage"):
			body.take_damage(damage_per_second * TICK, source)


func _build_visual() -> void:
	var flames := CPUParticles3D.new()
	flames.amount = int(clampf(radius * 12.0, 12.0, 60.0))
	flames.lifetime = 0.7
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flames.emission_sphere_radius = radius * 0.8
	flames.direction = Vector3.UP
	flames.spread = 15.0
	flames.gravity = Vector3(0.0, 2.0, 0.0)
	flames.initial_velocity_min = 0.5
	flames.initial_velocity_max = 1.5
	flames.scale_amount_min = 0.6
	flames.scale_amount_max = 1.2
	flames.color = Color(1.0, 0.5, 0.1)
	flames.mesh = FireZone.flame_mesh()
	flames.position.y = 0.3
	add_child(flames)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.5, 0.15)
	_light.omni_range = radius * 3.0
	_light.position.y = 1.0
	add_child(_light)


## Small unshaded quad tinted by particle color, shared by fire effects.
static func flame_mesh() -> Mesh:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	quad.material = material
	return quad
