class_name TimeLimitFail
extends MissionFail
## Fails when the whole mission has run longer than [member seconds]. (Per-step limits use
## MissionStep.time_limit.)

@export var seconds := 120.0


func _init() -> void:
	reason = "You ran out of time."


func _check(run: MissionRun, _delta: float) -> bool:
	return run.elapsed >= seconds
