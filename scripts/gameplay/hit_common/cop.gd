class_name Cop
extends GangMember
## A responding police officer. Fights like a rival (shared GangMember AI) but searches around the
## player's last known position and can report whether it sees the player.

## How far a cop can spot the player with a clear line of sight.
@export var sight_range := 35.0


func _init() -> void:
	gang_id = &"police"
	weapon_id = &"pistol"
	max_health = 70.0
	aggro_range = 30.0
	alerted_range = 45.0
	wander_radius = 8.0
	move_speed = 4.5
	drop_chance = 0.3


func _ready() -> void:
	super._ready()
	add_to_group("cops")
	_body_material.albedo_color = Color(0.1, 0.18, 0.45)
	var hat_mesh := CylinderMesh.new()
	hat_mesh.top_radius = 0.32
	hat_mesh.bottom_radius = 0.36
	hat_mesh.height = 0.18
	hat_mesh.material = _material(Color(0.05, 0.08, 0.2))
	var hat := MeshInstance3D.new()
	hat.mesh = hat_mesh
	hat.position.y = 1.85
	add_child(hat)


## Moves the cop's search area (it wanders around [param point] when it can't see the player).
func search_at(point: Vector3) -> void:
	_home = point
	_wander_target = point


## Clear line of sight to [param target] within [member sight_range].
func can_see(target: Node3D) -> bool:
	if not is_alive() or target == null or not is_inside_tree():
		return false
	var eye := global_position + Vector3(0.0, 1.6, 0.0)
	var aim := target.global_position + Vector3(0.0, 1.0, 0.0)
	if eye.distance_to(aim) > sight_range:
		return false
	var query := PhysicsRayQueryParameters3D.create(eye, aim, 1)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()
