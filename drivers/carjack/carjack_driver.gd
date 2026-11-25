class_name CarjackDriver
extends Node3D
## Self-contained gameplay driver for the carjack / hot car loop (not wired into the city map):
## jack a parked or occupied car through a swappable minigame, survive the alarm, outrun the
## tracker and roll the car into the chop shop for cash.
##
## Run: godot --path . res://drivers/carjack/carjack_driver.tscn [-- --minigame=hotwire --tracker=always --difficulty=hard]
## Debug keys: F1 panel, F2 minigame, F3 tracker, F4 difficulty, F5 reset, F6 jump to next car.

signal jack_started(car: HotCar, minigame: CarjackMinigame)
signal jack_finished(car: HotCar, success: bool)
## Something tipped off the police (bad attempt, slow attempt, witness...).
signal alarm_raised(reason: StringName)

const MINIGAME_AUTO := &"auto"
const MINIGAME_MODES: Array[StringName] = [&"auto", &"lock_pick", &"hotwire", &"struggle"]
const TRACKER_MODES: Array[StringName] = [&"per_car", &"always", &"never"]
const DIFFICULTIES := {&"easy": 0.7, &"normal": 1.0, &"hard": 1.4}
const DIFFICULTY_ORDER: Array[StringName] = [&"easy", &"normal", &"hard"]

const BLOCK_SPACING := 52.0
const BLOCK_SIZE := 40.0
const PLAYER_SPAWN := Vector3(-23.0, 1.0, -42.0)
const POLICE_SPAWN := Vector3(56.0, 0.5, -26.0)
## name, position, yaw, colour, value, occupied, tracker
const TARGETS := [
	["Sedan", Vector3(-23.5, 0.8, -30.0), 0.0, Color(0.55, 0.6, 0.65), 1200, false, false],
	["Sports coupe", Vector3(-28.5, 0.8, -4.0), PI, Color(0.8, 0.1, 0.1), 3500, false, true],
	["SUV", Vector3(-8.0, 0.8, -28.5), PI / 2.0, Color(0.15, 0.3, 0.2), 2200, true, false],
	["Muscle car", Vector3(10.0, 0.8, 23.5), -PI / 2.0, Color(0.9, 0.55, 0.1), 2800, false, true],
]

## &"auto" (parked: lock pick, occupied: struggle) or a [constant CarjackMinigame.KINDS] id.
@export var minigame_mode: StringName = MINIGAME_AUTO
## &"per_car" (use each car's has_tracker), &"always" or &"never".
@export var tracker_mode: StringName = &"per_car"
@export var difficulty_level: StringName = &"normal"
## Seconds from driving off until a fitted tracker starts pinging.
@export var tracker_delay := 2.0
## Police countdown after a botched parked-car attempt (car alarm).
@export var alarm_countdown := 15.0
## Police countdown when someone notices a slow attempt.
@export var witness_countdown := 30.0
## Police countdown after an occupied car's driver gets away to call it in.
@export var victim_countdown := 20.0
@export var cruisers_per_call := 2
@export var cruiser_sight := 25.0
## Seconds before a delivered / wrecked target car respawns.
@export var respawn_delay := 8.0
@export var read_command_line := true

var player: Player
var police_call: PoliceCall
var police_response: PoliceResponse
var chop_shop: ChopShop
var jam_zone: JamZone
var hud: CarjackHud
var minigame: CarjackMinigame
var minigame_car: HotCar
## The stolen car the player is currently moving.
var hot_car: HotCar
var cruisers: Array[PursuitCruiser] = []
var alarms: Array[StringName] = []
## Live handling values for every target car (F7 tuning panel). default_tuning is what the Vehicle
## code builds, captured from the first car so the defaults are untouched.
var tuning: VehicleTuning
var default_tuning: VehicleTuning

var _minigame_layer: CanvasLayer
var _targets: Array[HotCar] = []
var _teleport_index := 0


