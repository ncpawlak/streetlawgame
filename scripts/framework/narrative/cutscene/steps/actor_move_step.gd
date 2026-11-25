class_name ActorMoveStep
extends CutsceneStep
## Walks / runs an actor in a straight line to a marker (locomotion animation follows the speed).
## Skipping teleports it there.

@export var actor: StringName = &"player"
@export var marker: StringName
## Metres per second; 0 = walk (1.6) or run (4.5) from [member run].
@export var speed := 0.0
@export var run := false
## Turn to the marker's yaw on arrival.
@export var face_end := false


func begin(director: CutsceneDirector, state: Dictionary) -> void:
	var node := director.resolve_3d(actor)
	var spot := director.resolve_3d(marker)
	if node == null or spot == null:
		push_warning("ActorMoveStep: missing actor '%s' or marker '%s'" % [actor, marker])
		return
	director.claim(node)
	director.moving[node.get_instance_id()] = true
	state["node"] = node
	state["to"] = spot.global_position
	state["yaw"] = spot.global_rotation.y


func tick(director: CutsceneDirector, state: Dictionary, delta: float) -> bool:
	if not state.has("node") or not is_instance_valid(state["node"]):
		return true
	var node: Node3D = state["node"]
	var to: Vector3 = state["to"]
	var pace := speed if speed > 0.0 else (4.5 if run else 1.6)
	var offset := to - node.global_position
	var visual := Narrative.visual_of(node)
	if offset.length() <= pace * delta or offset.length() < 0.02:
		_arrive(director, state)
		return true
	var direction := offset.normalized()
	node.global_position += direction * pace * delta
	Narrative.face_toward(node, to)
	if visual != null:
		visual.update_motion(direction * pace, delta)
	return false


func skip(director: CutsceneDirector, state: Dictionary) -> void:
	if state.is_empty():
		begin(director, state)
	if state.has("node") and is_instance_valid(state["node"]):
		_arrive(director, state)


func validate() -> PackedStringArray:
	return PackedStringArray() if actor != &"" and marker != &"" else PackedStringArray(["needs actor and marker"])


func _arrive(director: CutsceneDirector, state: Dictionary) -> void:
	var node: Node3D = state["node"]
	node.global_position = state["to"]
	if face_end:
		node.global_rotation.y = state["yaw"]
	director.moving.erase(node.get_instance_id())
