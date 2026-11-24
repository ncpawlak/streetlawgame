extends Node3D
## Entry scene: lighting/environment, mouse capture, and placing the player in the generated city.

@onready var _city: CityGenerator = $City
@onready var _player: Player = $Player


func _ready() -> void:
	_build_environment()
	_player.global_position = _city.player_spawn
	_player.spawn_point = _city.player_spawn
	_spawn_starter_stash()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	EventBus.notify.emit.call_deferred("Welcome to The Bottoms. Take the city back, block by block.")
	EventBus.notify.emit.call_deferred("There's a weapon stash by your ride. Hold [Q] for the weapon wheel.")


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


## A few guns near spawn so the arsenal can be tried right away (until the gun store, #12).
func _spawn_starter_stash() -> void:
	var ground := _city.player_spawn - Vector3(0.0, 1.0, 0.0)
	var stash := {&"smg": Vector3(-4.0, 0.0, -3.0), &"shotgun": Vector3(-4.0, 0.0, 0.0), &"rifle": Vector3(-4.0, 0.0, 3.0)}
	for id: StringName in stash:
		var weapon := GameState.weapon_data(id)
		add_child(WeaponPickup.create(weapon, weapon.magazine_size * 3, ground + stash[id]))


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
	environment.fog_density = 0.003
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
