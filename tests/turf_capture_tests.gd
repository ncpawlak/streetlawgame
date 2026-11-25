extends RefCounted
## Turf capture driver tests: the capture rules (TurfCaptureModel) and a short run of the driver scene.

const DRIVER_SCENE := "res://drivers/turf_capture/turf_capture_driver.tscn"
## The driver is instanced far from the city so the two worlds don't collide.
const DRIVER_OFFSET := Vector3(2000.0, 0.0, 2000.0)

var _runner: Node


func _init(runner: Node) -> void:
	_runner = runner


func run(main: Node) -> void:
	_test_progress_only_inside()
	_test_guards_gate_capture()
	_test_waves_escalate()
	_test_completion_after_final_wave()
	await _test_driver_scene(main)


func _test_progress_only_inside() -> void:
	var model := TurfCaptureModel.new()
	model.configure(4, &"normal", 0)
	model.tick(5.0, false)
	_check(model.state == TurfCaptureModel.State.READY and model.progress == 0.0, "turf capture: nothing happens until you step into the zone")
	model.tick(0.1, true)
	_check(model.state == TurfCaptureModel.State.CAPTURING and model.wave_index == 0, "turf capture: entering the zone starts the capture and the first wave")
	model.tick(6.0, true)
	var held := model.progress
	_check(is_equal_approx(held, 6.0 / model.hold_time()), "turf capture: progress fills while inside (%.3f)" % held)
	model.tick(4.0, false)
	_check(model.progress < held and model.progress > 0.0, "turf capture: progress drains while outside")
	model.tick(1000.0, false)
	_check(model.progress == 0.0 and model.wave_index == 0 and model.state == TurfCaptureModel.State.CAPTURING, "turf capture: staying out drains the bar without bringing more waves")


func _test_guards_gate_capture() -> void:
	var model := TurfCaptureModel.new()
	model.configure(2, &"normal", 3)
	model.tick(10.0, true)
	_check(model.state == TurfCaptureModel.State.GUARDED and model.progress == 0.0 and model.enemies_remaining == 3, "turf capture: no progress while the guards are alive")
	model.remove_enemies(3, true)
	model.tick(0.1, true)
	_check(model.state == TurfCaptureModel.State.READY, "turf capture: killing the guards opens the zone")


func _test_waves_escalate() -> void:
	var escalates := true
	for difficulty in TurfCaptureModel.DIFFICULTIES:
		var model := TurfCaptureModel.new()
		model.configure(8, difficulty, 0)
		for i in range(1, 8):
			var before := model.plan_wave(i - 1)
			var after := model.plan_wave(i)
			escalates = escalates and after.total > before.total and after.cars >= before.cars and after.approaches >= before.approaches \
				and after.on_foot + after.cars * after.crew_per_car == after.total and after.on_foot >= 2
	var normal := TurfCaptureModel.new()
	_check(escalates, "turf capture: every wave is bigger than the last on every difficulty")
	_check(normal.plan_wave(0).cars == 0 and normal.plan_wave(1).cars > 0 and normal.plan_wave(3).approaches == 4, "turf capture: later waves bring cars and come from all four streets")
	var easy := TurfCaptureModel.new()
	easy.configure(4, &"easy", 0)
	var hard := TurfCaptureModel.new()
	hard.configure(4, &"hard", 0)
	_check(hard.plan_wave(2).total > easy.plan_wave(2).total and hard.hold_time() > easy.hold_time(), "turf capture: difficulty scales wave size and hold time")


func _test_completion_after_final_wave() -> void:
	var model := TurfCaptureModel.new()
	model.configure(3, &"easy", 0)
	var spawned: Array[int] = []
	model.wave_started.connect(func(index: int, plan: Dictionary) -> void:
		spawned.append(index)
		model.add_enemies(plan.total))
	model.tick(0.1, true)
	model.remove_enemies(model.enemies_remaining)
	model.progress = model.wave_threshold(1) - 0.01
	model.tick(0.0, true)
	_check(spawned == [0] and model.state == TurfCaptureModel.State.CAPTURING, "turf capture: clearing early waves doesn't capture the block")
	model.tick(model.hold_time(), true)
	_check(model.progress == 1.0 and spawned == [0, 1, 2] and model.state == TurfCaptureModel.State.CAPTURING, "turf capture: a full bar still needs the final wave dead")
	model.remove_enemies(model.enemies_remaining)
	model.tick(0.1, false)
	_check(model.state == TurfCaptureModel.State.CAPTURING, "turf capture: you have to be in the zone to lock it down")
	model.progress = 1.0
	model.tick(0.1, true)
	_check(model.state == TurfCaptureModel.State.CAPTURED, "turf capture: the block is captured once the final wave is dead")

	var doomed := TurfCaptureModel.new()
	doomed.configure(2, &"normal", 0)
	doomed.tick(0.1, true)
	doomed.fail()
	_check(doomed.state == TurfCaptureModel.State.FAILED, "turf capture: dying mid-capture fails it")


