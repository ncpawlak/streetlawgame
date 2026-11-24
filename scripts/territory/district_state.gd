class_name DistrictState
extends RefCounted
## Runtime state of one district. Plain data so it serializes to a Dictionary for save/load.

var id: StringName
var owner: StringName = &"none"
var capture_progress := 0.0
## Scratch data owned by the district's capture rule (e.g. claimant gang, claim in progress).
var capture := {}
## Reserved for safehouse management (upgrades, assigned crew). Not interpreted by the territory system.
var safehouse := {}


func _init(district_id: StringName = &"", owner_gang: StringName = &"none") -> void:
	id = district_id
	owner = owner_gang


func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"owner": String(owner),
		"capture_progress": capture_progress,
		"capture": capture.duplicate(true),
		"safehouse": safehouse.duplicate(true),
	}


static func from_dict(data: Dictionary) -> DistrictState:
	var state := DistrictState.new(StringName(data.get("id", "")), StringName(data.get("owner", "none")))
	state.capture_progress = float(data.get("capture_progress", 0.0))
	state.capture = (data.get("capture", {}) as Dictionary).duplicate(true)
	state.safehouse = (data.get("safehouse", {}) as Dictionary).duplicate(true)
	return state
