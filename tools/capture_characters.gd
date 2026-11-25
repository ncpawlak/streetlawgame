extends Node
## Renders reference screenshots of CharacterVisual poses and scale next to a car and a door.
## Usage: godot --path . res://tools/capture_characters.tscn -- <output_dir>

var _out := "user://"
var _poses: Array[CharacterVisual] = []
var _velocities: Array[Vector3] = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	_go.call_deferred()


func _go() -> void:
	get_window().size = Vector2i(1280, 720)
	var stage := Node3D.new()
	add_child(stage)
	_build_environment(stage)
	var cam := Camera3D.new()
	cam.fov = 50.0
	stage.add_child(cam)

	var labels := [&"idle", &"run", &"aim", &"shoot"]
	for i in labels.size():
		var v := CharacterVisual.create(&"player", 0)
		v.position = Vector3(i * 1.6 - 2.4, 0.0, 0.0)
		stage.add_child(v)
		v.set_weapon(_pistol())
		_poses.append(v)
		_velocities.append(Vector3(0, 0, -5.0) if labels[i] == &"run" else Vector3.ZERO)
	_poses[2].set_aiming(true)
	_poses[3].set_aiming(true)
	get_tree().process_frame.connect(_drive)

	cam.look_at_from_position(Vector3(-1.0, 1.6, -6.0), Vector3(0, 1.0, 0))
	await get_tree().create_timer(1.2).timeout
	_poses[3].fire()
	await get_tree().create_timer(0.12).timeout
	await _shot("player_poses.png")
	cam.look_at_from_position(Vector3(-3.0, 1.5, -2.5), Vector3(-1.0, 1.1, 0))
	await get_tree().create_timer(0.3).timeout
	await _shot("player_poses_side.png")
	for v in _poses:
		v.queue_free()
	_poses.clear()

	var car := Vehicle.new()
	car.position = Vector3(0, 0.5, 0)
	stage.add_child(car)
	var door := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.6, 2.6, 0.25)
	door.mesh = box
	door.position = Vector3(5.5, 1.3, -1.0)
	stage.add_child(door)
	var wall := MeshInstance3D.new()
	var wall_box := BoxMesh.new()
	wall_box.size = Vector3(8.0, 3.2, 0.2)
	wall.mesh = wall_box
	wall.position = Vector3(5.5, 1.6, -1.25)
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.55, 0.5, 0.45)
	wall.material_override = wall_mat
	stage.add_child(wall)
	var door_mat := StandardMaterial3D.new()
	door_mat.albedo_color = Color(0.35, 0.2, 0.1)
	door.material_override = door_mat

	var npcs := [
		[&"gang", Color(0.6, 0.1, 0.6), Vector3(2.2, 0, 0.6)],
		[&"cop", null, Vector3(-2.2, 0, 0.8)],
		[&"civilian", null, Vector3(5.5, 0, -0.5)],
		[&"crew", Color(0.1, 0.6, 0.2), Vector3(4.2, 0, -0.4)],
		[&"gang", Color(0.8, 0.1, 0.1), Vector3(7.0, 0, -0.4)],
		[&"player", null, Vector3(0.2, 0, 2.2)],
	]
	for i in npcs.size():
		var entry: Array = npcs[i]
		var v := CharacterVisual.create(entry[0], i * 7 + 3)
		v.position = entry[2]
		stage.add_child(v)
		if entry[1] != null:
			v.set_tint((entry[1] as Color).darkened(0.3))
			v.set_bandana(entry[1])
		if entry[0] != &"civilian":
			v.set_weapon(_pistol())
	cam.look_at_from_position(Vector3(2.5, 2.4, 9.5), Vector3(2.5, 1.0, 0))
	await get_tree().create_timer(1.0).timeout
	await _shot("npc_scale_car_door.png")
	get_tree().quit()


func _pistol() -> WeaponData:
	return GameState.weapon_data(&"pistol")


func _drive() -> void:
	for i in _poses.size():
		if is_instance_valid(_poses[i]):
			_poses[i].update_motion(_velocities[i], 1.0 / 60.0)


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _out.path_join(file)
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


func _build_environment(stage: Node3D) -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.3, 0.32)
	ground.material_override = mat
	stage.add_child(ground)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(floor_shape)
	stage.add_child(floor_body)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	stage.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.7, 0.85)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	stage.add_child(env)
