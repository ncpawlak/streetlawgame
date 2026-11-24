extends Node
## Territory authority: areas -> districts -> safehouses. Owns district/area ownership (by id), answers every
## ownership query, applies captures, computes turf income and serializes to plain Dictionaries.
## District nodes (generated or hand-built) register here; state exists even before they do.

const DEFAULT_CAPTURE_RULE := &"safehouse"
const DEFAULT_SAFEHOUSE := &"greybox"
const AREAS := &"areas"
const DISTRICTS := &"districts"
const SAFEHOUSES := &"safehouses"
const CAPTURE_RULES := &"capture_rules"
const SAVE_VERSION := 1

## District the player is standing in (&"" for none).
var current_district_id: StringName

var _areas := {}            # id -> AreaData
var _district_data := {}    # id -> DistrictData
var _districts := {}        # id -> DistrictState
var _area_states := {}      # id -> AreaState
var _nodes := {}            # id -> District
var _district_order: Array[StringName] = []
var _area_order: Array[StringName] = []


func _ready() -> void:
	reload()


func _physics_process(_delta: float) -> void:
	var player := GameState.player
	if player == null or not is_instance_valid(player):
		return
	var id := district_at(player.get_focus_position())
	if id != current_district_id:
		current_district_id = id
		EventBus.district_entered.emit(id)


## Rebuilds all state from content, at starting owners. Registered nodes stay attached.
func reload() -> void:
	_areas.clear()
	_district_data.clear()
	_districts.clear()
	_area_states.clear()
	_district_order.clear()
	_area_order.clear()
	for resource in TurfContent.all(AREAS):
		var area := resource as AreaData
		if area != null:
			_add_area(area)
	for resource in TurfContent.all(DISTRICTS):
		var district := resource as DistrictData
		if district != null:
			_add_district_data(district)
	for node: District in _nodes.values():
		node.state = _districts.get(node.district_id)
	_recompute_all_areas()


# --- Registration ------------------------------------------------------------------------------

## Called by [District] when it enters the tree. Districts with inline data that isn't in content are added.
func register_district(district: District) -> void:
	var id := district.district_id
	if not _district_data.has(id) and district.data != null:
		_add_district_data(district.data)
		_recompute_area(district.data.area_id)
	if not _districts.has(id):
		push_error("Turf: unknown district id '%s'" % id)
		return
	_nodes[id] = district
	district.state = _districts[id]
	if not district.tree_exiting.is_connected(_on_district_exiting):
		district.tree_exiting.connect(_on_district_exiting.bind(district))


# --- Queries -----------------------------------------------------------------------------------

func owner_of(district_id: StringName) -> StringName:
	var state: DistrictState = _districts.get(district_id)
	return state.owner if state != null else GameState.NO_GANG


func display_name(district_id: StringName) -> String:
	var data := district_data(district_id)
	return data.display_name if data != null else ""


func area_display_name(area_id: StringName) -> String:
	var area: AreaData = _areas.get(area_id)
	return area.display_name if area != null else ""


## The district containing [param position], or &"" outside every registered district.
func district_at(position: Vector3) -> StringName:
	for id: StringName in _nodes:
		var node: District = _nodes[id]
		if node.contains_point(position):
			return id
	return &""


func district_node(district_id: StringName) -> District:
	return _nodes.get(district_id)


func district_data(district_id: StringName) -> DistrictData:
	return _district_data.get(district_id)


func district_state(district_id: StringName) -> DistrictState:
	return _districts.get(district_id)


func area_data(area_id: StringName) -> AreaData:
	return _areas.get(area_id)


func area_of(district_id: StringName) -> StringName:
	var data := district_data(district_id)
	return data.area_id if data != null else &""


func all_districts() -> Array[StringName]:
	return _district_order.duplicate()


func all_areas() -> Array[StringName]:
	return _area_order.duplicate()


