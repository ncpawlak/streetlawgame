extends RefCounted
## Turf capture driver tests: the capture rules (TurfCaptureModel), the block ledger (income, counter-attacks,
## rival strength) and a short run of the driver scene.

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
	_test_strength_scales_capture()
	_test_counter_attack_rules()
	_test_ledger_income()
	_test_ledger_counter_attack()
	_test_ledger_strength()
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


func _test_strength_scales_capture() -> void:
	var base := TurfCaptureModel.new()
	base.configure(4, &"normal", 0)
	_check(is_equal_approx(base.hold_time(), base.hold_per_wave * 4) and TurfCaptureModel.strength_size_scale(TurfBlockLedger.DEFAULT_STRENGTH) == 1.0, "turf strength: the default strength leaves hold time and wave size untouched")
	var weak := TurfCaptureModel.new()
	weak.configure(4, &"normal", 0, 1.0)
	var strong := TurfCaptureModel.new()
	strong.configure(4, &"normal", 0, 5.0)
	_check(strong.hold_time() > base.hold_time() and base.hold_time() > weak.hold_time(), "turf strength: a stronger rival means a longer hold (%.0f / %.0f / %.0f s)" % [weak.hold_time(), base.hold_time(), strong.hold_time()])
	var bigger := true
	for i in 4:
		bigger = bigger and strong.plan_wave(i).total > base.plan_wave(i).total and base.plan_wave(i).total >= weak.plan_wave(i).total
	_check(bigger, "turf strength: a stronger rival sends bigger waves")
	_check(strong.plan_counter_attack().total > weak.plan_counter_attack().total and strong.plan_counter_attack().cars > 0 and weak.plan_counter_attack().cars == 0, "turf strength: a stronger rival counter-attacks harder, with a car")
	var clamped := TurfCaptureModel.new()
	clamped.configure(4, &"normal", 0, 99.0)
	_check(clamped.strength == TurfBlockLedger.MAX_STRENGTH, "turf strength: strength is capped")


func _captured_model() -> TurfCaptureModel:
	var model := TurfCaptureModel.new()
	model.configure(1, &"normal", 0)
	model.tick(0.1, true)
	model.remove_enemies(model.enemies_remaining)
	model.progress = 1.0
	model.tick(0.1, true)
	return model


func _test_counter_attack_rules() -> void:
	var fresh := TurfCaptureModel.new()
	fresh.configure(2, &"normal", 0)
	_check(not fresh.start_counter_attack() and fresh.state == TurfCaptureModel.State.READY, "turf counter: there's nothing to counter-attack before you hold the block")

	var model := _captured_model()
	var attackers := [0]
	model.counter_attack_started.connect(func(plan: Dictionary) -> void:
		attackers[0] = plan.total
		model.add_enemies(plan.total))
	_check(model.state == TurfCaptureModel.State.CAPTURED and model.is_held(), "turf counter: setup captured the block")
	_check(model.start_counter_attack() and model.state == TurfCaptureModel.State.UNDER_ATTACK and model.is_held() and model.enemies_remaining == attackers[0] and attackers[0] > 0, "turf counter: a counter-attack sends %d Vipers" % attackers[0])
	_check(not model.start_counter_attack(), "turf counter: only one counter-attack at a time")
	model.tick(10.0, true)
	_check(model.takeover == 0.0, "turf counter: the Vipers can't take the zone while you're in it")
	model.tick(10.0, false)
	var taken := model.takeover
	_check(is_equal_approx(taken, 10.0 / model.takeover_time), "turf counter: the takeover fills while you're out of the zone (%.2f)" % taken)
	model.tick(4.0, true)
	_check(model.takeover < taken and model.takeover > 0.0, "turf counter: getting back in the zone pushes the takeover back")
	model.remove_enemies(model.enemies_remaining)
	model.tick(0.1, false)
	_check(model.state == TurfCaptureModel.State.CAPTURED, "turf counter: killing every attacker repels the counter-attack")

	model.start_counter_attack()
	model.tick(model.takeover_time + 1.0, false)
	_check(model.state == TurfCaptureModel.State.LOST and not model.is_held(), "turf counter: leaving them in the zone long enough loses the block")


func _ledger(strength := TurfBlockLedger.DEFAULT_STRENGTH) -> TurfBlockLedger:
	var ledger := TurfBlockLedger.new()
	ledger.income_interval = 10.0
	ledger.counter_attack_delay = 30.0
	ledger.strength_growth = 0.0
	ledger.add_block(&"a", "A", &"vipers", strength)
	return ledger


