class_name Vehicle
extends VehicleBody3D
## Drivable vehicle. Supports entering/exiting, a chase camera, drive-by shooting, running over NPCs,
## and damage: it smokes when hurt, catches fire when critical and then explodes.
## Built in code by default (a generic car in [member body_color]). Authored scenes from the vehicle kit
## (scenes/vehicles/, see tools/vehicles/) bring their own "Body", wheels, collision, "Seats" and
## "Exit"/"EngineSmoke" markers; their physics values are set on the root and listed in
## data/vehicles/vehicles.json ([VehicleCatalog]).
## Getting in and out is animated ([method begin_enter], [method begin_exit]): the driver walks to the
## "DoorStand" marker, opens "Doors/Driver" by its "Handle", sits on "Seats/Driver" with feet on
## "Ride/Pedals" and hands on "Ride/Steer" (bikes are straddled, the bus is boarded up its "Ride/Step").
## [method enter] and [method exit] stay instant for scripts, bail-outs and explosions.

signal health_changed(current: float, maximum: float)
signal exploded

enum DamageState { OK, SMOKING, BURNING, WRECKED }

## Door swing (radians) when getting in or out.
const DOOR_OPEN_ANGLE := 1.1
## Faster than this (m/s) the driver bails out instantly instead of climbing out.
const CLIMB_OUT_MAX_SPEED := 3.0
## Walking pace (m/s) of the scripted walk to the door.
const BOARD_WALK_SPEED := 2.6

const WHEEL_LAYOUT := [
	# [position, is_front]
	[Vector3(0.9, 0.6, 1.4), true],
	[Vector3(-0.9, 0.6, 1.4), true],
	[Vector3(0.9, 0.6, -1.4), false],
	[Vector3(-0.9, 0.6, -1.4), false],
]

@export var body_color := Color(0.2, 0.2, 0.25)
@export var max_engine_force := 3000.0
@export var max_brake_force := 60.0
@export var max_steer := 0.55
@export var steer_speed := 2.5
@export var run_over_speed := 6.0
@export var mouse_sensitivity := 0.003
## Registry id (data/vehicles/vehicles.json); empty for code-built cars.
@export var model_id: StringName
## Seed for the registry paint variation; -1 keeps the authored colours.
@export var paint_seed := -1
## Forward speed cap in m/s (0 = none). Reverse is capped at a third of it.
@export var max_speed := 0.0
## Steering lock shrinks with speed: max_steer / (1 + steer_falloff * speed). 0 = constant lock.
@export var steer_falloff := 0.0
## Arcade anti-roll: torque (per kg) that rights the body around its forward axis, so tall trucks
## and the two-wheel bikes don't topple in hard turns. 0 = off. Pitch is left alone for ramps.
@export var upright_assist := 0.0
@export var camera_distance := 7.0
@export var camera_height := 1.8
@export_group("Damage")
@export var max_health := 300.0
## Fraction of health where the engine starts smoking.
@export var smoke_threshold := 0.5
## Fraction of health where it catches fire and burns down to an explosion.
@export var fire_threshold := 0.25
@export var burn_damage_per_second := 10.0
## Sudden speed changes above this (m/s) count as a crash.
@export var crash_speed_threshold := 7.0
@export var crash_damage_per_speed := 4.0
@export var explosion_radius := 8.0
@export var explosion_damage := 120.0
@export var explosion_impulse := 8000.0
## Seconds a wreck stays in the world.
@export var wreck_lifetime := 60.0

var driver: Player
var health := 0.0
var damage_state := DamageState.OK

var _camera_pivot: Node3D
var _spring_arm: SpringArm3D
var _camera: Camera3D
var _look_yaw := 0.0
var _last_velocity := Vector3.ZERO
var _last_attacker: Node
var _body_materials: Array[StandardMaterial3D] = []
var _smoke: CPUParticles3D
var _flames: CPUParticles3D
## Player mid get-in / get-out (the vehicle can't be taken meanwhile).
var _boarder: Player


