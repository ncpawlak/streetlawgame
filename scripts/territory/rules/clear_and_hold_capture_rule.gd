class_name ClearAndHoldCaptureRule
extends CaptureRule
## Legacy rule: kill every defender in the district, then stay inside on foot until the bar fills.

@export var capture_time := 8.0


func can_capture(district: District, gang_id: StringName) -> bool:
	return district.owner_gang != gang_id and district.defenders_remaining() == 0


func is_active(district: District) -> bool:
	return district.state.capture_progress > 0.0 or Turf.current_district_id == district.district_id


func tick(district: District, delta: float) -> void:
	var player := GameState.player
	var state := district.state
	var contesting := player != null and player.is_on_foot() \
		and district.contains_point(player.global_position) and can_capture(district, GameState.PLAYER_GANG)
	if contesting:
		state.capture_progress = minf(1.0, state.capture_progress + delta / capture_time)
		if state.capture_progress >= 1.0:
			district.complete_capture(GameState.PLAYER_GANG)
	else:
		state.capture_progress = maxf(0.0, state.capture_progress - delta / (capture_time * 2.0))


func status_text(district: District) -> String:
	var defenders := district.defenders_remaining()
	if defenders > 0:
		return "%d defenders left" % defenders
	return "Turf is open - hold it on foot to take over!"
