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
var _heat: HeatMap


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
	_heat = HeatMap.new()
	_session.set_heat_map(_heat)
	_house.heat_map = _heat
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
	await _test_safe()
	await _test_dog()
	await _test_cameras_disabled()
	await _test_crew()

	_session.reset()
	_session.crew.clear()
	_heat.free()
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
	_heat.clear()
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
	await _test_walkthrough()


## Every door and archway, on every tier, lets the player's 0.8 m x 1.8 m capsule walk straight
## through from a metre out on one side to a metre out on the other, past the open door leaf and any
## furniture. Doors are at least [constant HouseLayouts.MIN_DOOR_WIDTH] wide and 2.4 m tall.
func _test_walkthrough() -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	for tier in [HouseLayouts.Tier.LOW, HouseLayouts.Tier.MEDIUM, HouseLayouts.Tier.HIGH]:
		await _fresh(tier, false)
		for e: HouseEntry in _house.entries.values():
			if not e.is_window():
				e._set_open(true)
		await _frames(2)
		var space := _house.get_world_3d().direct_space_state
		var blocked: Array[String] = []
		var narrow: Array[String] = []
		for e: HouseEntry in _house.entries.values():
			if e.is_window():
				continue
			if e.width < HouseLayouts.MIN_DOOR_WIDTH - 0.001:
				narrow.append(e.entry_id)
			var through := e.global_basis.z.normalized()
			var centre := e.global_position + Vector3.UP * 1.0
			for side: float in [1.0, -1.0]:
				var query := PhysicsShapeQueryParameters3D.new()
				query.shape = capsule
				query.collision_mask = 1
				query.transform = Transform3D(Basis.IDENTITY, centre + through * side)
				query.motion = -through * side * 2.0
				var hit := space.cast_motion(query)
				if hit[0] < 1.0:
					blocked.append("%s(%s)" % [e.entry_id, "out" if side > 0 else "in"])
		_check(narrow.is_empty(), "%s doors are >= %.1f m wide %s" % [_house.tier_name(), HouseLayouts.MIN_DOOR_WIDTH, str(narrow)])
		_check(blocked.is_empty(), "%s: the player fits through every door and arch %s" % [_house.tier_name(), str(blocked)])
	_check(HouseEntry.DOOR_HEIGHT >= 2.4 and House.WALL_HEIGHT >= 3.0, "doors clear the 1.8 m model with room to spare")


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


func _test_safe() -> void:
	await _fresh(HouseLayouts.Tier.MEDIUM, false)
	_house.set_safes_locked(true)
	var safe: LootContainer = _house.safes()[0]
	_check(safe.locked and not safe.can_search(), "a locked safe can't just be searched")
	var bag := CarryBag.of(_player)
	var value := bag.total_value()
	var game := safe.crack(_player)
	_check(game != null and game.active and game.hits_needed == 3, "cracking the safe opens the timing minigame")
	game.auto_step = false
	game.show_ui = false
	for i in game.hits_needed:
		game.pin = (game.sweet_start + game.sweet_end) * 0.5
		game.press()
	_check(not safe.locked and safe.is_searched, "a cracked safe opens and gets emptied")
	_check(bag.total_value() > value, "the safe's contents go in the bag")


