class_name TrapTakeoverTests
extends RefCounted
## Tests for the trap takeover driver (drivers/trap_takeover/): house layout + navmesh, rival
## placement and re-roll, line of sight through walls, floor-to-floor pathing over the stairs, and
## the assault -> cleared -> claim -> complete flow. Hooked from run_tests.gd after main is freed.

const DRIVER_SCENE := preload("res://drivers/trap_takeover/trap_takeover_driver.tscn")

var _runner: Node


func _init(runner: Node) -> void:
	_runner = runner


func run() -> void:
	var driver := await _make_driver(-1)
	_test_boot(driver)
	_test_reroll(driver)
	_test_line_of_sight(driver)
	await _test_claim_flow(driver)
	_test_loud_entry(driver)
	await _test_quiet_entry(driver)
	await _test_alarm_timer(driver)
	await _test_keep(driver)
	await _test_destroy(driver)
	await _free(driver)
	driver = await _make_driver(0)
	await _test_stairs_navigation(driver)
	await _free(driver)
	_test_scale()


func _make_driver(enemies: int) -> TrapTakeoverDriver:
	var driver: TrapTakeoverDriver = DRIVER_SCENE.instantiate()
	driver.parse_cmdline = false
	driver.difficulty = TrapTakeoverDriver.Difficulty.NORMAL
	driver.enemy_count = enemies
	driver.rng_seed = 1234
	driver.god_mode = true
	_runner.get_tree().root.add_child(driver)
	_runner.get_tree().current_scene = driver
	await _runner._physics_frames(10)
	return driver


func _free(driver: Node) -> void:
	driver.queue_free()
	await _runner._physics_frames(3)


func _test_boot(driver: TrapTakeoverDriver) -> void:
	var navmesh := driver.builder.region.navigation_mesh
	_check(navmesh != null and navmesh.get_polygon_count() > 100, "trap house navmesh bakes (%d polygons)" % (navmesh.get_polygon_count() if navmesh else 0))
	_check(driver.builder.levels.size() == 4 and driver.builder.doors.size() == TrapHouseBuilder.SWING_DOORS.size(), "trap house builds basement, ground, upper floor, roof and swing doors")
	_check(driver.enemies.size() == 12 and driver.alive_enemies().size() == 12, "Normal difficulty places 12 rivals")
	var areas := {}
	for member in driver.enemies:
		areas[TrapHouseBuilder.area_of(member.global_position)] = true
	_check(areas.size() == 4, "rivals cover the yard and all three floors (%s)" % ", ".join(areas.keys()))
	_check(&"boss" in driver.placement, "Normal difficulty always places the boss")
	var landed := driver.enemies.all(func(member: IndoorGangMember) -> bool: return member.global_position.y > -3.3)
	_check(landed, "no rival falls through the floors")
	_check(driver.phase == TrapTakeoverDriver.Phase.ASSAULT and not driver.is_claimable(), "takeover starts in the assault phase")


func _test_reroll(driver: TrapTakeoverDriver) -> void:
	var first := driver.placement.duplicate()
	driver.start(1234)
	_check(driver.placement == first, "the same seed reproduces the same placement")
	driver.start(98765)
	_check(driver.placement.size() == first.size() and driver.placement != first, "re-rolling keeps the count but changes placement")
	driver.enemy_count = 5
	driver.start(1234)
	_check(driver.enemies.size() == 5 and driver.placement.size() == 5, "enemy count override is respected")
	driver.enemy_count = -1
	driver.start(1234)


func _test_line_of_sight(driver: TrapTakeoverDriver) -> void:
	var watcher := IndoorGangMember.new()
	watcher.process_mode = Node.PROCESS_MODE_DISABLED
	watcher.position = Vector3(0.5, 0.05, 12.0)
	driver.add_child(watcher)
	watcher.state = IndoorGangMember.State.COMBAT
	var player := driver.player
	var saved := player.global_position
	player.global_position = Vector3(0.5, 0.1, 17.0)
	var open_view := watcher.can_see(player)
	player.global_position = Vector3(-5.5, 0.1, -3.5)
	var through_walls := watcher.can_see(player)
	player.global_position = Vector3(0.5, -2.9, 0.0)
	var through_floor := watcher.can_see(player)
	player.global_position = saved
	_check(open_view and not through_walls and not through_floor, "rivals need line of sight: walls and floors block it")
	watcher.free()


