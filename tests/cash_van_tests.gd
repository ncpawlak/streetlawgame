extends RefCounted
## Cash van hit driver tests (drivers/cash_van). Instantiates the driver scene far away from the city,
## runs the whole hit (tires -> stop -> guards -> doors -> bag -> police escalation -> stash), then
## frees it and restores the main player.

const DRIVER_SCENE := "res://drivers/cash_van/cash_van_driver.tscn"
## Keep the driver's highway well clear of the city.
const OFFSET := Vector3(0.0, 0.0, 6000.0)

var _runner: Node


func _init(runner: Node) -> void:
	_runner = runner


func run(main: Node) -> void:
	var main_player: Player = GameState.player
	var cash := GameState.cash
	var respect := GameState.respect
	await _test_intel_briefing(main)
	await _test_no_intel(main)
	await _test_heat_and_crew(main)
	var driver: CashVanDriver = load(DRIVER_SCENE).instantiate()
	driver.position = OFFSET
	driver.heat_map_override = HeatMap.new()
	driver.has_intel = true
	driver.show_briefing = false
	driver.departure_delay = 0.0
	main.add_child(driver)
	await _runner._physics_frames(10)
	var player := driver.player
	var van := driver.van

	_runner._check(GameState.player == player and not player.is_on_foot(), "cash van: player starts in the chase car")
	_runner._check(van.state == ArmoredVan.State.DRIVING and van.speed > 10.0, "cash van: van drives the loop at speed")
	var before := van.distance
	await _runner._physics_frames(30)
	_runner._check(van.distance > before + 3.0 and van.global_position.distance_to(driver.route.global_sample(van.distance, van.lane).origin) < 1.0, "cash van: van follows the highway route")

	van.drive_enabled = false
	await _test_tires(driver, van, player)
	await _test_stop_and_guards(driver, van)
	await _test_doors_and_bag(driver, van, player)
	await _test_escalation(driver, player)
	_test_stash(driver, player)

	driver.queue_free()
	await _runner._physics_frames(2)
	GameState.player = main_player
	var camera := main_player.find_child("Camera3D", true, false) as Camera3D
	if main_player.is_on_foot() and camera != null:
		camera.make_current()
	GameState.cash = cash
	GameState.respect = respect


func _test_intel_briefing(main: Node) -> void:
	var driver: CashVanDriver = load(DRIVER_SCENE).instantiate()
	driver.position = OFFSET
	driver.heat_map_override = HeatMap.new()
	driver.has_intel = true
	driver.departure_delay = 1.0
	main.add_child(driver)
	await _runner._physics_frames(5)
	var intel := driver.intel
	_runner._check(driver.phase == CashVanDriver.Phase.BRIEFING and driver.briefing.visible and driver.van == null, "cash van intel: briefing comes first, van not on the road yet")
	var text := "\n".join(intel.lines())
	_runner._check(intel.known and intel.start_distance == CashVanDriver.VAN_ON_RAMP_DISTANCE and text.contains("leaves the on-ramp in 1s"), "cash van intel: reveals the route and schedule")
	_runner._check(intel.guard_count == 3 and intel.guard_loadout.size() == 3 and text.contains("Guards: 3"), "cash van intel: reveals guard count and loadout (%s)" % ", ".join(intel.guard_loadout))
	_runner._check(intel.cargo_value == 3470 and intel.cargo_slots == 12 and text.contains("$3470"), "cash van intel: reveals the cargo value")
	_runner._check(driver.route.get_node_or_null("IntelRoute") != null and driver.route.get_node_or_null("OnRampBeacon") != null, "cash van intel: route is marked on the road before the hit")
	await _runner._physics_frames(90)
	_runner._check(driver.van == null and driver.phase == CashVanDriver.Phase.BRIEFING, "cash van intel: the van waits for the briefing to end")
	driver.start_hit()
	_runner._check(driver.phase == CashVanDriver.Phase.WAIT and driver.van == null and driver.objective_text().contains("on-ramp"), "cash van intel: after the briefing, a known departure countdown")
	await _runner._physics_frames(75)
	var van := driver.van
	_runner._check(van != null and driver.phase == CashVanDriver.Phase.CHASE and absf(van.distance - CashVanDriver.VAN_ON_RAMP_DISTANCE) < 15.0, "cash van intel: van leaves the on-ramp on schedule")
	await _runner._physics_frames(2)
	_runner._check(driver.route.get_node_or_null("OnRampBeacon") == null, "cash van intel: on-ramp beacon clears when the van leaves")
	driver.queue_free()
	await _runner._physics_frames(2)


