extends Node
## Locations autoload: registry and state store for every placed Location, plus queries, status timers,
## register refills and interior pocket slots. Location state is plain data (to_dict/from_dict).

const POCKET_BASE_HEIGHT := 1000.0
const POCKET_SPACING := 40.0
const TICK_INTERVAL := 1.0

## func(position: Vector3) -> StringName district id. Defaults to Turf.district_at when the Turf
## autoload exists, else the snake_case name of the GameState territory at that point.
var district_resolver: Callable
## The location whose interior the player is in (null outside).
var current: Location

var _locations := {}
var _states := {}
var _pockets: Array[bool] = []
var _tick_left := TICK_INTERVAL
var _counter := 0


func _init() -> void:
	district_resolver = default_district_at


func _ready() -> void:
	EventBus.player_died.connect(_on_player_died)


func _process(delta: float) -> void:
	_tick_left -= delta
	if _tick_left > 0.0:
		return
	_tick_left = TICK_INTERVAL
	tick(TICK_INTERVAL)


## Advances status resets and register refills by [param seconds].
func tick(seconds: float) -> void:
	var now := GameState.play_time
	for id: StringName in _states:
		var state: LocationState = _states[id]
		if state.status_until > 0.0 and now >= state.status_until:
			state.status_until = 0.0
			_apply_status(id, Location.OPEN)
		var location: Location = _locations.get(id)
		if location != null and location.def.cash_regen_per_minute > 0.0 and state.status != Location.TAKEN_OUT:
			state.cash = minf(float(location.def.cash_capacity), state.cash + location.def.cash_regen_per_minute * seconds / 60.0)


## Creates a Location for [param def] at [param at] under [param parent]. Unique defs always get
## instance_id == def.id. Existing state for the id (e.g. loaded from a save) is reused.
func spawn(def: LocationDef, at: Transform3D, parent: Node, instance_id: StringName = &"") -> Location:
	var id := instance_id
	if def.unique:
		id = def.id
	elif id == &"":
		id = _next_id(def.id)
	if _locations.has(id):
		push_warning("Locations: '%s' is already spawned" % id)
		return _locations[id]
	var location := Location.create(def, at, id)
	location.state = _state_for(def, id, at.origin)
	parent.add_child(location)
	register(location)
	return location


func register(location: Location) -> void:
	if location.state == null:
		location.state = ensure_state(location)
	_locations[location.instance_id] = location
	if not location.tree_exiting.is_connected(_on_location_exiting):
		location.tree_exiting.connect(_on_location_exiting.bind(location))


## The state for a Location that was created outside [method spawn].
func ensure_state(location: Location) -> LocationState:
	return _state_for(location.def, location.instance_id, location.global_position if location.is_inside_tree() else location.position)


func get_location(instance_id: StringName) -> Location:
	return _locations.get(instance_id)


func state_of(instance_id: StringName) -> LocationState:
	return _states.get(instance_id)


## Every spawned location, sorted by instance id.
func all() -> Array[Location]:
	var ids: Array = _locations.keys()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	var result: Array[Location] = []
	for id: StringName in ids:
		result.append(_locations[id])
	return result


## Locations matching every non-empty filter.
func query(kind: StringName = &"", district_id: StringName = &"", owner_gang: StringName = &"", tag: StringName = &"") -> Array[Location]:
	return all().filter(func(location: Location) -> bool:
		return (kind == &"" or location.def.kind == kind) \
			and (district_id == &"" or location.district_id == district_id) \
			and (owner_gang == &"" or location.state.owner_gang == owner_gang) \
			and (tag == &"" or location.def.has_tag(tag)))


## Locations of a def id (for unique defs, at most one).
func of_def(def_id: StringName) -> Array[Location]:
	return all().filter(func(location: Location) -> bool: return location.def.id == def_id)


func nearest(position: Vector3, kind: StringName = &"") -> Location:
	var best: Location = null
	var best_distance := INF
	for location in query(kind):
		var distance := location.global_position.distance_squared_to(position)
		if distance < best_distance:
			best = location
			best_distance = distance
	return best


## Sets a status; [param reset_after] > 0 reverts it to open after that many seconds of play.
func set_status(location: Location, status: StringName, reset_after := 0.0) -> void:
	location.state.status_until = GameState.play_time + reset_after if reset_after > 0.0 else 0.0
	_apply_status(location.instance_id, status)


