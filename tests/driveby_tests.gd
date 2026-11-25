class_name DriveByTests
extends RefCounted
## Tests for the drive-by driver (res://drivers/driveby/): boot, shooting from the car, the crew
## gunner, retaliation (piling into cars, backup), chase car AI, escaping and failing.
## Hooked from run_tests.gd last: it frees the main scene and boots the driver scene repeatedly.

const DRIVER_SCENE := "res://drivers/driveby/driveby_driver.tscn"

var _runner: Node


func _init(runner: Node) -> void:
	_runner = runner


func _check(condition: bool, description: String) -> void:
	_runner.call("_check", condition, "drive-by: " + description)


func run(main: Node) -> void:
	main.queue_free()
	await _frames(2)
	var saved := [DriveByDriver.crew_size, DriveByDriver.rivals_have_cars, DriveByDriver.passenger_gunner, GameState.cash, GameState.respect, DriveByDriver.gunner_skill]
	DriveByDriver._args_read = true
	await _test_boot()
	await _test_shooting_from_car()
	await _test_crew_gunner()
	await _test_gunner_skill()
	await _test_retaliation_and_chase()
	await _test_backup_and_toggles()
	await _test_escape()
	await _test_fail()
	DriveByDriver.crew_size = saved[0]
	DriveByDriver.rivals_have_cars = saved[1]
	DriveByDriver.passenger_gunner = saved[2]
	GameState.cash = saved[3]
	GameState.respect = saved[4]
	DriveByDriver.gunner_skill = saved[5]


func _boot(crew_size: int, cars: bool, gunner: bool) -> DriveByDriver:
	DriveByDriver.crew_size = crew_size
	DriveByDriver.rivals_have_cars = cars
	DriveByDriver.passenger_gunner = gunner
	var driver: DriveByDriver = load(DRIVER_SCENE).instantiate()
	_runner.get_tree().root.add_child(driver)
	_runner.get_tree().current_scene = driver
	await _frames(20)
	return driver


func _free(driver: DriveByDriver) -> void:
	driver.queue_free()
	await _frames(3)


func _test_boot() -> void:
	var driver := await _boot(4, true, true)
	var player := driver.player
	_check(not player.is_on_foot() and player.current_vehicle == driver.player_car, "boots with the player behind the wheel")
	_check(player.weapons.current().data.id == &"smg", "player starts with a drive-by gun equipped")
	_check(driver.crew.size() == 4 and driver.crew.all(func(m: GangMember) -> bool: return m.gang_id == &"vipers" and m.is_alive()), "spawns the Red Vipers corner crew")
	_check(driver.rival_cars.size() == 2 and driver.mission.chasing_cars().is_empty(), "rival cars start parked")
	_check(driver.gunner != null and driver.gunner.get_parent() == driver.player_car, "a crew gunner rides shotgun")
	_check(driver.mission.phase == DriveByMission.Phase.APPROACH, "mission starts at the approach")
	var grid := driver.grid
	_check(grid.nearest_node(grid.node_position(Vector2i(1, 3)) + Vector3(4.0, 0.0, -3.0)) == Vector2i(1, 3) and grid.step_toward(Vector2i(0, 0), Vector2i(3, 1)) == Vector2i(1, 0), "road grid finds intersections and routes between them")
	await _free(driver)


func _test_shooting_from_car() -> void:
	var driver := await _boot(2, false, false)
	var car := driver.player_car
	var target := driver.crew[0]
	target.global_position = car.global_position + car.global_basis.x * -9.0
	target.move_speed = 0.0
	driver.crew[1].global_position = Vector3(-88.0, 0.0, -88.0)
	await _frames(5)
	var respect := GameState.respect
	var slot := driver.player.weapons.current()
	var rounds := slot.magazine
	var shots := 0
	while target.is_alive() and shots < 80:
		car._camera.look_at(target.global_position + Vector3.UP)
		car._drive_by_shoot()
		shots += 1
		await _frames(7)
	_check(slot.magazine < rounds or driver.player.weapons.is_reloading, "drive-by fire uses the player's ammo")
	_check(not target.is_alive(), "shooting from the car kills a corner crew member (%d shots)" % shots)
	_check(driver.mission.kills == 1 and GameState.respect > respect, "the kill counts for the mission and pays respect")
	_check(driver.mission.phase == DriveByMission.Phase.RETALIATION, "the hit sets off retaliation")
	await _free(driver)


func _test_crew_gunner() -> void:
	var driver := await _boot(1, false, true)
	var car := driver.player_car
	var target := driver.crew[0]
	target.global_position = car.global_position + car.global_basis.x * -10.0
	target.move_speed = 0.0
	await _frames(5)
	_check(driver.gunner.find_target() == target, "the gunner picks the rival in range")
	for i in 600:
		if not target.is_alive():
			break
		await _frames(1)
	_check(not target.is_alive() and driver.mission.kills == 1, "the crew gunner drops a rival and it counts")
	_check(driver.gunner.kills == 1 and int(driver.gunner.crew.xp.get(CrewGunner.SKILL_ID, 0)) == CrewGunner.XP_PER_KILL, "the gunner's kill earns them shooting xp")
	await _free(driver)


