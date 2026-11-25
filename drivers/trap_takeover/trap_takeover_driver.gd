class_name TrapTakeoverDriver
extends Node3D
## Standalone gameplay driver: assault "The Spot", a Red Vipers trap house, clear every rival on
## every floor, then hold the basement stash room to claim it. Not wired into the city map.
##
## Launch: godot --path . res://drivers/trap_takeover/trap_takeover_driver.tscn
##   -- --difficulty=easy|normal|hard --enemies=N --seed=N --claim-time=S --screenshots=DIR
## Debug keys: F1 panel, F2 difficulty, F3/F4 enemies -/+, F5 re-roll, F6 restart, F7 kill all,
## F8 floor view, F9 god mode.

signal phase_changed(phase: Phase)
signal takeover_completed

enum Phase { ASSAULT, CLEARED, CLAIMING, COMPLETE }
enum Difficulty { EASY, NORMAL, HARD }

const DIFFICULTIES := {
	Difficulty.EASY: {"name": "Easy", "count": 8, "health": 0.8, "damage": 0.2, "reaction": 0.7, "weapons": [&"pistol", &"pistol", &"smg"], "reinforcements": 0},
	Difficulty.NORMAL: {"name": "Normal", "count": 12, "health": 1.0, "damage": 0.3, "reaction": 0.45, "weapons": [&"pistol", &"smg", &"shotgun"], "reinforcements": 2},
	Difficulty.HARD: {"name": "Hard", "count": 18, "health": 1.4, "damage": 0.4, "reaction": 0.3, "weapons": [&"smg", &"shotgun", &"rifle"], "reinforcements": 4},
}
const AREAS := ["Yard", "Ground", "Upper", "Basement"]
const ALERT_SHARE_RADIUS := 12.0
const GUNFIRE_HEARING_RADIUS := 22.0
const REWARD_CASH := 1000
const REWARD_RESPECT := 100
const CLAIM_FLAG := &"trap_takeover_the_spot"
## Floor view cycle: -99 = off, then basement, ground, upper, roof.
const FLOOR_VIEWS := [-99, -1, 0, 1, 2]

@export var difficulty: Difficulty = Difficulty.NORMAL
## Rivals placed at the start (-1 = the difficulty's default).
@export var enemy_count := -1
## Placement seed (0 = random each run).
@export var rng_seed := 0
## Seconds the stash room must be held, uncontested.
@export var claim_time := 20.0
## Rivals that roll up from the street once the claim starts (-1 = the difficulty's default).
@export var reinforcement_count := -1
## Read the "--key=value" user args after "--" (tests turn this off).
@export var parse_cmdline := true

var builder: TrapHouseBuilder
var phase := Phase.ASSAULT
var claim_progress := 0.0
## The rivals placed at the start; all of them must die before the claim opens.
var enemies: Array[IndoorGangMember] = []
var reinforcements: Array[IndoorGangMember] = []
## Slot ids used by the current placement, in spawn order.
var placement: Array[StringName] = []
var current_seed := 0
var god_mode := false
var floor_view := -99

var _rivals: Node3D
var _claim_marker: Node3D
var _overlay: TakeoverOverlay
var _show_debug := true
var _reinforcements_sent := false
var _floor_camera: Camera3D
var _previous_camera: Camera3D
var _last_ammo := {}
var _screenshot_dir := ""

@onready var player: Player = $Player


func _ready() -> void:
	if parse_cmdline:
		_parse_cmdline()
	_build_environment()
	builder = TrapHouseBuilder.new()
	builder.build(self)
	builder.bake()
	_rivals = Node3D.new()
	_rivals.name = "Rivals"
	add_child(_rivals)
	_build_claim_marker()
	_overlay = TakeoverOverlay.new()
	_overlay.name = "TakeoverOverlay"
	add_child(_overlay)
	_floor_camera = Camera3D.new()
	_floor_camera.name = "FloorViewCamera"
	_floor_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_floor_camera.size = 19.0
	_floor_camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	add_child(_floor_camera)
	_spawn_loadout()
	player.weapons.changed.connect(_on_player_weapons_changed)
	EventBus.player_died.connect(_on_player_died)
	EventBus.gang_member_killed.connect(_on_member_killed)
	start(current_seed if current_seed != 0 else rng_seed)
	if _screenshot_dir.is_empty():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		EventBus.notify.emit.call_deferred("The Vipers run a trap out of that house. Clear it out and claim it.")
	else:
		_take_screenshots.call_deferred()


