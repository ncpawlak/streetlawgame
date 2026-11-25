extends Node3D
## Blood driver: a slab of concrete and a wall with passive targets to shoot, for checking the
## shared BloodFx (scripts/combat/blood_fx.gd): sprays from the impact along the shot, droplet
## splats on the ground and wall, wound marks that follow the body, and pools under the dead.
## Targets: a standing and a walking capsule, a standing civilian and cop model, a walking model and
## a passive rival gang member. Not part of the city.
##
## Debug keys: F5 respawn targets and clear blood, F6 clear blood, F7 slow motion, F8 kill all.
## Launch: godot --path . res://drivers/blood/blood_driver.tscn
## Screenshots: godot --path . res://drivers/blood/blood_driver.tscn -- --screenshots=<dir>

const PLAYER_START := Vector3(0.0, 1.0, 6.0)
const WALL_Z := -15.0
const ZOOM_FOV := 42.0
const HIP_FOV := 70.0
const CONCRETE := Color(0.62, 0.61, 0.58)
const POOL_SCREENSHOT_DELAY := 6.0

var targets: Array[Node3D] = []
var _gang_spawn := Vector3(6.5, 0.2, -6.0)
var _slow_motion := false
var _help: Label

@onready var _player: Player = $Player
@onready var _camera: Camera3D = $Player/CameraPivot/SpringArm/Camera


func _ready() -> void:
	_build_environment()
	_build_range()
	_spawn_targets()
	_build_help()
	_player.global_position = PLAYER_START
	_player.spawn_point = PLAYER_START
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	EventBus.notify.emit.call_deferred("Blood driver - shoot the targets. F5 reset, F6 clear blood, F7 slow-mo, F8 kill all")

	var shots := _screenshot_dir()
	if shots != "":
		_take_screenshots.call_deferred(shots)


func _process(delta: float) -> void:
	# RMB zooms over the shoulder; LMB alone fires from the hip.
	var zoomed := Input.is_action_pressed("aim") and _player.is_on_foot()
	_camera.fov = lerpf(_camera.fov, ZOOM_FOV if zoomed else HIP_FOV, clampf(delta * 12.0, 0.0, 1.0))
	var fx := BloodFx.of(self)
	_help.text = "Blood driver\nLMB fire (hip)  RMB zoom  1-9 / wheel weapon  R reload\nF5 reset targets + blood   F6 clear blood\nF7 slow motion%s   F8 kill all\n\nsplats %d/%d  pools %d/%d  wounds %d/%d  sprays %d/%d" % [
		" (on)" if _slow_motion else "", fx.splat_count(), BloodFx.MAX_SPLATS, fx.pool_count(), BloodFx.MAX_POOLS,
		fx.wound_count(), BloodFx.MAX_WOUNDS, fx.spray_count(), BloodFx.MAX_SPRAYS]


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_F5:
				reset()
				EventBus.notify.emit("Targets respawned, blood cleared")
			KEY_F6:
				BloodFx.of(self).clear()
				EventBus.notify.emit("Blood cleared")
			KEY_F7:
				set_slow_motion(not _slow_motion)
			KEY_F8:
				kill_all()
			_:
				return
		get_viewport().set_input_as_handled()


## Respawns every target at full health and clears all blood.
func reset() -> void:
	BloodFx.of(self).clear()
	for target in targets:
		if target is BloodTarget and is_instance_valid(target):
			(target as BloodTarget).respawn()
	_respawn_gang_member()
	_player.respawn()


func set_slow_motion(on: bool) -> void:
	_slow_motion = on
	Engine.time_scale = 0.25 if on else 1.0


## Shoots every target dead through the normal hit path (so they bleed and pool).
func kill_all() -> void:
	var pistol := GameState.weapon_data(&"pistol")
	for target in targets:
		if not is_instance_valid(target) or not target.call(&"is_alive"):
			continue
		var chest := target.global_position + Vector3(0.0, 1.2, 0.0)
		var muzzle := chest + (_player.global_position - chest).normalized() * 3.0
		for i in 20:
			if not target.call(&"is_alive"):
				break
			Hitscan.fire(_player, muzzle, chest - muzzle, pistol, [_player.get_rid()])


