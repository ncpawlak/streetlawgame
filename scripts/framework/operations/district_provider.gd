class_name DistrictProvider
extends RefCounted
## Answers "who owns which district" for the operations simulation. This base is a plain
## dictionary (used by tests and as an offline fallback); WorldDistrictProvider asks the live game.

var _owners := {}
var _names := {}


func owner_of(district_id: StringName) -> StringName:
	return _owners.get(district_id, &"none")


func display_name(district_id: StringName) -> String:
	return _names.get(district_id, String(district_id).capitalize())


func owned_districts(gang_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for district_id: StringName in all_districts():
		if owner_of(district_id) == gang_id:
			result.append(district_id)
	return result


func all_districts() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_owners.keys())
	ids.sort()
	return ids


func set_owner(district_id: StringName, gang_id: StringName, district_name: String = "") -> void:
	_owners[district_id] = gang_id
	if not district_name.is_empty():
		_names[district_id] = district_name