func _ready() -> void:
	add_to_group("vehicles")
	var authored := has_node("Body")
	if not authored:
		mass = 1000.0
		center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		center_of_mass = Vector3(0.0, 0.3, 0.0)
	collision_layer = 8
	collision_mask = 15
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	health = max_health
	if authored:
		_adopt_body_materials()
		if paint_seed >= 0:
			apply_paint(paint_seed)
	else:
		_build_body()
		_build_wheels()
	_build_camera()
	_build_damage_effects()
	_build_interactable()


## Entering is an ordinary interaction, so it shares the E prompt with everything else.
func _build_interactable() -> void:
	var interactable := Interactable.new()
	interactable.name = "Interactable"
	var entry := VehicleCatalog.find(model_id) if model_id != &"" else {}
	interactable.prompt_name = entry.get("name", "Vehicle")
	interactable.radius = maxf(3.5, _half_length() + 1.0)
	var enter_condition := MethodCondition.create(&"can_enter")
	enter_condition.hide_when_unmet = true
	var enter_effect := MethodEffect.create(&"begin_enter")
	enter_effect.pass_actor = true
	var conditions: Array[Condition] = [enter_condition]
	var effects: Array[Effect] = [enter_effect]
	interactable.add_action(InteractionAction.create(&"enter_vehicle", "Steal vehicle", effects, conditions))
	add_child(interactable)

## Seats including the driver (from the "Seats" markers; 4 for code-built cars).
func seat_count() -> int:
	var seats := get_node_or_null("Seats")
	return seats.get_child_count() if seats != null else 4


## Recolours the "paint" metadata meshes from the registry palette. Same seed, same colours.
func apply_paint(seed_value: int) -> void:
	paint_seed = seed_value
	var colors := VehicleCatalog.paint_colors(model_id, seed_value)
	if colors.is_empty():
		return
	for instance: MeshInstance3D in _painted_meshes():
		var material := instance.material_override as StandardMaterial3D
		if material != null:
			material.albedo_color = colors[0] if instance.get_meta("paint") == "primary" else colors[1]


func paint_color() -> Color:
	for instance: MeshInstance3D in _painted_meshes():
		if instance.get_meta("paint") == "primary" and instance.material_override is StandardMaterial3D:
			return (instance.material_override as StandardMaterial3D).albedo_color
	return body_color


func can_enter() -> bool:
	return driver == null and not is_wrecked() and not _is_boarding()


func _is_boarding() -> bool:
	return _boarder != null and is_instance_valid(_boarder) and _boarder.is_busy()


## The registry's seating data ([code]pose[/code], [code]entry[/code], [code]lean[/code], ...).
func ride_info() -> Dictionary:
	var entry := VehicleCatalog.find(model_id) if model_id != &"" else {}
	return entry.get("ride", {})


## Seated pose in this vehicle's space for [method CharacterVisual.set_ride]: hips on the driver seat,
## feet on the pedals / pegs, hands on the wheel / bars. The character faces +Z, so its left is +X.
func ride_pose() -> Dictionary:
	var info := ride_info()
	var seat := get_node_or_null("Seats/Driver") as Node3D
	var pedals := get_node_or_null("Ride/Pedals") as Node3D
	var steer := get_node_or_null("Ride/Steer") as Node3D
	var hips := seat.position if seat != null else Vector3(0.45, 1.3, -0.3)
	var feet_at := pedals.position if pedals != null else hips + Vector3(0.0, -0.45, 0.55)
	var hands_at := steer.position if steer != null else hips + Vector3(0.0, 0.4, 0.45)
	var feet := Vector3(float(info.get("feet", 0.12)), 0.0, 0.0)
	var grip := Vector3(float(info.get("grip", 0.2)), 0.0, 0.0)
	var ankle := Vector3(0.0, 0.08, 0.0)
	return {&"hips": hips, &"foot_l": feet_at + feet + ankle, &"foot_r": feet_at - feet + ankle,
		&"hand_l": hands_at + grip, &"hand_r": hands_at - grip, &"lean": float(info.get("lean", 0.0))}


