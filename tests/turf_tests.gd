extends RefCounted
## Turf tests (areas -> districts -> safehouses). Run from run_tests.gd; restores the Turf state it touches.

var _runner: Node
var _events: Array[String] = []
var _listeners := {}  # signal name -> Callable


func _init(runner: Node) -> void:
	_runner = runner


func run(city: CityGenerator, player: Player) -> void:
	var snapshot := Turf.to_dict()
	var cash := GameState.cash
	var respect := GameState.respect
	for signal_name: StringName in [&"district_captured", &"area_captured", &"area_lost", &"safehouse_claim_started"]:
		_listeners[signal_name] = _record.bind(signal_name)
		EventBus.connect(signal_name, _listeners[signal_name])

	_test_startup(city, player)
	await _test_safehouse_capture(player)
	_test_area_capture()
	await _test_rule_swap(city, player)
	_test_save_load(snapshot)

	for signal_name: StringName in _listeners:
		EventBus.disconnect(signal_name, _listeners[signal_name])
	for id in Turf.all_districts():
		Turf.district_node(id).set_capture_rule(Turf.capture_rule_for(id))
	Turf.from_dict(snapshot)
	GameState.cash = cash
	GameState.respect = respect
	player.respawn()
	await _frames(5)


func _test_startup(city: CityGenerator, player: Player) -> void:
	_check(Turf.all_districts().size() == 9 and city.districts.size() == 9, "city generates 9 districts from content")
	_check(Turf.all_areas().size() == 3, "districts are grouped into 3 areas")
	_check(Turf.validate().is_empty(), "territory content validates %s" % Turf.validate())
	_check(ContentDB.validate().is_empty(), "ContentDB content validates %s" % ContentDB.validate())
	_check(Turf.owned_districts(GameState.PLAYER_GANG) == [&"the_bottoms"], "player starts owning The Bottoms")
	_check(Turf.owned_areas(GameState.PLAYER_GANG).is_empty(), "player starts with no full area")
	_check(Turf.district_at(player.global_position) == &"the_bottoms" and Turf.current_district_id == &"the_bottoms", "district_at finds the player's district")
	var expected := 0
	var safehouses := 0
	for id in Turf.all_districts():
		if Turf.district_node(id).safehouse != null:
			safehouses += 1
		if Turf.owner_of(id) != GameState.PLAYER_GANG:
			var config := Turf.district_data(id).defenders
			expected += config.guard_count + config.patrol_count
	_check(safehouses == 9, "every district has a safehouse")
	_check(_runner.get_tree().get_nodes_in_group(&"gang_members").size() == expected, "rival districts get guards and patrols (%d)" % expected)
	_check(Turf.safehouse_of(&"rail_yards").data.id == &"warehouse" and Turf.safehouse_of(&"midtown").data.id == &"greybox", "safehouse style comes from district data")


func _test_safehouse_capture(player: Player) -> void:
	var district := Turf.district_node(&"rail_yards")
	var safehouse := district.safehouse
	var rule := district.capture_rule().duplicate() as SafehouseCaptureRule
	rule.claim_time_scale = 0.1
	district.set_capture_rule(rule)
	_check(district.guards_remaining() == 4 and not safehouse.interactable.perform(Safehouse.CLAIM_ACTION, player), "guards block the safehouse claim")
	var claim := safehouse.interactable.find_action(Safehouse.CLAIM_ACTION)
	_check(claim.unavailable_reason(safehouse.interactable.make_context(player, claim)) == "4 guards left", "the claim prompt says why it's blocked")
	var cash_before := GameState.cash
	var respect_before := GameState.respect
	_kill(&"rail_yards", &"guard", player)
	_check(district.guards_remaining() == 0 and district.defenders_remaining() == 2, "guards die, patrols remain")
	_check(GameState.cash > cash_before and GameState.respect > respect_before, "kills reward cash and respect")
	_check(safehouse.can_claim(player), "a cleared safehouse can be claimed")
	_kill(&"rail_yards", &"", player)

	_events.clear()
	player.global_position = safehouse.door_position() + Vector3(0.0, 1.0, 0.0)
	await _frames(10)
	_check(district.state.capture_progress == 0.0, "standing at the door alone doesn't start a takeover")
	_check(safehouse.interactable.perform(Safehouse.CLAIM_ACTION, player) and _events.has("safehouse_claim_started"), "[E] Take over starts the takeover")
	await _frames(20)
	var progress := district.state.capture_progress
	_check(progress > 0.0 and progress < 1.0, "holding the door fills the takeover bar (%.2f)" % progress)
	player.global_position = player.spawn_point
	await _frames(15)
	_check(district.state.capture_progress < progress and district.owner_gang != GameState.PLAYER_GANG, "leaving the door drains progress")
	player.global_position = safehouse.door_position() + Vector3(0.0, 1.0, 0.0)
	respect_before = GameState.respect
	await _frames(90)
	_check(district.owner_gang == GameState.PLAYER_GANG and _events.has("district_captured"), "holding the door takes the district")
	_check(GameState.respect == respect_before + Turf.district_data(&"rail_yards").capture_respect, "capturing pays district respect")
	_check(Turf.owned_districts(GameState.PLAYER_GANG).size() == 2 and district.state.capture.is_empty(), "captured district counts as player turf")
	var labels: Array[StringName] = []
	for action in safehouse.interactable.visible_actions(player):
		labels.append(action.id)
	_check(labels == [Safehouse.MANAGE_ACTION], "an owned safehouse offers Manage instead of Take over")
	var managed := [false]
	var on_manage := func(id: StringName) -> void: managed[0] = id == &"rail_yards"
	EventBus.safehouse_manage_requested.connect(on_manage)
	safehouse.interactable.perform(Safehouse.MANAGE_ACTION, player)
	EventBus.safehouse_manage_requested.disconnect(on_manage)
	_check(managed[0], "Manage requests the safehouse menu")
	player.global_position = player.spawn_point
	await _frames(5)


