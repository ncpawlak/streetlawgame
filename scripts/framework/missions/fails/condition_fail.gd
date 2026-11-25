class_name ConditionFail
extends MissionFail
## Fails while all [member conditions] are met (e.g. "flag alarm_raised set", "heat above 3 stars").

@export var conditions: Array[Condition] = []


func _check(run: MissionRun, _delta: float) -> bool:
	return not conditions.is_empty() and Condition.all_met(conditions, run.ctx)
