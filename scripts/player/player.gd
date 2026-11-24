class_name Player
extends CharacterBody3D
## Third-person on-foot controller: movement, orbit camera, shooting, vehicle entry and health.

@export var walk_speed := 5.0
@export var sprint_speed := 9.0
@export var acceleration := 10.0
@export var jump_velocity := 5.5
@export var mouse_sensitivity := 0.003
@export var max_health := 100.0
@export var health_regen := 2.0
@export var vehicle_enter_range := 3.5
## Fraction of cash lost when killed.
@export_range(0.0, 1.0) var death_cash_penalty := 0.1
## Seconds after taking damage before health starts regenerating.
@export var regen_delay := 4.0
## Range of the camera ray used to find what the crosshair is on.
@export var aim_ray_length := 200.0

var health := 0.0
var current_vehicle: Vehicle
var spawn_point := Vector3.ZERO
var weapons: WeaponInventory
## Finds and runs Interactables (E); vehicles are entered through it too.
var interactor: Interactor

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _regen_wait := 0.0
var _shake := 0.0

@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _spring_arm: SpringArm3D = $CameraPivot/SpringArm
@onready var _camera: Camera3D = $CameraPivot/SpringArm/Camera
@onready var _collision: CollisionShape3D = $Collision


func _ready() -> void:
	add_to_group("player")
	weapons = WeaponInventory.new()
	weapons.name = "Weapons"
	add_child(weapons)
	weapons.current_index = weapons.slots.size() - 1
	interactor = Interactor.new()
	interactor.name = "Interactor"
	add_child(interactor)
	health = max_health
	spawn_point = global_position
	_camera_pivot.top_level = true
	_spring_arm.add_excluded_object(get_rid())
	_camera.cull_mask &= ~GameState.MAP_LAYER
	_camera.make_current()
	GameState.player = self
	EventBus.explosion.connect(_on_explosion)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and is_on_foot() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_camera_pivot.rotate_y(-motion.relative.x * mouse_sensitivity)
		_spring_arm.rotation.x = clampf(_spring_arm.rotation.x - motion.relative.y * mouse_sensitivity, deg_to_rad(-65.0), deg_to_rad(25.0))
	elif event.is_action_pressed("interact"):
		if is_on_foot() and (interactor.try_interact() or _try_enter_vehicle()):
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("reload"):
		weapons.reload()
	elif event.is_action_pressed("detonate"):
		if weapons.detonate_charges() == 0 and weapons.find(&"c4") != null:
			EventBus.notify.emit("No C4 placed")
	elif event.is_action_pressed("next_weapon"):
		weapons.cycle(1)
	elif event.is_action_pressed("prev_weapon"):
		weapons.cycle(-1)
	else:
		for i in InputSetup.WEAPON_HOTKEYS:
			if event.is_action_pressed("weapon_%d" % (i + 1)):
				weapons.select(i)


func _process(delta: float) -> void:
	_camera_pivot.global_position = global_position + Vector3(0.0, 1.6, 0.0)
	_regen_wait = maxf(0.0, _regen_wait - delta)
	if health < max_health and health > 0.0 and _regen_wait <= 0.0:
		_set_health(minf(max_health, health + health_regen * delta))
	_update_shake(delta)


## Shakes whichever camera is active (on foot or driving) after a nearby explosion.
func _update_shake(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	_shake = move_toward(_shake, 0.0, delta * 1.5)
	camera.h_offset = randf_range(-_shake, _shake) * 0.3
	camera.v_offset = randf_range(-_shake, _shake) * 0.3


func _on_explosion(at: Vector3, radius: float) -> void:
	var distance := get_focus_position().distance_to(at)
	_shake = maxf(_shake, clampf(1.0 - distance / (radius * 5.0), 0.0, 1.0))


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := Basis(Vector3.UP, _camera_pivot.rotation.y) * Vector3(input.x, 0.0, input.y)
	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var blend := clampf(acceleration * delta, 0.0, 1.0)
	velocity.x = lerpf(velocity.x, direction.x * speed, blend)
	velocity.z = lerpf(velocity.z, direction.z * speed, blend)

	var aiming := Input.is_action_pressed("aim") or Input.is_action_pressed("shoot")
	if aiming:
		rotation.y = lerp_angle(rotation.y, _camera_pivot.rotation.y, clampf(20.0 * delta, 0.0, 1.0))
	elif direction.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), clampf(10.0 * delta, 0.0, 1.0))

	if wants_to_fire():
		shoot()

	move_and_slide()
	if global_position.y < -50.0:
		respawn()


func shoot() -> bool:
	var exclude: Array[RID] = [get_rid()]
	var muzzle := global_position + Vector3(0.0, 1.4, 0.0)
	var aim_point := Hitscan.camera_aim_point(_camera, aim_ray_length, exclude)
	return weapons.try_fire(self, muzzle, aim_point - muzzle, exclude)


## Point under the crosshair of whichever camera is active (used for drive-bys too).
func aim_point_from(camera: Camera3D, exclude: Array[RID]) -> Vector3:
	return Hitscan.camera_aim_point(camera, aim_ray_length, exclude)


## Automatic weapons fire while held; others once per click.
func wants_to_fire() -> bool:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or weapons.current() == null:
		return false
	if weapons.current().data.automatic:
		return Input.is_action_pressed("shoot")
	return Input.is_action_just_pressed("shoot")


func is_on_foot() -> bool:
	return current_vehicle == null


## Position the world should treat as "where the player is" (the vehicle when driving).
func get_focus_position() -> Vector3:
	return current_vehicle.global_position if current_vehicle else global_position


func nearest_free_vehicle() -> Vehicle:
	var best: Vehicle = null
	var best_distance := vehicle_enter_range
	for node in get_tree().get_nodes_in_group("vehicles"):
		var vehicle := node as Vehicle
		var distance := global_position.distance_to(vehicle.global_position)
		if vehicle.can_enter() and distance < best_distance:
			best = vehicle
			best_distance = distance
	return best


## Called by Vehicle when entering/exiting.
func set_on_foot(on_foot: bool, vehicle: Vehicle = null) -> void:
	current_vehicle = null if on_foot else vehicle
	visible = on_foot
	_collision.set_deferred("disabled", not on_foot)
	set_physics_process(on_foot)
	velocity = Vector3.ZERO
	if on_foot:
		_camera_pivot.rotation.y = rotation.y
		_camera.make_current()


func take_damage(amount: float, _source: Node = null) -> void:
	if health <= 0.0:
		return
	_regen_wait = regen_delay
	_set_health(health - amount)
	if health <= 0.0:
		_die()


func respawn() -> void:
	if current_vehicle:
		current_vehicle.exit()
	global_position = spawn_point
	velocity = Vector3.ZERO
	_set_health(max_health)


func heal(amount: float) -> void:
	if health > 0.0:
		_set_health(health + amount)


func _try_enter_vehicle() -> bool:
	var vehicle := nearest_free_vehicle()
	if vehicle == null:
		return false
	vehicle.enter(self)
	return true


func _die() -> void:
	var loss := int(GameState.cash * death_cash_penalty)
	GameState.add_cash(-loss)
	EventBus.notify.emit("WASTED - hospital bill: $%d" % loss)
	EventBus.player_died.emit()
	respawn()


func _set_health(value: float) -> void:
	health = clampf(value, 0.0, max_health)
	EventBus.player_health_changed.emit(health, max_health)
