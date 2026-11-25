class_name FadeStep
extends CutsceneStep
## Fades the screen to [member to] opacity of [member color] (1 = fade out, 0 = fade in).

@export_range(0.0, 1.0) var to := 1.0
@export var color := Color.BLACK
@export var duration := 0.75


func begin(_director: CutsceneDirector, state: Dictionary) -> void:
	Narrative.ui.fade_to(to, duration, color)
	state["t"] = 0.0


func tick(_director: CutsceneDirector, state: Dictionary, delta: float) -> bool:
	state["t"] += delta
	return state["t"] >= duration


func skip(_director: CutsceneDirector, _state: Dictionary) -> void:
	Narrative.ui.fade_to(to, 0.0, color)