func _test_no_intel(main: Node) -> void:
	var driver: CashVanDriver = load(DRIVER_SCENE).instantiate()
	driver.position = OFFSET
	driver.heat_map_override = HeatMap.new()
	driver.has_intel = false
	driver.intel_seed = 7
	main.add_child(driver)
	await _runner._physics_frames(5)
	var intel := driver.intel
	var text := "\n".join(intel.lines())
	_runner._check(not intel.known and text.contains("Route: UNKNOWN") and text.contains("Schedule: UNKNOWN") and text.contains("Guards: UNKNOWN") and text.contains("Cargo: UNKNOWN"), "cash van no intel: route, schedule, guards and cargo unknown")
	_runner._check(driver.route.get_node_or_null("IntelRoute") == null and driver.route.get_node_or_null("OnRampBeacon") == null, "cash van no intel: no route marked")
	var delay_ok := intel.departure_delay >= CashVanIntel.UNKNOWN_DELAY_RANGE.x and intel.departure_delay <= CashVanIntel.UNKNOWN_DELAY_RANGE.y
	_runner._check(delay_ok and intel.start_distance != CashVanDriver.VAN_ON_RAMP_DISTANCE, "cash van no intel: van leaves from an unknown spot after an unknown wait (%.0f m, %.1f s)" % [intel.start_distance, intel.departure_delay])
	driver.start_hit()
	_runner._check(driver.objective_text().contains("Find the cash van") and not driver.objective_text().contains("leaves"), "cash van no intel: no departure countdown shown")
	driver.queue_free()
	await _runner._physics_frames(2)


func _test_tires(driver: CashVanDriver, van: ArmoredVan, player: Player) -> void:
	var rifle := GameState.weapon_data(&"rifle")
	var front_left := van.get_tire(&"front_left")
	_runner._check(van.tires.size() == 4 and driver.hit_time < 0.0, "cash van: four tires, hit clock not started")
	var exclude: Array[RID] = [player.get_rid(), player.current_vehicle.get_rid()]
	var hits := 0
	for i in 2:
		var muzzle := van.to_global(Vector3(3.5, 0.5, 1.8))
		hits += Hitscan.fire(player, muzzle, front_left.global_position - muzzle, rifle, exclude)
	var others_untouched := true
	for tire in van.tires:
		if tire != front_left and tire.health < tire.max_health:
			others_untouched = false
	_runner._check(hits == 2 and front_left.health < front_left.max_health and others_untouched, "cash van: a shot damages only the tire it hits")
	_runner._check(driver.hit_time >= 0.0 and driver.session.police_call.is_counting(), "cash van: shooting the van starts the hit clock and the panic-button countdown")
	while not front_left.is_flat() and hits < 6:
		var muzzle := van.to_global(Vector3(3.5, 0.5, 1.8))
		hits += Hitscan.fire(player, muzzle, front_left.global_position - muzzle, rifle, exclude)
	_runner._check(front_left.is_flat() and van.flats() == 1, "cash van: enough hits flatten that tire (tracked per tire)")
	await _runner._physics_frames(60)
	var one_flat := van.speed
	_runner._check(one_flat < van.base_speed - 1.0 and not van.is_stopped(), "cash van: one flat slows the van (%.1f m/s)" % one_flat)
	van.get_tire(&"rear_right").pop()
	van.get_tire(&"front_right").pop()
	await _runner._physics_frames(60)
	_runner._check(van.flats() == 3 and van.speed < one_flat and not van.is_stopped(), "cash van: each flat slows it more, still rolling on 3 (%.1f m/s)" % van.speed)
	var guards_before := _runner.get_tree().get_nodes_in_group("van_guards").size()
	_runner._check(guards_before == 0, "cash van: no guards while the van is moving")


