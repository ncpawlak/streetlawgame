class_name Vehicle
extends VehicleBody3D
## Drivable car built in code. Supports entering/exiting, a chase camera, drive-by shooting, running
## over NPCs, and damage: it smokes when hurt, catches fire when critical and then explodes.
## Getting in and out is animated (see [method begin_enter] / [method begin_exit]): you can use any of
## the four doors and shuffle across to the wheel, and you climb out of the top or crawl out of a car
## lying on its side or roof.

signal health_changed(current: float, maximum: float)
signal exploded

enum DamageState { OK, SMOKING, BURNING, WRECKED }

const DEFAULT_BODY_COLOR := Color(0.2, 0.2, 0.25)
## Driver's seat in car space (cars face +Z; left-hand drive, so the driver sits on +X). The value is
## where the sitter's feet go: on the floor pan, the underside of the body.
## Low center of mass keeps cars planted while driving; once tipped past [constant TIPPED_UP] it moves
## up into the body so a car can come to rest on its side instead of always rolling back.
const DRIVING_CENTER_OF_MASS := Vector3(0.0, 0.2, 0.0)
const TIPPED_CENTER_OF_MASS := Vector3(0.0, 0.9, 0.0)
const TIPPED_UP := 0.5
const RIGHTED_UP := 0.85
const DRIVER_SEAT := Vector3(0.42, 0.4, 0.2)
## [side (+1 driver side, -1 passenger side), seat z]: front pair, then rear pair.
const DOORS := [[1.0, 0.2], [-1.0, 0.2], [1.0, -0.95], [-1.0, -0.95]]
const DOOR_LENGTH := 1.04
const DOOR_OPEN_ANGLE := 1.2
## Where you stand outside a door, measured from the car's centre line.
const DOOR_STAND_OFFSET := 1.45
## Getting in walks you to the door at this speed (m/s).
const BOARD_WALK_SPEED := 3.2
const WHEEL_LAYOUT := [
	# [position, is_front]
	[Vector3(0.9, 0.6, 1.4), true],
	[Vector3(-0.9, 0.6, 1.4), true],
	[Vector3(0.9, 0.6, -1.4), false],
	[Vector3(-0.9, 0.6, -1.4), false],
]

@export var body_color := DEFAULT_BODY_COLOR
## A [constant VehicleClass.TABLE] row (e.g. &"sports"): sets health, handling and, unless body_color
## was changed, the paint. Empty keeps the stock build.
@export var vehicle_class_id: StringName = &""
@export var max_engine_force := 3000.0
@export var max_brake_force := 60.0
@export var max_steer := 0.55
@export var steer_speed := 2.5
@export var run_over_speed := 6.0
@export var mouse_sensitivity := 0.003
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
## Resolved from vehicle_class_id in _ready (null for a stock car).
var vehicle_class: VehicleClass

var _camera_pivot: Node3D
var _spring_arm: SpringArm3D
var _camera: Camera3D
## Free-look chase camera: world-space yaw / pitch driven only by the mouse, so turning the car never
## drags the view back to straight ahead (look around and shoot while driving).
var _look_yaw := 0.0
var _look_pitch := deg_to_rad(-15.0)
var _last_velocity := Vector3.ZERO
var _last_attacker: Node
var _body_materials: Array[StandardMaterial3D] = []
var _smoke: CPUParticles3D
var _flames: CPUParticles3D
## Door hinges (index matches [constant DOORS]).
var _doors: Array[Node3D] = []
## Player walking up and climbing in (the car can't be taken meanwhile).
var _boarding: Player
var _exiting := false


func _ready() -> void:
	add_to_group("vehicles")
	mass = 1300.0
	collision_layer = 8
	collision_mask = 15
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = DRIVING_CENTER_OF_MASS
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	if vehicle_class_id != &"":
		vehicle_class = VehicleClass.find(vehicle_class_id)
		assert(vehicle_class != null, "Unknown vehicle class %s" % vehicle_class_id)
		if vehicle_class != null and body_color == DEFAULT_BODY_COLOR:
			body_color = vehicle_class.color
	health = max_health
	_build_body()
	_build_wheels()
	if vehicle_class != null:
		vehicle_class.apply_to(self)
	_build_camera()
	_build_damage_effects()
	_build_interactable()


## Entering is an ordinary interaction, so it shares the E prompt with everything else.
func _build_interactable() -> void:
	var interactable := Interactable.new()
	interactable.name = "Interactable"
	interactable.prompt_name = "Vehicle"
	interactable.radius = 3.5
	var enter_condition := MethodCondition.create(&"can_enter")
	enter_condition.hide_when_unmet = true
	var enter_effect := MethodEffect.create(&"begin_enter")
	enter_effect.pass_actor = true
	var conditions: Array[Condition] = [enter_condition]
	var effects: Array[Effect] = [enter_effect]
	interactable.add_action(InteractionAction.create(&"enter_vehicle", "Steal vehicle", effects, conditions))
	add_child(interactable)