func _ready() -> void:
	if read_command_line:
		_read_command_line()
	_build_environment()
	_build_world()
	player = $Player
	player.global_position = to_global(PLAYER_SPAWN)
	player.spawn_point = player.global_position
	_build_police()
	chop_shop = ChopShop.new()
	chop_shop.name = "ChopShop"
	chop_shop.position = Vector3(52.0, 0.0, 40.0)
	chop_shop.police_response = police_response
	chop_shop.delivered.connect(_on_delivered)
	add_child(chop_shop)
	jam_zone = JamZone.new()
	jam_zone.name = "ParkingGarage"
	jam_zone.position = Vector3(-52.0, 0.0, 52.0)
	add_child(jam_zone)
	var targets_root := Node3D.new()
	targets_root.name = "Targets"
	add_child(targets_root)
	for i in TARGETS.size():
		_spawn_target(i)
	_minigame_layer = CanvasLayer.new()
	_minigame_layer.name = "MinigameLayer"
	_minigame_layer.layer = 10
	add_child(_minigame_layer)
	hud = CarjackHud.new()
	hud.name = "CarjackHud"
	hud.driver = self
	add_child(hud)
	if get_tree().current_scene == self:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	EventBus.notify.emit.call_deferred("Carjack driver: jack a car, lose the tracker, deliver it to the CHOP SHOP (orange beam).")
	EventBus.notify.emit.call_deferred("F1 debug menu - F2 switches the carjack minigame.")


func _physics_process(delta: float) -> void:
	_update_cruisers(delta)
	if hot_car != null and not is_instance_valid(hot_car):
		hot_car = null


func _input(event: InputEvent) -> void:
	if is_minigame_open():
		return
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if hud != null and hud.is_over_panel((event as InputEventMouseButton).position):
			return
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_F1:
			hud.toggle_debug()
		KEY_F2:
			cycle_minigame_mode()
		KEY_F3:
			cycle_tracker_mode()
		KEY_F4:
			cycle_difficulty()
		KEY_F5:
			get_tree().reload_current_scene()
		KEY_F6:
			teleport_to_next_target()
		KEY_F7:
			hud.toggle_tuning()
		_:
			return
	get_viewport().set_input_as_handled()


# --- Debug settings ---------------------------------------------------------------------------

func cycle_minigame_mode() -> StringName:
	minigame_mode = MINIGAME_MODES[(MINIGAME_MODES.find(minigame_mode) + 1) % MINIGAME_MODES.size()]
	EventBus.notify.emit("Carjack minigame: %s" % minigame_mode_name())
	return minigame_mode


func cycle_tracker_mode() -> StringName:
	tracker_mode = TRACKER_MODES[(TRACKER_MODES.find(tracker_mode) + 1) % TRACKER_MODES.size()]
	EventBus.notify.emit("Trackers: %s" % tracker_mode_name())
	return tracker_mode


func cycle_difficulty() -> StringName:
	difficulty_level = DIFFICULTY_ORDER[(DIFFICULTY_ORDER.find(difficulty_level) + 1) % DIFFICULTY_ORDER.size()]
	EventBus.notify.emit("Difficulty: %s" % String(difficulty_level).capitalize())
	return difficulty_level


func minigame_mode_name() -> String:
	return "Auto (parked: lock pick, occupied: struggle)" if minigame_mode == MINIGAME_AUTO else CarjackMinigame.display_name(minigame_mode)


func tracker_mode_name() -> String:
	return {&"per_car": "Per car (coupe + muscle car)", &"always": "Every car", &"never": "Off"}.get(tracker_mode, String(tracker_mode))


func difficulty() -> float:
	return DIFFICULTIES.get(difficulty_level, 1.0)


func minigame_kind_for(car: HotCar) -> StringName:
	if minigame_mode != MINIGAME_AUTO and CarjackMinigame.KINDS.has(minigame_mode):
		return minigame_mode
	return CarjackMinigame.KIND_STRUGGLE if car != null and car.has_occupant() else CarjackMinigame.KIND_LOCK_PICK


## Sets one [constant VehicleTuning.PARAMS] value and applies it live to every target car.
func set_tuning(property: StringName, value: float) -> void:
	tuning.set(property, value)
	for car in targets():
		tuning.apply(car)


func reset_tuning() -> void:
	tuning = default_tuning.duplicate_tuning()
	for car in targets():
		tuning.apply(car)


