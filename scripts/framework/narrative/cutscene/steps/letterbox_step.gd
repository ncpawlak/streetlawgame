class_name LetterboxStep
extends CutsceneStep
## Slides the cinematic bars in (1) or out (0). CutsceneDef.letterbox already adds them for the whole
## scene; use this for mid-scene changes.

@export_range(0.0, 1.0) var amount := 1.0
@export var duration := 0.5


func begin(_director: CutsceneDirector, state: Dictionary) -> void:
	Narrative.ui.set_letterbox(amount, duration)
	state["t"] = 0.0


func tick(_director: CutsceneDirector, state: Dictionary, delta: float) -> bool:
	state["t"] += delta
	return state["t"] >= duration


func skip(_director: CutsceneDirector, _state: Dictionary) -> void:
	Narrative.ui.set_letterbox(amount, 0.0)
