class_name Vehicle
extends VehicleBody3D
## Drivable car built in code. Supports entering/exiting, a chase camera, drive-by shooting and running over NPCs.

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
@export var drive_by_weapon: WeaponData

var driver: Player

var _camera_pivot: Node3D
var _spring_arm: SpringArm3D
var _camera: Camera3D
var _look_yaw := 0.0
var _fire_cooldown := 0.0


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
	if drive_by_weapon == null:
		drive_by_weapon = WeaponData.new()
		drive_by_weapon.display_name = "Drive-by SMG"
		drive_by_weapon.damage = 18.0
		drive_by_weapon.fire_interval = 0.12
		drive_by_weapon.spread_degrees = 2.5
	_build_body()
	_build_wheels()
	_build_camera()


func _unhandled_input(event: InputEvent) -> void:
	if driver == null:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look_yaw -= (event as InputEventMouseMotion).relative.x * mouse_sensitivity
	elif event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		exit()


func _physics_process(delta: float) -> void:
	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)
	if driver == null:
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

	if Input.is_action_pressed("shoot") and _fire_cooldown <= 0.0 and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
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


func _drive_by_shoot() -> void:
	_fire_cooldown = drive_by_weapon.fire_interval
	var exclude: Array[RID] = [get_rid()]
	var muzzle := global_position + Vector3(0.0, 1.6, 0.0)
	var aim_point := Hitscan.camera_aim_point(_camera, drive_by_weapon.max_range, exclude)
	Hitscan.fire(self, muzzle, aim_point - muzzle, drive_by_weapon, exclude)


func _on_body_entered(body: Node) -> void:
	if body is GangMember and linear_velocity.length() > run_over_speed:
		(body as GangMember).take_damage(1000.0, self)


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
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = offset
	add_child(instance)