## Prints the current handling values and copies them to the clipboard.
func report_tuning() -> String:
	var text := "Car tuning: " + tuning.to_text()
	print(text)
	DisplayServer.clipboard_set(text)
	EventBus.notify.emit("Tuning copied to clipboard (also printed to the console)")
	return text


func targets() -> Array[HotCar]:
	var result: Array[HotCar] = []
	for car in _targets:
		if is_instance_valid(car):
			result.append(car)
	return result


func teleport_to_next_target() -> void:
	var cars := targets().filter(func(car: HotCar) -> bool: return car.can_jack())
	if cars.is_empty() or not player.is_on_foot():
		return
	var car: HotCar = cars[_teleport_index % cars.size()]
	_teleport_index += 1
	player.global_position = car.global_position + car.global_basis.x * 2.5 + Vector3.UP * 0.5
	player.velocity = Vector3.ZERO


# --- Jacking ----------------------------------------------------------------------------------

func is_minigame_open() -> bool:
	return minigame != null and is_instance_valid(minigame)


## Opens a minigame on [param car]. [param kind] overrides the debug setting.
func start_jack(car: HotCar, kind: StringName = &"") -> CarjackMinigame:
	if is_minigame_open() or car == null or not car.can_jack():
		return null
	minigame_car = car
	minigame = CarjackMinigame.create(kind if kind != &"" else minigame_kind_for(car))
	minigame.difficulty = difficulty()
	minigame.name = "Minigame"
	minigame.begin(car)
	minigame.finished.connect(_on_minigame_finished)
	minigame.too_slow.connect(_on_minigame_too_slow)
	minigame.cancelled.connect(_close_minigame)
	_minigame_layer.add_child(minigame)
	_set_player_frozen(true)
	jack_started.emit(car, minigame)
	return minigame


func _on_jack_requested(car: HotCar, actor: Node) -> void:
	if actor == player:
		start_jack(car)


func _on_minigame_too_slow() -> void:
	var car := minigame_car
	raise_alarm(PoliceCall.REASON_WITNESS, witness_countdown)
	if car != null:
		EventBus.notify.emit("Someone saw you messing with the %s" % car.car_name)


func _on_minigame_finished(success: bool, reason: String) -> void:
	var car := minigame_car
	EventBus.notify.emit(reason)
	if success:
		_close_minigame.call_deferred()
		_on_jack_success(car)
	else:
		if car != null and car.has_occupant():
			raise_alarm(PoliceCall.REASON_WITNESS, victim_countdown * 0.5)
		else:
			if car != null:
				car.set_alarm(true)
			raise_alarm(PoliceCall.REASON_NEIGHBOURS, alarm_countdown)
		get_tree().create_timer(1.2, false).timeout.connect(_close_minigame)
	jack_finished.emit(car, success)


func _close_minigame() -> void:
	if is_minigame_open():
		minigame.queue_free()
	minigame = null
	minigame_car = null
	_set_player_frozen(false)


func _on_jack_success(car: HotCar) -> void:
	if car == null or not is_instance_valid(car):
		return
	var was_occupied := car.has_occupant()
	car.unlock()
	if was_occupied:
		raise_alarm(PoliceCall.REASON_WITNESS, victim_countdown)
	if player.is_on_foot():
		car.enter(player)
	hot_car = car
	if _resolve_tracker(car):
		var tracker := HotCarTracker.new(car)
		tracker.name = "Tracker"
		car.tracker = tracker
		car.add_child(tracker)
		tracker.pinged.connect(_on_tracker_ping)
		tracker.lost.connect(_on_tracker_lost)
		if tracker_delay <= 0.0:
			_start_tracker(tracker)
		else:
			get_tree().create_timer(tracker_delay, false).timeout.connect(_start_tracker.bind(tracker))


func _resolve_tracker(car: HotCar) -> bool:
	match tracker_mode:
		&"always":
			return true
		&"never":
			return false
	return car.has_tracker


func _start_tracker(tracker: HotCarTracker) -> void:
	if not is_instance_valid(tracker) or not tracker.is_inside_tree():
		return
	tracker.start()
	EventBus.notify.emit("*beep* A TRACKER under the dash - it's pinging the cops! Outrun it or kill the signal in the parking garage.")