func _test_area_capture() -> void:
	var base := 0
	for id in Turf.districts_in_area(&"southside"):
		base += Turf.district_data(id).income_per_cycle
	_events.clear()
	var respect_before := GameState.respect
	Turf.set_district_owner(&"old_harbor", GameState.PLAYER_GANG, &"capture")
	_check(Turf.area_owner(&"southside") == GameState.PLAYER_GANG and _events.has("area_captured"), "taking every district takes the area")
	_check(GameState.respect == respect_before + 100 + 250, "area completion pays its respect bonus")
	_check(Turf.income_for(GameState.PLAYER_GANG) > base and Turf.has_unlock(GameState.PLAYER_GANG, &"southside_control"), "area bonuses boost income and unlock flags")
	_events.clear()
	Turf.set_district_owner(&"old_harbor", &"syndicate", &"counter_attack")
	_check(Turf.area_owner(&"southside") == GameState.NO_GANG and _events.has("area_lost") and not _events.has("district_captured"), "losing a district loses the area")


func _test_rule_swap(city: CityGenerator, player: Player) -> void:
	var district := Turf.district_node(&"eastside")
	var rule := (TurfContent.find(Turf.CAPTURE_RULES, &"clear_and_hold") as ClearAndHoldCaptureRule).duplicate() as ClearAndHoldCaptureRule
	rule.capture_time = 0.3
	district.set_capture_rule(rule)
	_kill(&"eastside", &"", player)
	var offset := city.block_size * 0.5 + city.road_width * 0.5
	player.global_position = district.global_position + Vector3(offset, 1.0, offset)
	await _frames(60)
	_check(district.owner_gang == GameState.PLAYER_GANG, "a swapped capture rule (clear and hold) captures the district")
	player.global_position = player.spawn_point
	await _frames(5)


func _test_save_load(snapshot: Dictionary) -> void:
	var saved: Dictionary = JSON.parse_string(JSON.stringify(Turf.to_dict()))
	_events.clear()
	Turf.from_dict(snapshot)
	_check(Turf.owned_districts(GameState.PLAYER_GANG) == [&"the_bottoms"] and _events.is_empty(), "loading restores owners without capture events")
	Turf.from_dict(saved)
	_check(Turf.owner_of(&"rail_yards") == GameState.PLAYER_GANG and Turf.owner_of(&"eastside") == GameState.PLAYER_GANG, "turf state survives a JSON round trip")


func _kill(district_id: StringName, role: StringName, killer: Node) -> void:
	for node in _runner.get_tree().get_nodes_in_group(&"gang_members"):
		var member := node as GangMember
		if member.home_district == district_id and member.is_alive() and (role == &"" or member.role == role):
			member.take_damage(1000.0, killer)


func _record(_a: Variant = null, _b: Variant = null, signal_name: StringName = &"") -> void:
	_events.append(String(signal_name))


func _frames(count: int) -> void:
	for i in count:
		await _runner.get_tree().physics_frame


func _check(condition: bool, description: String) -> void:
	_runner.call(&"_check", condition, description)