func districts_in_area(area_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for id in _district_order:
		if (_district_data[id] as DistrictData).area_id == area_id:
			result.append(id)
	return result


func owned_districts(gang_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for id in _district_order:
		if (_districts[id] as DistrictState).owner == gang_id:
			result.append(id)
	return result


func area_owner(area_id: StringName) -> StringName:
	var state: AreaState = _area_states.get(area_id)
	return state.owner if state != null else GameState.NO_GANG


func owned_areas(gang_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for id in _area_order:
		if (_area_states[id] as AreaState).owner == gang_id:
			result.append(id)
	return result


## Share (0..1) of the area's districts that [param gang_id] holds.
func area_progress(area_id: StringName, gang_id: StringName) -> float:
	var ids := districts_in_area(area_id)
	if ids.is_empty():
		return 0.0
	var held := 0
	for id in ids:
		if owner_of(id) == gang_id:
			held += 1
	return float(held) / float(ids.size())


## Bonuses of every area [param gang_id] fully controls.
func area_bonuses(gang_id: StringName) -> Array[AreaBonusData]:
	var result: Array[AreaBonusData] = []
	for area_id in owned_areas(gang_id):
		result.append_array((_areas[area_id] as AreaData).bonuses)
	return result


func has_unlock(gang_id: StringName, flag: StringName) -> bool:
	for bonus in area_bonuses(gang_id):
		if bonus.unlocks.has(flag):
			return true
	return false


## Income of one district per cycle, including the multiplier of its area when the owner holds the whole area.
func district_income(district_id: StringName) -> int:
	var data := district_data(district_id)
	if data == null:
		return 0
	var multiplier := 1.0
	var holder := owner_of(district_id)
	if holder != GameState.NO_GANG and area_owner(data.area_id) == holder:
		for bonus in (_areas[data.area_id] as AreaData).bonuses:
			multiplier *= bonus.income_multiplier
	return roundi(data.income_per_cycle * multiplier)


## Total turf income per cycle for [param gang_id]: districts plus flat area bonuses.
func income_for(gang_id: StringName) -> int:
	var total := 0
	for id in owned_districts(gang_id):
		total += district_income(id)
	for bonus in area_bonuses(gang_id):
		total += bonus.flat_income_per_cycle
	return total


func safehouse_of(district_id: StringName) -> Safehouse:
	var node := district_node(district_id)
	return node.safehouse if node != null else null


func safehouse_data_for(district_id: StringName) -> SafehouseData:
	var data := district_data(district_id)
	var id := DEFAULT_SAFEHOUSE if data == null or data.safehouse_id == &"" else data.safehouse_id
	var safehouse := TurfContent.find(SAFEHOUSES, id) as SafehouseData
	if safehouse == null and id != DEFAULT_SAFEHOUSE:
		safehouse = TurfContent.find(SAFEHOUSES, DEFAULT_SAFEHOUSE) as SafehouseData
	return safehouse if safehouse != null else SafehouseData.new()


func capture_rule_for(district_id: StringName) -> CaptureRule:
	var data := district_data(district_id)
	var id := DEFAULT_CAPTURE_RULE if data == null or data.capture_rule_id == &"" else data.capture_rule_id
	var rule := TurfContent.find(CAPTURE_RULES, id) as CaptureRule
	if rule == null:
		push_error("Turf: unknown capture rule '%s'" % id)
		rule = SafehouseCaptureRule.new()
	return rule


# --- Mutation ----------------------------------------------------------------------------------

## The single way district ownership changes. [param reason]: &"capture", &"counter_attack", &"load" or &"script".
## Only &"capture" pays respect and emits [signal EventBus.district_captured].
func set_district_owner(district_id: StringName, gang_id: StringName, reason: StringName = &"script") -> void:
	var state: DistrictState = _districts.get(district_id)
	if state == null:
		push_error("Turf: unknown district id '%s'" % district_id)
		return
	var previous := state.owner
	state.capture_progress = 0.0
	state.capture.clear()
	if previous == gang_id:
		return
	state.owner = gang_id
	EventBus.district_owner_changed.emit(district_id, gang_id, previous, reason)
	if reason == &"capture":
		EventBus.district_captured.emit(district_id, gang_id)
		if gang_id == GameState.PLAYER_GANG:
			GameState.add_respect(district_data(district_id).capture_respect)
		EventBus.notify.emit("%s is now %s turf!" % [display_name(district_id), GameState.gang_name(gang_id)])
	_recompute_area(area_of(district_id), reason)


# --- Save/load ---------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var districts := {}
	for id in _district_order:
		districts[String(id)] = (_districts[id] as DistrictState).to_dict()
	var areas := {}
	for id in _area_order:
		areas[String(id)] = (_area_states[id] as AreaState).to_dict()
	return {"version": SAVE_VERSION, "districts": districts, "areas": areas}


## Restores ownership and per-district state. Applies owners with reason &"load" (no rewards).
func from_dict(data: Dictionary) -> void:
	var districts: Dictionary = data.get("districts", {})
	for key: String in districts:
		var saved := DistrictState.from_dict(districts[key])
		var id := StringName(key)
		if not _districts.has(id):
			continue
		set_district_owner(id, saved.owner, &"load")
		var state: DistrictState = _districts[id]
		state.capture_progress = saved.capture_progress
		state.capture = saved.capture
		state.safehouse = saved.safehouse
	_recompute_all_areas(&"load")


## Content problems: dangling area/safehouse/rule ids, duplicates, empty areas.
func validate() -> PackedStringArray:
	var issues := PackedStringArray()
	for id in _district_order:
		var data: DistrictData = _district_data[id]
		if not _areas.has(data.area_id):
			issues.append("district '%s': unknown area '%s'" % [id, data.area_id])
		if data.safehouse_id != &"" and TurfContent.find(SAFEHOUSES, data.safehouse_id) == null:
			issues.append("district '%s': unknown safehouse '%s'" % [id, data.safehouse_id])
		if data.capture_rule_id != &"" and TurfContent.find(CAPTURE_RULES, data.capture_rule_id) == null:
			issues.append("district '%s': unknown capture rule '%s'" % [id, data.capture_rule_id])
		if not GameState.GANGS.has(data.starting_owner) and data.starting_owner != GameState.NO_GANG:
			issues.append("district '%s': unknown gang '%s'" % [id, data.starting_owner])
	for id in _area_order:
		if districts_in_area(id).is_empty():
			issues.append("area '%s' has no districts" % id)
	if TurfContent.find(SAFEHOUSES, DEFAULT_SAFEHOUSE) == null:
		issues.append("missing default safehouse '%s'" % DEFAULT_SAFEHOUSE)
	if TurfContent.find(CAPTURE_RULES, DEFAULT_CAPTURE_RULE) == null:
		issues.append("missing default capture rule '%s'" % DEFAULT_CAPTURE_RULE)
	return issues


# --- Internals ---------------------------------------------------------------------------------

func _add_area(area: AreaData) -> void:
	var id := TurfContent.id_of(area)
	if _areas.has(id):
		push_error("Turf: duplicate area id '%s'" % id)
		return
	_areas[id] = area
	_area_states[id] = AreaState.new(id)
	_area_order.append(id)
	_area_order.sort_custom(func(a: StringName, b: StringName) -> bool:
		var left: AreaData = _areas[a]
		var right: AreaData = _areas[b]
		return left.sort_order < right.sort_order if left.sort_order != right.sort_order else String(a) < String(b))


func _add_district_data(data: DistrictData) -> void:
	var id := TurfContent.id_of(data)
	if _district_data.has(id):
		push_error("Turf: duplicate district id '%s'" % id)
		return
	_district_data[id] = data
	_districts[id] = DistrictState.new(id, data.starting_owner)
	_district_order.append(id)


func _recompute_all_areas(reason: StringName = &"init") -> void:
	for id in _area_order:
		_recompute_area(id, reason)


## Area owner = the gang holding every district, else NO_GANG. Emits area_captured/area_lost on change.
func _recompute_area(area_id: StringName, reason: StringName = &"init") -> void:
	var state: AreaState = _area_states.get(area_id)
	if state == null:
		return
	var ids := districts_in_area(area_id)
	var holder := GameState.NO_GANG
	if not ids.is_empty():
		holder = owner_of(ids[0])
		for id in ids:
			if owner_of(id) != holder:
				holder = GameState.NO_GANG
				break
	var previous := state.owner
	if holder == previous:
		return
	state.owner = holder
	if reason == &"init":
		return
	if previous != GameState.NO_GANG:
		EventBus.area_lost.emit(area_id, previous)
	if holder != GameState.NO_GANG:
		EventBus.area_captured.emit(area_id, holder)
		if reason == &"capture" and holder == GameState.PLAYER_GANG:
			var respect := 0
			for bonus in (_areas[area_id] as AreaData).bonuses:
				respect += bonus.respect_reward
			if respect > 0:
				GameState.add_respect(respect)
			EventBus.notify.emit("You run all of %s!" % area_display_name(area_id))


func _on_district_exiting(district: District) -> void:
	if _nodes.get(district.district_id) == district:
		_nodes.erase(district.district_id)
