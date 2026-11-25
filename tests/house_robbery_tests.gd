class_name HouseRobberyTests
extends RefCounted
## House robbery driver + shared hit components: the neighbour countdown on an empty break-in, an
## alarmed door / camera calling the police at once, gunshots starting the countdown, looting into
## the carry bag and cashing the bag in at a stash. Runs in a sandbox far from the city and
## cleans up after itself.

const SANDBOX := Vector3(4000.0, 0.0, 4000.0)

var _runner: Node
var _root: Node3D
var _session: HitSession
var _house: House
var _player: Player


func _init(runner: Node) -> void:
	_runner = runner


func _check(condition: bool, description: String) -> void:
	_runner.call("_check", condition, "house robbery: " + description)


func run(player: Player) -> void:
	_player = player
	var saved_cash := GameState.cash
	var saved_position := player.global_position
	_root = Node3D.new()
	_root.name = "HouseRobberySandbox"
	_root.position = SANDBOX
	_runner.get_tree().root.add_child(_root)
	_ground()
	_session = HitSession.new()
	_root.add_child(_session)
	_house = House.new()
	_house.layout = {"pending": true}
	_session.setup(player, [SANDBOX + Vector3(200.0, 1.0, 0.0)], _house, 45.0, false)
	_root.add_child(_house)

	await _test_layouts()
	await _test_empty_break_in_starts_timer()
	await _test_owners_home_no_neighbour_timer()
	await _test_alarmed_door_calls_now()
	await _test_camera_calls_now()
	await _test_blind_spot()
	await _test_gunshot_starts_countdown()
	await _test_looting()
	await _test_stash()

	_session.reset()
	CarryBag.of(player).empty()
	_root.queue_free()
	player.global_position = saved_position
	player.velocity = Vector3.ZERO
	GameState.cash = saved_cash
	GameState.add_cash(0)
	await _frames(2)


func _frames(n: int) -> void:
	await _runner.call("_physics_frames", n)


func _ground() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0.0, -0.5, 0.0)
	_root.add_child(body)


## Rebuilds the house for a fresh scenario with the police and bag cleared and the player parked
## across the street.
func _fresh(tier: int, home: bool) -> void:
	_session.reset()
	CarryBag.of(_player).empty()
	_house.build(tier, home, 1234)
	_house.set_police_call(_session.police_call)
	_place(Vector3(0.0, 1.0, 25.0))
	await _frames(3)


## Puts the player at a house-local position (y is height above the ground).
func _place(local: Vector3) -> void:
	_player.global_position = _house.to_global(local)
	_player.velocity = Vector3.ZERO


func _test_layouts() -> void:
	var counts: Array[int] = []
	for tier in [HouseLayouts.Tier.LOW, HouseLayouts.Tier.MEDIUM, HouseLayouts.Tier.HIGH]:
		await _fresh(tier, false)
		counts.append(_house.cameras.size())
		var doors := 0
		var windows := 0
		for e: HouseEntry in _house.entries.values():
			if e.exterior and e.is_door():
				doors += 1
			elif e.exterior and e.is_window():
				windows += 1
		_check(doors >= 1 and windows >= 2 and (_house.layout["rooms"] as Array).size() >= 4,
			"%s has rooms, doors and windows" % _house.tier_name())
		_check(_house.loot_value() > 0, "%s has loot to steal" % _house.tier_name())
	_check(counts[0] == 0 and counts[1] == 1 and counts[2] >= 5, "cameras scale with income: %s" % str(counts))
	_check(_house.entry("master_side_window") != null and not _house.entry("master_side_window").alarmed, "the rich house has an unalarmed blind spot")


func _test_empty_break_in_starts_timer() -> void:
	await _fresh(HouseLayouts.Tier.LOW, false)
	var call := _session.police_call
	_check(not _house.anyone_home() and "looks empty" in _house.stakeout_report(), "a stakeout shows the empty house is empty")
	_check(not call.is_active(), "nothing happens before the break-in")
	_house.front_door().pick_lock(_player)
	_check(_house.is_broken_into, "picking the lock breaks in")
	_check(call.is_counting() and call.reason == PoliceCall.REASON_NEIGHBOURS, "an empty-house break-in starts the neighbour timer")
	_check(is_equal_approx(call.time_left, HouseLayouts.NEIGHBOUR_SECONDS[HouseLayouts.Tier.LOW]), "the timer uses the tier's neighbour time")
	await _frames(10)
	_check(call.is_counting() and call.time_left < HouseLayouts.NEIGHBOUR_SECONDS[0], "the neighbour timer counts down")


func _test_owners_home_no_neighbour_timer() -> void:
	await _fresh(HouseLayouts.Tier.LOW, true)
	_check(_house.anyone_home() and "moving inside" in _house.stakeout_report(), "a stakeout shows the owners are home")
	_house.front_door().pick_lock(_player)
	_check(not _session.police_call.is_active(), "a quiet break-in with the owners home starts no neighbour timer")


