extends RefCounted
## Player movement, combat feel and car entry / exit, on a MovementGround built above the city.

const ORIGIN := Vector3(0.0, 400.0, 0.0)

var _runner: Node
var _ground: MovementGround


func _init(runner: Node) -> void:
	_runner = runner


func run(main: Node, player: Player) -> void:
	player.respawn()
	_ground = MovementGround.new()
	_ground.position = ORIGIN
	main.add_child(_ground)
	await _frames(90)
	_test_crouch(player)
	await _test_stamina(player)
	await _test_aim_camera(player)
	await _test_strafe_hipfire(player)
	await _test_jump_pose(player)
	await _test_holster_and_reload(player)
	await _test_climbing(player)
	await _test_melee(player)
	await _test_headshot_and_hits(main, player)
	await _test_enter_each_door(player)
	await _test_exit_wrecks(player)
	_release_all()
	player.respawn()
	_ground.queue_free()
	await _frames(5)


func _test_crouch(player: Player) -> void:
	_place(player, Vector3(-20.0, 0.0, 20.0))
	var capsule := player.get_node("Collision").shape as CapsuleShape3D
	_check(player.set_crouching(true) and is_equal_approx(capsule.height, Player.CROUCH_HEIGHT), "crouching shrinks the capsule to %.1f m" % Player.CROUCH_HEIGHT)
	_check(is_equal_approx(Player.detection_scale(player), Player.CROUCH_DETECTION), "crouching shrinks enemy detection range")
	_place(player, MovementGround.OVERHANG)
	_check(not player.set_crouching(false) and player.is_crouching(), "can't stand up under a low overhang")
	_place(player, Vector3(-20.0, 0.0, 20.0))
	_check(player.set_crouching(false) and is_equal_approx(capsule.height, Player.STAND_HEIGHT), "standing up in the open restores the capsule")
	_check(is_equal_approx(Player.detection_scale(player), 1.0), "standing restores detection range")


func _test_stamina(player: Player) -> void:
	_place(player, Vector3(-20.0, 0.0, 25.0))
	player.health = 50.0
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _frames(60)
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	_check(player.is_sprinting() and speed > player.walk_speed + 1.0, "shift sprints (%.1f m/s)" % speed)
	_check(player.stamina < player.max_stamina - 10.0, "sprinting drains stamina (%.0f)" % player.stamina)
	player.stamina = 3.0
	await _frames(30)
	speed = Vector2(player.velocity.x, player.velocity.z).length()
	_check(not player.is_sprinting() and speed < player.walk_speed + 0.5, "running out of stamina drops you to a jog (%.1f m/s)" % speed)
	_release_all()
	var low := player.stamina
	await _frames(130)
	_check(player.stamina > low + 10.0, "stamina recovers after a rest (%.0f -> %.0f)" % [low, player.stamina])
	_check(is_equal_approx(player.health, 50.0), "health does not regenerate")
	player.health = player.max_health


func _test_aim_camera(player: Player) -> void:
	_place(player, Vector3(-20.0, 0.0, 20.0))
	_equip(player, &"pistol")
	var camera := player.get_node("CameraPivot/SpringArm/Camera") as Camera3D
	var arm := player.get_node("CameraPivot/SpringArm") as SpringArm3D
	_check(is_equal_approx(arm.spring_length, player.camera_distance) and player.camera_distance <= 3.0, "on-foot camera sits close (%.1f m)" % arm.spring_length)
	Input.action_press(&"aim")
	await _frames(40)
	_check(absf(camera.fov - player.aim_fov) < 1.0 and arm.spring_length < player.camera_distance - 1.0, "aiming zooms over the shoulder (fov %.0f, %.1f m)" % [camera.fov, arm.spring_length])
	_check(arm.position.x > 0.3, "camera starts over the right shoulder")
	_send_action(&"swap_shoulder")
	await _frames(30)
	_check(player.shoulder < 0.0 and arm.position.x < -0.3, "Z swaps the camera to the left shoulder (%.2f)" % arm.position.x)
	_send_action(&"swap_shoulder")
	Input.action_release(&"aim")
	await _frames(40)
	_check(arm.position.x > 0.3 and absf(camera.fov - player.camera_fov) < 1.0, "releasing aim returns the camera")
	var pitch := arm.rotation.x
	player.shoot()
	await _frames(1)
	_check(arm.rotation.x > pitch, "firing kicks the camera up")
	player.add_shake(0.5)
	await _frames(2)
	_check(camera.h_offset != 0.0 or camera.v_offset != 0.0, "camera shake offsets the view")
	arm.rotation.x = pitch


