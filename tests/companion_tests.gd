class_name CompanionTests
extends RefCounted
## Tests for passengers and companions: every registry vehicle lists its passenger seats with
## markers, the occupancy API, NPC (ally) animated boarding through doors / the bus / a pillion,
## the player riding along (hold E) and switching seats (X), NPCs bailing out of flipped and wrecked
## vehicles, the NPC driver, and the Ally / Party follower framework (follow, teleport, lead_to,
## commands, crew size, auto-boarding, downed and revive). Runs on its own ground far from the city.

const TEST_ORIGIN := Vector3(700.0, 400.0, 0.0)

var _runner: Node
var _ground: StaticBody3D
var _spawned: Array[Node] = []


func _init(runner: Node) -> void:
	_runner = runner


func _check(condition: bool, description: String) -> void:
	_runner.call("_check", condition, "companions: " + description)


func run(player: Player) -> void:
	var home := player.global_position
	Party.clear()
	_test_registry()
	_build_ground()
	await _test_occupancy()
	await _test_npc_boarding()
	await _test_player_passenger(player)
	await _test_bailing_out()
	await _test_follow_and_commands(player)
	await _test_lead_to(player)
	await _test_auto_board(player)
	await _test_npc_driver(player)
	await _test_combat_and_revive(player)
	_test_drive_plan()
	if player.current_vehicle != null:
		player.current_vehicle.exit_seat(player)
	player.cancel_moves()
	Party.clear()
	for node in _spawned:
		if is_instance_valid(node):
			node.free()
	_ground.free()
	player.global_position = home
	player.velocity = Vector3.ZERO


func _test_registry() -> void:
	var problems: Array[String] = []
	for entry: Dictionary in VehicleCatalog.entries():
		if not entry["drivable"]:
			continue
		var listed: Array = (entry["ride"] as Dictionary).get("passengers", [])
		if listed.size() != int(entry["seats"]) - 1:
			problems.append("%s lists %d of %d passengers" % [entry["id"], listed.size(), int(entry["seats"]) - 1])
			continue
		var scene := (load(entry["scene"]) as PackedScene).instantiate()
		for data: Dictionary in listed:
			var marker := scene.get_node_or_null("Seats/" + String(data["seat"])) as Node3D
			if marker == null:
				problems.append("%s has no Seats/%s" % [entry["id"], data["seat"]])
			elif marker.position.distance_to(Vector3(data["hip"][0], data["hip"][1], data["hip"][2])) > 0.01:
				problems.append("%s %s marker != registry hip" % [entry["id"], data["seat"]])
			if String(data.get("door", "")) != "" and not scene.has_node("Doors/%s/Handle" % data["door"]):
				problems.append("%s %s door %s has no handle" % [entry["id"], data["seat"], data["door"]])
			if String(data["entry"]) in ["door", "open", "bus"] and not data.has("stand"):
				problems.append("%s %s has no stand" % [entry["id"], data["seat"]])
		scene.free()
	_check(problems.is_empty(), "every drivable vehicle lists passenger seats with markers, doors and stands (%s)" % ", ".join(problems))
	var rustbucket := VehicleCatalog.find(&"rustbucket")
	var doors: Array[String] = []
	for data: Dictionary in rustbucket["ride"]["passengers"]:
		doors.append(String(data["door"]))
	_check(doors == ["Passenger1", "Passenger2", "Passenger3"], "a four-door car boards each passenger through their own door")
	_check(String(VehicleCatalog.find(&"transit")["ride"]["passengers"][0]["entry"]) == "bus"
		and String(VehicleCatalog.find(&"razorback")["ride"]["passengers"][0]["entry"]) == "straddle", "bus seats board via the aisle and the bike pillion is straddled")


