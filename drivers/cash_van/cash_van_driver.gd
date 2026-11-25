class_name CashVanDriver
extends Node3D
## Cash van hit driver (#23, Viper cash van on I-59): a standalone highway loop with an armoured van
## driving it. Keep up, shoot out all four tires, survive the guards, release the rear doors from the
## cab, bag what you can and lose the cops - the longer the hit takes, the more cruisers join the
## chase. Then drop the bag at the stash garage in the infield. Not part of the city; F5 restarts.
## See drivers/cash_van/README.md.

## Seconds per escalation level: every this-many seconds since the first shot adds a cruiser per
## wave, and a new wave rolls in.
const ESCALATION_INTERVAL := 20.0
const MAX_CRUISERS := 6
## Seconds from the first shot until the van's panic button brings the police.
const PANIC_SECONDS := 20.0
const PLAYER_START_BEHIND := 60.0
const CRUISER_SPAWN_BEHIND := 90.0
const ROADBLOCK_AHEAD := 110.0
const STASH_POSITION := Vector3(0.0, 0.0, 0.0)

enum Phase { CHASE, VAN_DOWN, LOOT, ESCAPE, STASH, DONE, BUSTED }

var route: HighwayRoute
var van: ArmoredVan
var session: HitSession
var stash: StashDropoff
var getaway_car: Vehicle
var cruisers: Array[PursuitCruiser] = []
var phase := Phase.CHASE
## Seconds since the first shot at the van (null-ish -1 until then).
var hit_time := -1.0
var cash_made := 0

var _status: Label

@onready var player: Player = $Player


func _ready() -> void:
	_build_environment()
	route = HighwayRoute.new()
	route.name = "Route"
	add_child(route)

	van = ArmoredVan.new()
	van.name = "CashVan"
	van.route = route
	van.start_distance = PLAYER_START_BEHIND + 10.0
	add_child(van)
	van.attacked.connect(_on_van_attacked)
	van.tire_popped.connect(func(_tire: VanTire, _flats: int) -> void: _refresh_objective())
	van.stopped.connect(func() -> void: _set_phase(Phase.VAN_DOWN))
	van.doors_released.connect(func(_actor: Node) -> void: _set_phase(Phase.LOOT))

	_place_player()

	session = HitSession.new()
	session.name = "HitSession"
	add_child(session)
	session.setup(player, _roadblock_points(), van, PANIC_SECONDS)
	var response := session.police_response
	response.spawn_cruiser = false
	response.escalation_interval = ESCALATION_INTERVAL
	response.reinforcement_delay = 10.0
	response.wave_size_hook = func(_wanted_time: float, _wave: int) -> int: return cops_per_wave()
	response.cops_arrived.connect(func(_count: int) -> void: _spawn_cruisers(cruisers_per_wave()))
	response.escaped.connect(_on_escaped)
	session.finished.connect(func(cash: int) -> void:
		cash_made = cash
		_set_phase(Phase.DONE))
	session.failed.connect(func(_reason: StringName) -> void:
		_clear_cruisers()
		_set_phase(Phase.BUSTED))

	stash = StashDropoff.new()
	stash.name = "Stash"
	stash.prompt_name = "Stash garage"
	stash.position = STASH_POSITION
	add_child(stash)
	session.register_stash(stash)
	session.bag.changed.connect(_refresh_objective)

	_build_status_label()
	_refresh_objective()


func _physics_process(delta: float) -> void:
	if hit_time >= 0.0 and phase < Phase.STASH:
		hit_time += delta
	if session != null:
		session.police_response.spawn_points = _roadblock_points()
	_prune_cruisers()
	if phase == Phase.LOOT and _done_looting():
		_set_phase(Phase.ESCAPE if session.police_response.is_wanted() or session.police_call.is_active() else Phase.STASH)
	elif phase == Phase.ESCAPE and not session.police_response.is_wanted() and not session.police_call.is_active():
		_set_phase(Phase.STASH)
	_update_status()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F5:
		get_tree().reload_current_scene()


## 1 at the first shot, +1 every [constant ESCALATION_INTERVAL] seconds.
func heat_level() -> int:
	return 0 if hit_time < 0.0 else 1 + int(hit_time / ESCALATION_INTERVAL)


func cruisers_per_wave() -> int:
	return maxi(1, heat_level())


## Foot cops at the roadblock ahead: none at first, then one more per level.
func cops_per_wave() -> int:
	return maxi(0, heat_level() - 1)


func alive_cruisers() -> Array[PursuitCruiser]:
	var result: Array[PursuitCruiser] = []
	for cruiser in cruisers:
		if is_instance_valid(cruiser) and not cruiser.is_wrecked():
			result.append(cruiser)
	return result


func _on_van_attacked(_source: Node) -> void:
	if hit_time >= 0.0:
		return
	hit_time = 0.0
	session.police_call.start_countdown(PoliceCall.REASON_ALARM, PANIC_SECONDS)
	EventBus.notify.emit("The van crew hit the panic button - cops in %ds!" % int(PANIC_SECONDS))
	_refresh_objective()


func _on_escaped() -> void:
	_clear_cruisers()
	if phase == Phase.ESCAPE or phase == Phase.LOOT:
		_set_phase(Phase.STASH)


