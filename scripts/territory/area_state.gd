class_name AreaState
extends RefCounted
## Runtime state of one area. [member owner] is a gang only while it holds every district of the area.

var id: StringName
var owner: StringName = &"none"


func _init(area_id: StringName = &"", owner_gang: StringName = &"none") -> void:
	id = area_id
	owner = owner_gang


func to_dict() -> Dictionary:
	return {"id": String(id), "owner": String(owner)}


static func from_dict(data: Dictionary) -> AreaState:
	return AreaState.new(StringName(data.get("id", "")), StringName(data.get("owner", "none")))