## Where the driver's body (feet origin) sits, in this vehicle's space, facing forward (+Z).
func seat_transform() -> Transform3D:
	var pose := ride_pose()
	var hips: Vector3 = pose[&"hips"]
	var pedals := get_node_or_null("Ride/Pedals") as Node3D
	var floor_y := pedals.position.y if pedals != null else hips.y - 0.45
	return Transform3D(Basis(Vector3.UP, PI), Vector3(hips.x, floor_y, hips.z))


## Animated get-in: walk to the door, open it, sit down, shut it, then [method enter].
## Vehicles without seating markers are entered instantly.
func begin_enter(player: Player) -> void:
	if not can_enter():
		return
	var stand := get_node_or_null("DoorStand") as Node3D
	if stand == null or not has_node("Ride/Pedals") or player.is_busy():
		enter(player)
		return
	_boarder = player
	var seat := seat_transform()
	var steps := _walk_to(player, stand.position, seat.origin)
	var stand_xf := steps[-1]["to"] as Transform3D
	var hop := 0.12 if seat.origin.y > 0.3 else 0.04
	match String(ride_info().get("entry", "door")):
		"straddle":
			steps.append(_step(seat, 0.65, {"arc": 0.35, "seated": 1.0}))
		"bus":
			var step_at := (get_node("Ride/Step") as Node3D).position
			var forward := Basis(Vector3.UP, PI)
			steps.append(_step(Transform3D(forward, step_at), 0.5, {"arc": 0.15, "walk": true}))
			steps.append(_step(Transform3D(forward, Vector3(0.1, seat.origin.y, seat.origin.z - 0.6)), 0.7, {"walk": true}))
			steps.append(_step(seat, 0.6, {"seated": 1.0}))
		_:
			var door := get_node_or_null("Doors/Driver") as Node3D
			var handle := get_node_or_null("Doors/Driver/Handle") as Node3D
			if door != null and handle != null:
				var side := _hand_for(stand_xf, handle.position)
				var behind := Transform3D(stand_xf.basis, stand_xf.origin + Vector3(0.0, 0.0, -0.25))
				steps.append(_step(stand_xf, 0.3, {"reach": [side, handle, 1.0]}))
				steps.append(_step(behind, 0.45, {"reach": [side, handle, 1.0], "call": _swing_door.bind(door, true)}))
				steps.append(_step(seat, 0.75, {"arc": hop, "seated": 1.0, "reach": [side, handle, 0.0]}))
				steps.append(_step(seat, 0.35, {"call": _swing_door.bind(door, false)}))
			else:
				steps.append(_step(seat, 0.7, {"arc": hop, "seated": 1.0}))
	player.play_moves(steps, _finish_enter.bind(player))