## Puts [param count] cruisers on the road behind the player (capped at [constant MAX_CRUISERS]).
func _spawn_cruisers(count: int) -> void:
	var focus := player.get_focus_position()
	var behind := route.closest_distance(focus) - CRUISER_SPAWN_BEHIND
	for i in count:
		if alive_cruisers().size() >= MAX_CRUISERS:
			return
		var cruiser := PursuitCruiser.new()
		cruiser.name = "Cruiser%d" % cruisers.size()
		cruiser.response = session.police_response
		var lane := 3.5 if i % 2 == 0 else -3.5
		var road := route.global_sample(behind - i * 12.0, lane)
		cruiser.transform = global_transform.affine_inverse() * road
		cruiser.speed = 18.0
		add_child(cruiser)
		cruisers.append(cruiser)


func _prune_cruisers() -> void:
	for i in range(cruisers.size() - 1, -1, -1):
		if not is_instance_valid(cruisers[i]):
			cruisers.remove_at(i)


func _clear_cruisers() -> void:
	for cruiser in cruisers:
		if is_instance_valid(cruiser):
			cruiser.queue_free()
	cruisers.clear()


func _roadblock_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	if route == null or player == null:
		return points
	var ahead := route.closest_distance(player.get_focus_position()) + ROADBLOCK_AHEAD
	points.append(route.global_sample(ahead, 3.0).origin)
	points.append(route.global_sample(ahead, -3.0).origin)
	return points


func _done_looting() -> bool:
	var bag := session.bag
	if van.loot.is_empty():
		return true
	if bag.free_slots() <= 0:
		return true
	return player.get_focus_position().distance_to(van.global_position) > 30.0


func _set_phase(next: Phase) -> void:
	if phase == next or phase == Phase.DONE:
		return
	phase = next
	match phase:
		Phase.VAN_DOWN:
			EventBus.notify.emit("Van's down! Get to the cab and pop the rear doors.")
		Phase.ESCAPE:
			EventBus.notify.emit("Bag's loaded - lose the cops!")
		Phase.STASH:
			EventBus.notify.emit("Clear. Get the bag to the stash garage in the infield.")
		Phase.DONE:
			_clear_cruisers()
			EventBus.notify.emit("Cash van hit done: +$%d. [F5] to run it again." % cash_made)
		Phase.BUSTED:
			EventBus.notify.emit("Busted. The bag's gone. [F5] to try again.")
	_refresh_objective()


func objective_text() -> String:
	match phase:
		Phase.CHASE:
			return "Keep up with the cash van and shoot out its tires (%d/4 flat)" % van.flats()
		Phase.VAN_DOWN:
			return "Van's down - get to the FRONT of the van and release the rear doors [E]"
		Phase.LOOT:
			return "Bag the cargo from the back (%d/%d slots) - then go" % [session.bag.used_slots(), session.bag.capacity]
		Phase.ESCAPE:
			return "Escape! Lose the cops"
		Phase.STASH:
			return "Drop the bag at the stash garage (infield)" if not session.bag.is_empty() else "Bag's empty. [F5] to run it again"
		Phase.DONE:
			return "Done! +$%d. [F5] restart" % cash_made
		Phase.BUSTED:
			return "Busted. [F5] restart"
	return ""


func _refresh_objective() -> void:
	if session != null and session.hud != null:
		session.hud.set_objective(objective_text())


func _place_player() -> void:
	getaway_car = Vehicle.new()
	getaway_car.name = "ChaseCar"
	getaway_car.body_color = Color(0.55, 0.08, 0.1)
	var start := route.global_sample(van.start_distance - PLAYER_START_BEHIND, van.lane)
	getaway_car.transform = global_transform.affine_inverse() * start
	getaway_car.position.y += 0.6
	add_child(getaway_car)
	player.global_position = getaway_car.global_position + getaway_car.global_basis.x * 2.0 + Vector3.UP * 0.5
	player.spawn_point = player.global_position
	player.weapons.add_weapon(GameState.weapon_data(&"rifle"), 150)
	player.weapons.add_weapon(GameState.weapon_data(&"smg"), 180)
	player.weapons.select(player.weapons.slots.find(player.weapons.find(&"rifle")))
	_enter_car.call_deferred()


func _enter_car() -> void:
	if is_instance_valid(getaway_car) and player.is_on_foot():
		getaway_car.enter(player)


func _build_status_label() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DriverStatus"
	add_child(layer)
	_status = Label.new()
	_status.position = Vector2(16.0, 200.0)
	_status.add_theme_font_size_override("font_size", 16)
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.add_theme_constant_override("outline_size", 4)
	layer.add_child(_status)


func _update_status() -> void:
	if _status == null:
		return
	var lines: PackedStringArray = ["CASH VAN HIT  [F5] restart"]
	var tire_text: PackedStringArray = []
	for tire in van.tires:
		tire_text.append("%s:%s" % [String(tire.tire_id).replace("front_", "F").replace("rear_", "R").replace("left", "L").replace("right", "R"), "FLAT" if tire.is_flat() else "%d" % int(tire.health)])
	lines.append("Van %.0f km/h  tires %s" % [van.speed * 3.6, " ".join(tire_text)])
	if hit_time >= 0.0:
		lines.append("Hit clock %ds  heat %d  cruisers %d  cops %d" % [int(hit_time), heat_level(), alive_cruisers().size(), session.police_response.alive_cops().size()])
	_status.text = "\n".join(lines)


func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.35, 0.5, 0.75)
	sky_material.sky_horizon_color = Color(0.8, 0.65, 0.55)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_density = 0.002
	environment.fog_light_color = Color(0.75, 0.65, 0.6)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
	add_child(sun)
