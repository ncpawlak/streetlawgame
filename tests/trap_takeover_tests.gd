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
	await _free(driver)
	driver = await _make_driver(0)
	await _test_stairs_navigation(driver)
	await _free(driver)


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
	_check(GameState.cash == cash + TrapTakeoverDriver.REWARD_CASH and GameState.has_flag(TrapTakeoverDriver.CLAIM_FLAG), "the takeover pays out and sets the claimed flag")


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
	for i in 60:
		await _runner._physics_frames(15)
		player.global_position = to + Vector3(0.0, 0.1, 0.0)
		highest = maxf(highest, rusher.global_position.y)
		if rusher.global_position.y > 2.5:
			break
	_check(rusher.global_position.y > 2.5, "a rival climbs from the basement to the upper floor to reach the player (got to y=%.1f)" % highest)
	rusher.queue_free()


func _check(condition: bool, description: String) -> void:
	_runner._check(condition, description)
