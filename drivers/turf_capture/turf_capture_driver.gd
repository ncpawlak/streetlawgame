class_name TurfCaptureDriver
extends Node3D
## Standalone turf-capture driver: one Red Vipers intersection with a highlighted capture zone. Clear the
## guards, step into the zone, then hold it while escalating waves come at you on foot and by car from every
## street. The block is yours when the bar is full and the last wave is dead.
##
## Debug (also in the F1 panel):
##   godot --path . res://drivers/turf_capture/turf_capture_driver.tscn -- --waves=6 --difficulty=hard --guards=0
## Everything is placed relative to this node, so it can be instanced anywhere (the tests offset it).

const ENEMY_GANG := &"vipers"
const ROAD_WIDTH := 14.0
const BLOCK_SIZE := 48.0
const SIDEWALK_WIDTH := 4.0
## Half-length of each street from the intersection.
const STREET_REACH := 140.0
## Approach directions, ordered so the player's own street (south, +Z) is the last to get hit.
const APPROACHES: Array[Vector3] = [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1)]
const FOOT_SPAWN_DISTANCE := 70.0
const CAR_SPAWN_DISTANCE := 112.0
const CAR_STOP_DISTANCE := 24.0
const PLAYER_START := Vector3(0.0, 1.0, 46.0)
## Wave members always know where you are.
const WAVE_AGGRO_RANGE := 160.0
const CAPTURE_REWARD := 1000
const CAPTURE_RESPECT := 150
const RETRY_DELAY := 4.0

@export var wave_count := 4
@export var difficulty: StringName = &"normal"
@export var guard_count := 4
@export var zone_radius := 10.0

var model := TurfCaptureModel.new()
var zone: CaptureZone
## Live hostiles this run: GangMember -> true if it's a guard.
var enemies: Dictionary = {}
var raid_cars: Array[RaidCar] = []

var _retry_left := -1.0
var _rng := RandomNumberGenerator.new()

@onready var player: Player = $Player
@onready var hud: TurfCaptureHud = $TurfHUD


func _ready() -> void:
	_apply_cmdline_args()
	_build_environment()
	_build_block()
	zone = CaptureZone.new()
	zone.name = "CaptureZone"
	zone.radius = zone_radius
	add_child(zone)
	_spawn_stash()
	model.wave_started.connect(_on_wave_started)
	model.state_changed.connect(_on_state_changed)
	EventBus.gang_member_killed.connect(_on_member_killed)
	EventBus.player_died.connect(_on_player_died)
	hud.restart_requested.connect(restart)
	player.spawn_point = to_global(PLAYER_START)
	restart(wave_count, difficulty, guard_count)
	if not Engine.is_editor_hint() and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	EventBus.notify.emit.call_deferred("Red Vipers run this corner. Take out their guards, then hold the zone.")
	EventBus.notify.emit.call_deferred("Guns and explosives on the sidewalk behind you. Hold [Q] for the weapon wheel.")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
			and not hud.is_debug_visible():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if _retry_left > 0.0:
		_retry_left -= delta
		if _retry_left <= 0.0:
			restart(model.wave_count, model.difficulty, model.guard_count)
	model.tick(delta, is_player_holding())
	hud.refresh(model)


## Starts a fresh capture with these debug options (also used by the F1 panel).
func restart(waves: int, difficulty_id: StringName, guards: int) -> void:
	_retry_left = -1.0
	_clear_hostiles()
	wave_count = waves
	difficulty = difficulty_id
	guard_count = guards
	model.configure(waves, difficulty_id, guards)
	hud.set_options(model.wave_count, model.difficulty, model.guard_count)
	for i in model.guard_count:
		var angle := TAU * i / model.guard_count + _rng.randf_range(-0.3, 0.3)
		var guard := _make_member(false)
		guard.position = Vector3(cos(angle), 0.0, sin(angle)) * zone_radius * 0.6 + Vector3.UP * 0.2
		_track(guard, true)
		add_child(guard)
	player.respawn()
	player.rotation.y = 0.0
	hud.refresh(model)