## Animated get-out (the reverse of [method begin_enter]); instant when moving fast.
func begin_exit() -> void:
	var player := driver
	var stand := get_node_or_null("DoorStand") as Node3D
	if player == null:
		return
	if stand == null or not has_node("Ride/Pedals") or linear_velocity.length() > CLIMB_OUT_MAX_SPEED:
		exit()
		return
	driver = null
	_boarder = player
	var seat := seat_transform()
	var away := Basis(Vector3.UP, atan2(-stand.position.x, 0.0)) if absf(stand.position.x) > 0.01 else Basis.IDENTITY
	var out := Transform3D(away, stand.position)
	var steps: Array[Dictionary] = [_step(seat, 0.05, {})]
	var hop := 0.12 if seat.origin.y > 0.3 else 0.04
	match String(ride_info().get("entry", "door")):
		"straddle":
			steps.append(_step(out, 0.65, {"arc": 0.35, "seated": 0.0}))
		"bus":
			var step_at := (get_node("Ride/Step") as Node3D).position
			var back := Basis.IDENTITY
			steps.append(_step(Transform3D(back, Vector3(0.1, seat.origin.y, seat.origin.z - 0.6)), 0.6, {"seated": 0.0}))
			steps.append(_step(Transform3D(back, step_at), 0.7, {"walk": true}))
			steps.append(_step(out, 0.5, {"arc": 0.15, "walk": true}))
		_:
			var door := get_node_or_null("Doors/Driver") as Node3D
			if door != null:
				steps.append(_step(seat, 0.3, {"call": _swing_door.bind(door, true)}))
			steps.append(_step(out, 0.75, {"arc": hop, "seated": 0.0}))
			var clear := Transform3D(away, stand.position + away * Vector3(0.0, 0.0, -0.6))
			steps.append(_step(clear, 0.45, {"walk": true, "call": _swing_door.bind(door, false) if door != null else Callable()}))
	player.play_moves(steps, _finish_exit.bind(player))


func _finish_enter(player: Player) -> void:
	_boarder = null
	if driver == null and not is_wrecked() and is_instance_valid(player) and player.current_vehicle == null:
		enter(player)
	else:
		player.set_on_foot(true)


func _finish_exit(player: Player) -> void:
	_boarder = null
	if is_instance_valid(player) and player.current_vehicle == self:
		player.set_on_foot(true)


## Scripted move in this vehicle's space (see [method Player.play_moves]).
func _step(to: Transform3D, time: float, extra: Dictionary) -> Dictionary:
	var step := {"to": to, "time": time, "frame": self}
	step.merge(extra)
	if step.get("call") is Callable and not (step["call"] as Callable).is_valid():
		step.erase("call")
	return step


## Walk steps from the player to [param stand] (vehicle space), around the nose or tail if they're on
## the far side, ending turned toward [param look_at].
func _walk_to(player: Player, stand: Vector3, look_at: Vector3) -> Array[Dictionary]:
	var start := global_transform.affine_inverse() * player.global_position
	start.y = 0.0
	var points: Array[Vector3] = []
	var half := _half_length()
	if absf(stand.x) > 0.01 and signf(start.x) != signf(stand.x) and absf(start.z) < half + 0.3:
		var end_z := (half + 0.8) * (1.0 if start.z >= 0.0 else -1.0)
		points.append(Vector3(start.x, 0.0, end_z))
		points.append(Vector3(stand.x, 0.0, end_z))
	points.append(Vector3(stand.x, 0.0, stand.z))
	var steps: Array[Dictionary] = []
	var from := start
	for point in points:
		var direction := point - from
		if direction.length() > 0.05:
			var facing := Basis(Vector3.UP, atan2(-direction.x, -direction.z))
			steps.append(_step(Transform3D(facing, point), clampf(direction.length() / BOARD_WALK_SPEED, 0.15, 3.0), {"walk": true}))
		from = point
	var toward := look_at - stand
	var turn := Basis(Vector3.UP, atan2(-toward.x, -toward.z)) if Vector2(toward.x, toward.z).length() > 0.05 else Basis.IDENTITY
	steps.append(_step(Transform3D(turn, Vector3(stand.x, 0.0, stand.z)), 0.2, {}))
	return steps


## Which hand reaches [param target] from a stance (the character's right is its basis +X).
func _hand_for(stance: Transform3D, target: Vector3) -> StringName:
	return &"R" if (target - stance.origin).dot(stance.basis.x) > 0.0 else &"L"


func _swing_door(door: Node3D, open: bool) -> void:
	if not is_instance_valid(door):
		return
	var side := signf(door.position.x) if absf(door.position.x) > 0.01 else 1.0
	create_tween().tween_property(door, "rotation:y", -side * DOOR_OPEN_ANGLE if open else 0.0, 0.3 if open else 0.25)


