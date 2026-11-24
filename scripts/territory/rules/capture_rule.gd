class_name CaptureRule
extends ContentDef
## How a district changes hands. Stateless and shared between districts: per-district progress lives in
## [member DistrictState.capture_progress] and [member DistrictState.capture]. Subclass for new mechanics
## and point [member DistrictData.capture_rule_id] at the new resource.


## Called once when a district using this rule is ready.
func setup(_district: District) -> void:
	pass


## Whether [param gang_id] may currently start taking [param district].
func can_capture(district: District, gang_id: StringName) -> bool:
	return district.owner_gang != gang_id


## Starts a capture attempt by [param gang_id] (e.g. the player pressed "Take over"). Returns true if started.
func begin(_district: District, _gang_id: StringName, _actor: Node) -> bool:
	return false


## Whether the rule needs ticking (a capture is in progress or the player is around).
func is_active(district: District) -> bool:
	return district.state.capture_progress > 0.0


## Advances [member DistrictState.capture_progress]; calls [method District.complete_capture] when done.
func tick(_district: District, _delta: float) -> void:
	pass


## A one-line HUD hint for the player standing in the district.
func status_text(_district: District) -> String:
	return ""
