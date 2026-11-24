class_name LocationTests
extends RefCounted
## Tests for the Locations framework (placement, rob, pocket interiors, take-out, serialization).
## Hooked from FrameworkTests. Test locations live in the framework sandbox and are forgotten afterwards.

var _framework: FrameworkTests
var _player: Player


func _init(framework: FrameworkTests) -> void:
	_framework = framework


func run(main: Node, player: Player) -> void:
	_player = player
	_test_city_placement(main)
	_test_district_ids()
	await _framework.with_sandbox(main, _test_door_only_rob)
	await _framework.with_sandbox(main, _test_pocket_interior_and_rob)
	await _framework.with_sandbox(main, _test_take_out)
	_test_serialization()


func _check(condition: bool, description: String) -> void:
	_framework.check(condition, description)


func _spawn(def_id: StringName, instance_id: StringName, offset: Vector3) -> Location:
	var def := ContentDB.get_def(LocationDef.TYPE, def_id) as LocationDef
	var at := Transform3D(Basis.IDENTITY, FrameworkTests.SANDBOX + offset)
	return Locations.spawn(def, at, _framework.sandbox(), instance_id)


func _test_city_placement(main: Node) -> void:
	var city := main.get_node("City") as CityGenerator
	_check(city.building_lots.size() > 50, "the city records building lots")
	var informants := Locations.of_def(&"informant_flat")
	_check(informants.size() == 1 and informants[0].instance_id == &"informant_flat", "unique locations are placed once with instance_id == def id")
	_check(Locations.of_def(&"rival_front").size() >= 2 and Locations.of_def(&"corner_store").size() >= 2, "min_count is honoured")
	_check(Locations.query(&"safehouse").is_empty(), "the placer leaves safehouses to their owner system")
	var all_have_districts := true
	var fronts_per_district := {}
	for location in Locations.all():
		all_have_districts = all_have_districts and location.district_id != &""
		if location.def.id == &"rival_front":
			fronts_per_district[location.district_id] = int(fronts_per_district.get(location.district_id, 0)) + 1
	_check(all_have_districts, "every placed location knows its district")
	_check(fronts_per_district.values().all(func(count: int) -> bool: return count <= 1), "max_per_district is honoured")

	var placer := LocationPlacer.new()
	placer.placement_seed = city.city_seed
	placer.density = main.placer_density
	var lots: Array[Dictionary] = main.placer_lots
	var first := placer.plan(lots, main.placer_defs())
	var second := placer.plan(lots, main.placer_defs())
	var same := first.size() == second.size()
	for i in mini(first.size(), second.size()):
		same = same and first[i]["instance_id"] == second[i]["instance_id"] and first[i]["transform"] == second[i]["transform"]
	_check(same and not first.is_empty(), "placement is deterministic for a seed")
	var spawned := true
	for entry in first:
		var location := Locations.get_location(entry["instance_id"])
		spawned = spawned and location != null and location.global_position.is_equal_approx(entry["transform"].origin)
	_check(spawned, "the city layout matches the placer plan")
	var roster_placed := true
	for spot: Dictionary in NorthEndSpots.SPOTS:
		if spot["kind"] == &"marker":
			continue
		var id: StringName = spot["id"] if spot["kind"] == &"site" else spot["instance"]
		var location := Locations.get_location(id)
		var near := location != null and Vector2(location.global_position.x, location.global_position.z).distance_to(Vector2(CityGenerator.px_to_world(spot["px"]).x, CityGenerator.px_to_world(spot["px"]).z)) < 60.0
		roster_placed = roster_placed and near
		if not near:
			print("  roster spot off: %s" % id)
	_check(roster_placed, "North End roster spots are placed at their wireframe positions")
	var door := LocationPlacer.door_transform({"center": Vector3(10.0, 0.0, 0.0), "footprint": Vector2(8.0, 8.0), "block_center": Vector3.ZERO})
	_check(door.origin.is_equal_approx(Vector3(14.15, 0.0, 0.0)) and door.basis.z.is_equal_approx(Vector3.RIGHT), "doors face the road, away from the block centre")

	var marker_location := Locations.all()[0]
	_check(not marker_location.is_marker_visible(), "map markers are hidden by default")
	marker_location.set_marker_visible(true)
	_check(marker_location.is_marker_visible(), "set_marker_visible shows the marker")
	marker_location.set_marker_visible(false)


