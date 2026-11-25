class_name DriveByDriver
extends Node3D
## Standalone drive-by driver: a few blocks of street, a Red Vipers corner crew with their cars
## parked nearby, and the player already behind the wheel (optionally with a crew gunner riding
## shotgun). Not part of the city map - boots straight into the drive-by loop.
##
## Run: godot --path . res://drivers/driveby/driveby_driver.tscn [-- --crew=6 --no-cars --no-gunner --gunner-skill=8]
## Debug keys: F1/F2 crew size -/+, F3 rivals have cars, F4 crew gunner, F5 restart,
## F6/F7 gunner shooting skill -/+ (applies live).

const MIN_CREW := 1
const MAX_CREW := 8
const PLAYER_START := Vector3(0.0, 0.6, 70.0)
## Curb the corner crew hangs out on (north-east corner block of the target intersection).
const CORNER_START := Vector3(8.0, 0.0, -36.0)
const PARKED_CARS := [Vector3(17.0, 0.6, -48.0), Vector3(28.0, 0.6, -40.0)]

## Debug settings. Static so they survive the scene reload that applies them.
static var crew_size := 4
static var rivals_have_cars := true
static var passenger_gunner := true
## Shooting skill (1-10) of the crew member riding shotgun.
static var gunner_skill := 5
static var _args_read := false

var grid: StreetGrid
var mission: DriveByMission
var player_car: Vehicle
var gunner: CrewGunner
var crew: Array[GangMember] = []
var rival_cars: Array[ChaseCar] = []

var _objective_label: Label
var _escape_bar: ProgressBar
var _debug_label: Label
var _result_label: Label

@onready var player: Player = $Player


func _ready() -> void:
	_read_args()
	_build_environment()
	grid = StreetGrid.new()
	grid.name = "Streets"
	add_child(grid)
	_spawn_player()
	_spawn_crew()
	if rivals_have_cars:
		_spawn_rival_cars()
	mission = DriveByMission.new()
	mission.name = "Mission"
	add_child(mission)
	mission.setup(crew, rival_cars)
	mission.completed.connect(func(_kills: int) -> void: _show_result("DRIVE-BY COMPLETE", Color(0.5, 1.0, 0.5)))
	mission.failed.connect(func(reason: String) -> void: _show_result("FAILED - %s" % reason, Color(1.0, 0.4, 0.4)))
	_build_ui()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	EventBus.notify.emit.call_deferred("Red Vipers are posted up on the corner ahead. Roll by and light 'em up.")


func _process(_delta: float) -> void:
	_objective_label.text = mission.objective_text()
	_escape_bar.visible = mission.phase == DriveByMission.Phase.RETALIATION and mission.can_escape()
	_escape_bar.value = mission.unseen_time / mission.escape_time * 100.0
	_debug_label.text = "Vipers left %d   Cars chasing %d   Kills %d\n%s\n[F1/F2] Crew size %d   [F3] Rival cars %s   [F4] Gunner %s   [F5] Restart   [F6/F7] Gunner skill" % [
		mission.living_crew().size(), mission.chasing_cars().size(), mission.kills, _gunner_text(),
		crew_size, "ON" if rivals_have_cars else "OFF", "ON" if passenger_gunner else "OFF"]


func _gunner_text() -> String:
	if gunner == null:
		return "No gunner"
	return "Gunner %s: shooting %d/%d   spread %.1f   reaction %.2fs   bursts %d-%d   range %.0fm   kills %d" % [
		gunner.crew.display_name, gunner.skill_level(), CrewMemberData.MAX_SKILL, gunner.extra_spread,
		gunner.reaction_time, gunner.burst_min, gunner.burst_max, gunner.gun_range, gunner.kills]


## Changes the gunner's shooting skill on the fly so the difference shows mid-run.
func set_gunner_skill(level: int) -> void:
	gunner_skill = clampi(level, 1, CrewMemberData.MAX_SKILL)
	if gunner != null:
		gunner.crew.skills[CrewGunner.SKILL_ID] = gunner_skill
		gunner.crew.xp.erase(CrewGunner.SKILL_ID)
		gunner.apply_skill()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_F1:
				_restart_with(func() -> void: crew_size = maxi(MIN_CREW, crew_size - 1))
			KEY_F2:
				_restart_with(func() -> void: crew_size = mini(MAX_CREW, crew_size + 1))
			KEY_F3:
				_restart_with(func() -> void: rivals_have_cars = not rivals_have_cars)
			KEY_F4:
				_restart_with(func() -> void: passenger_gunner = not passenger_gunner)
			KEY_F5:
				_restart_with(func() -> void: pass)
			KEY_F6:
				set_gunner_skill(gunner_skill - 1)
				get_viewport().set_input_as_handled()
			KEY_F7:
				set_gunner_skill(gunner_skill + 1)
				get_viewport().set_input_as_handled()