func can_enter() -> bool:
	return driver == null and _boarding == null and not _exiting and not is_wrecked() and global_basis.y.y > 0.5


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


func _unhandled_input(event: InputEvent) -> void:
	if driver == null:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_look_yaw = wrapf(_look_yaw - motion.relative.x * mouse_sensitivity, -PI, PI)
		_look_pitch = clampf(_look_pitch - motion.relative.y * mouse_sensitivity, deg_to_rad(-60.0), deg_to_rad(20.0))
	elif event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		begin_exit()


func _physics_process(delta: float) -> void:
	_check_crash()
	var up := global_basis.y.y
	if up < TIPPED_UP and center_of_mass != TIPPED_CENTER_OF_MASS:
		center_of_mass = TIPPED_CENTER_OF_MASS
	elif up > RIGHTED_UP and center_of_mass != DRIVING_CENTER_OF_MASS:
		center_of_mass = DRIVING_CENTER_OF_MASS
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
		engine_force = throttle * max_engine_force
		brake = 0.0
	if Input.is_action_pressed("handbrake"):
		brake = max_brake_force
	steering = move_toward(steering, Input.get_axis("move_right", "move_left") * max_steer, steer_speed * delta)

	if driver.wants_to_fire():
		_drive_by_shoot()


func _process(_delta: float) -> void:
	if driver == null:
		return
	_camera_pivot.global_position = global_position + Vector3(0.0, 1.8, 0.0)
	_camera_pivot.rotation.y = _look_yaw
	_spring_arm.rotation.x = _look_pitch


func enter(player: Player) -> void:
	driver = player
	player.set_on_foot(false, self)
	_look_yaw = wrapf(global_rotation.y + PI, -PI, PI)
	_look_pitch = deg_to_rad(-15.0)
	_camera_pivot.global_position = global_position + Vector3(0.0, 1.8, 0.0)
	_camera_pivot.rotation.y = _look_yaw
	_spring_arm.rotation.x = _look_pitch
	_camera.make_current()


## Instantly puts the driver back on foot beside the car (explosions, respawns, scripted events).
func exit() -> void:
	if driver == null:
		return
	var player := driver
	driver = null
	var side := _flat(global_basis.x)
	if side == Vector3.ZERO:
		side = _flat(global_basis.z).cross(Vector3.UP).normalized()
	var spot := global_position + side * 1.8
	spot.y = maxf(global_position.y, _ground_y(spot, global_position.y)) + 0.5
	player.global_transform = Transform3D(Basis(Vector3.UP, _look_yaw), spot)
	player.set_on_foot(true)


## Walks [param player] to the nearest door, opens it, climbs in (shuffling across to the wheel from a
## passenger or rear door), shuts it and starts driving. Returns false if the car can't be taken.
func begin_enter(player: Player) -> bool:
	if player == null or not can_enter() or not player.is_on_foot() or player.is_busy():
		return false
	_boarding = player
	var door := nearest_door(player.global_position)
	var side: float = DOORS[door][0]
	var seat := seat_position(door)
	var outside := global_transform * Vector3(side * DOOR_STAND_OFFSET, 0.0, seat.z)
	outside.y = player.global_position.y
	var inward := _flat(-global_basis.x * side)
	var handle := Vector3(side * 1.0, 1.05, seat.z + 0.35)
	var walk_time := clampf(player.global_position.distance_to(outside) / BOARD_WALK_SPEED, 0.15, 2.5)
	var steps: Array = [
		{to = outside, time = walk_time, face = outside - player.global_position, walk = true},
		{time = 0.2, face = inward},
		{time = 0.4, frame = self, face = Vector3(-side, 0.0, 0.0), reach = {&"R" if side > 0.0 else &"L": handle}, start = open_door.bind(door)},
		{to = seat, time = 0.6, frame = self, face = Vector3.FORWARD * -1.0, seated = 1.0, arc = 0.12},
	]
	if seat.x != DRIVER_SEAT.x or seat.z != DRIVER_SEAT.z:
		steps.append({to = DRIVER_SEAT, time = 0.75 if seat.z != DRIVER_SEAT.z else 0.5, frame = self, face = Vector3.BACK, seated = 1.0, arc = 0.12 if seat.z != DRIVER_SEAT.z else 0.04})
	steps.append({to = DRIVER_SEAT, time = 0.25, frame = self, face = Vector3.BACK, seated = 1.0, start = close_door.bind(door)})
	player.play_moves(steps, _finish_boarding.bind(player))
	return true