## (Re)starts the takeover: player back on the street, fresh rivals placed with [param seed_value]
## (0 = random seed).
func start(seed_value := 0) -> void:
	current_seed = seed_value if seed_value != 0 else randi_range(1, 999999)
	for member: Variant in enemies + reinforcements:
		if is_instance_valid(member) and (member as Node).get_parent() == _rivals:
			_rivals.remove_child(member)
			member.queue_free()
	enemies.clear()
	reinforcements.clear()
	placement.clear()
	_reinforcements_sent = false
	claim_progress = 0.0
	_claim_marker.visible = false
	_overlay.show_banner("")
	if player.current_vehicle:
		player.current_vehicle.exit()
	player.spawn_point = TrapHouseBuilder.PLAYER_SPAWN
	player.respawn()
	player.rotation.y = 0.0
	_place_rivals()
	_set_phase(Phase.ASSAULT)


func config() -> Dictionary:
	return DIFFICULTIES[difficulty]


func target_enemy_count() -> int:
	return clampi(enemy_count if enemy_count >= 0 else config()["count"], 0, TrapHouseBuilder.SLOTS.size())


func alive_enemies() -> Array[IndoorGangMember]:
	return _living(enemies)


func alive_rivals() -> Array[IndoorGangMember]:
	var living := _living(enemies)
	living.append_array(_living(reinforcements))
	return living


func alive_by_area() -> Dictionary:
	var counts := {}
	for area in AREAS:
		counts[area] = 0
	for member in alive_rivals():
		counts[TrapHouseBuilder.area_of(member.global_position)] += 1
	return counts


func is_claimable() -> bool:
	return phase == Phase.CLEARED or phase == Phase.CLAIMING


func player_in_claim_zone() -> bool:
	if not player.is_on_foot() or player.health <= 0.0:
		return false
	var offset := player.global_position - TrapHouseBuilder.CLAIM_POINT
	return Vector2(offset.x, offset.z).length() <= TrapHouseBuilder.CLAIM_RADIUS and absf(offset.y) < 1.5


func is_contested() -> bool:
	for member in alive_rivals():
		if TrapHouseBuilder.is_inside(member.global_position):
			return true
	return false


func kill_all() -> void:
	for member in alive_rivals():
		member.take_damage(member.health + 1000.0, player)


func _physics_process(delta: float) -> void:
	if god_mode and player.health < player.max_health:
		player.heal(player.max_health)
	match phase:
		Phase.ASSAULT:
			if alive_enemies().is_empty():
				_set_phase(Phase.CLEARED)
		Phase.CLEARED, Phase.CLAIMING:
			_update_claim(delta)
	_update_overlay()


func _update_claim(delta: float) -> void:
	var inside := player_in_claim_zone()
	if inside and phase == Phase.CLEARED:
		_set_phase(Phase.CLAIMING)
		_send_reinforcements()
	if phase != Phase.CLAIMING:
		return
	if inside and not is_contested():
		claim_progress += delta / maxf(claim_time, 0.01)
	elif not inside:
		claim_progress -= delta / maxf(claim_time, 0.01) * 0.5
	claim_progress = clampf(claim_progress, 0.0, 1.0)
	if claim_progress >= 1.0:
		_complete()


func _complete() -> void:
	_set_phase(Phase.COMPLETE)
	_claim_marker.visible = false
	var scattered := 0
	for member in alive_rivals():
		member.queue_free()
		scattered += 1
	reinforcements.clear()
	GameState.add_cash(REWARD_CASH)
	GameState.add_respect(REWARD_RESPECT)
	GameState.set_flag(CLAIM_FLAG)
	EventBus.notify.emit("The Spot is yours. +$%d, +%d respect." % [REWARD_CASH, REWARD_RESPECT])
	_overlay.show_banner("TRAP HOUSE CLAIMED\nThe Spot now runs for you.\n+$%d   +%d respect%s\n\n[F6] restart   [F5] re-roll" % [
		REWARD_CASH, REWARD_RESPECT, "\n(%d stragglers scattered)" % scattered if scattered > 0 else ""])
	takeover_completed.emit()


func _set_phase(value: Phase) -> void:
	if phase == value and value != Phase.ASSAULT:
		return
	phase = value
	if value == Phase.CLEARED:
		_claim_marker.visible = true
		EventBus.notify.emit("House is clear. Get down to the stash room and hold it.")
	phase_changed.emit(value)


# --- Rivals -------------------------------------------------------------------------------------