func _test_district_ids() -> void:
	_check(Locations.to_district_id("The Bottoms") == &"the_bottoms" and Locations.to_district_id("  Old-Town  Docks ") == &"old_town_docks", "district names convert to snake_case ids")
	var previous := Locations.district_resolver
	Locations.district_resolver = func(_position: Vector3) -> StringName: return &"test_district"
	_check(Locations.resolve_district(Vector3.ZERO) == &"test_district", "district_resolver is pluggable")
	Locations.district_resolver = previous


func _test_door_only_rob() -> void:
	var cash_before := GameState.cash
	var house := _spawn(&"house", &"test_house", Vector3(0.0, 0.0, -6.0))
	_check(not house.is_enterable() and house.door.find_action(&"smash_and_grab") != null, "door-only locations offer their door actions")
	var register := int(house.state.cash)
	_check(house.door.perform(&"smash_and_grab", _player), "break-in succeeds")
	_check(GameState.cash >= cash_before + register + 10 and house.state.cash == 0.0 and house.status() == Location.ROBBED, "break-in takes the cash and marks the house robbed")
	_check(not house.door.perform(&"smash_and_grab", _player), "a robbed house can't be hit again until it resets")
	house.state.status_until = GameState.play_time - 1.0
	Locations.tick(60.0)
	_check(house.status() == Location.OPEN and house.state.cash > 0.0, "status resets and the register refills over time")

	var informant := Locations.get_location(&"informant_flat")
	var informant_state := informant.state.to_dict()
	var intel_action := informant.door.find_action(&"buy_intel_informant")
	_check(intel_action != null, "door-only occupants offer their actions on the door")
	GameState.cash = cash_before + 500
	var revealed := false
	if intel_action != null:
		var ctx := informant.door.make_context(_player, intel_action)
		_check(ctx.occupant is Occupant and (ctx.occupant as Occupant).role() == &"informant", "door actions know which occupant they belong to")
		informant.door.run(intel_action, ctx)
		revealed = GameState.has_flag(&"intel:rival_fronts") and Locations.query(&"front").all(func(location: Location) -> bool: return location.is_marker_visible())
	_check(revealed, "intel sets its flag and reveals rival fronts on the map")
	for location in Locations.query(&"front"):
		location.set_marker_visible(false)
	GameState.flags.erase(&"intel:rival_fronts")
	Locations.forget(&"test_house")
	informant.state.from_dict(informant_state)
	GameState.cash = cash_before
	EventBus.cash_changed.emit(GameState.cash)


func _test_pocket_interior_and_rob() -> void:
	var cash_before := GameState.cash
	var respect_before := GameState.respect
	var store := _spawn(&"corner_store", &"test_store", Vector3(0.0, 0.0, -6.0))
	var entered: Array[Location] = []
	var on_entered := func(location: Location, _actor: Node) -> void: entered.append(location)
	EventBus.location_entered.connect(on_entered)
	_check(store.door.perform(&"enter_building", _player), "enter action runs")
	EventBus.location_entered.disconnect(on_entered)
	_check(Locations.current == store and store.interior_root != null and entered == [store], "entering streams the interior and emits location_entered")
	_check(_player.global_position.y > Locations.POCKET_BASE_HEIGHT - 5.0 and absf(_player.global_position.x - store.global_position.x) < 20.0, "the interior pocket sits above the door (same XZ)")
	var clerks := store.occupants.filter(func(occupant: Occupant) -> bool: return occupant.interactable != null)
	_check(clerks.size() == 1, "friendly occupants spawn inside")
	if clerks.size() == 1:
		var clerk: Occupant = clerks[0]
		_player.weapons.select(0)
		_check(not clerk.interactable.perform(&"rob_register", _player), "robbing needs a drawn weapon")
		_player.weapons.select(1)
		_check(clerk.interactable.perform(&"rob_register", _player), "robbing the clerk works with a weapon out")
		_check(GameState.cash == cash_before + 400 and GameState.respect == respect_before + 2 and store.status() == Location.ROBBED, "rob takes the register, gives respect and marks the store robbed")
		_player.weapons.select(0)
	await _framework.frames(2)
	store.exit(_player)
	_check(Locations.current == null and store.interior_root == null and _player.global_position.distance_to(store.outside_point()) < 1.0, "exit frees the interior and returns the player outside")
	_check(store.occupants.is_empty(), "interior occupants are freed on exit")
	Locations.forget(&"test_store")
	GameState.cash = cash_before
	GameState.respect = respect_before
	EventBus.cash_changed.emit(GameState.cash)
	EventBus.respect_changed.emit(GameState.respect)