func _finish_boarding(player: Player) -> void:
	_boarding = null
	if is_instance_valid(player) and player.health > 0.0 and driver == null and not is_wrecked():
		enter(player)


## Gets the driver out the way the car is lying: through the driver's door (the passenger door if
## that side is blocked) when upright, up and over the top when on its side, or crawling out of the
## window when it's on its roof. Returns false if nobody is driving.
func begin_exit() -> bool:
	if driver == null or _exiting:
		return false
	var player := driver
	driver = null
	_exiting = true
	var up := global_basis.y
	var steps: Array
	if up.y > 0.6:
		steps = _upright_exit()
	elif up.y < -0.6:
		steps = _roof_exit()
	else:
		steps = _side_exit()
	player.set_on_foot(true)
	player.play_moves(steps, _finish_exit)
	return true


func _finish_exit() -> void:
	_exiting = false


func _upright_exit() -> Array:
	var door := 0
	if not _door_clear(0) and _door_clear(1):
		door = 1
	var side: float = DOORS[door][0]
	var seat := seat_position(door)
	var outside := _ground(global_transform * Vector3(side * DOOR_STAND_OFFSET, 0.4, seat.z))
	var steps: Array = []
	if door != 0:
		steps.append({to = seat, time = 0.5, frame = self, face = Vector3.BACK, seated = 1.0, arc = 0.04})
	var handle := Vector3(side * 0.85, 1.0, seat.z + 0.3)
	steps.append({to = seat, time = 0.35, frame = self, face = Vector3.BACK, seated = 1.0, reach = {&"R" if side > 0.0 else &"L": handle}, start = open_door.bind(door)})
	steps.append({to = outside, time = 0.55, face = _flat(global_basis.x * side), seated = 0.0, arc = 0.1})
	steps.append({to = outside, time = 0.3, face = _flat(global_basis.z), start = close_door.bind(door)})
	return steps


## Car on its side: open the door facing the sky, climb up onto the side, then hop down off the roof
## edge.
func _side_exit() -> Array:
	var side := signf(global_basis.x.y)
	if side == 0.0:
		side = 1.0
	var door := 0 if side > 0.0 else 1
	var seat := seat_position(door)
	var sky := Vector3.UP
	var roof_dir := _flat(global_basis.y)
	if roof_dir == Vector3.ZERO:
		roof_dir = _flat(global_basis.z)
	var hatch := global_transform * Vector3(side * 0.95, 1.2, seat.z)
	var on_top := global_transform * Vector3(side * 0.97, 0.9, seat.z)
	var landing := _ground(on_top + roof_dir * 1.8)
	return [
		{time = 0.35, frame = self, reach = {&"L": Vector3(side * 0.97, 1.2, seat.z + 0.4), &"R": Vector3(side * 0.97, 1.2, seat.z - 0.3)}, seated = 0.5, start = open_door.bind(door)},
		{to = hatch - sky * 1.0, time = 0.5, face = roof_dir, crouch = true, seated = 0.0, reach = {&"L": hatch + sky * 0.1 + _flat(global_basis.z) * 0.3, &"R": hatch + sky * 0.1 - _flat(global_basis.z) * 0.3}},
		{to = on_top, time = 0.45, face = roof_dir, crouch = true},
		{to = on_top, time = 0.3, face = roof_dir, crouch = false},
		{to = landing, time = 0.55, face = roof_dir, arc = 0.45},
		{to = landing, time = 0.25, face = roof_dir, crouch = true},
		{to = landing, time = 0.2, face = roof_dir, crouch = false},
	]


## Car on its roof: crawl out through the driver's (or passenger's) window and stand up.
func _roof_exit() -> Array:
	var door := 0 if _door_clear(0) or not _door_clear(1) else 1
	var side: float = DOORS[door][0]
	var seat := seat_position(door)
	var out_dir := _flat(global_basis.x * side)
	var under := _ground(global_transform * Vector3(side * 0.5, 0.4, seat.z))
	var outside := _ground(global_transform * Vector3(side * 1.9, 0.4, seat.z))
	return [
		{to = under, time = 0.5, face = out_dir, crawl = 1.0, seated = 0.0, start = open_door.bind(door)},
		{to = outside, time = 0.9, face = out_dir, crawl = 1.0, walk = true},
		{to = outside, time = 0.45, face = out_dir, crawl = 0.0},
	]


## Index into [constant DOORS] of the door nearest [param point].
func nearest_door(point: Vector3) -> int:
	var best := 0
	var best_distance := INF
	for i in DOORS.size():
		var outside := global_transform * Vector3(DOORS[i][0] * DOOR_STAND_OFFSET, 0.4, DOORS[i][1])
		var distance := outside.distance_squared_to(point)
		if distance < best_distance:
			best_distance = distance
			best = i
	return best


