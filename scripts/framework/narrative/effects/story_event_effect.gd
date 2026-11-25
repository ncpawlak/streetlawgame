class_name StoryEventEffect
extends Effect
## Fires a story event (EventBus.story_event), e.g. event &"lead_added" payload {"id": &"shooter_car"}.
## Missions, objectives and logs listen for these instead of polling flags.

@export var event: StringName
@export var payload: Dictionary = {}


func _apply(_ctx: ActionContext) -> void:
	Narrative.emit_event(event, payload)


func _describe(_ctx: ActionContext) -> String:
	return String(event)
