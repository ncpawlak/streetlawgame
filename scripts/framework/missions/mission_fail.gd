class_name MissionFail
extends Resource
## A rule that fails a mission (on [MissionDef].fail_conditions) or a single step
## (on [MissionStep].fail_conditions). Override _check (polled every physics frame) and/or _handle
## (mission events). Return the failure text, or "" while the rule holds.

@export var reason := "Mission failed."


func check(run: MissionRun, delta: float) -> String:
	return reason if _check(run, delta) else ""


func handle(event: Dictionary, run: MissionRun) -> String:
	return reason if _handle(event, run) else ""


## Fresh per-run state (rules with timers keep state on themselves).
func clone() -> MissionFail:
	return duplicate()


func _check(_run: MissionRun, _delta: float) -> bool:
	return false


func _handle(_event: Dictionary, _run: MissionRun) -> bool:
	return false