func _test_strafe_hipfire(player: Player) -> void:
	_place(player, Vector3(-20.0, 0.0, 20.0))
	_equip(player, &"pistol")
	await _frames(int(Player.RAISED_LINGER * 60.0) + 10)
	var camera := player.get_node("CameraPivot/SpringArm/Camera") as Camera3D
	var slot := player.weapons.current()
	var before := slot.magazine
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Input.action_press(&"shoot")
	Input.action_press(&"move_right")
	await _frames(40)
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		player.shoot()  # Headless can't capture the mouse, which firing from input needs.
	_check(slot.magazine < before, "LMB fires without aiming")
	_check(not player.is_aiming() and absf(camera.fov - player.camera_fov) < 1.0, "hip-fire doesn't zoom (fov %.0f)" % camera.fov)
	var flat := Vector3(player.velocity.x, 0.0, player.velocity.z)
	_check(player.is_weapon_raised() and absf(angle_difference(player.rotation.y, 0.0)) < 0.05 and flat.dot(Vector3.RIGHT) > 2.0,
		"moving right while firing keeps the body facing the crosshair (yaw %.2f, %.1f m/s right)" % [player.rotation.y, flat.dot(Vector3.RIGHT)])
	_check(player.visual.is_aiming(), "the upper body points the gun forward while strafing")
	_release_all()
	await _frames(30)
	var hip := player.weapons.extra_spread
	Input.action_press(&"aim")
	await _frames(30)
	_check(player.weapons.extra_spread < hip - 1.0 and absf(camera.fov - player.aim_fov) < 1.0, "RMB zooms and tightens spread (%.1f -> %.1f)" % [hip, player.weapons.extra_spread])
	_release_all()
	await _frames(int(Player.RAISED_LINGER * 60.0) + 10)
	_check(not player.is_weapon_raised(), "the gun lowers a moment after the last shot")
	Input.action_press(&"move_right")
	await _frames(45)
	_check(absf(angle_difference(player.rotation.y, -PI * 0.5)) < 0.2, "with the gun lowered the body turns to face where it runs")
	_release_all()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _frames(10)


func _test_jump_pose(player: Player) -> void:
	_place(player, Vector3(-20.0, 0.0, 25.0))
	await _frames(20)
	var visual := player.visual
	_check(not player.is_airborne() and is_zero_approx(visual.air_amount()), "standing on the ground isn't airborne")
	Input.action_press(&"move_forward")
	await _frames(20)
	Input.action_press(&"jump")
	await _frames(2)
	Input.action_release(&"jump")
	await _frames(12)
	var pose: Object = visual.get(&"_pose")
	var stride: float = visual.animation_tree.get(&"parameters/free/blend_position")
	_check(player.is_airborne() and visual.air_amount() > 0.8, "jumping switches to the airborne pose (%.2f)" % visual.air_amount())
	_check(stride < 0.5 and (pose.get(&"foot_weights") as Dictionary)[&"L"] > 0.8, "no stride in the air; the legs tuck (stride %.2f)" % stride)
	var landed := false
	for i in 90:
		await _frames(1)
		if player.is_on_floor():
			landed = true
			break
	await _frames(1)
	_check(landed and not visual.is_airborne() and visual.landing_amount() > 0.1, "touching down plays a landing dip (%.2f)" % visual.landing_amount())
	_release_all()
	await _frames(40)
	_check(visual.air_amount() < 0.01, "the airborne pose blends out after landing")


func _test_holster_and_reload(player: Player) -> void:
	_place(player, Vector3(-20.0, 0.0, 20.0))
	player.weapons.add_weapon(GameState.weapon_data(&"rifle"), 30)
	_equip(player, &"pistol")
	await _frames(ceili(Player.HOLSTER_DELAY * 60.0) + 40)
	var visual := player.visual
	_check(visual.is_holstered(), "the gun is holstered after a while out of combat")
	var hip := visual.get_node("HipHolster") as Node3D
	var back := visual.get_node("BackSling") as Node3D
	_check(hip.visible and back.visible, "holstered pistol shows on the hip and the rifle on the back")
	_check(hip.global_position.y < back.global_position.y, "hip holster sits below the back sling")
	var slot := player.weapons.current()
	slot.magazine = 1
	slot.reserve = 30
	_check(player.weapons.reload() and player.weapons.is_reloading, "R starts a reload")
	await _frames(5)
	_check(not visual.is_holstered() and visual.get(&"_reload_style") == WeaponData.ReloadStyle.PISTOL, "reloading draws the gun and plays the pistol reload")
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _frames(10)
	_check(not player.weapons.is_reloading and slot.magazine == 1, "sprinting cancels a reload")
	_release_all()
	await _frames(10)


