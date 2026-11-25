class_name TargetDestroyedFail
extends MissionFail
## Fails when a protected target is gone: the node tagged [member target_tag] (or held in run var
## [member target_var]) was freed, wrecked or killed after it had been seen. "Don't wreck the car."

@export var target_tag: StringName
@export var target_var: StringName

var _seen := false


func _init() -> void:
	reason = "The target was destroyed."


func _check(run: MissionRun, _delta: float) -> bool:
	var target: Variant = null
	if target_tag != &"":
		target = Missions.first_tagged(target_tag)
	elif target_var != &"":
		target = run.ctx.vars.get(target_var)
	if target == null or not is_instance_valid(target):
		return _seen
	_seen = true
	var node := target as Node
	if node.is_queued_for_deletion():
		return true
	if node.has_method("is_wrecked") and node.call("is_wrecked"):
		return true
	return node.has_method("is_alive") and not node.call("is_alive")