func _test_occupancy() -> void:
	var car := _vehicle(&"rustbucket", Vector3(0.0, 0.3, 0.0))
	var a := _ally("A", Vector3(-5.0, 0.0, 0.0))
	var b := _ally("B", Vector3(-6.0, 0.0, 0.0))
	await _frames(30)
	_check(car.seat_count() == 4 and car.free_seat() == 0 and car.free_seat(true) == 1, "an empty car offers the driver's seat, then passenger seat 1")
	car.enter_seat(a, 1)
	car.enter_seat(b, 0)
	_check(car.occupant(1) == a and car.seat_of(b) == 0 and car.occupants() == [b, a] and car.passengers() == [a], "enter_seat seats NPCs and the occupancy queries list them")
	_check(a.current_vehicle == car and not a.is_on_foot() and car.can_ride_along() and not car.can_enter(), "a seated NPC is in the car and the player can only ride along")
	_check(car.switch_seat(a) and car.seat_of(a) == 2 and car.is_seat_free(1), "switch_seat moves to the next free seat")
	await _frames(20)
	var hips := a.visual.hips_position()
	var seat := car.global_transform * (car.get_node("Seats/Passenger2") as Node3D).position
	_check(hips.distance_to(seat) < 0.25, "the passenger sits on their seat (hips %.2f m off)" % hips.distance_to(seat))
	var exits := [0]
	car.occupant_exited.connect(func(_who: Node3D, _seat: int) -> void: exits[0] += 1)
	car.eject_all()
	_check(car.occupants().is_empty() and a.is_on_foot() and b.is_on_foot() and exits[0] == 2, "eject_all puts everyone outside")
	_check(a.global_position.distance_to(car.global_position) > 1.0, "ejected NPCs land outside the car")
	_free(a)
	_free(b)
	_free(car)


## Allies board a front and rear door (door swings, hips on the seat), the bus aisle and the pillion,
## then climb out beside their stand.
func _test_npc_boarding() -> void:
	var cases := [[&"rustbucket", 1], [&"rustbucket", 3], [&"hopper", 2], [&"transit", 5], [&"razorback", 1], [&"palmetto", 1]]
	var index := 0
	for case: Array in cases:
		var id: StringName = case[0]
		var seat: int = case[1]
		var car := _vehicle(id, Vector3(index * 20.0, 0.3, 40.0))
		index += 1
		await _frames(45)
		var info := car.seat_info(seat)
		var stand: Vector3 = info.get("stand", Vector3.ZERO)
		var ally := _ally("Rider", car.global_transform * (stand + Vector3(signf(stand.x) * 3.0, 0.0, 1.0)))
		await _frames(5)
		var began := car.begin_enter_seat(ally, seat)
		var reserved := not car.is_seat_free(seat) and car.reserved_seat_of(ally) == seat
		var door := car.get_node_or_null("Doors/" + String(info["door"])) as Node3D if info["door"] != "" else null
		var swing := 0.0
		for frame in 1200:
			if not ally.is_busy():
				break
			await _frames(1)
			if door != null:
				swing = maxf(swing, absf(door.rotation.y))
		await _frames(10)
		var marker := car.get_node_or_null("Seats/Passenger%d" % seat) as Node3D
		var hip := car.global_transform * (marker.position if marker != null else (info["hip"] as Vector3))
		var hips := ally.visual.hips_position()
		_check(began and reserved and car.seat_of(ally) == seat and ally.current_vehicle == car, "%s seat %d: an NPC gets in with an animated walk-up" % [id, seat])
		_check(hips.distance_to(hip) < 0.25, "%s seat %d: the NPC's hips rest on the seat (%.2f m off)" % [id, seat, hips.distance_to(hip)])
		if door != null:
			_check(swing > 0.8 and absf(door.rotation.y) < 0.05, "%s seat %d: the %s door opens and shuts (%.2f rad)" % [id, seat, info["door"], swing])
		_check(car.begin_exit_seat(ally) and car.occupant(seat) == null, "%s seat %d: the NPC starts climbing out" % [id, seat])
		for frame in 1200:
			if not ally.is_busy():
				break
			await _frames(1)
		var out := car.global_transform * stand
		var flat := Vector2(ally.global_position.x - out.x, ally.global_position.z - out.z).length()
		_check(ally.is_on_foot() and flat < 1.2 and ally.global_basis.y.y > 0.99, "%s seat %d: the NPC ends standing by the vehicle (%.2f m)" % [id, seat, flat])
		_free(ally)
		_free(car)


func _test_player_passenger(player: Player) -> void:
	var car := _vehicle(&"regent", Vector3(0.0, 0.3, 80.0))
	await _frames(45)
	var stand := car.global_transform * (car.get_node("DoorStand") as Node3D).position
	player.global_position = stand + Vector3(0.0, 0.1, 0.0)
	player.velocity = Vector3.ZERO
	await _frames(12)
	_action("interact", true)
	await _frames(40)
	_action("interact", false)
	var seat := car.reserved_seat_of(player)
	_check(seat >= 1, "holding E at a free car gets in as a passenger (seat %d)" % seat)
	for frame in 900:
		if not player.is_busy():
			break
		await _frames(1)
	_check(car.seat_of(player) >= 1 and player.current_vehicle == car and car.driver == null and car.has_player(), "the player rides as a passenger")
	_action("switch_seat", true)
	_action("switch_seat", false)
	await _frames(2)
	_check(car.seat_of(player) == 2, "X switches the player to the next free seat (now %d)" % car.seat_of(player))
	_check(car.switch_seat(player, 0) and car.driver == player, "the player can slide over into the driver's seat")
	car.exit_seat(player)
	await _frames(5)
	_check(player.is_on_foot() and not car.has_player(), "the player gets out")

	var npc := _ally("Driver", car.global_transform * Vector3(4.0, 0.0, 0.0))
	car.enter_seat(npc, 0)
	_check(car.can_ride_along() and not car.can_enter(), "with an NPC driving, the car offers \"Ride along\" instead of stealing it")
	car.begin_ride_along(player)
	for frame in 900:
		if not player.is_busy():
			break
		await _frames(1)
	_check(car.seat_of(player) >= 1 and car.seat_of(npc) == 0, "riding along seats the player beside the NPC driver")
	car.exit_seat(player)
	_free(npc)
	_free(car)


