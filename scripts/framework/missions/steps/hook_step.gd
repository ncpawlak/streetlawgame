class_name HookStep
extends MissionStep
## Hand off to another system by string id: plays a cutscene, starts a phone call, or any custom
## hook kind (see MissionService.register_hook). Waits for finish_hook(kind, hook_id) unless
## [member wait] is off. The outcome is stored in run var [member store_outcome_as].

@export var kind: StringName = MissionService.HOOK_CUTSCENE
@export var hook_id: StringName
@export var wait := true
@export var store_outcome_as: StringName = &"hook_outcome"


func _begin() -> void:
	Missions.request_hook(kind, hook_id, run.ctx)
	if not wait:
		complete()


func _handle(event: Dictionary) -> void:
	if event["type"] == &"hook_done" and event.get("kind") == kind and event.get("hook_id") == hook_id:
		run.ctx.vars[store_outcome_as] = event.get("outcome", &"done")
		complete()