## Tips off the police: starts (or shortens) the [PoliceCall] countdown.
func raise_alarm(reason: StringName, seconds: float) -> void:
	alarms.append(reason)
	police_call.start_countdown(reason, seconds)
	alarm_raised.emit(reason)


func _set_player_frozen(frozen: bool) -> void:
	if player == null:
		return
	player.velocity = Vector3.ZERO
	player.set_physics_process(not frozen and player.is_on_foot())
	player.set_process_unhandled_input(not frozen)


# --- Tracker & police -------------------------------------------------------------------------

func _on_tracker_ping(at: Vector3) -> void:
	if not police_call.is_called():
		police_call.call_now(&"tracker")
	if police_response.is_wanted():
		police_response.last_seen = at
		police_response.unseen_time = 0.0
		for cop in police_response.alive_cops():
			cop.search_at(at)
	if cruisers.is_empty():
		_spawn_cruisers()
	for cruiser in cruisers:
		cruiser.chase(at)


func _on_tracker_lost(reason: StringName) -> void:
	match reason:
		&"expired":
			EventBus.notify.emit("The tracker went dead - you outran it")
		&"jammed":
			EventBus.notify.emit("The garage roof killed the tracker signal")


func _on_cops_arrived(_count: int) -> void:
	if cruisers.is_empty():
		_spawn_cruisers()


func _spawn_cruisers() -> void:
	for i in cruisers_per_call:
		var cruiser := PursuitCruiser.new()
		cruiser.name = "Cruiser%d" % i
		cruiser.position = POLICE_SPAWN + Vector3(i * 7.0, 0.3, 3.0 * (i % 2))
		cruiser.rotation.y = -PI / 2.0
		add_child(cruiser)
		cruiser.chase(police_response.last_seen if police_response.is_wanted() else to_global(POLICE_SPAWN))
		cruisers.append(cruiser)


## Cruisers follow sightings; a cruiser with eyes on the player counts as a sighting.
func _update_cruisers(_delta: float) -> void:
	cruisers = cruisers.filter(func(cruiser: PursuitCruiser) -> bool: return is_instance_valid(cruiser) and not cruiser.is_wrecked())
	if cruisers.is_empty() or player == null or not police_response.is_wanted():
		return
	var target := player.get_focus_position()
	for cruiser in cruisers:
		if cruiser.global_position.distance_to(target) <= cruiser_sight:
			police_response.last_seen = target
			police_response.unseen_time = 0.0
			break
	for cruiser in cruisers:
		cruiser.chase(police_response.last_seen)


func _clear_cruisers() -> void:
	for cruiser in cruisers:
		if is_instance_valid(cruiser):
			cruiser.queue_free()
	cruisers.clear()


func _on_delivered(car: HotCar, _payout: int) -> void:
	if car == hot_car:
		hot_car = null
	_clear_cruisers()
	_schedule_respawn(car)


# --- Building ---------------------------------------------------------------------------------

func _spawn_target(index: int) -> HotCar:
	var spec: Array = TARGETS[index]
	var car := HotCar.new()
	car.name = String(spec[0]).replace(" ", "")
	car.car_name = spec[0]
	car.position = spec[1]
	car.rotation.y = spec[2]
	car.body_color = spec[3]
	car.car_value = spec[4]
	car.occupied = spec[5]
	car.has_tracker = spec[6]
	car.set_meta(&"target_index", index)
	car.jack_requested.connect(_on_jack_requested)
	car.exploded.connect(_schedule_respawn.bind(car))
	get_node("Targets").add_child(car)
	_targets.append(car)
	if tuning == null:
		default_tuning = VehicleTuning.from_vehicle(car)
		tuning = default_tuning.duplicate_tuning()
	else:
		tuning.apply(car)
	return car


func _schedule_respawn(car: HotCar) -> void:
	var index: int = car.get_meta(&"target_index", -1)
	_targets.erase(car)
	if index < 0 or respawn_delay < 0.0:
		return
	get_tree().create_timer(respawn_delay, false).timeout.connect(func() -> void:
		if is_inside_tree():
			_spawn_target(index))


