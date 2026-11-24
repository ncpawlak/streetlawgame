class_name Vehicle
extends VehicleBody3D
## Drivable car built in code. Supports entering/exiting, a chase camera, drive-by shooting, running
## over NPCs, and damage: it smokes when hurt, catches fire when critical and then explodes.

signal health_changed(current: float, maximum: float)
signal exploded

enum DamageState { OK, SMOKING, BURNING, WRECKED }

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


func _ready() -> void:
	add_to_group("vehicles")
	mass = 1000.0
	collision_layer = 8
	collision_mask = 15
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, 0.3, 0.0)
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	health = max_health
	_build_body()
	_build_wheels()
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
	var enter_effect := MethodEffect.create(&"enter")
	enter_effect.pass_actor = true
	var conditions: Array[Condition] = [enter_condition]
	var effects: Array[Effect] = [enter_effect]
	interactable.add_action(InteractionAction.create(&"enter_vehicle", "Steal vehicle", effects, conditions))
	add_child(interactable)

func can_enter() -> bool:
	return driver == null and not is_wrecked()


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
		_look_yaw -= (event as InputEventMouseMotion).relative.x * mouse_sensitivity
	elif event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		exit()


func _physics_process(delta: float) -> void:
	_check_crash()
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


func _process(delta: float) -> void:
	if driver == null:
		return
	if not Input.is_action_pressed("aim") and not Input.is_action_pressed("shoot"):
		_look_yaw = lerp_angle(_look_yaw, 0.0, clampf(1.5 * delta, 0.0, 1.0))
	_camera_pivot.global_position = global_position + Vector3(0.0, 1.8, 0.0)
	var target_yaw := global_rotation.y + PI + _look_yaw
	_camera_pivot.rotation.y = lerp_angle(_camera_pivot.rotation.y, target_yaw, clampf(6.0 * delta, 0.0, 1.0))


func enter(player: Player) -> void:
	driver = player
	player.set_on_foot(false, self)
	_look_yaw = 0.0
	_camera_pivot.global_position = global_position + Vector3(0.0, 1.8, 0.0)
	_camera_pivot.rotation.y = global_rotation.y + PI
	_camera.make_current()


func exit() -> void:
	if driver == null:
		return
	var player := driver
	driver = null
	player.global_position = global_position + global_basis.x * 1.8 + Vector3.UP * 0.5
	player.rotation.y = global_rotation.y + PI
	player.set_on_foot(true)


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