func _spawn_targets() -> void:
	_add_target(Vector3(-6.0, 0.0, -5.0), false)
	_add_target(Vector3(-9.0, 0.0, -10.0), false, &"", Vector3(6.0, 0.0, 0.0))
	_add_target(Vector3(-2.0, 0.0, -6.0), true, &"civilian", Vector3.ZERO, 0)
	_add_target(Vector3(2.0, 0.0, -5.0), true, &"cop", Vector3.ZERO, 0)
	_add_target(Vector3(2.0, 0.0, -11.0), true, &"civilian", Vector3(7.0, 0.0, 0.0), 3)
	_respawn_gang_member()


func _add_target(at: Vector3, animated: bool, archetype: StringName = &"", patrol := Vector3.ZERO, variant := 0) -> BloodTarget:
	var target := BloodTarget.new()
	target.name = "Target%d" % targets.size()
	target.animated = animated
	if archetype != &"":
		target.archetype = archetype
	target.variant = variant
	target.patrol_offset = patrol
	target.position = at
	target.rotation.y = PI
	add_child(target)
	targets.append(target)
	return target


## A real rival NPC that won't fight back: checks the GangMember / CharacterVisual hit path.
func _respawn_gang_member() -> void:
	for target in targets.duplicate():
		if target is GangMember:
			targets.erase(target)
			if is_instance_valid(target):
				target.queue_free()
	var member := GangMember.new()
	member.name = "RivalGangMember"
	member.gang_id = &"vipers"
	member.weapon_id = &"pistol"
	member.aggro_range = 0.0
	member.alerted_range = 0.0
	member.wander_radius = 0.0
	member.drop_chance = 0.0
	member.corpse_lifetime = 3600.0
	member.position = _gang_spawn
	member.rotation.y = PI
	add_child(member)
	targets.append(member)


# --- world ----------------------------------------------------------------------------------------

func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.32, 0.45, 0.7)
	sky_material.sky_horizon_color = Color(0.78, 0.7, 0.62)
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
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)


func _build_range() -> void:
	_box("Ground", Vector3(80.0, 1.0, 80.0), Vector3(0.0, -0.5, 0.0), CONCRETE)
	_box("Wall", Vector3(26.0, 5.0, 0.6), Vector3(0.0, 2.5, WALL_Z), CONCRETE.lightened(0.15))
	# Lane lines so the splat spread reads in screenshots.
	for x in [-12.0, -4.0, 4.0, 12.0]:
		_box("Line", Vector3(0.08, 0.01, 22.0), Vector3(x, 0.005, -4.0), Color(0.85, 0.8, 0.3), false)


func _box(node_name: String, box_size: Vector3, at: Vector3, color: Color, solid := true) -> Node3D:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	if not solid:
		visual.name = node_name
		visual.position = at
		add_child(visual)
		return visual
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 1
	body.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = box_size
	shape.shape = box
	body.add_child(shape)
	body.add_child(visual)
	add_child(body)
	return body


func _build_help() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	_help = Label.new()
	_help.position = Vector2(16.0, 160.0)
	_help.add_theme_font_size_override("font_size", 14)
	_help.add_theme_color_override("font_color", Color(1.0, 1.0, 0.8))
	_help.add_theme_color_override("font_outline_color", Color.BLACK)
	_help.add_theme_constant_override("outline_size", 5)
	layer.add_child(_help)


# --- screenshots ----------------------------------------------------------------------------------

func _screenshot_dir() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshots="):
			return arg.trim_prefix("--screenshots=")
	return ""


