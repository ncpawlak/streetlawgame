class_name CarjackTests
extends RefCounted
## Tests for the carjack driver (drivers/carjack): each minigame's success / fail / too-slow paths,
## failures and witnesses raising the police alarm, jacking parked and occupied cars, the tracker
## (pings call the police, the garage jams it, it expires) and chop shop payouts. Runs the driver
## scene far away from anything else and restores GameState.player afterwards.
## Focused run: godot --headless --path . res://tests/carjack_test_runner.tscn

const SCENE := "res://drivers/carjack/carjack_driver.tscn"
const OFFSET := Vector3(3000.0, 0.0, 3000.0)

var _runner: Node


func _init(runner: Node) -> void:
	_runner = runner


func _check(condition: bool, description: String) -> void:
	_runner.call("_check", condition, "carjack: " + description)


func run() -> void:
	_test_lock_pick()
	_test_hotwire()
	_test_struggle()
	_test_vehicle_classes()
	var saved_player := GameState.player
	var saved_cash := GameState.cash
	var driver: CarjackDriver = load(SCENE).instantiate()
	driver.read_command_line = false
	driver.respawn_delay = -1.0
	driver.position = OFFSET
	_runner.get_tree().root.add_child(driver)
	await _frames(30)
	await _test_driver(driver)
	driver.queue_free()
	await _frames(5)
	GameState.player = saved_player
	GameState.cash = saved_cash
	EventBus.cash_changed.emit(saved_cash)


func _results(minigame: CarjackMinigame) -> Dictionary:
	var results := {"finished": [], "slow": 0}
	minigame.finished.connect(func(success: bool, _reason: String) -> void: results["finished"].append(success))
	minigame.too_slow.connect(func() -> void: results["slow"] += 1)
	return results


## The shared class table (scripts/vehicles/vehicle_class.gd) on a plain Vehicle.
func _test_vehicle_classes() -> void:
	_check(VehicleClass.ids() == [&"junker", &"sedan", &"muscle", &"suv", &"sports", &"luxury"], "the class table has junker, sedan, muscle, SUV, sports and luxury")
	var stock := VehicleTuning.new()
	_check(VehicleClass.find(&"sedan").handling.to_text() == stock.to_text(), "the sedan row is the stock handling")
	_check(VehicleClass.find(&"sports").roll_tracker() and VehicleClass.find(&"luxury").roll_tracker() and not VehicleClass.find(&"junker").roll_tracker(), "tracker chance: sports / luxury always, junker never")
	_check(VehicleClass.find(&"hovercraft") == null, "unknown class ids return null")
	var plain := Vehicle.new()
	var muscle := Vehicle.new()
	muscle.vehicle_class_id = &"muscle"
	_runner.add_child(plain)
	_runner.add_child(muscle)
	var data := VehicleClass.find(&"muscle")
	_check(plain.vehicle_class == null and plain.mass == 1300.0 and plain.max_engine_force == 3000.0, "a Vehicle without a class keeps the stock build")
	_check(VehicleTuning.from_vehicle(plain).to_text() == stock.to_text(), "a plain Vehicle's body and wheels match the VehicleTuning stock defaults")
	_check(stock.mass == 1300.0 and is_equal_approx(stock.center_of_mass_y, 0.2) and stock.suspension_stiffness == 73.0
		and is_equal_approx(stock.damping_compression, 1.55) and is_equal_approx(stock.damping_relaxation, 2.15)
		and is_equal_approx(stock.friction_slip, 4.9), "stock handling is the play-tuned sedan (1300 kg, CoM 0.2, 73 / 1.55 / 2.15, grip 4.9)")
	_check(muscle.vehicle_class == data and muscle.mass == data.handling.mass and muscle.max_engine_force == data.handling.engine_force
		and muscle.health == data.max_health and muscle.body_color == data.color
		and is_equal_approx(VehicleTuning.wheels_of(muscle)[0].wheel_friction_slip, data.handling.friction_slip), "a Vehicle with a class takes its handling, health and paint")
	plain.free()
	muscle.free()


