class_name Cop
extends GangMember
## A responding police officer. Fights like a rival (shared GangMember AI) but searches around the
## player's last known position and can report whether it sees the player.

## Uniform tint for the SWAT model.
const UNIFORM := Color(0.1, 0.18, 0.45)

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
	# Police uniform on the SWAT model instead of the gang look GangMember builds.
	remove_child(visual)
	visual.free()
	visual = CharacterVisual.create(&"cop", randi())
	visual.set_tint(UNIFORM)
	visual.set_weapon(current_weapon())
	add_child(visual)


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