## Capture only counts while you're standing in the zone on foot.
func is_player_holding() -> bool:
	return player.is_on_foot() and player.health > 0.0 and zone.contains(player.global_position)


## Local point where wave member [param index] from [param direction] starts walking in. Pairs fill both
## sidewalks, further back as the group grows.
func foot_spawn_point(direction: Vector3, index: int) -> Vector3:
	var lateral := Vector3(-direction.z, 0.0, direction.x)
	var side := 1.0 if index % 2 == 0 else -1.0
	var back := FOOT_SPAWN_DISTANCE + float(index / 2) * 1.6
	return direction * back + lateral * side * (ROAD_WIDTH * 0.5 - 1.0) + Vector3.UP * 0.2


func _on_wave_started(index: int, plan: Dictionary) -> void:
	var approaches: Array[Vector3] = APPROACHES.slice(0, plan.approaches)
	var foot_groups: Array[int] = []
	foot_groups.resize(approaches.size())
	for i in plan.on_foot:
		foot_groups[i % approaches.size()] += 1
	for a in approaches.size():
		for i in foot_groups[a]:
			var member := _make_member(true)
			member.position = foot_spawn_point(approaches[a], i)
			_track(member, false)
			add_child(member)
	model.add_enemies(plan.on_foot)
	for c in plan.cars:
		# Cars favour a different street from the first foot group, and queue up when they share one.
		_spawn_raid_car(approaches[(c + 1) % approaches.size()], plan.crew_per_car, c / approaches.size())
	model.add_enemies(plan.cars * plan.crew_per_car)
	var cars_text := " + %d car%s" % [plan.cars, "" if plan.cars == 1 else "s"] if plan.cars > 0 else ""
	var final_text := "FINAL WAVE" if index == model.wave_count - 1 else "WAVE %d" % (index + 1)
	hud.banner("%s  -  %d Vipers%s" % [final_text, plan.total, cars_text], Color(1.0, 0.45, 0.4))
	EventBus.notify.emit("Wave %d: %d Vipers inbound from %d direction(s)" % [index + 1, plan.total, plan.approaches])


func _spawn_raid_car(direction: Vector3, crew: int, row: int) -> void:
	var car := RaidCar.new()
	var lateral := Vector3(-direction.z, 0.0, direction.x)
	var lane := lateral * -ROAD_WIDTH * 0.25
	car.position = direction * (CAR_SPAWN_DISTANCE + row * 12.0) + lane + Vector3.UP * 0.6
	car.rotation.y = atan2(-direction.x, -direction.z)
	car.destination = to_global(direction * (CAR_STOP_DISTANCE + row * 8.0) + lane)
	car.crew = crew
	car.body_color = GameState.gang_color(ENEMY_GANG).darkened(0.45)
	car.crew_setup = func(member: GangMember) -> void: _configure_member(member, true)
	car.unloaded.connect(func(members: Array[GangMember]) -> void:
		for member in members:
			_track(member, false))
	car.crew_lost.connect(func(count: int) -> void:
		model.remove_enemies(count)
		EventBus.notify.emit("Raid car down - %d Vipers burned with it" % count))
	raid_cars.append(car)
	add_child(car)


func _make_member(wave: bool) -> GangMember:
	var member := GangMember.new()
	_configure_member(member, wave)
	return member


func _configure_member(member: GangMember, wave: bool) -> void:
	member.gang_id = ENEMY_GANG
	member.max_health *= float(model.tuning("health"))
	member.damage_scale *= float(model.tuning("damage"))
	if wave:
		member.aggro_range = WAVE_AGGRO_RANGE
		member.alerted_range = WAVE_AGGRO_RANGE
		member.drop_chance = 0.35
	else:
		member.wander_radius = zone_radius * 0.5


func _track(member: GangMember, guard: bool) -> void:
	enemies[member] = guard


func _on_member_killed(member: GangMember, _killer: Node) -> void:
	if not enemies.has(member):
		return
	var guard: bool = enemies[member]
	enemies.erase(member)
	model.remove_enemies(1, guard)