func _capture(dir: String, file: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(dir.path_join(file))
	print("screenshot: ", dir.path_join(file))


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _seconds(time: float) -> void:
	await get_tree().create_timer(time, true, false, true).timeout


## One shot from the player's muzzle at [param point] through the shared hit path.
func _shoot_at(point: Vector3, weapon_id: StringName = &"pistol") -> void:
	var muzzle := _player.global_position + Vector3(0.0, 1.4, 0.0)
	Hitscan.fire(_player, muzzle, point - muzzle, GameState.weapon_data(weapon_id), [_player.get_rid()])
	_player.visual.fire()


func _take_screenshots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await _wait(30)
	var civilian := targets[2] as BloodTarget
	var cop := targets[3] as BloodTarget
	var capsule := targets[0] as BloodTarget
	var view := Camera3D.new()
	view.fov = 50.0
	add_child(view)

	# 1. Spray: side-on view of a shot into the civilian's chest, slowed down to catch it mid-air.
	_player.global_position = Vector3(-1.0, 0.0, 2.0)
	var facing := civilian.global_position - _player.global_position
	_player.rotation.y = atan2(-facing.x, -facing.z)
	civilian.health = 10000.0
	view.look_at_from_position(Vector3(1.6, 1.4, -3.4), civilian.global_position + Vector3(0.0, 1.1, -0.6), Vector3.UP)
	view.make_current()
	await _wait(10)
	set_slow_motion(true)
	_shoot_at(civilian.global_position + Vector3(0.05, 1.3, 0.0))
	await _seconds(0.05)
	_shoot_at(civilian.global_position + Vector3(-0.12, 1.05, 0.0))
	await _seconds(0.04)
	await _capture(dir, "blood_spray.png")
	set_slow_motion(false)
	await _seconds(1.0)

	# 2. Wound marks: a few more hits on the cop, close-up from the front; they ride the bones.
	cop.health = 10000.0
	for offset in [Vector3(0.1, 1.45, 0.0), Vector3(-0.15, 1.2, 0.0), Vector3(0.08, 0.95, 0.0), Vector3(-0.1, 0.6, 0.0)]:
		_shoot_at(cop.global_position + offset)
		await _seconds(0.12)
	await _seconds(1.0)
	view.look_at_from_position(cop.global_position + Vector3(0.25, 1.25, 1.5), cop.global_position + Vector3(0.0, 1.05, 0.0), Vector3.UP)
	await _wait(5)
	await _capture(dir, "blood_wounds.png")
	cop.visual.hit()
	await _seconds(0.15)
	await _capture(dir, "blood_wounds_hit_reaction.png")

	# 3. Ground and wall splats: rifle and shotgun bursts at the capsules and the walker.
	capsule.health = 10000.0
	for i in 6:
		_shoot_at(capsule.global_position + Vector3(randf_range(-0.2, 0.2), randf_range(0.5, 1.6), 0.0), &"rifle")
		await _seconds(0.1)
	for target in [targets[1], targets[4]]:
		(target as BloodTarget).health = 10000.0
		for i in 3:
			_shoot_at(target.global_position + Vector3(0.0, 1.2, 0.0), &"shotgun")
			await _seconds(0.15)
	await _seconds(1.0)
	view.look_at_from_position(Vector3(-2.0, 7.5, 3.0), Vector3(-3.0, 0.0, -7.5), Vector3.UP)
	await _wait(5)
	await _capture(dir, "blood_ground_splats.png")

	# 4. Pools growing under the dead (undo the screenshot health boosts first).
	for target in targets:
		if target is BloodTarget:
			(target as BloodTarget).health = minf((target as BloodTarget).health, (target as BloodTarget).max_health)
	kill_all()
	await _seconds(POOL_SCREENSHOT_DELAY)
	view.look_at_from_position(Vector3(3.5, 4.5, -1.0), Vector3(1.0, 0.0, -7.0), Vector3.UP)
	await _wait(5)
	await _capture(dir, "blood_pools.png")

	# 5. The player's own over-the-shoulder view, zoomed.
	_player.global_position = Vector3(0.0, 0.0, 1.0)
	_player.rotation.y = 0.0
	var pivot: Node3D = _player.get_node("CameraPivot")
	pivot.rotation.y = 0.0
	_camera.make_current()
	Input.action_press(&"aim")
	await _wait(30)
	await _capture(dir, "blood_player_view.png")
	Input.action_release(&"aim")
	view.queue_free()
	get_tree().quit()