func _test_take_out() -> void:
	var cash_before := GameState.cash
	var respect_before := GameState.respect
	var front := _spawn(&"rival_front", &"test_front", Vector3(0.0, 0.0, -6.0))
	front.state.owner_gang = &"vipers"
	_check(front.hostiles_remaining() == 4, "hostile count comes from the occupant defs")
	var taken: Array[Location] = []
	var on_taken := func(location: Location, _previous: StringName) -> void: taken.append(location)
	EventBus.location_taken_out.connect(on_taken)
	front.enter(_player)
	var hostiles: Array[GangMember] = []
	for node in _player.get_tree().get_nodes_in_group("gang_members"):
		if front.interior_root.is_ancestor_of(node):
			hostiles.append(node as GangMember)
	_check(hostiles.size() == 4 and hostiles.all(func(member: GangMember) -> bool: return member.gang_id == &"vipers"), "hostiles spawn inside for the owning gang")
	if hostiles.size() > 1:
		hostiles[0].take_damage(9999.0, _player)
		_check(front.hostiles_remaining() == 3 and front.status() == Location.OPEN, "killing one hostile leaves the front standing")
		front.exit(_player)
		_check(int(front.state.flags["hostiles_left"]) == 3, "the dead stay dead after leaving")
		front.enter(_player)
		for node in _player.get_tree().get_nodes_in_group("gang_members"):
			var member := node as GangMember
			if front.interior_root.is_ancestor_of(member) and member.is_alive():
				member.take_damage(9999.0, _player)
	EventBus.location_taken_out.disconnect(on_taken)
	_check(front.status() == Location.TAKEN_OUT and taken == [front], "clearing every hostile takes the front out once")
	_check(GameState.cash > cash_before + 300 and GameState.respect >= respect_before + 15, "cleared_effects pay out")
	front.exit(_player)
	_player.health = _player.max_health
	Locations.forget(&"test_front")
	GameState.cash = cash_before
	GameState.respect = respect_before
	EventBus.cash_changed.emit(GameState.cash)
	EventBus.respect_changed.emit(GameState.respect)


func _test_serialization() -> void:
	var location := Locations.all()[0]
	var original := location.state.to_dict()
	location.state.status = Location.ROBBED
	location.state.cash = 12.5
	location.state.memory[&"rob_register"] = {"last": 3.0, "count": 2}
	location.state.flags["hostiles_left"] = 1
	var saved: Dictionary = JSON.parse_string(JSON.stringify(Locations.to_dict()))
	location.state.from_dict(original)
	Locations.from_dict(saved)
	var state := Locations.state_of(location.instance_id)
	_check(state == location.state and state.status == Location.ROBBED and is_equal_approx(state.cash, 12.5) and int(state.flags["hostiles_left"]) == 1, "location state survives a JSON round trip")
	var ctx := ActionContext.new(_player)
	ctx.memory = location.door.memory
	_check(int(ctx.action_memory(&"rob_register")["count"]) == 2, "interaction memory survives a JSON round trip (StringName keys)")
	location.state.from_dict(original)