func is_wrecked() -> bool:
	return damage_state == DamageState.WRECKED


func take_damage(amount: float, source: Node = null) -> void:
	if is_wrecked() or amount <= 0.0:
		return
	if source != null and source != self:
		_last_attacker = source
	health = maxf(0.0, health - amount)
	health_changed.emit(health, max_health)
	_update_damage_state()


## Leaves a bullet hole (or a crack in glass) where a shot struck the bodywork. See BulletHoles.
func on_bullet_hit(point: Vector3, direction: Vector3, normal: Vector3) -> void:
	BulletHoles.add(self, point, direction, normal)


func _unhandled_input(event: InputEvent) -> void:
	if driver == null:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look_yaw -= (event as InputEventMouseMotion).relative.x * mouse_sensitivity
	elif event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		begin_exit()


func _physics_process(delta: float) -> void:
	_check_crash()
	if upright_assist > 0.0:
		_apply_upright_assist()
	if damage_state == DamageState.BURNING:
		take_damage(burn_damage_per_second * delta, _last_attacker)
	if driver == null or is_wrecked():
		engine_force = 0.0
		brake = 2.0
		steering = move_toward(steering, 0.0, steer_speed * delta)
		return

	var throttle := Input.get_axis("move_back", "move_forward")
	var forward_speed := linear_velocity.dot(global_basis.z)
	if throttle < 0.0 and forward_speed > 1.0:
		engine_force = 0.0
		brake = max_brake_force
	else:
		engine_force = throttle * max_engine_force * _speed_limit_factor(throttle, forward_speed)
		brake = 0.0
	if Input.is_action_pressed("handbrake"):
		brake = max_brake_force
	var lock := max_steer / (1.0 + steer_falloff * absf(forward_speed))
	steering = move_toward(steering, Input.get_axis("move_right", "move_left") * lock, steer_speed * delta)

	if driver.wants_to_fire():
		_drive_by_shoot()


func _process(delta: float) -> void:
	if driver == null:
		return
	if not Input.is_action_pressed("aim") and not Input.is_action_pressed("shoot"):
		_look_yaw = lerp_angle(_look_yaw, 0.0, clampf(1.5 * delta, 0.0, 1.0))
	_camera_pivot.global_position = global_position + Vector3(0.0, camera_height, 0.0)
	var target_yaw := global_rotation.y + PI + _look_yaw
	_camera_pivot.rotation.y = lerp_angle(_camera_pivot.rotation.y, target_yaw, clampf(6.0 * delta, 0.0, 1.0))


func enter(player: Player) -> void:
	driver = player
	player.set_on_foot(false, self)
	_look_yaw = 0.0
	_camera_pivot.global_position = global_position + Vector3(0.0, camera_height, 0.0)
	_camera_pivot.rotation.y = global_rotation.y + PI
	_camera.make_current()


func exit() -> void:
	var player := driver
	if player == null and _boarder != null and is_instance_valid(_boarder) and _boarder.current_vehicle == self:
		player = _boarder
	if player == null:
		return
	player.cancel_moves()
	driver = null
	_boarder = null
	var door := get_node_or_null("Doors/Driver") as Node3D
	if door != null:
		door.rotation.y = 0.0
	var exit_marker := get_node_or_null("Exit") as Node3D
	var exit_point := exit_marker.global_position if exit_marker != null else global_position + global_basis.x * 1.8
	player.global_position = exit_point + Vector3.UP * 0.5
	player.rotation.y = global_rotation.y + PI
	player.set_on_foot(true)
	player.visual.set_ride(null)
	player.visual.set_seated(0.0)


## Drive-bys use the driver's equipped gun and ammo. Melee and explosives can't be used from a car.
func _drive_by_shoot() -> void:
	var weapons := driver.weapons
	if weapons.current() == null or not weapons.current().data.uses_ammo() or weapons.current().data.is_projectile():
		return
	var exclude: Array[RID] = [get_rid(), driver.get_rid()]
	var muzzle := global_position + Vector3(0.0, 1.6, 0.0)
	weapons.try_fire(self, muzzle, driver.aim_point_from(_camera, exclude) - muzzle, exclude)