func _test_claim_flow(driver: TrapTakeoverDriver) -> void:
	var player := driver.player
	driver.claim_time = 0.5
	driver.reinforcement_count = 0
	player.global_position = TrapHouseBuilder.CLAIM_POINT + Vector3(0.0, 0.1, 0.0)
	await _runner._physics_frames(40)
	_check(driver.phase == TrapTakeoverDriver.Phase.ASSAULT and driver.claim_progress == 0.0, "the claim stays locked while rivals are alive")
	driver.kill_all()
	await _runner._physics_frames(2)
	_check(driver.alive_enemies().is_empty() and driver.is_claimable(), "killing every rival clears the house and opens the claim")
	var cash: int = GameState.cash
	var completed := [false]
	driver.takeover_completed.connect(func() -> void: completed[0] = true)
	player.global_position = TrapHouseBuilder.CLAIM_POINT + Vector3(0.0, 0.1, 0.0)
	await _runner._physics_frames(60)
	_check(driver.phase == TrapTakeoverDriver.Phase.COMPLETE and completed[0], "holding the stash room completes the takeover")
	_check(GameState.cash == cash + driver.last_reward_cash and driver.last_reward_cash >= TrapTakeoverDriver.REWARD_CASH and GameState.has_flag(TrapTakeoverDriver.CLAIM_FLAG), "the takeover pays out and sets the claimed flag")
	_check(driver.outcome == TrapTakeoverDriver.Outcome.PENDING, "after the claim the player chooses to keep or destroy the trap")


func _test_loud_entry(driver: TrapTakeoverDriver) -> void:
	driver.start(1234)
	var front: SwingDoor = driver.builder.doors[0]
	_check(front.locked and not front.is_open and driver.can_breach(), "the front door starts locked to the player and can be breached")
	driver.breach_front_door()
	var all_alert := driver.alive_enemies().all(func(member: IndoorGangMember) -> bool: return not member.is_unaware())
	_check(front.is_open and front.jammed and not front.locked, "kicking in the front door leaves it open")
	_check(driver.entry == TrapTakeoverDriver.Entry.LOUD and driver.alarm_raised and all_alert, "a loud entry alerts the whole house")
	driver.start(1234)
	_check(front.locked and not front.jammed and not driver.alarm_raised and driver.entry == TrapTakeoverDriver.Entry.NONE, "restarting re-locks the front door and resets the alarm")


func _test_quiet_entry(driver: TrapTakeoverDriver) -> void:
	driver.start(1234)
	driver.climb_window(true)
	_check(TrapHouseBuilder.is_inside(driver.player.global_position) and driver.entry == TrapTakeoverDriver.Entry.QUIET and driver.entry_route == "back window",
		"climbing through the back window is a quiet entry")
	var target: IndoorGangMember = driver.enemies[0]
	var others := driver.alive_enemies().filter(func(member: IndoorGangMember) -> bool: return member != target)
	_check(driver.silent_takedown(target) and not target.is_alive() and driver.takedowns == 1, "a silent takedown kills an unaware rival")
	_check(target.visual is CharacterVisual and not target.visual.is_dead(), "a takedown plays the hit reaction before the body drops")
	await _runner._physics_frames(int(IndoorGangMember.TAKEDOWN_COLLAPSE_DELAY * 60.0) + 10)
	_check(target.visual.is_dead(), "the taken-down rival then plays the death animation")
	var still_unaware := others.all(func(member: IndoorGangMember) -> bool: return member.is_unaware())
	_check(not driver.alarm_raised and still_unaware, "a silent takedown doesn't alert anyone")
	var aware: IndoorGangMember = others[0]
	aware.alert(driver.player.global_position)
	_check(not driver.silent_takedown(aware) and aware.is_alive(), "a rival who's onto you can't be taken out quietly")
	var takedown := aware.get_node("Takedown") as Interactable
	var unaware_member: IndoorGangMember = driver.alive_enemies().filter(func(member: IndoorGangMember) -> bool: return member.is_unaware())[0]
	var prompt := unaware_member.get_node("Takedown") as Interactable
	_check(takedown.visible_actions(driver.player).is_empty() and prompt.visible_actions(driver.player).size() == 1, "the takedown prompt only shows on unaware rivals")