func _place_rivals() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = current_seed
	var count := target_enemy_count()
	var pool: Array = TrapHouseBuilder.SLOTS.duplicate()
	_shuffle(pool, rng)
	var chosen: Array = []
	if count >= 5 and difficulty != Difficulty.EASY:
		for slot: Dictionary in pool:
			if slot.get("boss", false):
				chosen.append(slot)
		pool = pool.filter(func(slot: Dictionary) -> bool: return not slot.get("boss", false))
	# Spread rivals over every area before doubling up.
	for area in AREAS:
		if chosen.size() >= count:
			break
		if chosen.any(func(slot: Dictionary) -> bool: return slot["area"] == area):
			continue
		for slot: Dictionary in pool:
			if slot["area"] == area:
				chosen.append(slot)
				pool.erase(slot)
				break
	while chosen.size() < count and not pool.is_empty():
		chosen.append(pool.pop_back())
	for slot: Dictionary in chosen:
		enemies.append(_spawn_rival(slot, rng))
		placement.append(slot["id"])


func _spawn_rival(slot: Dictionary, rng: RandomNumberGenerator) -> IndoorGangMember:
	var settings := config()
	var member := IndoorGangMember.new()
	member.gang_id = &"vipers"
	member.name = "Viper_%s" % slot["id"]
	member.post = IndoorGangMember.Post[String(slot["post"])]
	member.post_yaw = TrapHouseBuilder.slot_yaw(slot)
	var patrol: Array[Vector3] = []
	for point: Vector3 in slot.get("patrol", []):
		patrol.append(point + Vector3(0.0, 0.05, 0.0))
	member.patrol_points = patrol
	member.max_health = 60.0 * settings["health"]
	member.damage_scale = settings["damage"]
	member.reaction_time = settings["reaction"]
	var weapons: Array = settings["weapons"]
	member.weapon_id = weapons[rng.randi() % weapons.size()]
	if member.post == IndoorGangMember.Post.OVERWATCH and difficulty != Difficulty.EASY:
		member.weapon_id = &"rifle"
	if slot.get("boss", false):
		member.max_health *= 2.5
		member.weapon_id = &"shotgun"
		member.name = "Viper_boss"
	var jitter := Vector3(rng.randf_range(-0.25, 0.25), 0.05, rng.randf_range(-0.25, 0.25))
	member.position = slot["pos"] + jitter
	_rivals.add_child(member)
	member.alerted.connect(_on_member_alerted)
	if _screenshot_dir != "":
		member.process_mode = Node.PROCESS_MODE_DISABLED
	return member


func _send_reinforcements() -> void:
	if _reinforcements_sent:
		return
	_reinforcements_sent = true
	var count: int = reinforcement_count if reinforcement_count >= 0 else config()["reinforcements"]
	if count <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = current_seed + 7
	for i in count:
		var spawn: Vector3 = TrapHouseBuilder.REINFORCEMENT_SPAWNS[i % TrapHouseBuilder.REINFORCEMENT_SPAWNS.size()]
		var member := _spawn_rival({"id": StringName("backup_%d" % i), "pos": spawn, "look": Vector3(0.5, 0.0, 0.0), "post": &"GUARD"}, rng)
		reinforcements.append(member)
		member.alert.call_deferred(player.global_position)
	EventBus.notify.emit("Viper backup rolling up from the street!")


func _on_member_alerted(member: IndoorGangMember) -> void:
	for other in alive_rivals():
		if other != member and other.state == IndoorGangMember.State.IDLE and other.global_position.distance_to(member.global_position) <= ALERT_SHARE_RADIUS:
			other.alert(member.last_known_position)


func _on_player_weapons_changed() -> void:
	var slot := player.weapons.current()
	if slot == null:
		return
	var key := player.weapons.current_index
	var fired: bool = _last_ammo.get(key, -1) > slot.magazine and slot.data.uses_ammo()
	_last_ammo.clear()
	_last_ammo[key] = slot.magazine
	if not fired:
		return
	for member in alive_rivals():
		if member.global_position.distance_to(player.global_position) <= GUNFIRE_HEARING_RADIUS:
			member.alert(player.global_position)


func _on_player_died() -> void:
	for member in alive_rivals():
		member.stand_down()


func _on_member_killed(member: GangMember, _killer: Node) -> void:
	if member in enemies and phase == Phase.ASSAULT:
		var left := alive_enemies().size()
		if left > 0 and left <= 3:
			EventBus.notify.emit("%d Viper%s left." % [left, "" if left == 1 else "s"])