func _test_climbing(player: Player) -> void:
	var cases := [
		[&"vault", MovementGround.VAULT_WALL + Vector3(0.0, 0.0, 0.85), 0.0],
		[&"step", MovementGround.STEP_BOX + Vector3(0.0, 0.0, 1.8), MovementGround.STEP_HEIGHT],
		[&"ledge", MovementGround.LEDGE_LOW + Vector3(0.0, 0.0, 2.3), MovementGround.LEDGE_LOW_HEIGHT],
		[&"ledge", MovementGround.LEDGE_HIGH + Vector3(0.0, 0.0, 2.3), MovementGround.LEDGE_HIGH_HEIGHT],
	]
	for case in cases:
		var start: Vector3 = case[1]
		_place(player, start)
		await _frames(3)
		var climb := player.find_climb()
		_check(climb.get("kind") == case[0], "Space finds a %s %.1f m up (got %s)" % [case[0], case[2] if case[2] > 0.0 else MovementGround.VAULT_HEIGHT, climb.get("kind")])
		Input.action_press(&"jump")
		await _frames(1)
		Input.action_release(&"jump")
		await _frames(2)
		_check(player.is_busy(), "the %s plays as a scripted climb" % case[0])
		for _i in 120:
			if not player.is_busy():
				break
			await _frames(1)
		await _frames(10)
		var local := player.global_position - ORIGIN
		var ok := not player.is_busy() and absf(local.y - float(case[2])) < 0.2 and local.z < start.z - 1.0
		_check(ok, "the %s ends up on / over it (at %s)" % [case[0], local])


func _test_melee(player: Player) -> void:
	var sleeper: GangMember = _ground.dummies[0]
	var awake: GangMember = _ground.dummies[1]
	for dummy in [sleeper, awake]:
		dummy.rotation = Vector3.ZERO
	_place(player, sleeper.global_position - ORIGIN + Vector3(0.0, 0.0, 0.9))
	await _frames(2)
	_check(player.melee(), "V swings a melee attack")
	await _frames(30)
	_check(not sleeper.is_alive(), "hitting an unaware gang member from behind is a silent takedown")
	await _frames(30)
	_check(sleeper.visual.ragdoll != null, "killed gang members fall as a ragdoll")
	awake.max_health = 1000.0
	awake.health = 1000.0
	_place(player, awake.global_position - ORIGIN + Vector3(0.0, 0.0, -0.9), PI)
	await _frames(2)
	player.melee()
	await _frames(30)
	_check(awake.is_alive() and awake.health < 1000.0, "a melee hit from the front only hurts (%.0f)" % awake.health)


func _test_headshot_and_hits(main: Node, player: Player) -> void:
	var dummy: GangMember = _ground.dummies[2]
	dummy.max_health = 1000.0
	dummy.health = 1000.0
	var head := dummy.visual.head_position()
	_check(Hitscan.is_headshot(dummy, head), "a hit on the head bone counts as a headshot")
	_check(not Hitscan.is_headshot(dummy, dummy.global_position + Vector3.UP * 1.0), "a body hit is not a headshot")
	var gun: WeaponData = GameState.weapon_data(&"pistol").duplicate()
	gun.spread_degrees = 0.0
	gun.show_tracer = false
	var muzzle := head + Vector3(0.0, 0.0, 4.0)
	var exclude: Array[RID] = [player.get_rid()]
	Hitscan.fire(player, muzzle, head - muzzle, gun, exclude)
	var lost := 1000.0 - dummy.health
	_check(is_equal_approx(lost, gun.damage * Hitscan.HEADSHOT_MULTIPLIER), "headshots multiply damage (%.0f of %.0f)" % [lost, gun.damage])
	var reticle: CombatReticle = main.get_node("HUD").get("reticle")
	_place(player, Vector3(-20.0, 0.0, 20.0))
	var origins := []
	var record := func(origin: Vector3) -> void: origins.append(origin)
	player.damaged_from.connect(record)
	var shooter := player.global_position + Vector3(5.0, 1.0, 0.0)
	player.register_hit(shooter, Vector3(-30.0, 0.0, 0.0))
	player.take_damage(10.0)
	player.damaged_from.disconnect(record)
	_check(origins.size() == 1 and origins[0] == shooter, "taking damage reports where it came from")
	_check(reticle != null and reticle.has_damage_arcs(), "the HUD shows a damage direction arc")
	player.health = player.max_health