func set_owner_gang(location: Location, gang_id: StringName) -> void:
	location.state.owner_gang = gang_id
	EventBus.location_status_changed.emit(location, location.state.status)


func resolve_district(position: Vector3) -> StringName:
	if district_resolver.is_valid():
		return StringName(district_resolver.call(position))
	return &""


func default_district_at(position: Vector3) -> StringName:
	var turf := get_node_or_null(^"/root/Turf")
	if turf != null and turf.has_method("district_at"):
		return StringName(turf.call("district_at", position))
	var territory := GameState.territory_at(position)
	return to_district_id(territory.display_name) if territory != null else &""


## "The Bottoms" -> &"the_bottoms" (same rule as data/districts file names).
static func to_district_id(display_name: String) -> StringName:
	var result := ""
	for character in display_name.strip_edges().to_lower():
		var code := character.unicode_at(0)
		var alnum := (code >= 97 and code <= 122) or (code >= 48 and code <= 57)
		if alnum:
			result += character
		elif not result.ends_with("_") and result != "":
			result += "_"
	return StringName(result.trim_suffix("_"))


## Interior pockets: each streamed interior gets its own height slot above the city.
func allocate_pocket() -> int:
	for i in _pockets.size():
		if not _pockets[i]:
			_pockets[i] = true
			return i
	_pockets.append(true)
	return _pockets.size() - 1


func release_pocket(slot: int) -> void:
	if slot >= 0 and slot < _pockets.size():
		_pockets[slot] = false


func pocket_height(slot: int) -> float:
	return POCKET_BASE_HEIGHT + slot * POCKET_SPACING


func to_dict() -> Dictionary:
	var states := {}
	for id: StringName in _states:
		states[String(id)] = (_states[id] as LocationState).to_dict()
	return {"states": states}


## Restores state; spawned locations update in place, others pick it up when spawned.
func from_dict(d: Dictionary) -> void:
	var states: Dictionary = d.get("states", {})
	for key: String in states:
		var id := StringName(key)
		var state: LocationState = _states.get(id)
		if state == null:
			state = LocationState.new()
			_states[id] = state
		state.from_dict(states[key])
		if _locations.has(id):
			EventBus.location_status_changed.emit(_locations[id], state.status)


## Despawns [param instance_id] (if spawned) and drops its state, e.g. a demolished building.
func forget(instance_id: StringName) -> void:
	var location: Location = _locations.get(instance_id)
	if location != null and is_instance_valid(location):
		if current == location:
			location.exit(GameState.player)
		location.queue_free()
	_locations.erase(instance_id)
	_states.erase(instance_id)


## Frees every location and forgets all state (new game / tests).
func clear() -> void:
	if current != null:
		current.exit(GameState.player)
	for location: Location in _locations.values():
		if is_instance_valid(location):
			location.queue_free()
	_locations.clear()
	_states.clear()
	_counter = 0


func _state_for(def: LocationDef, id: StringName, position: Vector3) -> LocationState:
	if _states.has(id):
		return _states[id]
	var state := LocationState.new()
	state.instance_id = id
	state.def_id = def.id
	state.district_id = resolve_district(position)
	state.owner_gang = def.resolve_owner(_district_owner(position))
	state.cash = float(def.cash_capacity)
	_states[id] = state
	return state


func _district_owner(position: Vector3) -> StringName:
	var turf := get_node_or_null(^"/root/Turf")
	if turf != null and turf.has_method("owner_of"):
		return StringName(turf.call("owner_of", resolve_district(position)))
	var territory := GameState.territory_at(position)
	return territory.owner_gang if territory != null else GameState.NO_GANG


func _next_id(def_id: StringName) -> StringName:
	while true:
		_counter += 1
		var id := StringName("%s_%d" % [def_id, _counter])
		if not _locations.has(id):
			return id
	return &""


func _apply_status(id: StringName, status: StringName) -> void:
	var state: LocationState = _states.get(id)
	if state == null or state.status == status:
		return
	state.status = status
	var location: Location = _locations.get(id)
	if location != null:
		EventBus.location_status_changed.emit(location, status)


func _on_location_exiting(location: Location) -> void:
	if _locations.get(location.instance_id) == location:
		_locations.erase(location.instance_id)
	if current == location:
		current = null


func _on_player_died() -> void:
	if current != null:
		current.exit(GameState.player)
