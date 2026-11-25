class_name WaitStep
extends MissionStep
## Waits for whichever is configured first: a mission event ([member event_type] whose fields match
## [member event_match]), a GameState flag reaching [member flag_value], all [member conditions]
## holding, or [member duration] seconds passing.

@export var event_type: StringName
## Event fields that must match (compared as strings), e.g. {"unlock_id": "pedro_trust"}.
@export var event_match: Dictionary = {}
@export var flag: StringName
@export var flag_value: Variant = true
@export var conditions: Array[Condition] = []
@export var duration := 0.0


func _begin() -> void:
	_check()


func _tick(_delta: float) -> void:
	if duration > 0.0 and elapsed >= duration:
		complete()
		return
	_check()


func _handle(event: Dictionary) -> void:
	if event_type != &"" and event["type"] == event_type and matches(event, event_match):
		complete()


func _check() -> void:
	if state != State.ACTIVE:
		return
	if flag != &"" and GameState.get_flag(flag, null) == flag_value:
		complete()
	elif not conditions.is_empty() and Condition.all_met(conditions, run.ctx):
		complete()


static func matches(event: Dictionary, wanted: Dictionary) -> bool:
	for key in wanted:
		if str(event.get(key)) != str(wanted[key]):
			return false
	return true