func _on_state_changed(state: TurfCaptureModel.State) -> void:
	match state:
		TurfCaptureModel.State.GUARDED:
			zone.set_color(GameState.gang_color(ENEMY_GANG))
		TurfCaptureModel.State.READY:
			zone.set_color(Color(0.95, 0.95, 0.95), true)
			if model.guard_count > 0:
				hud.banner("GUARDS DOWN - take the corner", Color(1.0, 0.95, 0.6))
		TurfCaptureModel.State.CAPTURING:
			zone.set_color(GameState.gang_color(GameState.PLAYER_GANG), true)
			hud.banner("HOLD THE ZONE", GameState.gang_color(GameState.PLAYER_GANG).lightened(0.4))
		TurfCaptureModel.State.CAPTURED:
			zone.set_color(GameState.gang_color(GameState.PLAYER_GANG))
			hud.banner("BLOCK CAPTURED", Color(0.7, 1.0, 0.7), 6.0)
			GameState.add_cash(CAPTURE_REWARD)
			GameState.add_respect(CAPTURE_RESPECT)
			EventBus.notify.emit("The corner is yours: +$%d, +%d respect. [F1] to run it again." % [CAPTURE_REWARD, CAPTURE_RESPECT])
		TurfCaptureModel.State.FAILED:
			zone.set_color(GameState.gang_color(ENEMY_GANG))
			hud.banner("CAPTURE FAILED", Color(1.0, 0.4, 0.4), RETRY_DELAY)
			_retry_left = RETRY_DELAY


func _on_player_died() -> void:
	model.fail()


func _clear_hostiles() -> void:
	for member: GangMember in enemies:
		if is_instance_valid(member):
			member.queue_free()
	enemies.clear()
	for car in raid_cars:
		if is_instance_valid(car):
			car.queue_free()
	raid_cars.clear()


func _apply_cmdline_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		if parts.size() != 2:
			continue
		match parts[0]:
			"waves":
				wave_count = clampi(parts[1].to_int(), 1, 12)
			"difficulty":
				difficulty = StringName(parts[1].to_lower())
			"guards":
				guard_count = clampi(parts[1].to_int(), 0, 10)


func _spawn_stash() -> void:
	var weapons := {
		&"smg": Vector3(9.5, 0.3, 40.0), &"shotgun": Vector3(9.5, 0.3, 43.0), &"rifle": Vector3(9.5, 0.3, 46.0),
		&"grenade": Vector3(-9.5, 0.3, 40.0), &"molotov": Vector3(-9.5, 0.3, 43.0), &"rpg": Vector3(-9.5, 0.3, 46.0),
	}
	for id: StringName in weapons:
		var weapon := GameState.weapon_data(id)
		add_child(WeaponPickup.create(weapon, weapon.magazine_size * (5 if weapon.thrown else 4), weapons[id]))


# --- World -----------------------------------------------------------------------------------------------

func _build_block() -> void:
	var asphalt := _material(Color(0.17, 0.17, 0.19))
	var sidewalk := _material(Color(0.45, 0.45, 0.46))
	var line := _material(Color(0.9, 0.85, 0.5))
	var ground_size := STREET_REACH * 2.0 + 40.0
	_static_box(Vector3(ground_size, 1.0, ground_size), Vector3(0.0, -0.5, 0.0), asphalt)
	# Lane markings down both streets (skipping the intersection).
	for direction in APPROACHES:
		for i in range(1, 14):
			var at := direction * (ROAD_WIDTH * 0.5 + i * 9.0)
			var size := Vector3(0.25, 0.02, 4.0) if direction.x == 0.0 else Vector3(4.0, 0.02, 0.25)
			_mesh_box(size, at + Vector3.UP * 0.01, line)
	# 2x2 blocks per quadrant around the intersection, with side streets between them.
	var offset := ROAD_WIDTH * 0.5 + BLOCK_SIZE * 0.5
	var pitch := BLOCK_SIZE + ROAD_WIDTH
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			for i in 2:
				for j in 2:
					var center := Vector3(sx * (offset + i * pitch), 0.0, sz * (offset + j * pitch))
					_static_box(Vector3(BLOCK_SIZE, 0.2, BLOCK_SIZE), center + Vector3.UP * 0.1, sidewalk)
					_build_buildings(center, int(center.x * 31.0 + center.z))
	# Outer walls so nobody falls off the edge.
	for direction in APPROACHES:
		var wall := Vector3(2.0, 12.0, ground_size) if direction.x != 0.0 else Vector3(ground_size, 12.0, 2.0)
		_static_box(wall, direction * (ground_size * 0.5) + Vector3.UP * 6.0, null)
	_build_cover()