static func _living(members: Array[IndoorGangMember]) -> Array[IndoorGangMember]:
	var living: Array[IndoorGangMember] = []
	for member in members:
		if is_instance_valid(member) and member.is_alive():
			living.append(member)
	return living


static func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = items[i]
		items[i] = items[j]
		items[j] = swap


# --- World --------------------------------------------------------------------------------------

func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.3, 0.42, 0.65)
	sky_material.sky_horizon_color = Color(0.85, 0.6, 0.45)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.8
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_density = 0.004
	environment.fog_light_color = Color(0.75, 0.62, 0.55)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)


func _build_claim_marker() -> void:
	_claim_marker = Node3D.new()
	_claim_marker.name = "ClaimMarker"
	_claim_marker.position = TrapHouseBuilder.CLAIM_POINT
	add_child(_claim_marker)
	var ring_material := StandardMaterial3D.new()
	ring_material.albedo_color = Color(0.3, 1.0, 0.4, 0.45)
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var ring := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = TrapHouseBuilder.CLAIM_RADIUS
	disc.bottom_radius = TrapHouseBuilder.CLAIM_RADIUS
	disc.height = 0.04
	disc.material = ring_material
	ring.mesh = disc
	ring.position.y = 0.03
	_claim_marker.add_child(ring)
	# Beacon drawn over everything so the claim spot can be found from the yard.
	var beacon_material := StandardMaterial3D.new()
	beacon_material.albedo_color = Color(0.3, 1.0, 0.4, 0.35)
	beacon_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beacon_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beacon_material.no_depth_test = true
	var beacon := MeshInstance3D.new()
	var column := CylinderMesh.new()
	column.top_radius = 0.15
	column.bottom_radius = 0.15
	column.height = 12.0
	column.material = beacon_material
	beacon.mesh = column
	beacon.position.y = 6.0
	_claim_marker.add_child(beacon)
	var label := Label3D.new()
	label.text = "CLAIM"
	label.font_size = 48
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color(0.5, 1.0, 0.55)
	label.position.y = 2.2
	_claim_marker.add_child(label)


func _spawn_loadout() -> void:
	for id: StringName in [&"smg", &"shotgun", &"rifle", &"grenade", &"molotov"]:
		var weapon := GameState.weapon_data(id)
		if weapon != null and player.weapons.find(id) == null:
			player.weapons.add_weapon(weapon, weapon.magazine_size * (4 if weapon.thrown else 5))
	var stash := {&"rifle": Vector3(-3.0, 0.0, -3.0), &"shotgun": Vector3(-1.5, 0.0, -3.0), &"grenade": Vector3(1.5, 0.0, -3.0), &"molotov": Vector3(3.0, 0.0, -3.0)}
	for id: StringName in stash:
		var weapon := GameState.weapon_data(id)
		if weapon != null:
			add_child(WeaponPickup.create(weapon, weapon.magazine_size * (4 if weapon.thrown else 3), TrapHouseBuilder.PLAYER_SPAWN + stash[id]))
	var car := Vehicle.new()
	car.name = "GetawayCar"
	car.body_color = Color(0.45, 0.15, 0.6)
	car.position = Vector3(-7.0, 0.8, 24.0)
	car.rotation.y = PI / 2.0
	add_child(car)


# --- Debug --------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and _screenshot_dir.is_empty():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).keycode:
		KEY_F1:
			_show_debug = not _show_debug
		KEY_F2:
			difficulty = ((difficulty + 1) % Difficulty.size()) as Difficulty
			enemy_count = -1
			start(current_seed)
			EventBus.notify.emit("Difficulty: %s" % config()["name"])
		KEY_F3:
			enemy_count = maxi(0, target_enemy_count() - 1)
			start(current_seed)
		KEY_F4:
			enemy_count = mini(TrapHouseBuilder.SLOTS.size(), target_enemy_count() + 1)
			start(current_seed)
		KEY_F5:
			start(0)
			EventBus.notify.emit("Re-rolled placement (seed %d)." % current_seed)
		KEY_F6:
			start(current_seed)
		KEY_F7:
			kill_all()
		KEY_F8:
			set_floor_view(FLOOR_VIEWS[(FLOOR_VIEWS.find(floor_view) + 1) % FLOOR_VIEWS.size()])
		KEY_F9:
			god_mode = not god_mode
			EventBus.notify.emit("God mode %s" % ("ON" if god_mode else "OFF"))
		_:
			return
	get_viewport().set_input_as_handled()