func _test_alarm_timer(driver: TrapTakeoverDriver) -> void:
	driver.start(1234)
	var spotter: IndoorGangMember = driver.enemies[0]
	spotter.alert(driver.player.global_position)
	await _runner._physics_frames(int(TrapTakeoverDriver.ALARM_DELAY * 60.0 * 0.5))
	_check(not driver.alarm_raised and driver.spotter != null, "a rival who spots you doesn't raise the alarm right away")
	await _runner._physics_frames(int(TrapTakeoverDriver.ALARM_DELAY * 60.0) + 10)
	_check(driver.alarm_raised and driver.alive_enemies().all(func(member: IndoorGangMember) -> bool: return not member.is_unaware()),
		"the alarm goes up after %.0fs and the whole house is alerted" % TrapTakeoverDriver.ALARM_DELAY)
	driver.start(1234)
	driver.enemies[0].alert(driver.player.global_position)
	await _runner._physics_frames(20)
	for member in driver.alive_enemies():
		if not member.is_unaware():
			member.take_damage(member.health + 1000.0, driver.player)
	await _runner._physics_frames(int(TrapTakeoverDriver.ALARM_DELAY * 60.0) + 30)
	_check(not driver.alarm_raised, "dropping whoever spotted you before the timer runs out keeps the alarm quiet")


## Kills everyone and holds the stash room until the takeover completes.
func _clear_and_claim(driver: TrapTakeoverDriver) -> void:
	driver.start(1234)
	driver.claim_time = 0.3
	driver.reinforcement_count = 0
	driver.kill_all()
	await _runner._physics_frames(2)
	driver.player.global_position = TrapHouseBuilder.CLAIM_POINT + Vector3(0.0, 0.1, 0.0)
	await _runner._physics_frames(40)


func _test_keep(driver: TrapTakeoverDriver) -> void:
	await _clear_and_claim(driver)
	_check(driver.phase == TrapTakeoverDriver.Phase.COMPLETE and driver.outcome == TrapTakeoverDriver.Outcome.PENDING, "clearing and claiming completes the takeover")
	var model: OperationsModel = Operations.model
	_check(driver.keep_trap() == "" and driver.outcome == TrapTakeoverDriver.Outcome.KEPT, "keeping the trap after the takeover")
	_check(model.site(TrapTakeoverDriver.SITE_ID) != null and model.is_site_acquired(TrapTakeoverDriver.SITE_ID), "a kept trap becomes an owned Operations site")
	var custom := driver.customization
	_check(custom.level == 1 and custom.rooms.size() == 1 and custom.rooms.has(&"grow_room") and custom.product_recipe() == &"grow_weed", "a taken trap starts as a House with the grow room on weed")
	_check(driver.keep_trap() != "" and driver.destroy_trap() != "" and driver.builder.levels.size() == 4, "once kept, the choice is made")
	GameState.add_cash(30000)
	_check(driver.buy_room(&"pill_press") == "" and custom.rooms.size() == 2, "buying a room fills a slot")
	_check(driver.buy_room(&"security") != "" and not custom.rooms.has(&"security"), "rooms need a free slot")
	_check(driver.upgrade_trap() == "" and custom.level == 2 and driver.buy_room(&"security") == "", "upgrading to a Compound opens another room slot")
	var site := model.site(TrapTakeoverDriver.SITE_ID)
	_check(site.max_workers == 6 and site.stash_capacity == 400 and site.tags.has(&"security"), "upgrades and rooms are pushed into the site")
	_check(driver.set_product(&"cut_and_bag") != "" and custom.product == &"grow_room", "the product needs its production room")
	driver.set_product(&"pill_press")
	_check(custom.product == &"pill_press", "switching product to another owned production room")
	var crew := driver.crew_members()
	_check(not crew.is_empty(), "there is crew to staff the trap")
	if not crew.is_empty():
		var reason := driver.assign_crew(crew[0].id, &"guard")
		_check(reason == "" and driver.site_workers() == 1 and driver.crew_job_text(crew[0].id).begins_with("Guard"), "assigning crew to guard the trap (%s)" % reason)
	var saved: Dictionary = GameState.get_flag(TrapTakeoverDriver.TRAP_FLAG, {})
	_check(TrapCustomization.from_dict(saved).to_dict() == custom.to_dict() and saved["level"] == 2, "the trap's build-out is saved")
	driver.open_manage_panel(false)
	_check(driver.manage_panel.is_open, "the manage panel opens for a kept trap")
	driver.manage_panel.close()
	driver.start(1234)
	_check(not model.is_site_acquired(TrapTakeoverDriver.SITE_ID) and driver.site_workers() == 0 and driver.outcome == TrapTakeoverDriver.Outcome.NONE, "restarting releases the kept trap and its crew")