func _test_ledger_income() -> void:
	var ledger := _ledger()
	var paid: Array[int] = []
	ledger.income_paid.connect(func(_id: StringName, amount: int) -> void: paid.append(amount))
	var defended := func(_id: StringName) -> bool: return true
	ledger.tick(100.0, defended)
	_check(paid.is_empty() and not ledger.is_held(&"a"), "turf income: a rival block pays you nothing")
	ledger.capture(&"a")
	_check(ledger.is_held(&"a") and ledger.held_blocks() == [&"a"] and ledger.total_income() == ledger.income_of(&"a"), "turf income: capturing a block makes it yours")
	ledger.tick(9.0, defended)
	_check(paid.is_empty(), "turf income: nothing until the interval is up")
	ledger.tick(1.5, defended)
	ledger.tick(10.0, defended)
	_check(paid.size() == 2 and paid[0] == ledger.income_of(&"a"), "turf income: a held block pays every interval")
	_check(ledger.fast_forward_income(&"a") and paid.size() == 3 and is_equal_approx(ledger.income_left(&"a"), 10.0), "turf income: [F2] pays now and restarts the timer")
	_check(_ledger(5.0).income_of(&"a") > _ledger(1.0).income_of(&"a"), "turf income: blocks taken from a stronger rival pay more")
	ledger.fast_forward_counter_attack(&"a")
	ledger.tick(50.0, defended)
	_check(paid.size() == 3 and not ledger.fast_forward_income(&"a"), "turf income: no payouts while the block is under attack")
	ledger.lose(&"a")
	ledger.tick(100.0, defended)
	_check(paid.size() == 3 and not ledger.is_held(&"a") and ledger.total_income() == 0, "turf income: losing the block stops the income")


func _test_ledger_counter_attack() -> void:
	var ledger := _ledger()
	var due: Array[StringName] = []
	var owners: Array[StringName] = []
	ledger.counter_attack_due.connect(func(id: StringName, _strength: float) -> void: due.append(id))
	ledger.owner_changed.connect(func(_id: StringName, gang: StringName, _previous: StringName, reason: StringName) -> void: owners.append(StringName("%s:%s" % [gang, reason])))
	var defended := [true]
	var is_defended := func(_id: StringName) -> bool: return defended[0]
	ledger.capture(&"a")
	ledger.tick(100.0, is_defended)
	_check(due.is_empty(), "turf counter: a defended block isn't counter-attacked")
	defended[0] = false
	ledger.tick(20.0, is_defended)
	var left := ledger.counter_attack_left(&"a")
	_check(due.is_empty() and is_equal_approx(left, 10.0), "turf counter: the counter-attack timer runs while the block is undefended")
	defended[0] = true
	ledger.tick(10.0, is_defended)
	_check(ledger.counter_attack_left(&"a") > left and due.is_empty(), "turf counter: coming back winds the timer back")
	defended[0] = false
	ledger.tick(30.0, is_defended)
	_check(due == [&"a"] and ledger.is_under_attack(&"a") and ledger.is_held(&"a"), "turf counter: leave it long enough and the Vipers hit back")
	ledger.tick(100.0, is_defended)
	_check(due.size() == 1, "turf counter: one counter-attack at a time")
	ledger.repel(&"a")
	_check(not ledger.is_under_attack(&"a") and is_equal_approx(ledger.counter_attack_left(&"a"), 30.0), "turf counter: repelling it resets the timer")
	_check(ledger.fast_forward_counter_attack(&"a") and due.size() == 2, "turf counter: [F3] triggers one now")
	var before := ledger.strength_of(&"a")
	ledger.lose(&"a")
	_check(ledger.owner_of(&"a") == &"vipers" and ledger.strength_of(&"a") > before and not ledger.fast_forward_counter_attack(&"a"), "turf counter: losing hands the block back to a stronger rival")
	_check(owners == [&"player:capture", &"vipers:counter_attack"], "turf counter: owner changes report why (%s)" % [owners])


