class_name VanTire
extends StaticBody3D
## One tire of the [ArmoredVan]. Its own physics body so hitscan rays, explosions and the like hit
## each tire individually; it goes flat when its health runs out.

signal popped(tire: VanTire)

@export var max_health := 45.0
@export var radius := 0.5
@export var width := 0.4

## &"front_left", &"front_right", &"rear_left" or &"rear_right".
var tire_id: StringName
var health := 0.0
var van: Node

var _visual: MeshInstance3D
var _material: StandardMaterial3D


func _ready() -> void:
	add_to_group("van_tires")
	collision_layer = 8
	collision_mask = 0
	health = max_health
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	# A little bigger than the visual so it's fair to hit from a moving car.
	cylinder.radius = radius + 0.05
	cylinder.height = width + 0.1
	shape.shape = cylinder
	shape.rotation.z = PI / 2.0
	add_child(shape)
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = width
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.06, 0.06, 0.06)
	mesh.material = _material
	_visual = MeshInstance3D.new()
	_visual.mesh = mesh
	_visual.rotation.z = PI / 2.0
	add_child(_visual)
	var hub := MeshInstance3D.new()
	var hub_mesh := CylinderMesh.new()
	hub_mesh.top_radius = radius * 0.45
	hub_mesh.bottom_radius = radius * 0.45
	hub_mesh.height = width + 0.02
	var hub_material := StandardMaterial3D.new()
	hub_material.albedo_color = Color(0.55, 0.55, 0.58)
	hub_mesh.material = hub_material
	hub.mesh = hub_mesh
	_visual.add_child(hub)


func is_flat() -> bool:
	return health <= 0.0


func take_damage(amount: float, source: Node = null) -> void:
	# Guards' and cops' stray rounds don't count; only the crew pops tires.
	if is_flat() or amount <= 0.0 or source is GangMember:
		return
	health = maxf(0.0, health - amount)
	if van != null and van.has_method("notify_attacked"):
		van.notify_attacked(source)
	if is_flat():
		_go_flat()
		popped.emit(self)
	else:
		_material.emission_enabled = true
		_material.emission = Color(1.0, 0.6, 0.3)
		get_tree().create_timer(0.08, false).timeout.connect(func() -> void: _material.emission_enabled = false)


## Pops the tire immediately (tests and scripted moments).
func pop() -> void:
	take_damage(health + 1.0)


func _go_flat() -> void:
	# The visual is rolled 90 degrees, so its local X is world up.
	_visual.scale = Vector3(0.6, 1.0, 1.0)
	_visual.position.y = -radius * 0.2
	_material.albedo_color = Color(0.12, 0.1, 0.09)