func _test_dog() -> void:
	await _fresh(HouseLayouts.Tier.LOW, false)
	_check(_house.dog == null, "the low-income house has no dog")
	await _fresh(HouseLayouts.Tier.MEDIUM, false)
	var dog := _house.dog
	_check(dog != null and dog.is_alive(), "the medium house has a dog")
	dog.bark()
	_check(_session.police_call.is_counting() and _session.police_call.reason == PoliceCall.REASON_DOG, "a barking dog starts the neighbour timer before any break-in")

	await _fresh(HouseLayouts.Tier.MEDIUM, false)
	dog = _house.dog
	var tools := HitTools.of(_player)
	tools.give(HitTools.DOG_TREAT)
	var treats := tools.count(HitTools.DOG_TREAT)
	dog.interactable.perform(&"feed", _player)
	_check(dog.is_friendly() and tools.count(HitTools.DOG_TREAT) == treats - 1, "a treat makes the dog a friend")
	dog.bark()
	_check(not _session.police_call.is_active(), "a fed dog doesn't bark")

	await _fresh(HouseLayouts.Tier.HIGH, false)
	dog = _house.dog
	dog.take_damage(999.0, _player)
	EventBus.gunshot.emit(dog.global_position, _player)
	_check(not dog.is_alive() and _session.police_call.is_counting() and _session.police_call.reason == PoliceCall.REASON_GUNSHOT, "shooting the dog is loud: the countdown starts")


func _test_cameras_disabled() -> void:
	await _fresh(HouseLayouts.Tier.HIGH, false)
	var camera: SecurityCamera = _house.cameras[0]
	_check(camera.is_working() and _house.devices.has(HouseDevice.BREAKER) and _house.devices.has(HouseDevice.DVR), "the rich house has a breaker box and a recorder")
	(_house.devices[HouseDevice.BREAKER] as HouseDevice).interactable.perform(&"use", _player)
	_check(not _house.is_power_on() and not camera.is_working(), "cutting the power blinds the cameras")
	_check(_house.front_door().alarmed, "door alarms stay armed on battery")
	_house.cut_power(0.05)
	await _frames(10)
	_check(_house.is_power_on() and camera.is_working(), "the cameras come back when the power does")

	var tools := HitTools.of(_player)
	tools.give(HitTools.SPRAY_PAINT)
	var cans := tools.count(HitTools.SPRAY_PAINT)
	camera.spray(_player)
	_check(not camera.is_working() and tools.count(HitTools.SPRAY_PAINT) == cans - 1, "spray paint blinds a camera")
	_check(_house.cameras[1].is_working(), "the other cameras still work")

	var identity := HitIdentity.of(_player)
	identity.set_masked(false)
	identity.begin_hit()
	identity.witness(_heat, &"camera")
	_heat.add_area_heat(_session.heat_area, 30.0)
	_check(_heat.personal_heat > 0.0, "being caught on camera unmasked adds heat")
	(_house.devices[HouseDevice.DVR] as HouseDevice).interactable.perform(&"use", _player)
	_check(_house.dvr_unplugged and _heat.personal_heat == 0.0 and _heat.area_heat(_session.heat_area) < 30.0, "unplugging the recorder wipes the footage and its heat")
	var all_off := true
	for each in _house.cameras:
		all_off = all_off and not each.is_working()
	_check(all_off, "with the recorder unplugged no camera records")
	identity.end_hit()


func _test_crew() -> void:
	_session.crew.assign(CrewSlot.Role.LOOKOUT)
	await _fresh(HouseLayouts.Tier.LOW, false)
	_house.front_door().pick_lock(_player)
	_check(is_equal_approx(_session.police_call.time_left, HouseLayouts.NEIGHBOUR_SECONDS[HouseLayouts.Tier.LOW] * CrewSlot.LOOKOUT_TIME), "a lookout stretches the neighbour timer")
	_session.crew.dismiss(CrewSlot.Role.LOOKOUT)

	await _fresh(HouseLayouts.Tier.LOW, true)
	var muscle := _session.crew.assign(CrewSlot.Role.MUSCLE)
	var owner_node: Homeowner = _house.alive_owners()[0]
	muscle.global_position = owner_node.global_position + Vector3(1.0, 0.0, 0.0)
	_check(muscle._hold_nearby() >= 1 and owner_node.is_held(), "muscle holds the owners")
	owner_node.alert(_player.global_position)
	_check(not owner_node.is_phoning(), "a held owner can't phone the police")
	_session.crew.dismiss(CrewSlot.Role.MUSCLE)