func _test_destroy(driver: TrapTakeoverDriver) -> void:
	await _clear_and_claim(driver)
	var cash: int = GameState.cash
	_check(driver.destroy_trap() == "" and GameState.cash == cash + TrapTakeoverDriver.DESTROY_PAYOUT, "destroying the trap pays out $%d" % TrapTakeoverDriver.DESTROY_PAYOUT)
	_check(driver.builder.levels.is_empty() and driver.builder.doors.is_empty() and driver.outcome == TrapTakeoverDriver.Outcome.DESTROYED, "destroying knocks the house down")
	var saved: Dictionary = GameState.get_flag(TrapTakeoverDriver.LOT_FLAG, {})
	_check(driver.lot.state == LotState.State.EMPTY and saved.get("state") == "EMPTY" and driver.lot_is_empty(), "the lot is left empty")
	_check(driver.keep_trap() != "", "a destroyed trap can't be kept")
	await _runner._physics_frames(30)
	_check(driver.player.global_position.y > -0.5, "the player stands on the empty lot")
	GameState.add_cash(5000)
	_check(driver.start_lot_build(&"stash_house") == "" and driver.lot.state == LotState.State.CONSTRUCTION and driver.lot.project == &"stash_house", "starting a build on the empty lot")
	_check(driver.start_lot_build(&"trap_house") != "", "only one build at a time")
	driver.start(1234)
	await _runner._physics_frames(2)
	var navmesh := driver.builder.region.navigation_mesh
	_check(driver.builder.levels.size() == 4 and driver.builder.doors[0].locked and navmesh.get_polygon_count() > 100 and driver.enemies.size() == 12,
		"restarting rebuilds the house, navmesh and rivals")


func _test_stairs_navigation(driver: TrapTakeoverDriver) -> void:
	var map := driver.builder.region.get_navigation_map()
	var from := Vector3(1.0, -3.0, -3.0)
	var to := Vector3(2.25, 3.0, -5.0)
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	var reaches := path.size() > 1 and path[path.size() - 1].distance_to(to) < 1.0
	_check(reaches, "navmesh connects the basement to the upper floor over both staircases")

	var player := driver.player
	player.global_position = to + Vector3(0.0, 0.1, 0.0)
	var rusher := IndoorGangMember.new()
	rusher.damage_scale = 0.0
	rusher.move_speed = 6.0
	rusher.close_distance = 0.5
	rusher.position = from + Vector3(0.0, 0.05, 0.0)
	driver.add_child(rusher)
	await _runner._physics_frames(5)
	rusher.alert(player.global_position)
	var highest := rusher.global_position.y
	var animated_speed := 0.0
	for i in 60:
		await _runner._physics_frames(15)
		player.global_position = to + Vector3(0.0, 0.1, 0.0)
		highest = maxf(highest, rusher.global_position.y)
		animated_speed = maxf(animated_speed, rusher.visual._local_velocity.length())
		if rusher.global_position.y > 2.5:
			break
	_check(rusher.global_position.y > 2.5, "a rival climbs from the basement to the upper floor to reach the player (got to y=%.1f)" % highest)
	_check(animated_speed > 1.0, "the rival's character model plays its locomotion while it navigates (%.1f m/s)" % animated_speed)
	rusher.queue_free()


func _test_scale() -> void:
	var head_room := TrapHouseBuilder.DOOR_HEIGHT - CharacterVisual.HEIGHT
	_check(head_room >= 0.4 and TrapHouseBuilder.DOOR_HEIGHT < TrapHouseBuilder.WALL_HEIGHT, "doorways clear the 1.8 m model by >= 0.4 m and fit under the ceiling (SCALE.md)")
	_check(TrapHouseBuilder.FLOOR_HEIGHT >= 3.0 and TrapHouseBuilder.FLOOR_HEIGHT <= 3.5, "storeys are 3.0-3.5 m (SCALE.md)")


func _check(condition: bool, description: String) -> void:
	_runner._check(condition, description)
