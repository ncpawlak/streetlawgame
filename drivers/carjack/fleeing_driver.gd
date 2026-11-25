class_name FleeingDriver
extends Node3D
## The jacked car's owner: bails out, runs away from the car and disappears (to call the cops).

@export var run_speed := 6.0
@export var lifetime := 6.0

var direction := Vector3.RIGHT
## Animated civilian body (same model as the person who was sitting in the car).
var visual: CharacterVisual
var _variant := -1


static func spawn(parent: Node, at: Vector3, away: Vector3, variant: int = -1) -> FleeingDriver:
	var runner := FleeingDriver.new()
	runner.direction = Vector3(away.x, 0.0, away.z).normalized()
	runner._variant = variant
	parent.add_child(runner)
	runner.global_position = _ground_at(runner, at)
	return runner


## Drops [param at] onto the ground below it (the model stands on its origin).
static func _ground_at(node: Node3D, at: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * 4.0, 1)
	var hit := node.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position if not hit.is_empty() else Vector3(at.x, at.y - 0.8, at.z)


func _ready() -> void:
	add_to_group("fleeing_drivers")
	visual = CharacterVisual.create(&"civilian", _variant)
	add_child(visual)
	# Dragged out of the seat: flinch first, then run.
	visual.hit()
	if direction.length_squared() > 0.0:
		look_at(global_position + direction, Vector3.UP)


func _process(delta: float) -> void:
	global_position += direction * run_speed * delta
	visual.update_motion(direction * run_speed, delta)
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()