func _test_stop_and_guards(driver: CashVanDriver, van: ArmoredVan) -> void:
	var player := driver.player
	_runner._check(not van.can_release_doors(player), "cash van: doors can't be released while the van is moving")
	van.get_tire(&"rear_left").pop()
	for i in 300:
		if van.is_stopped():
			break
		await _runner._physics_frames(1)
	_runner._check(van.is_stopped() and van.speed == 0.0 and van.flats() == 4, "cash van: four flats stop the van")
	_runner._check(driver.phase == CashVanDriver.Phase.VAN_DOWN, "cash van: objective moves to releasing the doors")
	var guards := _runner.get_tree().get_nodes_in_group("van_guards")
	var armed := true
	for guard in guards:
		armed = armed and (guard as VanGuard).current_weapon() != null and guard.global_position.distance_to(van.global_position) < 6.0
	_runner._check(guards.size() == van.guard_count and armed, "cash van: armed guards bail out next to the van")
	var modelled := not guards.is_empty()
	for guard in guards:
		var gv: CharacterVisual = (guard as VanGuard).visual
		modelled = modelled and gv != null and gv.get_parent() == guard and gv.model_id != &"" and gv.is_armed()
	_runner._check(modelled and (guards[0] as VanGuard).get_children().filter(func(c): return c is CharacterVisual).size() == 1, "cash van: guards use one armed character model each")
	for guard in guards:
		(guard as VanGuard).take_damage(1000.0, player)


func _test_doors_and_bag(driver: CashVanDriver, van: ArmoredVan, player: Player) -> void:
	player.current_vehicle.exit()
	await _runner._physics_frames(2)
	player.global_position = van.rear_point() + Vector3(0.0, -0.9, 0.0)
	_runner._check(not van.rear_interactable.perform(&"open", player), "cash van: rear doors stay locked from the back")
	_runner._check(not van.front_interactable.perform(&"release_doors", player) and not van.doors_open, "cash van: door release fails away from the cab")
	player.global_position = van.front_point() + Vector3(0.0, -0.9, 0.0)
	_runner._check(van.front_interactable.perform(&"release_doors", player) and van.doors_open, "cash van: door release works from the front")
	_runner._check(van.loot.size() == 8 and driver.phase == CashVanDriver.Phase.LOOT, "cash van: cargo spills out as loot")

	var bag := driver.session.bag
	var slots := 0
	for item in van.loot:
		slots += item.slots
	_runner._check(slots > bag.capacity, "cash van: more cargo (%d slots) than the bag holds (%d)" % [slots, bag.capacity])
	var sacks: Array[LootItem] = []
	var bundle: LootItem
	for item in van.loot:
		if item.item_name == "Cash sack":
			sacks.append(item)
		elif item.item_name == "Cash bundle" and bundle == null:
			bundle = item
	for sack in sacks:
		sack.take(player)
	_runner._check(bag.used_slots() == bag.capacity and bag.total_value() == 2600, "cash van: four sacks fill the bag ($%d)" % bag.total_value())
	_runner._check(not bundle.can_take(player) and not bundle.take(player) and bag.used_slots() == bag.capacity, "cash van: a full bag rejects more cargo")
	await _runner._physics_frames(2)
	_runner._check(driver.phase == CashVanDriver.Phase.ESCAPE, "cash van: full bag with cops coming -> escape")