func _test_lock_pick() -> void:
	var game := LockPickMinigame.new()
	var results := _results(game)
	game.begin()
	_check(game.timing is TimingMinigame and game.timing.active and game.timing.hits_needed == game.pins_needed, "lock pick: runs on the shared hit_common TimingMinigame")
	for i in game.pins_needed:
		game.needle = game.zone_center()
		game.press_primary()
	_check(game.succeeded and results["finished"] == [true], "lock pick: setting every pin in the zone opens the car")
	game.free()

	game = LockPickMinigame.new()
	results = _results(game)
	game.begin()
	for i in game.max_misses:
		_miss(game)
	_check(game.done and not game.succeeded and results["finished"] == [false] and not game.timing.active, "lock pick: too many misses snaps the pick")
	game.free()

	game = LockPickMinigame.new()
	results = _results(game)
	game.begin()
	game.needle = game.zone_center()
	game.press_primary()
	_check(game.pins_set == 1, "lock pick: a pin starts the streak")
	_check(game.timing.sweet_start > game.needle, "lock pick: the next green spot is further along the bar")
	game.needle = game.zone_center()
	game.press_primary()
	_check(game.pins_set == 2, "lock pick: back-to-back pins build the streak (bang, bang)")
	game.needle = 0.999
	game.tick(0.05)
	_check(game.pins_set == 0 and game.resets == 1 and game.misses == 0 and not game.done and game.needle == 0.0, "lock pick: hitting the wall before the last pin resets the streak")
	game.needle = game.zone_center()
	game.press_primary()
	_miss(game)
	_check(game.pins_set == 0 and game.resets == 2 and game.misses == 1 and not game.done, "lock pick: a mis-press drops the pins too")
	game.free()

	game = LockPickMinigame.new()
	game.begin()
	var normal_speed := game.timing.speed
	var normal_width := game.timing.sweet_width
	game.free()
	game = LockPickMinigame.new()
	game.difficulty = VehicleClass.find(&"luxury").lock_difficulty
	game.begin()
	_check(game.timing.speed > normal_speed and game.timing.sweet_width < normal_width, "lock pick: lock difficulty speeds the pin up and narrows the green")
	game.free()

	game = LockPickMinigame.new()
	results = _results(game)
	game.begin()
	var start := game.needle
	game.tick(0.2)
	_check(game.needle != start, "lock pick: the needle sweeps")
	game.tick(game.slow_after)
	game.tick(1.0)
	_check(results["slow"] == 1 and not game.done, "lock pick: dawdling reports too_slow once without ending the attempt")
	game.free()


func _test_hotwire() -> void:
	var game := HotwireMinigame.new()
	var results := _results(game)
	game.begin()
	_check(game.slots.size() == 4 and game.sequence.size() == game.sequence_length, "hotwire: four wires and a %d-wire sequence" % game.sequence_length)
	while not game.done:
		game.press_option(game.correct_slot())
	_check(game.succeeded and results["finished"] == [true], "hotwire: connecting the wires in order starts the car")
	game.free()

	game = HotwireMinigame.new()
	results = _results(game)
	game.begin()
	for i in game.max_sparks:
		game.press_option((game.correct_slot() + 1) % 4)
	_check(game.done and not game.succeeded and results["finished"] == [false], "hotwire: wrong wires short the ignition")
	game.free()

	game = HotwireMinigame.new()
	game.difficulty = 1.4
	results = _results(game)
	game.begin()
	_check(game.sequence.size() == game.sequence_length + 1, "hotwire: hard adds a wire")
	for i in game.max_sparks:
		game.tick(game.step_time / game.difficulty + 0.01)
	_check(game.done and not game.succeeded, "hotwire: running out the step timer sparks too")
	game.free()


func _test_struggle() -> void:
	var game := StruggleMinigame.new()
	var results := _results(game)
	game.begin()
	var presses := 0
	while not game.done and presses < 50:
		game.press_primary()
		game.tick(0.05)
		presses += 1
	_check(game.succeeded and results["finished"] == [true], "struggle: mashing drags the driver out (%d presses)" % presses)
	game.free()

	game = StruggleMinigame.new()
	results = _results(game)
	game.begin()
	var grip := game.grip
	game.tick(0.5)
	_check(game.grip < grip, "struggle: the driver claws grip back")
	for i in 200:
		game.tick(0.05)
	_check(game.done and not game.succeeded and results["finished"] == [false], "struggle: doing nothing lets the driver fight you off")
	game.free()

	game = StruggleMinigame.new()
	game.start_grip = 0.9
	game.resist = 0.0
	game.begin()
	game.tick(game.time_limit + 0.1)
	_check(game.done and not game.succeeded, "struggle: the time limit ends the attempt")
	game.free()


func _find(driver: CarjackDriver, car_name: String) -> HotCar:
	for car in driver.targets():
		if car.car_name == car_name:
			return car
	return null


