class_name SafehouseCaptureRule
extends CaptureRule
## Default rule: kill the safehouse guards, start the takeover at the door ([E] "Take over", which calls
## [method begin]), then hold the door until the
## claim completes. Leaving the claim radius makes progress drain; at zero the attempt is abandoned.

## Scales [member SafehouseData.claim_time].
@export var claim_time_scale := 1.0
## Progress drains this many times slower than it builds.
@export var decay_ratio := 0.5


func can_capture(district: District, gang_id: StringName) -> bool:
	return district.owner_gang != gang_id and district.safehouse != null and district.guards_remaining() == 0


func begin(district: District, gang_id: StringName, _actor: Node) -> bool:
	if is_claiming(district) or not can_capture(district, gang_id):
		return false
	district.state.capture["gang"] = String(gang_id)
	EventBus.safehouse_claim_started.emit(district.district_id, gang_id)
	return true


func is_claiming(district: District) -> bool:
	return district.state.capture.has("gang")


func claimant(district: District) -> StringName:
	return StringName(district.state.capture.get("gang", ""))


func is_active(district: District) -> bool:
	return is_claiming(district) or district.state.capture_progress > 0.0


func tick(district: District, delta: float) -> void:
	var safehouse := district.safehouse
	if safehouse == null:
		return
	if not is_claiming(district):
		return
	var gang := claimant(district)
	var claim_time := maxf(0.05, safehouse.data.claim_time * claim_time_scale)
	var state := district.state
	if gang == district.owner_gang:
		state.capture.clear()
		state.capture_progress = 0.0
	elif _claimant_present(district, gang) and district.guards_remaining() == 0:
		state.capture_progress = minf(1.0, state.capture_progress + delta / claim_time)
		if state.capture_progress >= 1.0:
			district.complete_capture(gang)
	else:
		state.capture_progress = maxf(0.0, state.capture_progress - delta * decay_ratio / claim_time)
		if state.capture_progress <= 0.0:
			state.capture.clear()


func status_text(district: District) -> String:
	if district.safehouse == null:
		return ""
	var guards := district.guards_remaining()
	if guards > 0:
		return "Safehouse guarded by %d - take them out" % guards
	if is_claiming(district):
		return "Taking over the safehouse - hold the door!"
	return "Safehouse is open - [E] at the door to take over"


## Rival (AI) claimants are driven by whoever started them (counter-attacks), so only the player is checked.
func _claimant_present(district: District, gang: StringName) -> bool:
	if gang != GameState.PLAYER_GANG:
		return true
	return _player_at_door(district)


func _player_at_door(district: District) -> bool:
	var player := GameState.player
	if player == null or not player.is_on_foot():
		return false
	var offset := player.global_position - district.safehouse.door_position()
	offset.y = 0.0
	return offset.length() <= district.safehouse.data.claim_radius