func _build_police() -> void:
	police_call = PoliceCall.new()
	police_call.name = "PoliceCall"
	police_call.hearing_radius = 60.0
	add_child(police_call)
	police_response = PoliceResponse.new()
	police_response.name = "PoliceResponse"
	police_response.police_call = police_call
	police_response.spawn_cruiser = false
	police_response.cops_per_wave = 2
	police_response.search_radius = 45.0
	police_response.lose_time = 10.0
	for offset: Vector3 in [Vector3(-4.0, 0.0, 0.0), Vector3(-8.0, 0.0, 2.0)]:
		var marker := Marker3D.new()
		marker.position = POLICE_SPAWN + offset
		police_response.add_child(marker)
	add_child(police_response)
	police_response.cops_arrived.connect(_on_cops_arrived)
	police_call.reset_done.connect(_clear_cruisers)


func _read_command_line() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		if parts.size() != 2:
			continue
		var value := StringName(parts[1].to_lower())
		match parts[0]:
			"minigame":
				if MINIGAME_MODES.has(value):
					minigame_mode = value
			"tracker":
				if TRACKER_MODES.has(value):
					tracker_mode = value
			"difficulty":
				if DIFFICULTIES.has(value):
					difficulty_level = value


func _build_world() -> void:
	var world := Node3D.new()
	world.name = "World"
	add_child(world)
	var half := BLOCK_SPACING * 2.0
	_static_box(world, Vector3(half * 2.0 + 20.0, 1.0, half * 2.0 + 20.0), Vector3(0.0, -0.5, 0.0), Color(0.3, 0.32, 0.3))
	var asphalt := Color(0.16, 0.16, 0.17)
	for i in 4:
		var line := -BLOCK_SPACING * 1.5 + i * BLOCK_SPACING
		_mesh_box(world, Vector3(12.0, 0.02, half * 2.0), Vector3(line, 0.01, 0.0), asphalt)
		_mesh_box(world, Vector3(half * 2.0, 0.02, 12.0), Vector3(0.0, 0.012, line), asphalt)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var special := {Vector2i(1, 1): true, Vector2i(-1, 1): true}
	for bx in range(-1, 2):
		for bz in range(-1, 2):
			var center := Vector3(bx * BLOCK_SPACING, 0.0, bz * BLOCK_SPACING)
			if special.has(Vector2i(bx, bz)):
				continue
			if Vector2i(bx, bz) == Vector2i(1, -1):
				_static_box(world, Vector3(30.0, 9.0, 24.0), center + Vector3(0.0, 4.5, -4.0), Color(0.25, 0.3, 0.45))
				var station := Label3D.new()
				station.text = "POLICE"
				station.font_size = 128
				station.position = center + Vector3(0.0, 11.0, 8.0)
				station.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				station.modulate = Color(0.5, 0.65, 1.0)
				world.add_child(station)
				continue
			for corner in 4:
				var offset := Vector3(-9.5 if corner % 2 == 0 else 9.5, 0.0, -9.5 if corner < 2 else 9.5)
				var height := rng.randf_range(6.0, 22.0)
				var shade := rng.randf_range(0.35, 0.6)
				_static_box(world, Vector3(17.0, height, 17.0), center + offset + Vector3(0.0, height * 0.5, 0.0), Color(shade, shade * 0.95, shade * 0.9))
	for side in 4:
		var along := side < 2
		var side_sign := -1.0 if side % 2 == 0 else 1.0
		var wall_size := Vector3(half * 2.0 + 20.0, 4.0, 1.0) if along else Vector3(1.0, 4.0, half * 2.0 + 20.0)
		var at := Vector3(0.0, 2.0, side_sign * (half + 8.0)) if along else Vector3(side_sign * (half + 8.0), 2.0, 0.0)
		_static_box(world, wall_size, at, Color(0.5, 0.45, 0.4))


func _static_box(parent: Node, box_size: Vector3, at: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = box_size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	_mesh_box(body, box_size, Vector3.ZERO, color)


func _mesh_box(parent: Node, box_size: Vector3, at: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	parent.add_child(instance)


func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.25, 0.3, 0.5)
	sky_material.sky_horizon_color = Color(0.85, 0.55, 0.4)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
	add_child(sun)
