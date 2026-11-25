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
	_check(Turf.all_districts().size() == 3 and city.districts.size() == 3, "city generates the 3 North End districts from content")
	_check(Turf.all_areas() == [&"north_end"], "districts are grouped into the North End area")
	_check(Turf.validate().is_empty(), "territory content validates %s" % Turf.validate())
	_check(ContentDB.validate().is_empty(), "ContentDB content validates %s" % ContentDB.validate())
	_check(Turf.owned_districts(GameState.PLAYER_GANG).is_empty() and Turf.owner_of(&"tamarack_row") == &"vipers", "the Red Vipers run the North End at start")
	_check(Turf.owned_areas(GameState.PLAYER_GANG).is_empty(), "player starts with no full area")
	_check(Turf.district_at(player.global_position) == &"tamarack_row" and Turf.current_district_id == &"tamarack_row", "district_at finds the player's district")
	var resolved := true
	for district in city.districts:
		resolved = resolved and Locations.resolve_district(district.global_position) == district.district_id
	_check(resolved and Locations.resolve_district(Vector3(1.0e5, 0.0, 1.0e5)) == &"", "Locations.resolve_district returns Turf district ids")
	_check(Locations.district_resolver == Turf.district_at, "Turf installs itself as the Locations district resolver")
	var expected := 0
	var safehouses := 0
	for id in Turf.all_districts():
		if Turf.district_node(id).safehouse != null:
			safehouses += 1
		if Turf.owner_of(id) != GameState.PLAYER_GANG:
			var config := Turf.district_data(id).defenders
			expected += config.guard_count + config.patrol_count
	_check(safehouses == 3, "every district has a safehouse")
	_check(_runner.get_tree().get_nodes_in_group(&"gang_members").size() == expected, "rival districts get guards and patrols (%d)" % expected)
	_check(Turf.safehouse_of(&"mangona").data.id == &"warehouse" and Turf.safehouse_of(&"northgrove").data.id == &"greybox" and Turf.safehouse_of(&"tamarack_row").data.id == &"duplex", "safehouse style comes from district data")


func _test_safehouse_capture(player: Player) -> void:
	var district := Turf.district_node(&"mangona")
	var safehouse := district.safehouse
	var rule := district.capture_rule().duplicate() as SafehouseCaptureRule
	rule.claim_time_scale = 0.1
	district.set_capture_rule(rule)
	_check(district.guards_remaining() == 4 and not safehouse.interactable.perform(Safehouse.CLAIM_ACTION, player), "guards block the safehouse claim")
	var claim := safehouse.interactable.find_action(Safehouse.CLAIM_ACTION)
	_check(claim.unavailable_reason(safehouse.interactable.make_context(player, claim)) == "4 guards left", "the claim prompt says why it's blocked")
	var cash_before := GameState.cash
	var respect_before := GameState.respect
	_kill(&"mangona", &"guard", player)
	_check(district.guards_remaining() == 0 and district.defenders_remaining() == 2, "guards die, patrols remain")
	_check(GameState.cash == cash_before and GameState.respect > respect_before, "kills reward respect; the cash stays on the body")
	var looted := 0
	await _frames(1)
	for node in _runner.get_tree().get_nodes_in_group(&"gang_members"):
		var body := BodyLoot.of(node)
		if body != null and body.interactable.perform(BodyLoot.ACTION, player):
			looted += 1
	_check(looted >= 4 and GameState.cash > cash_before, "searching the dead guards' bodies pays their cash")
	_check(safehouse.can_claim(player), "a cleared safehouse can be claimed")
	_kill(&"mangona", &"", player)

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
	_check(GameState.respect == respect_before + Turf.district_data(&"mangona").capture_respect, "capturing pays district respect")
	_check(Turf.owned_districts(GameState.PLAYER_GANG) == [&"mangona"] and district.state.capture.is_empty(), "captured district counts as player turf")
	var labels: Array[StringName] = []
	for action in safehouse.interactable.visible_actions(player):
		labels.append(action.id)
	_check(labels == [Safehouse.MANAGE_ACTION], "an owned safehouse offers Manage instead of Take over")
	var managed := [false]
	var on_manage := func(id: StringName) -> void: managed[0] = id == &"mangona"
	EventBus.safehouse_manage_requested.connect(on_manage)
	safehouse.interactable.perform(Safehouse.MANAGE_ACTION, player)
	EventBus.safehouse_manage_requested.disconnect(on_manage)
	_check(managed[0], "Manage requests the safehouse menu")
	player.global_position = player.spawn_point
	await _frames(5)


func _test_area_capture() -> void:
	var base := 0
	for id in Turf.districts_in_area(&"north_end"):
		base += Turf.district_data(id).income_per_cycle
	Turf.set_district_owner(&"tamarack_row", GameState.PLAYER_GANG, &"capture")
	_events.clear()
	var respect_before := GameState.respect
	Turf.set_district_owner(&"northgrove", GameState.PLAYER_GANG, &"capture")
	_check(Turf.area_owner(&"north_end") == GameState.PLAYER_GANG and _events.has("area_captured"), "taking every district takes the area")
	_check(GameState.respect == respect_before + 100 + 250, "area completion pays its respect bonus")
	_check(Turf.income_for(GameState.PLAYER_GANG) > base and Turf.has_unlock(GameState.PLAYER_GANG, &"north_end_control"), "area bonuses boost income and unlock flags")
	_events.clear()
	Turf.set_district_owner(&"northgrove", &"vipers", &"counter_attack")
	_check(Turf.area_owner(&"north_end") == GameState.NO_GANG and _events.has("area_lost") and not _events.has("district_captured"), "losing a district loses the area")


func _test_rule_swap(_city: CityGenerator, player: Player) -> void:
	var district := Turf.district_node(&"northgrove")
	var rule := (TurfContent.find(Turf.CAPTURE_RULES, &"clear_and_hold") as ClearAndHoldCaptureRule).duplicate() as ClearAndHoldCaptureRule
	rule.capture_time = 0.3
	district.set_capture_rule(rule)
	_kill(&"northgrove", &"", player)
	player.global_position = district.safehouse.door_position() + Vector3(0.0, 1.0, 0.0)
	await _frames(60)
	_check(district.owner_gang == GameState.PLAYER_GANG, "a swapped capture rule (clear and hold) captures the district")
	player.global_position = player.spawn_point
	await _frames(5)


func _test_save_load(snapshot: Dictionary) -> void:
	var saved: Dictionary = JSON.parse_string(JSON.stringify(Turf.to_dict()))
	_events.clear()
	Turf.from_dict(snapshot)
	_check(Turf.owned_districts(GameState.PLAYER_GANG).is_empty() and _events.is_empty(), "loading restores owners without capture events")
	Turf.from_dict(saved)
	_check(Turf.owner_of(&"mangona") == GameState.PLAYER_GANG and Turf.owner_of(&"northgrove") == GameState.PLAYER_GANG, "turf state survives a JSON round trip")


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
