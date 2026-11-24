extends Node
## Autoload: the player gang's clout per district (0-100). Owned business sites grant clout to
## their district (Businesses.acquire / lose_site). Read it with [method clout_of]; gate content
## with CloutCondition. Influence levels and clout multipliers are a later step (#36).

const MAX_CLOUT := 100

var _clout := {}  # district_id -> int


func clout_of(district_id: StringName) -> int:
	return int(_clout.get(district_id, 0))


## Adds (or removes, if negative) clout, clamped to 0-100. Returns the new value.
func add(district_id: StringName, amount: int) -> int:
	return set_clout(district_id, clout_of(district_id) + amount)


func set_clout(district_id: StringName, value: int) -> int:
	if district_id == &"":
		return 0
	var previous := clout_of(district_id)
	var clamped := clampi(value, 0, MAX_CLOUT)
	if clamped == 0:
		_clout.erase(district_id)
	else:
		_clout[district_id] = clamped
	if clamped != previous:
		EventBus.clout_changed.emit(district_id, clamped, previous)
	return clamped


## Every district with clout, as {district_id: clout}.
func all() -> Dictionary:
	return _clout.duplicate()


func clear() -> void:
	for district_id: StringName in _clout.keys():
		set_clout(district_id, 0)


func to_dict() -> Dictionary:
	var districts := {}
	for district_id: StringName in _clout:
		districts[String(district_id)] = _clout[district_id]
	return {"districts": districts}


func from_dict(data: Dictionary) -> void:
	clear()
	var districts: Dictionary = data.get("districts", {})
	for district_id: String in districts:
		set_clout(StringName(district_id), int(districts[district_id]))