func _test_driver(driver: CarjackDriver) -> void:
	var player := driver.player
	_check(GameState.player == player and player.is_on_floor(), "driver scene spawns a grounded player")
	var sedan := _find(driver, "Sedan")
	var suv := _find(driver, "SUV")
	var coupe := _find(driver, "Sports coupe")
	_check(driver.targets().size() == CarjackDriver.TARGETS.size() and suv.has_occupant() and not sedan.has_occupant(), "parked and occupied target cars spawn")
	_check(not sedan.can_enter() and sedan.can_jack(), "a target car is locked until it's jacked")
	_check(driver.chop_shop.deliver(sedan) == 0, "the chop shop refuses a car that hasn't been stolen")
	var seated := suv.get_node_or_null("Occupant") as CharacterVisual
	_check(seated != null and seated.position.x > 0.0 and seated.position.x < 0.95 and seated.position.y + seated.head_height() <= 2.0, "the occupant is an animated civilian in the driver's (+X, exit) seat, head under the roof")
	_check(sedan.get_node_or_null("Occupant") == null, "parked cars are empty")
	var seated_variant := seated.variant if seated != null else -2

	# Car classes: one of each spawns, and the class sets value, lock difficulty, trackers and handling.
	var classes := {}
	for car in driver.targets():
		classes[car.vehicle_class.id] = car
	_check(classes.size() == VehicleClass.TABLE.size(), "the driver spawns one car of every class")
	var junker: HotCar = classes[&"junker"]
	var luxury: HotCar = classes[&"luxury"]
	_check(junker.car_value == VehicleClass.find(&"junker").chop_value and luxury.car_value > coupe.car_value and coupe.car_value > junker.car_value, "a car's chop value comes from its class")
	_check(driver.jack_difficulty(junker) < driver.jack_difficulty(sedan) and driver.jack_difficulty(sedan) < driver.jack_difficulty(luxury), "classes set lock difficulty (junker < sedan < luxury)")
	_check(coupe.has_tracker and luxury.has_tracker and not junker.has_tracker, "sports and luxury cars always carry a tracker, junkers never do")
	_check(suv.mass == VehicleClass.find(&"suv").handling.mass and suv.mass > sedan.mass and luxury.mass > sedan.mass and junker.max_health < sedan.max_health, "classes set the handling and health")
	driver.difficulty_level = &"hard"
	_check(driver.jack_difficulty(luxury) == CarjackDriver.MAX_JACK_DIFFICULTY, "hard + luxury is capped so it stays winnable")
	driver.difficulty_level = &"normal"
	var lux_game := driver.start_jack(luxury, CarjackMinigame.KIND_LOCK_PICK)
	_check(lux_game != null and is_equal_approx(lux_game.difficulty, VehicleClass.find(&"luxury").lock_difficulty), "the minigame runs at the car's class difficulty")
	lux_game.cancel()
	await _frames(2)

	_check(driver.minigame_kind_for(sedan) == CarjackMinigame.KIND_LOCK_PICK and driver.minigame_kind_for(suv) == CarjackMinigame.KIND_STRUGGLE, "auto mode: lock pick for parked cars, struggle for occupied ones")
	_check(driver.cycle_minigame_mode() == &"lock_pick" and driver.cycle_minigame_mode() == &"hotwire", "F2 cycles the minigame")
	_check(driver.minigame_kind_for(suv) == CarjackMinigame.KIND_HOTWIRE, "a chosen minigame applies to every car")
	driver.minigame_mode = CarjackDriver.MINIGAME_AUTO
	_check(driver.cycle_tracker_mode() == &"always" and driver.cycle_difficulty() == &"hard", "F3 / F4 cycle trackers and difficulty")
	driver.tracker_mode = &"never"
	driver.difficulty_level = &"normal"

	# The interaction prompt routes to the driver.
	player.global_position = sedan.global_position + sedan.global_basis.x * 2.5
	sedan.get_node("Interactable").perform(&"jack_car", player)
	var game := driver.minigame
	_check(game is LockPickMinigame and driver.minigame_car == sedan, "the Jack action opens the minigame")
	_check(not player.is_physics_processing() and not player.is_processing_unhandled_input(), "the player is held still during the minigame")
	game.set_process(false)

	# A botched attempt sets the car alarm off and starts the police countdown.
	var alarm_reasons: Array[StringName] = []
	driver.alarm_raised.connect(func(reason: StringName) -> void: alarm_reasons.append(reason))
	var lock := game as LockPickMinigame
	for i in lock.max_misses:
		_miss(lock)
	_check(sedan.alarm_on and driver.police_call.is_counting() and alarm_reasons == [PoliceCall.REASON_NEIGHBOURS], "failing the minigame sets off the car alarm and a police countdown")
	_check(sedan.locked and sedan.can_jack(), "a failed car stays locked and can be retried")
	await _frames(90)
	_check(not driver.is_minigame_open() and player.is_physics_processing(), "the failed minigame closes and frees the player")

	# Taking too long gets noticed.
	driver.police_call.reset()
	alarm_reasons.clear()
	game = driver.start_jack(sedan)
	game.set_process(false)
	game.tick(game.slow_after + 0.1)
	_check(driver.police_call.is_counting() and alarm_reasons == [PoliceCall.REASON_WITNESS], "a slow attempt is noticed and the police get called")
	game.cancel()
	await _frames(2)
	_check(not driver.is_minigame_open() and sedan.locked, "Esc walks away from the car")

	# Success: the car opens, the player gets in, no tracker.
	driver.police_call.reset()
	game = driver.start_jack(sedan, CarjackMinigame.KIND_HOTWIRE)
	game.set_process(false)
	var wires := game as HotwireMinigame
	while not wires.done:
		wires.press_option(wires.correct_slot())
	await _frames(2)
	_check(sedan.stolen and player.current_vehicle == sedan and driver.hot_car == sedan and not driver.is_minigame_open(), "a successful jack puts the player in the car")
	_check(sedan.tracker == null and not driver.police_call.is_active(), "a clean parked-car jack with trackers off stays quiet")

	# Free-look driving camera: turning the car doesn't swing the view back to straight ahead.
	sedan._look_yaw = wrapf(sedan.global_rotation.y + PI + 1.5, -PI, PI)
	var look := sedan._look_yaw
	sedan.global_rotation.y += 1.0
	await _frames(10)
	_check(is_equal_approx(sedan._camera_pivot.rotation.y, look) and is_equal_approx(sedan._look_yaw, look), "the driving camera stays where you look while the car turns")

	# Live handling tuning (F7): per class, sliders push values onto that class's cars; reset restores.
	driver.select_tuning_class(&"sedan")
	_check(driver.default_tuning().mass == 1300.0 and driver.default_tuning().suspension_stiffness == 73.0, "the sedan class keeps the stock handling")
	driver.set_tuning(&"mass", 2400.0)
	driver.set_tuning(&"damping_relaxation", 2.5)
	var wheels := VehicleTuning.wheels_of(sedan)
	_check(sedan.mass == 2400.0 and wheels.size() == 4 and wheels[0].damping_relaxation == 2.5, "tuning sliders apply live to the class being tuned")
	_check(suv.mass == VehicleClass.find(&"suv").handling.mass and VehicleClass.find(&"sedan").handling.mass == 1300.0, "tuning one class leaves other classes and the class table alone")
	var report := driver.report_tuning()
	_check(report.contains("[sedan]") and report.contains("mass=2400"), "tuning values can be copied out, labelled with the class")
	driver.reset_tuning()
	_check(sedan.mass == 1300.0 and is_equal_approx(VehicleTuning.wheels_of(sedan)[0].damping_relaxation, driver.default_tuning().damping_relaxation), "reset restores the class's handling")
	_check(driver.cycle_tuning_class() == &"muscle", "F8 steps the tuning panel to the next class")
	driver.select_tuning_class(&"sedan")

	# Chop shop: park on the pad and get paid.
	var payouts: Array[int] = []
	driver.chop_shop.delivered.connect(func(_car: HotCar, amount: int) -> void: payouts.append(amount))
	var cash := GameState.cash
	sedan.global_position = driver.chop_shop.global_position + Vector3(0.0, 0.8, 0.0)
	sedan.linear_velocity = Vector3.ZERO
	await _frames(20)
	_check(payouts.size() == 1 and GameState.cash == cash + payouts[0], "stopping on the chop shop pad pays out ($%d)" % (payouts[0] if not payouts.is_empty() else 0))
	_check(not payouts.is_empty() and payouts[0] > 1200, "an undamaged car with no tracker earns the cold-car bonus")
	_check(not is_instance_valid(sedan) and player.is_on_foot() and driver.hot_car == null, "the chop shop strips the car and the player is back on foot")

	var ride := driver.targets().filter(is_instance_valid).map(func(car: HotCar) -> float: return car.global_position.y)
	_check(ride.size() >= 4 and ride.min() > -0.15 and ride.max() - ride.min() < 0.15, "every class rides on its wheels, even the heavy SUV (suspension force scales with mass)")

	# Occupied car: struggle, the driver runs off and calls the cops.
	driver.police_call.reset()
	alarm_reasons.clear()
	player.global_position = suv.global_position + suv.global_basis.x * 2.5
	game = driver.start_jack(suv)
	_check(game is StruggleMinigame, "jacking an occupied car opens the struggle")
	game.set_process(false)
	while not game.done:
		game.press_primary()
	await _frames(2)
	var runners := _runner.get_tree().get_nodes_in_group("fleeing_drivers")
	_check(not suv.has_occupant() and not runners.is_empty(), "the yanked driver runs off")
	var runner := runners[0] as FleeingDriver
	_check(runner.visual != null and runner.visual.variant == seated_variant and absf(runner.global_position.y - suv.global_position.y) < 0.3, "the runner is the same animated civilian, standing on the ground")
	_check(player.current_vehicle == suv and alarm_reasons == [PoliceCall.REASON_WITNESS] and driver.police_call.is_counting(), "the victim calls the cops")
	await _frames(2)
	_check(driver.tuning_class == &"suv", "getting into a car switches the tuning panel to its class")
	suv.exit()
	await _frames(2)

	# Tracker: pings call the police and send cruisers, the garage roof kills the signal.
	driver.police_call.reset()
	driver.tracker_mode = &"always"
	driver.tracker_delay = 0.0
	player.global_position = coupe.global_position + coupe.global_basis.x * 2.5
	game = driver.start_jack(coupe, CarjackMinigame.KIND_LOCK_PICK)
	game.set_process(false)
	lock = game as LockPickMinigame
	while not lock.done:
		lock.needle = lock.zone_center()
		lock.press_primary()
	await _frames(3)
	var tracker := coupe.tracker
	_check(tracker != null and tracker.active and tracker.pings >= 1, "a hot car's tracker starts pinging")
	_check(driver.police_call.is_called() and driver.police_response.is_wanted() and driver.cruisers.size() == driver.cruisers_per_call, "a tracker ping calls the police and sends cruisers")
	var cop := driver.cruisers[0]._cop
	_check(cop != null and cop.model_id == &"swat", "cruisers have an animated cop at the wheel")
	driver.cruisers[0].exploded.emit()
	_check(cop.is_dead(), "a wrecked cruiser's cop plays the death animation")
	driver.police_response.unseen_time = 5.0
	tracker._next_ping = 0.0
	tracker.update(0.01)
	_check(driver.police_response.unseen_time == 0.0 and driver.police_response.last_seen.distance_to(coupe.global_position) < 1.0, "every ping tells the police where the car is")
	_check(driver.chop_shop.payout_for(coupe) < int(coupe.car_value * 1.2 * coupe.condition()), "a car still being tracked earns no cold-car bonus")
	var lost_reasons: Array[StringName] = []
	tracker.lost.connect(func(reason: StringName) -> void: lost_reasons.append(reason))
	coupe.global_position = driver.jam_zone.global_position + Vector3(0.0, 0.8, 0.0)
	coupe.linear_velocity = Vector3.ZERO
	await _frames(2)
	tracker.update(tracker.jam_time + 0.1)
	_check(not tracker.active and lost_reasons == [&"jammed"], "parking under the garage roof kills the tracker")

	var dummy := Node3D.new()
	driver.add_child(dummy)
	var timed := HotCarTracker.new(dummy)
	dummy.add_child(timed)
	var expired: Array[StringName] = []
	timed.lost.connect(func(reason: StringName) -> void: expired.append(reason))
	timed.start()
	timed.update(timed.duration + 1.0)
	_check(not timed.active and expired == [&"expired"], "outlasting the tracker's timer kills it")
	dummy.queue_free()

	# Delivering ends the chase.
	payouts.clear()
	coupe.global_position = driver.chop_shop.global_position + Vector3(0.0, 0.8, 0.0)
	coupe.linear_velocity = Vector3.ZERO
	driver.police_response._seen = false
	var paid := driver.chop_shop.deliver(coupe)
	await _frames(2)
	_check(paid > 0 and not driver.police_response.is_wanted() and driver.cruisers.is_empty(), "delivering to the chop shop pays and ends the chase")


func _frames(count: int) -> void:
	for i in count:
		await _runner.get_tree().physics_frame


## Presses just before the green spot (always a miss: the spot is placed ahead of the pin).
func _miss(game: LockPickMinigame) -> void:
	game.needle = maxf(0.0, game.timing.sweet_start - 0.01)
	game.press_primary()
