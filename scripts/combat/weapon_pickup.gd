class_name WeaponPickup
extends Area3D
## Spinning weapon/ammo pickup. Gives the weapon (or just ammo if already owned) to the player.

@export var weapon: WeaponData
@export var ammo := 0
## Seconds before the pickup despawns. 0 keeps it forever.
@export var lifetime := 0.0

var _visual: Node3D


static func create(weapon_data: WeaponData, ammo_amount: int, position: Vector3, despawn_after := 0.0) -> WeaponPickup:
	var pickup := WeaponPickup.new()
	pickup.weapon = weapon_data
	pickup.ammo = ammo_amount
	pickup.lifetime = despawn_after
	pickup.position = position
	return pickup


func _ready() -> void:
	add_to_group("pickups")
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var sphere := SphereShape3D.new()
	sphere.radius = 1.0
	var shape := CollisionShape3D.new()
	shape.shape = sphere
	shape.position.y = 0.6
	add_child(shape)
	_build_visual()
	body_entered.connect(_on_body_entered)
	if lifetime > 0.0:
		get_tree().create_timer(lifetime, false).timeout.connect(queue_free)


func _process(delta: float) -> void:
	_visual.rotate_y(2.0 * delta)


func _on_body_entered(body: Node3D) -> void:
	var player := body as Player
	if player == null or weapon == null:
		return
	player.weapons.add_weapon(weapon, ammo)
	EventBus.notify.emit("Picked up %s%s" % [weapon.display_name, " (+%d ammo)" % ammo if weapon.uses_ammo() else ""])
	queue_free()


func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.position.y = 0.6
	add_child(_visual)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.15, 0.15, 0.15)
	material.emission_enabled = true
	material.emission = weapon.tracer_color if weapon else Color.WHITE
	material.emission_energy_multiplier = 0.6
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 0.25, 0.3 + clampf((weapon.max_range if weapon else 30.0) / 150.0, 0.0, 0.7))
	box.material = material
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	_visual.add_child(mesh)
	var light := OmniLight3D.new()
	light.light_color = material.emission
	light.omni_range = 2.5
	light.light_energy = 0.8
	_visual.add_child(light)
