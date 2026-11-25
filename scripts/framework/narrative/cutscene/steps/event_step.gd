class_name EventStep
extends CutsceneStep
## Fires a story event (Narrative.emit_event / EventBus.story_event) and applies effects at this
## point of the scene, e.g. set a flag, add a lead, start a phone call.

@export var event: StringName
@export var payload: Dictionary = {}
@export var effects: Array[Effect] = []
## Still fire when the scene is skipped before reaching this step (end-state guarantee).
@export var fire_on_skip := true


func begin(director: CutsceneDirector, state: Dictionary) -> void:
	state["fired"] = true
	if event != &"":
		director.emit_event(event, payload)
	Effect.apply_all(effects, director.ctx)


func skip(director: CutsceneDirector, state: Dictionary) -> void:
	if state.is_empty() and fire_on_skip:
		begin(director, state)


func validate() -> PackedStringArray:
	return PackedStringArray() if event != &"" or not effects.is_empty() else PackedStringArray(["needs an event or effects"])