func _test_escalation(driver: CashVanDriver, player: Player) -> void:
	var response := driver.session.police_response
	driver.hit_time = 1.0
	driver.session.police_call.call_now(PoliceCall.REASON_ALARM)
	_runner._check(response.is_wanted() and driver.alive_cruisers().size() == 1, "cash van: police arrive with one cruiser early on")
	var cops_early := response.alive_cops().size()
	driver.hit_time = 1.0 + CashVanDriver.ESCALATION_INTERVAL * 2.0
	response.update(CashVanDriver.ESCALATION_INTERVAL)
	var cruisers_late := driver.alive_cruisers().size()
	_runner._check(response.waves == 2 and cruisers_late == 1 + 3, "cash van: a later wave brings more cruisers (%d)" % cruisers_late)
	_runner._check(response.alive_cops().size() > cops_early, "cash van: and a roadblock of cops on foot (%d)" % response.alive_cops().size())
	var cop: Cop = response.alive_cops()[0]
	_runner._check(cop.visual != null and cop.visual.get_parent() == cop and cop.get_children().filter(func(c): return c is CharacterVisual).size() == 1, "cash van: cops use the police character model")
	var cruiser := driver.alive_cruisers()[0]
	var cops_before := response.cops.size()
	cruiser.take_damage(cruiser.max_health, player)
	_runner._check(cruiser.bailed_out and response.cops.size() == cops_before + cruiser.cops_per_car, "cash van: a wrecked cruiser bails its cops into the chase")
	await _runner._physics_frames(2)


func _test_stash(driver: CashVanDriver, player: Player) -> void:
	var stash := driver.stash
	_runner._check(not stash.can_cash_in(player), "cash van: can't stash while wanted")
	driver.session.police_response.stand_down()
	var cash := GameState.cash
	var paid := stash.cash_in(player)
	_runner._check(paid == 2600 and GameState.cash == cash + 2600 and driver.phase == CashVanDriver.Phase.DONE, "cash van: stashing the bag pays out and finishes the hit")


func _heat_driver(main: Node, heat: HeatMap) -> CashVanDriver:
	var driver: CashVanDriver = load(DRIVER_SCENE).instantiate()
	driver.position = OFFSET
	driver.heat_map_override = heat
	driver.has_intel = true
	driver.show_briefing = false
	driver.departure_delay = 0.0
	main.add_child(driver)
	await _runner._physics_frames(5)
	driver.van.drive_enabled = false
	return driver


