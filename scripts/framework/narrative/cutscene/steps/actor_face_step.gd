class_name ActorFaceStep
extends CutsceneStep
## Turns an actor toward another node, or to an absolute yaw, over [member duration].

@export var actor: StringName = &"player"
## Node to face; empty = use [member yaw_degrees].
@export var toward: StringName
@export var yaw_degrees := 0.0
@export var duration := 0.3


func begin(director: CutsceneDirector, state: Dictionary) -> void:
	var node := director.resolve_3d(actor)
	if node == null:
		return
	director.claim(node)
	state["node"] = node
	state["from"] = node.global_rotation.y
	state["to"] = _target_yaw(director, node)
	state["t"] = 0.0


func tick(_director: CutsceneDirector, state: Dictionary, delta: float) -> bool:
	if not state.has("node") or not is_instance_valid(state["node"]):
		return true
	state["t"] += delta
	var k := clampf(state["t"] / maxf(duration, 0.001), 0.0, 1.0)
	(state["node"] as Node3D).global_rotation.y = lerp_angle(state["from"], state["to"], k)
	return k >= 1.0


func skip(director: CutsceneDirector, state: Dictionary) -> void:
	if state.is_empty():
		begin(director, state)
	if state.has("node") and is_instance_valid(state["node"]):
		(state["node"] as Node3D).global_rotation.y = state["to"]


func _target_yaw(director: CutsceneDirector, node: Node3D) -> float:
	var other := director.resolve_3d(toward)
	if other == null:
		return deg_to_rad(yaw_degrees)
	var flat := other.global_position - node.global_position
	return atan2(-flat.x, -flat.z) if Vector2(flat.x, flat.z).length() > 0.01 else node.global_rotation.y