func _test_enter_each_door(player: Player) -> void:
	var car: Vehicle = _ground.cars[0]
	var names := ["driver", "passenger", "rear driver-side", "rear passenger-side"]
	for door in Vehicle.DOORS.size():
		var outside := car.global_transform * Vector3(Vehicle.DOORS[door][0] * 2.4, 0.0, Vehicle.DOORS[door][1])
		_place(player, Vector3(outside.x, 0.0, outside.z) - Vector3(ORIGIN.x, 0.0, ORIGIN.z))
		await _frames(3)
		_check(car.nearest_door(player.global_position) == door, "standing by the %s door picks it" % names[door])
		_check(car.begin_enter(player), "E starts getting in at the %s door" % names[door])
		var opened := false
		for _i in 400:
			opened = opened or car.is_door_open(door)
			if player.current_vehicle == car:
				break
			await _frames(1)
		await _frames(30)
		var seat := car.global_transform * Vehicle.DRIVER_SEAT
		_check(opened and player.current_vehicle == car and car.driver == player, "getting in through the %s door opens it and ends up driving" % names[door])
		_check(player.global_position.distance_to(seat) < 0.15 and not car.is_door_open(door), "slides across to the driver's seat and shuts the %s door" % names[door])
		if door == 0:
			car.begin_exit()
			await _wait_idle(player)
			var local := car.global_transform.affine_inverse() * player.global_position
			_check(player.is_on_foot() and car.driver == null and local.x > 1.0, "E gets out of the driver's door (%s)" % local)
			_check(not (player.get_node("Collision") as CollisionShape3D).disabled, "collision comes back after getting out")
			_check(car.can_enter(), "the car can be taken again")
		else:
			car.exit()
			await _frames(5)


func _test_exit_wrecks(player: Player) -> void:
	for index in [1, 2]:
		var car: Vehicle = _ground.cars[index]
		var label := "on its side" if index == 1 else "on its roof"
		_check(not car.can_enter(), "a car %s can't be entered" % label)
		car.enter(player)
		await _frames(5)
		_check(car.begin_exit(), "E starts climbing out of a car %s" % label)
		await _wait_idle(player)
		var local := player.global_position - ORIGIN
		var flat := Vector2(player.global_position.x - car.global_position.x, player.global_position.z - car.global_position.z).length()
		_check(player.is_on_foot() and absf(local.y) < 0.35 and flat > 1.3, "climbs out of a car %s and lands beside it (%.1f m away, y %.2f)" % [label, flat, local.y])
		_check(car.driver == null and not player.is_busy(), "nobody is left in the car %s" % label)


func _wait_idle(player: Player) -> void:
	for _i in 600:
		if not player.is_busy():
			break
		await _frames(1)
	await _frames(10)


func _equip(player: Player, id: StringName) -> void:
	var slot := player.weapons.find(id)
	if slot == null:
		slot = player.weapons.add_weapon(GameState.weapon_data(id), 60)
	player.weapons.select(player.weapons.slots.find(slot))
	slot.magazine = slot.data.magazine_size


func _place(player: Player, local: Vector3, yaw := 0.0) -> void:
	player.cancel_moves()
	player.global_position = ORIGIN + local + Vector3.UP * 0.02
	player.rotation = Vector3(0.0, yaw, 0.0)
	(player.get_node("CameraPivot") as Node3D).rotation.y = yaw
	player.velocity = Vector3.ZERO


func _send_action(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)


func _release_all() -> void:
	for action in [&"move_forward", &"move_back", &"move_left", &"move_right", &"sprint", &"aim", &"jump", &"shoot"]:
		Input.action_release(action)


func _frames(count: int) -> void:
	for i in count:
		await _runner.get_tree().physics_frame


func _check(condition: bool, description: String) -> void:
	_runner.call(&"_check", condition, description)