func _test_driver_scene(main: Node) -> void:
	var main_player: Player = GameState.player
	var cash := GameState.cash
	var respect := GameState.respect
	var driver: TurfCaptureDriver = load(DRIVER_SCENE).instantiate()
	driver.wave_count = 2
	driver.guard_count = 2
	driver.position = DRIVER_OFFSET
	main.add_child(driver)
	await _frames(60)
	var player := driver.player
	player.max_health = 1.0e6
	player.health = player.max_health
	var model := driver.model
	_check(GameState.player == player and player.is_on_floor() and not driver.is_player_holding(), "turf driver: boots with the player on the ground outside the zone")
	_check(model.state == TurfCaptureModel.State.GUARDED and driver.enemies.size() == 2, "turf driver: Viper guards hold the corner")

	for member: GangMember in driver.enemies.keys():
		member.take_damage(1000.0, player)
	await _frames(2)
	_check(model.state == TurfCaptureModel.State.READY and model.enemies_remaining == 0, "turf driver: killing the guards opens the zone")

	player.global_position = driver.zone.global_position + Vector3(0.0, 0.5, 2.0)
	await _frames(10)
	var first := model.plan_wave(0)
	_check(driver.is_player_holding() and model.state == TurfCaptureModel.State.CAPTURING, "turf driver: standing in the zone starts the capture")
	_check(model.wave_index == 0 and driver.enemies.size() == first.total and model.enemies_remaining == first.total, "turf driver: wave 1 spawns %d Vipers" % first.total)
	var progress := model.progress
	await _frames(30)
	_check(model.progress > progress, "turf driver: the bar fills while you hold the zone")

	model.progress = model.wave_threshold(1)
	await _frames(2)
	var second := model.plan_wave(1)
	_check(model.wave_index == 1 and driver.raid_cars.size() == second.cars and second.cars > 0, "turf driver: wave 2 rolls in with a raid car")
	var car := driver.raid_cars[0]
	var crew: Array[GangMember] = []
	car.unloaded.connect(func(members: Array[GangMember]) -> void: crew.append_array(members))
	var start := car.global_position
	for i in 1200:
		if car.is_unloaded:
			break
		await _runner.get_tree().physics_frame
	var to_stop := (car.global_position - car.destination) * Vector3(1, 0, 1)
	_check(car.is_unloaded and car.global_position.distance_to(start) > 50.0 and to_stop.length() < 25.0, "turf driver: the raid car drives in and drops its crew (%.0f m from its stop)" % to_stop.length())
	_check(crew.size() == second.crew_per_car and crew.all(func(m: GangMember) -> bool: return driver.enemies.has(m)) and driver.enemies.size() == model.enemies_remaining, "turf driver: the car's crew counts toward Vipers left (%d)" % model.enemies_remaining)

	player.global_position = driver.zone.global_position + Vector3(0.0, 0.5, 2.0)
	model.progress = 1.0
	for member: GangMember in driver.enemies.keys():
		member.take_damage(1000.0, player)
	await _frames(3)
	_check(model.state == TurfCaptureModel.State.CAPTURED and GameState.cash > cash, "turf driver: killing the last wave in the zone captures the block")

	driver.queue_free()
	await _frames(2)
	GameState.player = main_player
	main_player.get_node("CameraPivot/SpringArm/Camera").make_current()
	GameState.cash = cash
	GameState.respect = respect


func _frames(count: int) -> void:
	for i in count:
		await _runner.get_tree().physics_frame


func _check(condition: bool, description: String) -> void:
	_runner.call(&"_check", condition, description)
