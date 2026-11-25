class_name VanGuard
extends GangMember
## Armoured-transport guard. Bails out of the stopped [ArmoredVan] and fights to protect it.

const WEAPONS: Array[StringName] = [&"smg", &"shotgun", &"pistol"]


func _init() -> void:
	gang_id = &"armored_guard"
	max_health = 90.0
	move_speed = 3.0
	aggro_range = 40.0
	attack_range = 18.0
	alerted_range = 70.0
	alert_duration = 30.0
	wander_radius = 3.0
	damage_scale = 0.35
	drop_chance = 0.5


func _ready() -> void:
	if weapon_id == &"":
		weapon_id = WEAPONS.pick_random()
	super._ready()
	add_to_group("van_guards")
	_body_material.albedo_color = Color(0.42, 0.4, 0.3)
	var vest_mesh := BoxMesh.new()
	vest_mesh.size = Vector3(0.86, 0.6, 0.86)
	vest_mesh.material = _material(Color(0.15, 0.15, 0.14))
	var vest := MeshInstance3D.new()
	vest.mesh = vest_mesh
	vest.position.y = 1.15
	add_child(vest)
