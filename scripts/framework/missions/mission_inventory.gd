class_name MissionInventory
extends RefCounted
## Key items picked up during missions (notes, keys, packages). Item ids are free-form StringNames;
## there is no player item inventory on main yet, so missions keep their own.

signal changed(item_id: StringName, count: int)

var _counts: Dictionary = {}


func add(item_id: StringName, count := 1) -> void:
	if count == 0:
		return
	var total := maxi(0, count_of(item_id) + count)
	if total == 0:
		_counts.erase(item_id)
	else:
		_counts[item_id] = total
	changed.emit(item_id, total)


func remove(item_id: StringName, count := 1) -> bool:
	if count_of(item_id) < count:
		return false
	add(item_id, -count)
	return true


func count_of(item_id: StringName) -> int:
	return int(_counts.get(item_id, 0))


func has(item_id: StringName, count := 1) -> bool:
	return count_of(item_id) >= count


func items() -> Dictionary:
	return _counts.duplicate()


func clear() -> void:
	_counts.clear()


func to_dict() -> Dictionary:
	return {"items": _counts.duplicate()}


func from_dict(data: Dictionary) -> void:
	_counts.clear()
	var items_data: Dictionary = data.get("items", {})
	for key in items_data:
		_counts[StringName(key)] = int(items_data[key])