func _test_gunner_skill() -> void:
	var rookie_frames := await _frames_to_first_shot(1)
	var veteran_frames := await _frames_to_first_shot(10)
	_check(veteran_frames + 30 < rookie_frames, "a skilled gunner opens fire faster (%d vs %d frames)" % [veteran_frames, rookie_frames])

	DriveByDriver.gunner_skill = 1
	var driver := await _boot(1, false, true)
	var gunner := driver.gunner
	_check(gunner.crew.skill_for(CrewGunner.SKILL_ID) == 1 and gunner.skill_level() == 1, "the gunner's skill comes from their crew member's shooting level")
	var rookie := [gunner.extra_spread, gunner.reaction_time, gunner.burst_max, gunner.gun_range]
	driver.set_gunner_skill(10)
	await _frames(1)
	_check(gunner.skill_level() == 10 and gunner.weapons.extra_spread == gunner.extra_spread, "the debug key changes the gunner's skill live")
	_check(gunner.extra_spread < rookie[0] and gunner.reaction_time < rookie[1] and gunner.burst_max < rookie[2] and gunner.gun_range > rookie[3], "skill tightens spread, speeds reactions, shortens bursts and adds range")
	driver.set_gunner_skill(99)
	_check(gunner.skill_level() == CrewMemberData.MAX_SKILL, "gunner skill is clamped to 1-10")
	await _free(driver)


## Frames between a rival stepping into view and the gunner's first shot.
func _frames_to_first_shot(skill: int) -> int:
	DriveByDriver.gunner_skill = skill
	var driver := await _boot(1, false, true)
	var car := driver.player_car
	var slot := driver.gunner.weapons.current()
	var rounds := slot.magazine
	var target := driver.crew[0]
	target.move_speed = 0.0
	target.global_position = car.global_position + car.global_basis.x * -10.0
	var frames := 0
	while slot.magazine == rounds and frames < 300:
		frames += 1
		await _frames(1)
	await _free(driver)
	return frames


func _test_retaliation_and_chase() -> void:
	var driver := await _boot(4, true, false)
	var mission := driver.mission
	mission.pile_in_delay = 0.3
	driver.crew[0].take_damage(5.0, driver.player)
	await _frames(2)
	_check(mission.phase == DriveByMission.Phase.RETALIATION, "hurting the crew triggers retaliation")
	await _frames(30)
	var chasing := mission.chasing_cars()
	var riders := 0
	for car in chasing:
		riders += car.occupants.size()
	_check(chasing.size() >= 1 and riders > 0 and mission.living_crew().size() == 4 - riders and mission.kills == 0, "survivors pile into the cars (%d cars, %d riders)" % [chasing.size(), riders])

	var player_car := driver.player_car
	var chaser := chasing[0] if not chasing.is_empty() else null
	var start := chaser.global_position.distance_to(player_car.global_position) if chaser else 0.0
	var closest := start
	for i in 1500:
		if chaser == null or player_car.health < player_car.max_health:
			break
		closest = minf(closest, chaser.global_position.distance_to(player_car.global_position))
		await _frames(1)
	_check(chaser != null and closest < start - 30.0, "chase car drives the streets after the player (%.0f m -> %.0f m)" % [start, closest])
	_check(player_car.health < player_car.max_health, "chase car occupants shoot the player's car (%.0f hp)" % player_car.health)
	await _free(driver)


func _test_backup_and_toggles() -> void:
	var driver := await _boot(6, false, false)
	_check(driver.crew.size() == 6 and driver.rival_cars.is_empty() and driver.gunner == null, "debug toggles set crew size, no rival cars and no gunner")
	await _free(driver)

	driver = await _boot(2, true, false)
	var mission := driver.mission
	mission.pile_in_delay = 0.2
	for member in driver.crew.duplicate():
		member.take_damage(1000.0, driver.player)
	await _frames(25)
	var chasing := mission.chasing_cars()
	_check(mission.kills == 2 and chasing.size() == 1 and chasing[0].occupants.size() == mission.backup_occupants, "with the crew wiped out, backup rolls out in one car")
	await _free(driver)


func _test_escape() -> void:
	var driver := await _boot(2, false, false)
	var mission := driver.mission
	mission.escape_time = 1.0
	var watcher := driver.crew[1]
	watcher.move_speed = 0.0
	watcher.aggro_range = 0.0
	watcher.alerted_range = 0.0
	mission.start_retaliation()
	await _frames(90)
	_check(mission.phase == DriveByMission.Phase.RETALIATION, "no escape before anyone's been hit")

	driver.crew[0].take_damage(1000.0, driver.player)
	var car := driver.player_car
	watcher.global_position = car.global_position + Vector3(6.0, 0.0, 0.0)
	await _frames(3)
	_check(mission.is_seen() and mission.unseen_time == 0.0, "a rival with a clear view keeps you spotted")
	watcher.global_position = car.global_position + Vector3(0.0, 0.0, -100.0)
	await _frames(3)
	_check(not mission.is_seen(), "distance breaks line of sight")
	var block_center := (driver.grid.node_position(Vector2i(2, 3)) + driver.grid.node_position(Vector2i(3, 4))) * 0.5
	_check(not DriveByMission.line_of_sight(driver, block_center + Vector3(5.0, 1.0, 20.0), block_center + Vector3(5.0, 1.0, -20.0)), "buildings block line of sight")

	var cash := GameState.cash
	for i in 300:
		if mission.phase != DriveByMission.Phase.RETALIATION:
			break
		await _frames(1)
	_check(mission.phase == DriveByMission.Phase.COMPLETE and GameState.cash == cash + mission.reward_cash, "staying out of sight completes the drive-by and pays out (unseen %.2fs, seen %s)" % [mission.unseen_time, mission.is_seen()])
	await _free(driver)


func _test_fail() -> void:
	var driver := await _boot(1, false, false)
	driver.player.take_damage(10000.0)
	await _frames(2)
	_check(driver.mission.phase == DriveByMission.Phase.FAILED, "dying fails the drive-by")
	await _free(driver)


func _frames(count: int) -> void:
	for i in count:
		await _runner.get_tree().physics_frame