func _restart_with(change: Callable) -> void:
	change.call()
	get_viewport().set_input_as_handled()
	get_tree().reload_current_scene.call_deferred()


## Command-line overrides (after "--"): --crew=N, --cars / --no-cars, --gunner / --no-gunner,
## --gunner-skill=N.
static func _read_args() -> void:
	if _args_read:
		return
	_args_read = true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--crew="):
			crew_size = clampi(arg.trim_prefix("--crew=").to_int(), MIN_CREW, MAX_CREW)
		elif arg == "--no-cars":
			rivals_have_cars = false
		elif arg == "--cars":
			rivals_have_cars = true
		elif arg == "--no-gunner":
			passenger_gunner = false
		elif arg == "--gunner":
			passenger_gunner = true
		elif arg.begins_with("--gunner-skill="):
			gunner_skill = clampi(arg.trim_prefix("--gunner-skill=").to_int(), 1, CrewMemberData.MAX_SKILL)


func _spawn_player() -> void:
	player.global_position = PLAYER_START + Vector3(3.0, 0.5, 4.0)
	player.spawn_point = player.global_position
	var smg := player.weapons.add_weapon(GameState.weapon_data(&"smg"), 150)
	player.weapons.select(player.weapons.slots.find(smg))
	player_car = Vehicle.new()
	player_car.name = "PlayerCar"
	player_car.body_color = GameState.gang_color(GameState.PLAYER_GANG).darkened(0.4)
	player_car.position = PLAYER_START
	player_car.rotation.y = PI
	add_child(player_car)
	if passenger_gunner:
		gunner = CrewGunner.new()
		gunner.name = "Gunner"
		gunner.crew = CrewMemberData.create("Dre", {CrewGunner.SKILL_ID: gunner_skill})
		player_car.add_child(gunner)
	player_car.enter(player)


func _spawn_crew() -> void:
	for i in crew_size:
		var member := GangMember.new()
		member.name = "Viper%d" % i
		member.gang_id = &"vipers"
		member.wander_radius = 2.0
		member.position = CORNER_START + Vector3((i % 2) * 1.5, 0.0, i * 2.2)
		add_child(member)
		crew.append(member)


func _spawn_rival_cars() -> void:
	for i in PARKED_CARS.size():
		var car := ChaseCar.new()
		car.name = "ViperCar%d" % i
		car.gang_id = &"vipers"
		car.grid = grid
		car.position = PARKED_CARS[i]
		car.rotation.y = -PI / 2.0
		add_child(car)
		rival_cars.append(car)


func _show_result(text: String, color: Color) -> void:
	_result_label.text = text + "\n[F5] Run it again"
	_result_label.modulate = color
	_result_label.visible = true


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DriveByUI"
	layer.layer = 5
	add_child(layer)

	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.offset_top = 70.0
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	layer.add_child(top)
	_objective_label = _label(22)
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_objective_label)
	_escape_bar = ProgressBar.new()
	_escape_bar.custom_minimum_size = Vector2(320.0, 14.0)
	_escape_bar.show_percentage = false
	_escape_bar.modulate = Color(0.5, 1.0, 0.5)
	top.add_child(_escape_bar)

	_result_label = _label(42)
	_result_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_result_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_result_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.visible = false
	layer.add_child(_result_label)

	_debug_label = _label(15)
	_debug_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_debug_label.offset_left = 16.0
	_debug_label.offset_top = -170.0
	_debug_label.modulate = Color(0.85, 0.85, 0.85)
	layer.add_child(_debug_label)


func _label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	return label


func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.25, 0.32, 0.55)
	sky_material.sky_horizon_color = Color(0.85, 0.55, 0.4)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_density = 0.004
	environment.fog_light_color = Color(0.75, 0.6, 0.55)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, -40.0, 0.0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
	add_child(sun)
