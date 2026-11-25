class_name PhoneCallEffect
extends Effect
## Schedules an incoming PhoneCallDef after [member delay] seconds (rings once the player is free).

@export var call_id: StringName
@export var delay := 0.0


func _apply(_ctx: ActionContext) -> void:
	Narrative.phone.schedule_call(call_id, delay)