## Seat (car space, feet on the floor pan) behind door [param door].
func seat_position(door: int) -> Vector3:
	return Vector3(DOORS[door][0] * DRIVER_SEAT.x, DRIVER_SEAT.y, DOORS[door][1])


func is_door_open(door: int) -> bool:
	return absf(_doors[door].rotation.y) > 0.3


func open_door(door: int) -> void:
	_swing_door(door, -DOORS[door][0] * DOOR_OPEN_ANGLE)


func close_door(door: int) -> void:
	_swing_door(door, 0.0)


func _swing_door(door: int, angle: float) -> void:
	if door < 0 or door >= _doors.size():
		return
	var tween := create_tween()
	tween.tween_property(_doors[door], "rotation:y", angle, 0.25).set_trans(Tween.TRANS_SINE)


## Room to stand outside door [param door] (walls, other cars).
func _door_clear(door: int) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.4
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, global_transform * Vector3(DOORS[door][0] * DOOR_STAND_OFFSET, 0.4, DOORS[door][1]) + Vector3.UP * 0.6)
	query.collision_mask = 1 | 8
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


## [param point] dropped onto the ground beneath it.
func _ground(point: Vector3) -> Vector3:
	return Vector3(point.x, _ground_y(point, point.y - 0.5), point.z)


func _ground_y(point: Vector3, fallback: float) -> float:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.5, point + Vector3.DOWN * 4.0, 1)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return (hit["position"] as Vector3).y if not hit.is_empty() else fallback


static func _flat(direction: Vector3) -> Vector3:
	direction.y = 0.0
	return direction.normalized() if direction.length_squared() > 0.0001 else Vector3.ZERO


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
		var member := body as GangMember
		member.register_hit(global_position, linear_velocity * 12.0, member.global_position + Vector3.UP, false)
		member.take_damage(1000.0, self)


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
	if _boarding != null:
		_boarding.cancel_moves()
		_boarding = null
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
	# Roof slab so a flipped car rests on its roof instead of sinking the cabin into the road. The
	# windows stay open to bullets.
	var roof_box := BoxShape3D.new()
	roof_box.size = Vector3(1.7, 0.1, 2.0)
	var roof := CollisionShape3D.new()
	roof.name = "RoofCollision"
	roof.shape = roof_box
	roof.position = Vector3(0.0, 1.95, -0.3)
	add_child(roof)

	_add_box_mesh(box.size, Vector3(0.0, 0.9, 0.0), body_color)
	# Tinted glass so whoever is inside shows; the roof is solid.
	_add_box_mesh(Vector3(1.7, 0.55, 2.0), Vector3(0.0, 1.675, -0.3), Color(0.1, 0.12, 0.15, 0.55))
	_body_materials[1].transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_add_box_mesh(Vector3(1.6, 0.2, 0.1), Vector3(0.0, 1.0, 2.11), Color(1.0, 0.95, 0.7))
	_add_box_mesh(Vector3(1.72, 0.06, 2.02), Vector3(0.0, 1.97, -0.3), body_color)
	_build_doors()


## Door panels on hinges at their front edge, swung open by [method open_door]. Visual only; the
## body box does the colliding.
func _build_doors() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.05, 0.8, DOOR_LENGTH - 0.04)
	mesh.material = _body_materials[0]
	var window := BoxMesh.new()
	window.size = Vector3(0.04, 0.5, DOOR_LENGTH - 0.12)
	window.material = _body_materials[1]
	for spec: Array in DOORS:
		var side: float = spec[0]
		var hinge := Node3D.new()
		hinge.name = "Door%s%s" % ["Front" if spec[1] > 0.0 else "Rear", "Right" if side > 0.0 else "Left"]
		hinge.position = Vector3(side * 0.975, 0.9, float(spec[1]) + DOOR_LENGTH * 0.5)
		add_child(hinge)
		var panel := MeshInstance3D.new()
		panel.mesh = mesh
		panel.position = Vector3(0.0, 0.0, -DOOR_LENGTH * 0.5)
		hinge.add_child(panel)
		var glass := MeshInstance3D.new()
		glass.mesh = window
		glass.position = Vector3(-side * 0.04, 0.68, -DOOR_LENGTH * 0.5)
		hinge.add_child(glass)
		_doors.append(hinge)


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
		wheel.suspension_stiffness = 73.0
		wheel.damping_compression = 1.55
		wheel.damping_relaxation = 2.15
		wheel.wheel_friction_slip = 4.9
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
	_spring_arm.spring_length = 7.0
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
	particles.position = Vector3(0.0, 1.4, 1.5)
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
