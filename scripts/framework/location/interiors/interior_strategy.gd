class_name InteriorStrategy
extends Resource
## How "inside" works for a location (strategy). The base class is a door-only interior: nothing to
## enter, occupants are dealt with through the door. Subclass to stream rooms, seamless shells, etc.
## Presets live in data/interiors/<id>.tres.

const TYPE := &"interiors"


func is_enterable() -> bool:
	return false


## Moves [param actor] inside. Returns false when it can't.
func enter(_location: Location, _actor: Node3D) -> bool:
	return false


## Moves [param actor] back out (to the door) and unloads whatever [method enter] built.
func exit(location: Location, actor: Node3D) -> void:
	if actor != null:
		actor.global_position = location.outside_point()


func is_loaded(location: Location) -> bool:
	return location.interior_root != null