## A few storefronts per block, set back from the sidewalk.
func _build_buildings(center: Vector3, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var inner := BLOCK_SIZE * 0.5 - SIDEWALK_WIDTH
	var lots := [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1)]
	for lot: Vector3 in lots:
		var footprint := Vector3(rng.randf_range(14.0, 19.0), rng.randf_range(7.0, 22.0), rng.randf_range(14.0, 19.0))
		var at := center + lot * (inner - footprint.x * 0.5) + Vector3.UP * (footprint.y * 0.5 + 0.2)
		var color := Color.from_hsv(rng.randf_range(0.0, 0.12), rng.randf_range(0.15, 0.35), rng.randf_range(0.35, 0.6))
		_static_box(footprint, at, _material(color))


## Barriers, crates and a dumpster around the zone so there's something to fight from.
func _build_cover() -> void:
	var concrete := _material(Color(0.62, 0.6, 0.56))
	var crate := _material(Color(0.45, 0.3, 0.15))
	var dumpster := _material(Color(0.15, 0.35, 0.2))
	var r := zone_radius
	_static_box(Vector3(3.0, 1.1, 0.6), Vector3(0.0, 0.55, -r * 0.55), concrete)
	_static_box(Vector3(0.6, 1.1, 3.0), Vector3(r * 0.55, 0.55, 0.0), concrete)
	_static_box(Vector3(0.6, 1.1, 3.0), Vector3(-r * 0.55, 0.55, 0.0), concrete)
	_static_box(Vector3(1.2, 1.2, 1.2), Vector3(-2.5, 0.6, r * 0.45), crate)
	_static_box(Vector3(1.2, 1.2, 1.2), Vector3(-1.2, 0.6, r * 0.5), crate)
	_static_box(Vector3(1.0, 1.0, 1.0), Vector3(-1.9, 1.7, r * 0.47), crate)
	_static_box(Vector3(3.2, 1.6, 1.8), Vector3(ROAD_WIDTH * 0.5 + 2.0, 1.0, ROAD_WIDTH * 0.5 + 3.5), dumpster)
	_static_box(Vector3(1.8, 1.6, 3.2), Vector3(-ROAD_WIDTH * 0.5 - 3.5, 1.0, -ROAD_WIDTH * 0.5 - 2.0), dumpster)
	# A ride for the player, parked at the curb down their street (out of the raid cars' lane).
	var car := Vehicle.new()
	car.position = Vector3(-ROAD_WIDTH * 0.5 + 1.6, 0.6, 58.0)
	car.body_color = Color(0.25, 0.12, 0.4)
	add_child(car)


func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.22, 0.25, 0.45)
	sky_material.sky_horizon_color = Color(0.85, 0.5, 0.4)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.fog_enabled = true
	environment.fog_density = 0.004
	environment.fog_light_color = Color(0.7, 0.55, 0.5)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, -40.0, 0.0)
	sun.light_energy = 0.9
	sun.light_color = Color(1.0, 0.85, 0.7)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
	add_child(sun)


func _static_box(size: Vector3, at: Vector3, material: StandardMaterial3D) -> void:
	var body := StaticBody3D.new()
	body.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	if material != null:
		var mesh := BoxMesh.new()
		mesh.size = size
		mesh.material = material
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		body.add_child(instance)
	add_child(body)


func _mesh_box(size: Vector3, at: Vector3, material: StandardMaterial3D) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	add_child(instance)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material