## Top-down cutaway of one level (-1 basement .. 2 roof); [code]-99[/code] goes back to the player camera.
func set_floor_view(level: int) -> void:
	floor_view = level
	var on := level != -99
	for index: int in builder.levels:
		(builder.levels[index] as Node3D).visible = not on or index <= level
	for label in builder.room_labels:
		label.visible = on and is_equal_approx(label.global_position.y - 0.05, TrapHouseBuilder.level_y(level))
	for member in alive_rivals():
		member.visible = not on or TrapHouseBuilder.level_of(member.global_position) <= level
	player.visible = not on or TrapHouseBuilder.level_of(player.global_position) <= level
	if on:
		if not _floor_camera.current:
			_previous_camera = get_viewport().get_camera_3d()
		_floor_camera.position = Vector3(0.0, TrapHouseBuilder.level_y(level) + 30.0, 0.5)
		_floor_camera.make_current()
	elif _floor_camera.current:
		if is_instance_valid(_previous_camera):
			_previous_camera.make_current()
		_floor_camera.current = false


func _update_overlay() -> void:
	match phase:
		Phase.ASSAULT:
			var counts := alive_by_area()
			_overlay.set_objective("TAKE THE SPOT - clear out the Red Vipers (%d left)\nYard %d   Ground %d   Upper %d   Basement %d" % [
				alive_enemies().size(), counts["Yard"], counts["Ground"], counts["Upper"], counts["Basement"]])
		Phase.CLEARED:
			_overlay.set_objective("House is clear. Hold the stash room in the basement to claim it.")
		Phase.CLAIMING:
			_overlay.set_objective("Hold the stash room until the house is yours." if player_in_claim_zone() else "Get back in the stash room - the claim is slipping!")
		Phase.COMPLETE:
			_overlay.set_objective("The Spot is yours.")
	_overlay.set_progress(claim_progress, phase == Phase.CLAIMING, is_contested() and player_in_claim_zone())
	var counts := alive_by_area()
	_overlay.set_debug("TRAP TAKEOVER DRIVER\nPhase: %s\nDifficulty: %s\nEnemies: %d placed / %d alive\nSeed: %d\nPlayer: %s\nRivals by area: Y%d G%d U%d B%d\nGod mode: %s   View: %s\n\nF1 panel  F2 difficulty\nF3/F4 enemies -/+  F5 re-roll\nF6 restart  F7 kill all\nF8 floor view  F9 god mode" % [
		Phase.keys()[phase], config()["name"], enemies.size(), alive_enemies().size(), current_seed,
		TrapHouseBuilder.room_at(player.global_position), counts["Yard"], counts["Ground"], counts["Upper"], counts["Basement"],
		"on" if god_mode else "off", "player" if floor_view == -99 else TrapHouseBuilder.LEVEL_NAMES[floor_view]], _show_debug)


func _parse_cmdline() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		var value := parts[1] if parts.size() > 1 else ""
		match parts[0]:
			"difficulty":
				match value.to_lower():
					"easy":
						difficulty = Difficulty.EASY
					"hard":
						difficulty = Difficulty.HARD
					_:
						difficulty = Difficulty.NORMAL
			"enemies":
				enemy_count = value.to_int()
			"seed":
				rng_seed = value.to_int()
			"claim-time":
				claim_time = value.to_float()
			"screenshots":
				_screenshot_dir = value


## Saves a cutaway of every floor plus an exterior shot to [member _screenshot_dir], then quits.
func _take_screenshots() -> void:
	DirAccess.make_dir_recursive_absolute(_screenshot_dir)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	_show_debug = false
	_claim_marker.visible = true
	for i in 30:
		await get_tree().process_frame
	var shots := {-1: "1_basement", 0: "2_ground", 1: "3_upper", 2: "4_roof"}
	for level: int in shots:
		set_floor_view(level)
		for i in 8:
			await get_tree().process_frame
		_save_shot(shots[level])
	set_floor_view(-99)
	var exterior := Camera3D.new()
	add_child(exterior)
	exterior.look_at_from_position(Vector3(24.0, 16.0, 30.0), Vector3(0.0, 1.5, 0.0))
	exterior.make_current()
	for i in 8:
		await get_tree().process_frame
	_save_shot("0_exterior")
	exterior.look_at_from_position(Vector3(-20.0, 14.0, -26.0), Vector3(0.0, 1.5, 0.0))
	for i in 8:
		await get_tree().process_frame
	_save_shot("5_back_yard")
	get_tree().quit()


func _save_shot(shot_name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var path := _screenshot_dir.path_join("trap_takeover_%s.png" % shot_name)
	image.save_png(path)
	print("Saved ", path)