func _test_alarmed_door_calls_now() -> void:
	await _fresh(HouseLayouts.Tier.MEDIUM, false)
	var call := _session.police_call
	_check(_house.front_door().alarmed, "the medium front door is alarmed")
	_house.front_door().pick_lock(_player)
	_check(call.is_called() and call.reason == PoliceCall.REASON_ALARM, "opening an alarmed door calls the police immediately")
	_session.reset()
	await _fresh(HouseLayouts.Tier.HIGH, false)
	_house.front_door().kick_in(_player)
	_check(_session.police_call.is_called() and _session.police_call.reason == PoliceCall.REASON_ALARM, "kicking in the rich front door trips the alarm")


func _test_camera_calls_now() -> void:
	await _fresh(HouseLayouts.Tier.MEDIUM, false)
	var call := _session.police_call
	# The side door has no alarm and no camera on it: a quiet way in starts only the neighbours.
	_place(Vector3(-8.0, 0.1, 2.0))
	await _frames(3)
	_house.entry("side_door").pick_lock(_player)
	_check(call.is_counting() and call.reason == PoliceCall.REASON_NEIGHBOURS, "an unwatched door starts only the neighbour timer")
	# Walking round the front into the porch camera's view calls it in.
	_place(Vector3(-1.5, 0.1, 8.0))
	await _frames(5)
	_check(call.is_called() and call.reason == PoliceCall.REASON_CAMERA, "being seen by a camera after a break-in calls the police immediately")


func _test_blind_spot() -> void:
	await _fresh(HouseLayouts.Tier.HIGH, false)
	var window := _house.entry("master_side_window")
	_player.global_position = window.global_position + _house.global_basis * window.outward * 1.2 + Vector3(0.0, -0.8, 0.0)
	_player.velocity = Vector3.ZERO
	await _frames(3)
	window.pry_open(_player)
	_check(_session.police_call.is_counting() and not _session.police_call.is_called(), "prying the blind-spot window avoids the alarm")


func _test_gunshot_starts_countdown() -> void:
	await _fresh(HouseLayouts.Tier.LOW, true)
	var call := _session.police_call
	EventBus.gunshot.emit(_house.global_position, _player)
	_check(call.is_counting() and call.reason == PoliceCall.REASON_GUNSHOT, "a gunshot at the house starts the countdown")
	# The owners hear it too.
	var owner_node: Homeowner = _house.alive_owners()[0]
	_check(owner_node.mood != Homeowner.Mood.CALM, "the owners react to the gunshot")
	# Killing the owners with a gun: the shot itself is what alerts the street.
	await _fresh(HouseLayouts.Tier.LOW, true)
	for victim in _house.alive_owners():
		victim.take_damage(9999.0, _player)
	EventBus.gunshot.emit(_house.global_position, _player)
	_check(not _house.anyone_home(), "the owners can be killed")
	_check(_session.police_call.is_counting(), "the gunshots that killed them start the countdown")


func _test_looting() -> void:
	await _fresh(HouseLayouts.Tier.MEDIUM, false)
	var bag := CarryBag.of(_player)
	var items := _house.loot_items()
	_check(not items.is_empty(), "loose loot is scattered around")
	var item: LootItem = items[0]
	var before := bag.total_value()
	var value := item.value
	_check(item.take(_player), "a loose item can be taken")
	_check(bag.total_value() == before + value, "taking loot adds it to the bag")
	var container: LootContainer = _house.containers[0]
	container.set_contents({"name": "Watch", "value": 300, "slots": 1, "cash": false})
	var used := bag.used_slots()
	container.interactable.perform(&"search", _player)
	_check(bag.used_slots() == used + 1 and container.is_searched, "searching a container bags what's inside")
	_check(container.search(_player).is_empty(), "a searched container is empty")
	before = bag.total_value()
	_house.containers[1].set_contents({"name": "Cash", "value": 120, "cash": true})
	_house.containers[1].search(_player)
	_check(bag.total_value() == before + 120 and bag.cash >= 120, "found cash goes in the bag")
	_house.reroll_loot(99)
	_check(_house.loot_seed == 99 and not _house.loot_items().is_empty() and not _house.containers[0].is_searched, "loot can be re-rolled")


func _test_stash() -> void:
	var stash := StashDropoff.new()
	stash.position = Vector3(0.0, 0.0, 40.0)
	_root.add_child(stash)
	_session.register_stash(stash)
	var bag := CarryBag.of(_player)
	if bag.is_empty():
		bag.add_item("TV", 200, 2)
	var value := bag.total_value()
	_session.police_response.wanted = true
	_check(stash.cash_in(_player) == 0 and not bag.is_empty(), "the stash refuses the bag while the cops are on you")
	_session.police_response.wanted = false
	var cash := GameState.cash
	var paid := stash.cash_in(_player)
	_check(paid == value and GameState.cash == cash + value, "the stash converts the bag to cash")
	_check(bag.is_empty() and _session.state == HitSession.State.DONE, "the bag is empty and the hit is done")