func _on_body_entered(body: Node) -> void:
	if body is GangMember and linear_velocity.length() > run_over_speed:
		(body as GangMember).take_damage(1000.0, self)


## Sudden changes in velocity (hitting walls or other cars, hard landings) damage the car.
func _check_crash() -> void:
	var speed_change := (_last_velocity - linear_velocity).length()
	_last_velocity = linear_velocity
	if speed_change > crash_speed_threshold:
		take_damage((speed_change - crash_speed_threshold) * crash_damage_per_speed, driver)


func _update_damage_state() -> void:
	var fraction := health / max_health
	var next := DamageState.OK
	if health <= 0.0:
		next = DamageState.WRECKED
	elif fraction <= fire_threshold:
		next = DamageState.BURNING
	elif fraction <= smoke_threshold:
		next = DamageState.SMOKING
	if next == damage_state:
		return
	damage_state = next
	_smoke.emitting = next != DamageState.OK
	_flames.emitting = next == DamageState.BURNING or next == DamageState.WRECKED
	if next == DamageState.BURNING and driver != null:
		EventBus.notify.emit("Your ride is on fire - get out!")
	elif next == DamageState.WRECKED:
		_explode.call_deferred()


func _explode() -> void:
	if driver != null:
		exit()
	engine_force = 0.0
	for material in _body_materials:
		material.albedo_color = material.albedo_color.darkened(0.75)
	apply_central_impulse(Vector3.UP * mass * 6.0)
	apply_torque_impulse(Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * mass * 2.0)
	Explosion.detonate(self, global_position + Vector3.UP, explosion_radius, explosion_damage, explosion_impulse, _last_attacker)
	exploded.emit()
	get_tree().create_timer(6.0, false).timeout.connect(func() -> void: _flames.emitting = false)
	get_tree().create_timer(wreck_lifetime, false).timeout.connect(queue_free)


func _build_body() -> void:
	var box := BoxShape3D.new()
	box.size = Vector3(1.9, 1.0, 4.2)
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position.y = 0.9
	add_child(shape)

	_add_box_mesh(box.size, Vector3(0.0, 0.9, 0.0), body_color)
	_add_box_mesh(Vector3(1.7, 0.6, 2.0), Vector3(0.0, 1.7, -0.3), Color(0.1, 0.12, 0.15))
	_add_box_mesh(Vector3(1.6, 0.2, 0.1), Vector3(0.0, 1.0, 2.11), Color(1.0, 0.95, 0.7))


func _build_wheels() -> void:
	var tire := CylinderMesh.new()
	tire.top_radius = 0.4
	tire.bottom_radius = 0.4
	tire.height = 0.3
	var tire_material := StandardMaterial3D.new()
	tire_material.albedo_color = Color(0.05, 0.05, 0.05)
	tire.material = tire_material
	for spec: Array in WHEEL_LAYOUT:
		var wheel := VehicleWheel3D.new()
		wheel.position = spec[0]
		wheel.use_as_steering = spec[1]
		wheel.use_as_traction = not spec[1]
		wheel.wheel_radius = 0.4
		wheel.wheel_rest_length = 0.3
		wheel.suspension_travel = 0.3
		wheel.suspension_stiffness = 40.0
		wheel.wheel_friction_slip = 3.0
		var tire_mesh := MeshInstance3D.new()
		tire_mesh.mesh = tire
		tire_mesh.rotation.z = PI / 2.0
		wheel.add_child(tire_mesh)
		add_child(wheel)