## Carry-over I-59 heat, mask + swap car, and the lookout / driver / muscle crew slots.
func _test_heat_and_crew(main: Node) -> void:
	var heat := HeatMap.new()
	var area := CashVanDriver.HEAT_AREA
	# Hit 1: no crew, no mask, police never called.
	var driver := await _heat_driver(main, heat)
	var session := driver.session
	var player := driver.player
	_runner._check(session.heat_area == area and session.police_response.heat_area == area and driver.stash.heat_area == area, "cash van heat: the hit counts towards the I-59 heat area")
	driver.van.attacked.emit(player)
	_runner._check(session.in_progress and session.police_call.is_counting() and session.police_call.hidden, "cash van crew: without a lookout the panic-button call is silent")
	_runner._check(session.identity.face_seen and is_equal_approx(heat.personal_heat, HeatMap.FACE_HEAT) and session.identity.seen_vehicle == driver.getaway_car, "cash van mask: unmasked, the van cam gets your face and the chase car")
	session.reset()
	_runner._check(is_equal_approx(heat.area_heat(area), HeatMap.HIT_HEAT) and not session.in_progress, "cash van heat: ending the hit adds I-59 area heat (%.0f)" % heat.area_heat(area))
	driver.queue_free()
	await _runner._physics_frames(2)

	# Hit 2: the area is hotter now - more cops, shorter countdown. Lookout, driver and muscle on.
	heat.personal_heat = 0.0
	heat.add_area_heat(area, 30.0)
	driver = await _heat_driver(main, heat)
	session = driver.session
	player = driver.player
	var extra := heat.extra_cops(area)
	_runner._check(extra == 2 and driver.heat_extra() == extra and driver.cruisers_per_wave() == 1 + extra, "cash van heat: a hot I-59 adds %d cops and cruisers per wave" % extra)
	_runner._check(driver.briefing_lines()[1].contains("+2"), "cash van heat: the briefing shows the heat and the extra cops")
	driver.toggle_crew(CrewSlot.Role.LOOKOUT)
	driver.toggle_crew(CrewSlot.Role.DRIVER)
	session.identity.set_masked(true)
	await _runner._physics_frames(2)
	driver.van.attacked.emit(player)
	var expected := CashVanDriver.PANIC_SECONDS * CrewSlot.LOOKOUT_TIME * heat.countdown_multiplier(area)
	_runner._check(session.police_call.is_counting() and not session.police_call.hidden and absf(session.police_call.time_left - expected) < 0.2, "cash van crew: the lookout reveals the panic-button call and buys time (%.1f s)" % session.police_call.time_left)
	_runner._check(session.police_call.countdown_scale < CrewSlot.LOOKOUT_TIME, "cash van heat: heat shortens the countdown (x%.2f)" % session.police_call.countdown_scale)
	_runner._check(not session.identity.face_seen and heat.personal_heat == 0.0, "cash van mask: masked, the van cam gets nothing")
	session.police_call.call_now(PoliceCall.REASON_ALARM)
	_runner._check(driver.alive_cruisers().size() == 1 + extra and session.police_response.alive_cops().size() == extra, "cash van heat: the first wave brings the heat's extra cops (%d) and cruisers (%d)" % [session.police_response.alive_cops().size(), driver.alive_cruisers().size()])
	await _runner._physics_frames(2)
	_runner._check(player.current_vehicle == driver.getaway_car and is_equal_approx(session.police_response.escape_rate, CrewSlot.DRIVER_ESCAPE), "cash van crew: the driver speeds up the escape in the chase car (x%.1f)" % session.police_response.escape_rate)

	# Muscle holds a guard.
	player.current_vehicle.exit()
	await _runner._physics_frames(2)
	driver.toggle_crew(CrewSlot.Role.MUSCLE)
	var guard := VanGuard.new()
	guard.weapon_id = &"smg"
	driver.add_child(guard)
	guard.global_position = player.global_position + Vector3(3.0, 0.5, 0.0)
	await _runner._physics_frames(6)
	_runner._check(guard.is_in_group("hostages") and guard.is_held() and is_equal_approx(Vector2(guard.velocity.x, guard.velocity.z).length(), 0.0), "cash van crew: the muscle holds a guard (hands up, not moving)")
	guard.queue_free()

	# Mask off + swap car = heat drops fastest; the chase car keeps it slow.
	_runner._check(session.identity.seen_vehicle == driver.getaway_car, "cash van mask: police note the chase car")
	driver.getaway_car.enter(player)
	await _runner._physics_frames(2)
	var marked := session.identity.decay_multiplier()
	player.current_vehicle.exit()
	session.identity.set_masked(false)
	driver.swap_car.enter(player)
	await _runner._physics_frames(2)
	var clean := session.identity.decay_multiplier()
	_runner._check(marked == HitIdentity.MARKED and clean == HitIdentity.CLEAN_SWAP and session.police_response.escape_multiplier() > 1.0, "cash van mask: mask off in the swap car sheds heat x%.1f (chase car with mask x%.1f)" % [clean, marked])
	heat.personal_heat = 50.0
	GameState.player = player
	heat._process(1.0)
	var swap_drop := 50.0 - heat.personal_heat
	_runner._check(is_equal_approx(swap_drop, heat.personal_decay * HitIdentity.CLEAN_SWAP), "cash van mask: personal heat decays x4 after the clean swap")
	var before := heat.area_heat(area)
	session.reset()
	_runner._check(heat.area_heat(area) > before + HeatMap.HIT_HEAT, "cash van heat: a hit with the police called adds extra area heat (%.0f -> %.0f)" % [before, heat.area_heat(area)])
	driver.queue_free()
	await _runner._physics_frames(2)