func _test_bailing_out() -> void:
	var car := _vehicle(&"meridian", Vector3(40.0, 0.3, 80.0))
	var ally := _ally("Bail", Vector3(44.0, 0.0, 80.0))
	await _frames(30)
	car.enter_seat(ally, 1)
	var flips := [0]
	car.flipped.connect(func() -> void: flips[0] += 1)
	car.global_transform = Transform3D(Basis(Vector3.FORWARD, PI), car.global_position + Vector3.UP * 3.0)
	car.linear_velocity = Vector3.ZERO
	car.sleeping = false
	await _frames(int((Vehicle.FLIP_TIME + 1.5) * 60.0))
	_check(flips[0] == 1 and car.is_flipped() and ally.is_on_foot(), "NPCs climb out of a vehicle that's on its roof")
	_check(ally.global_basis.y.y > 0.99, "bailed-out NPCs stand upright")
	_check(car.health == car.max_health and car.linear_velocity.length() < 1.0, "climbing out doesn't shove the vehicle (%.1f m/s)" % car.linear_velocity.length())
	_free(car)
	car = _vehicle(&"meridian", Vector3(60.0, 0.3, 80.0))
	await _frames(30)
	car.enter_seat(ally, 1)
	car.take_damage(car.max_health * 2.0)
	await _frames(5)
	_check(ally.is_on_foot() and car.occupants().is_empty(), "a wrecked vehicle throws its occupants out")
	_free(ally)
	_free(car)


func _test_follow_and_commands(player: Player) -> void:
	_place_player(player, Vector3(0.0, 0.0, 120.0))
	var allies: Array[Ally] = []
	for i in 4:
		allies.append(_ally("Homie %d" % i, Vector3(-3.0 - i, 0.0, 120.0)))
	await _frames(10)
	_check(Party.recruit(allies[0]) and Party.recruit(allies[1]) and Party.recruit(allies[2]), "the crew takes up to max_followers allies")
	_check(not Party.recruit(allies[3]) and not allies[3].can_recruit(), "a full crew turns away the next recruit")
	_check(allies[0].gang_id == GameState.PLAYER_GANG and allies[0].is_in_group("allies"), "allies are in the player's gang")
	_check(allies[0].mode == Ally.Mode.FOLLOW, "recruits follow the player")
	_place_player(player, Vector3(15.0, 0.0, 120.0))
	await _frames(300)
	var gap := allies[0].global_position.distance_to(Party.formation_point(allies[0]))
	_check(gap < 1.5, "followers catch up to their formation slot (%.2f m)" % gap)
	var spots := [Party.formation_point(allies[0]), Party.formation_point(allies[1]), Party.formation_point(allies[2])]
	_check(spots[0].distance_to(spots[1]) > 1.0 and spots[1].distance_to(spots[2]) > 1.0, "each follower gets their own formation slot")

	_place_player(player, Vector3(90.0, 0.0, 120.0))
	await _frames(5)
	gap = allies[0].global_position.distance_to(player.global_position)
	_check(gap < 8.0, "a follower left far behind teleports to the player (%.1f m)" % gap)

	Party.command_all(&"hold")
	var held := allies[1].global_position
	_place_player(player, Vector3(110.0, 0.0, 120.0))
	await _frames(120)
	_check(allies[1].mode == Ally.Mode.HOLD and allies[1].global_position.distance_to(held) < 1.5, "hold keeps followers in place")
	Party.command_all(&"toggle")
	_check(allies[1].mode == Ally.Mode.FOLLOW, "the crew command toggles back to follow")
	Party.dismiss(allies[2])
	_check(not Party.is_member(allies[2]) and allies[2].mode == Ally.Mode.IDLE and Party.has_room(), "dismissing frees a crew slot")
	Party.command_all(&"dismiss")
	_check(Party.members.is_empty(), "dismiss sends the whole crew home")
	for ally in allies:
		_free(ally)