func _build_camera() -> void:
	_camera_pivot = Node3D.new()
	_camera_pivot.top_level = true
	add_child(_camera_pivot)
	_spring_arm = SpringArm3D.new()
	_spring_arm.spring_length = camera_distance
	_spring_arm.margin = 0.3
	_spring_arm.collision_mask = 1
	_spring_arm.rotation.x = deg_to_rad(-15.0)
	_spring_arm.add_excluded_object(get_rid())
	_camera_pivot.add_child(_spring_arm)
	_camera = Camera3D.new()
	_camera.fov = 75.0
	_camera.cull_mask &= ~GameState.MAP_LAYER
	_spring_arm.add_child(_camera)


func _add_box_mesh(size: Vector3, offset: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	_body_materials.append(material)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = offset
	add_child(instance)


func _build_damage_effects() -> void:
	_smoke = _make_particles(Color(0.25, 0.25, 0.25, 0.7), 24, 1.6, 2.5)
	_flames = _make_particles(Color(1.0, 0.45, 0.1), 32, 0.6, 1.5)
	_flames.scale_amount_min = 1.0
	_flames.scale_amount_max = 2.0


func _make_particles(color: Color, amount: int, particle_lifetime: float, rise_speed: float) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = particle_lifetime
	particles.emitting = false
	particles.local_coords = false
	var smoke_marker := get_node_or_null("EngineSmoke") as Node3D
	particles.position = smoke_marker.position if smoke_marker != null else Vector3(0.0, 1.4, 1.5)
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3(0.6, 0.1, 0.4)
	particles.direction = Vector3.UP
	particles.spread = 20.0
	particles.gravity = Vector3(0.0, rise_speed, 0.0)
	particles.initial_velocity_min = 0.5
	particles.initial_velocity_max = 1.5
	particles.scale_amount_min = 0.8
	particles.scale_amount_max = 1.6
	particles.color = color
	particles.mesh = FireZone.flame_mesh()
	add_child(particles)
	return particles


## Fades the engine out near the top speed (forward) or a third of it (reverse).
func _speed_limit_factor(throttle: float, forward_speed: float) -> float:
	if max_speed <= 0.0:
		return 1.0
	var limit := max_speed if throttle > 0.0 else max_speed / 3.0
	var speed := forward_speed if throttle > 0.0 else -forward_speed
	return clampf((limit - speed) / maxf(1.0, limit * 0.1), 0.0, 1.0)


## Authored scenes share mesh resources between instances, so each vehicle takes its own copy of
## every body material (one copy per shared material) to paint and to scorch when it explodes.
func _adopt_body_materials() -> void:
	var copies := {}
	var stack: Array[Node] = [get_node("Body")]
	if has_node("Doors"):
		stack.append(get_node("Doors"))
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		var instance := node as MeshInstance3D
		if instance == null or instance.mesh == null:
			continue
		var source := instance.mesh.surface_get_material(0) as StandardMaterial3D
		if source == null:
			continue
		if not copies.has(source):
			var copy := source.duplicate() as StandardMaterial3D
			copies[source] = copy
			_body_materials.append(copy)
		instance.material_override = copies[source]


func _painted_meshes() -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	var stack: Array[Node] = []
	for root_name in ["Body", "Doors"]:
		var root := get_node_or_null(root_name)
		if root != null:
			stack.append(root)
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is MeshInstance3D and node.has_meta("paint"):
			result.append(node)
	return result


## Half the vehicle's length from its collision boxes (2.1 m for the code-built car).
func _half_length() -> float:
	var half := 2.1
	for child in get_children():
		var shape := child as CollisionShape3D
		if shape != null and shape.shape is BoxShape3D:
			half = maxf(half, absf(shape.position.z) + (shape.shape as BoxShape3D).size.z / 2.0)
	return half

func _apply_upright_assist() -> void:
	var forward := global_basis.z
	var roll := global_basis.y.cross(Vector3.UP).dot(forward)
	var roll_rate := angular_velocity.dot(forward)
	apply_torque(forward * (roll * upright_assist - roll_rate * upright_assist * 0.15) * mass)