func _test_ledger_strength() -> void:
	var ledger := _ledger(2.0)
	ledger.strength_growth = 0.1
	var defended := func(_id: StringName) -> bool: return true
	ledger.tick(5.0, defended)
	_check(is_equal_approx(ledger.strength_of(&"a"), 2.5), "turf strength: the rival digs in while you leave it alone")
	ledger.set_contested(&"a", true)
	ledger.tick(5.0, defended)
	_check(is_equal_approx(ledger.strength_of(&"a"), 2.5), "turf strength: no reinforcements while you're taking the block")
	ledger.set_contested(&"a", false)
	ledger.tick(1000.0, defended)
	_check(ledger.strength_of(&"a") == TurfBlockLedger.MAX_STRENGTH, "turf strength: strength tops out at %d" % roundi(TurfBlockLedger.MAX_STRENGTH))
	ledger.capture(&"a")
	ledger.tick(1000.0, defended)
	_check(ledger.strength_of(&"a") == TurfBlockLedger.MAX_STRENGTH, "turf strength: a held block doesn't change the rival's strength")


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
	await _test_driver_block(driver, player)

	driver.queue_free()
	await _frames(2)
	GameState.player = main_player
	main_player.get_node("CameraPivot/SpringArm/Camera").make_current()
	GameState.cash = cash
	GameState.respect = respect


func _test_driver_block(driver: TurfCaptureDriver, player: Player) -> void:
	var model := driver.model
	var ledger := driver.ledger
	var id := TurfCaptureDriver.BLOCK_ID
	var incomes: Array[int] = []
	var owners: Array[StringName] = []
	var on_income := func(_id: StringName, amount: int) -> void: incomes.append(amount)
	var on_owner := func(_id: StringName, gang: StringName, _previous: StringName, _reason: StringName) -> void: owners.append(gang)
	EventBus.turf_block_income.connect(on_income)
	EventBus.turf_block_owner_changed.connect(on_owner)
	_check(ledger.is_held(id) and driver.hud.title_text().contains("your turf") and driver.hud.block_text().contains("pays $"), "turf driver: the captured block shows up as yours with its income")

	var cash := GameState.cash
	driver.debug_pay_income()
	_check(GameState.cash == cash + ledger.income_of(id) and incomes == [ledger.income_of(id)], "turf driver: [F2] pays the block's income (+$%d)" % ledger.income_of(id))

	player.global_position = driver.zone.global_position + Vector3(0.0, 0.5, TurfCaptureDriver.DEFEND_RADIUS + 8.0)
	await _frames(3)
	_check(not driver.is_defending() and driver.hud.block_text().contains("Undefended"), "turf driver: walking away leaves the block undefended")
	driver.debug_counter_attack()
	await _frames(2)
	var plan := model.plan_counter_attack()
	_check(model.state == TurfCaptureModel.State.UNDER_ATTACK and model.enemies_remaining == plan.total and driver.enemies.size() == plan.on_foot, "turf driver: [F3] sends a %d-man counter-attack into the zone" % plan.total)
	var inside := driver.enemies.keys().all(func(m: GangMember) -> bool: return driver.zone.contains(m.global_position))
	_check(inside and driver.hud.block_text().contains("on hold"), "turf driver: the attackers dig into the zone and the income stops")
	cash = GameState.cash
	driver.debug_pay_income()
	_check(GameState.cash == cash, "turf driver: no payout while the block is under attack")

	await _frames(30)
	_check(model.takeover > 0.0, "turf driver: the takeover fills while you're away")
	for member: GangMember in driver.enemies.keys():
		member.take_damage(1000.0, player)
	for car in driver.raid_cars:
		if is_instance_valid(car) and not car.is_unloaded:
			car.queue_free()
	model.remove_enemies(model.enemies_remaining - driver.enemies.size())
	await _frames(3)
	_check(model.state == TurfCaptureModel.State.CAPTURED and ledger.is_held(id) and not ledger.is_under_attack(id), "turf driver: killing the attackers repels the counter-attack")

	driver.debug_counter_attack()
	await _frames(2)
	model.takeover = 0.99
	await _frames(60)
	_check(model.state == TurfCaptureModel.State.LOST and ledger.owner_of(id) == TurfCaptureDriver.ENEMY_GANG, "turf driver: leaving the attackers in the zone loses the block")
	cash = GameState.cash
	driver.debug_pay_income()
	ledger.tick(ledger.income_interval * 3.0, driver.is_defending)
	_check(GameState.cash == cash and incomes.size() == 1, "turf driver: a lost block stops paying")
	_check(owners == [TurfCaptureDriver.ENEMY_GANG], "turf driver: losing the block goes out on the EventBus")
	EventBus.turf_block_income.disconnect(on_income)
	EventBus.turf_block_owner_changed.disconnect(on_owner)


func _frames(count: int) -> void:
	for i in count:
		await _runner.get_tree().physics_frame


func _check(condition: bool, description: String) -> void:
	_runner.call(&"_check", condition, description)