func _test_lead_to(player: Player) -> void:
	_place_player(player, Vector3(0.0, 0.0, 160.0))
	var pedro := _ally("Pedro", Vector3(2.0, 0.0, 160.0))
	await _frames(10)
	var goal := TEST_ORIGIN + Vector3(25.0, 0.0, 160.0)
	var arrived := [false]
	pedro.lead_to(goal, 8.0).connect(func() -> void: arrived[0] = true, CONNECT_ONE_SHOT)
	_place_player(player, Vector3(-30.0, 0.0, 160.0))
	await _frames(240)
	var progress := pedro.global_position.distance_to(TEST_ORIGIN + Vector3(2.0, 0.0, 160.0))
	_check(not arrived[0] and pedro.mode == Ally.Mode.LEAD and progress < 2.0, "leading waits for a player who lags behind (moved %.1f m)" % progress)
	for step in 12:
		_place_player(player, (pedro.global_position - TEST_ORIGIN) + Vector3(-2.0, 0.0, 0.0))
		await _frames(30)
		if arrived[0]:
			break
	_check(arrived[0] and _flat(pedro.global_position).distance_to(_flat(goal)) < 2.5, "lead_to reaches the target and emits arrived")
	_check(pedro.mode == Ally.Mode.IDLE, "after leading the ally goes back to what they were doing")

	var car := _vehicle(&"rustbucket", Vector3(40.0, 0.3, 160.0))
	await _frames(30)
	arrived[0] = false
	pedro.lead_to(car, 30.0).connect(func() -> void: arrived[0] = true, CONNECT_ONE_SHOT)
	for frame in 600:
		if arrived[0]:
			break
		await _frames(1)
	_check(arrived[0] and pedro.enter_vehicle(car, 1), "leading to a car stops at its passenger door, ready to board")
	for frame in 900:
		if pedro.current_vehicle == car and not pedro.is_busy():
			break
		await _frames(1)
	_check(car.seat_of(pedro) == 1, "the ally boards the car they led the player to")
	_free(pedro)
	_free(car)


func _test_auto_board(player: Player) -> void:
	_place_player(player, Vector3(0.0, 0.0, 200.0))
	var car := _vehicle(&"rustbucket", Vector3(6.0, 0.3, 200.0))
	var a := _ally("Left", Vector3(-3.0, 0.0, 198.0))
	var b := _ally("Right", Vector3(-3.0, 0.0, 202.0))
	await _frames(30)
	Party.recruit(a)
	Party.recruit(b)
	car.enter(player)
	for frame in 900:
		if a.current_vehicle == car and b.current_vehicle == car and not a.is_busy() and not b.is_busy():
			break
		await _frames(1)
	_check(car.seat_of(a) > 0 and car.seat_of(b) > 0 and car.seat_of(a) != car.seat_of(b), "followers pile into the player's car, one seat each (%d, %d)" % [car.seat_of(a), car.seat_of(b)])
	car.exit_seat(player)
	for frame in 900:
		if a.is_on_foot() and b.is_on_foot():
			break
		await _frames(1)
	_check(a.is_on_foot() and b.is_on_foot() and car.occupants().is_empty(), "followers get out when the player does")

	var bike := _vehicle(&"razorback", Vector3(20.0, 0.3, 200.0))
	await _frames(30)
	bike.enter(player)
	await _frames(2)
	for frame in 600:
		if bike.passengers().size() == 1 and not a.is_busy() and not b.is_busy():
			break
		await _frames(1)
	_check(bike.passengers().size() == 1, "only as many followers board as there are seats")
	bike.exit_seat(player)
	await _frames(240)
	Party.clear()
	_free(a)
	_free(b)
	_free(car)
	_free(bike)


func _test_npc_driver(player: Player) -> void:
	var car := _vehicle(&"regent", Vector3(0.0, 0.3, 240.0))
	var pedro := _ally("Pedro", Vector3(3.0, 0.0, 240.0))
	await _frames(45)
	car.enter_seat(pedro, 0)
	car.enter_seat(player, 1)
	NpcDriver.for_vehicle(car).use_roads = false
	var goal := car.global_position + car.global_basis.z * 45.0 + car.global_basis.x * 10.0
	var arrived := [false]
	pedro.drive_to(goal).connect(func() -> void: arrived[0] = true, CONNECT_ONE_SHOT)
	for frame in 900:
		if arrived[0]:
			break
		await _frames(1)
	var miss := _flat(car.global_position).distance_to(_flat(goal))
	_check(arrived[0] and miss < 8.0, "an NPC drives the player to a target (%.1f m off)" % miss)
	_check(car.seat_of(player) == 1 and car.ai_control and car.driver == null, "the player stays in the passenger seat while the NPC drives")
	NpcDriver.for_vehicle(car).stop()
	_check(not car.ai_control, "stopping the NPC driver hands the controls back")
	car.exit_seat(player)
	_free(pedro)
	_free(car)


