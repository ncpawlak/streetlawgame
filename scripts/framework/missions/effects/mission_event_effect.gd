class_name MissionEventEffect
extends Effect
## Posts a mission event (a WaitStep can wait for it). [member data] is merged into the event.

@export var event_type: StringName
@export var data: Dictionary = {}


func _apply(_ctx: ActionContext) -> void:
	Missions.post_event(event_type, data.duplicate())
