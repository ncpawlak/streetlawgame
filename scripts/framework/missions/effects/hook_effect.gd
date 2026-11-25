class_name HookEffect
extends Effect
## Fires a hook (cutscene, phone call, dialogue...) without waiting for it. See HookStep to wait.

@export var kind: StringName = &"cutscene"
@export var hook_id: StringName


func _apply(ctx: ActionContext) -> void:
	Missions.request_hook(kind, hook_id, ctx)