func _test_combat_and_revive(player: Player) -> void:
	_place_player(player, Vector3(0.0, 0.0, 280.0))
	var ally := _ally("Fighter", Vector3(3.0, 0.0, 280.0))
	var rival := GangMember.new()
	rival.gang_id = &"vipers"
	rival.aggro_range = 0.0
	rival.alerted_range = 0.0
	_runner.add_child(rival)
	_spawned.append(rival)
	rival.global_position = TEST_ORIGIN + Vector3(10.0, 0.0, 280.0)
	await _frames(10)
	Party.recruit(ally)
	ally.health = ally.max_health
	_check(rival.call("_pick_target") == ally, "rivals target a closer ally over the player")
	await _frames(20)
	_check(ally.target == rival, "allies engage nearby rivals")
	var health := ally.health
	ally.take_damage(50.0, player)
	_check(ally.health == health, "the player can't hurt their own crew")
	ally.take_damage(1000.0, rival)
	await _frames(2)
	_check(ally.mode == Ally.Mode.DOWNED and not ally.is_targetable() and ally.can_revive(), "lethal damage downs an ally instead of killing them")
	var actions := ally.interactable.visible_actions(player)
	_check(actions.size() == 1 and actions[0].id == &"revive" and actions[0].duration > 0.0, "a downed ally offers a timed Revive")
	ally.revive()
	_check(ally.mode == Ally.Mode.FOLLOW and ally.health > 0.0 and Party.is_member(ally), "reviving puts the ally back in the fight")
	Party.safehouse_position = TEST_ORIGIN + Vector3(-20.0, 0.5, 280.0)
	ally.bleed_out_time = 0.1
	ally.take_damage(1000.0, rival)
	await _frames(20)
	_check(not Party.is_member(ally) and ally.is_alive() and ally.global_position.distance_to(Party.safehouse_position) < 1.5, "bleeding out drops the ally from the crew and respawns them at the safehouse")
	Party.safehouse_position = Vector3.ZERO
	_free(rival)
	_free(ally)


func _test_drive_plan() -> void:
	var straight := NpcDriver.plan(Vector3(5000.0, 0.0, 5000.0), Vector3(5100.0, 0.0, 5000.0))
	_check(straight.size() == 2, "off the street network the NPC driver heads straight for the target")
	var pts: Array = (NorthEndLayout.ROADS[0] as Dictionary)["pts"]
	var a := CityGenerator.px_to_world(pts[0])
	var b := CityGenerator.px_to_world(pts[pts.size() - 1])
	_check(NpcDriver.plan(a, b).size() >= 3, "on the street network the NPC driver follows a road route")


# --- Helpers ------------------------------------------------------------------------------------

func _build_ground() -> void:
	_ground = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 700.0)
	shape.shape = box
	_ground.add_child(shape)
	_runner.add_child(_ground)
	_ground.global_position = TEST_ORIGIN + Vector3(60.0, -0.5, 150.0)


func _vehicle(id: StringName, at: Vector3) -> Vehicle:
	var vehicle := VehicleCatalog.instantiate(id, 3) as Vehicle
	_runner.add_child(vehicle)
	vehicle.global_position = TEST_ORIGIN + at
	_spawned.append(vehicle)
	return vehicle


## [param at] is relative to the test origin, or a world point when already near it.
func _ally(ally_name: String, at: Vector3) -> Ally:
	var ally := Ally.new()
	ally.display_name = ally_name
	ally.visual_seed = 1
	_runner.add_child(ally)
	ally.global_position = (at if at.distance_to(TEST_ORIGIN) < 500.0 else TEST_ORIGIN + at) + Vector3.UP * 0.1
	_spawned.append(ally)
	return ally


func _place_player(player: Player, at: Vector3) -> void:
	player.global_position = TEST_ORIGIN + at + Vector3.UP * 0.1
	player.velocity = Vector3.ZERO


func _free(node: Node) -> void:
	if is_instance_valid(node):
		node.free()


func _action(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	_runner.get_viewport().push_input(event)


func _frames(count: int) -> void:
	await _runner.call("_physics_frames", count)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)

