class_name WaitStep
extends CutsceneStep
## Holds for [member seconds].

@export var seconds := 1.0


func begin(_director: CutsceneDirector, state: Dictionary) -> void:
	state["t"] = 0.0


func tick(_director: CutsceneDirector, state: Dictionary, delta: float) -> bool:
	state["t"] += delta
	return state["t"] >= seconds
