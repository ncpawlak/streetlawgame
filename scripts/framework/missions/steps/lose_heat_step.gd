class_name LoseHeatStep
extends MissionStep
## Lose the heat: completes once Missions.heat is 0 for [member hold_time] seconds. With
## [member require_heat_first] it waits for heat to appear before counting (scripted shootouts).

@export var hold_time := 0.0
@export var require_heat_first := false

var _cool_for := 0.0
var _had_heat := false


func _begin() -> void:
	_cool_for = 0.0
	_had_heat = Missions.heat.is_hot()
	_tick(0.0)


func _tick(delta: float) -> void:
	if state != State.ACTIVE:
		return
	if Missions.heat.is_hot():
		_had_heat = true
		_cool_for = 0.0
		return
	if require_heat_first and not _had_heat:
		return
	_cool_for += delta
	if _cool_for >= hold_time:
		complete()


func _progress() -> String:
	var stars := Missions.heat.stars()
	return "heat %s" % "*".repeat(stars) if stars > 0 else ""
