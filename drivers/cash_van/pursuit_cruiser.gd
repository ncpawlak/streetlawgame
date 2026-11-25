class_name PursuitCruiser
extends CharacterBody3D
## A police cruiser that chases the player down the highway: steers at the player (or their car),
## rams them, keeps the [PoliceResponse] informed of where it last saw them, and bails two [Cop]s
## out when it catches the player on foot (or slow), or when it's wrecked.

signal bailed(cops: Array[Cop])
signal wrecked

@export var max_speed := 27.0
@export var acceleration := 9.0
## Radians per second.
@export var turn_rate := 1.7
@export var max_health := 160.0
@export var sight_range := 70.0
@export var ram_damage := 18.0
@export var ram_impulse := 3.0
@export var bail_range := 14.0
@export var cops_per_car := 2

var response: PoliceResponse
var health := 0.0
var speed := 0.0
var bailed_out := false

var _heading := 0.0
var _ram_cooldown := 0.0
var _stuck_time := 0.0
var _reverse_left := 0.0
var _lights: Array[StandardMaterial3D] = []
var _light_time := 0.0
var _body_material: StandardMaterial3D


func _ready() -> void:
	add_to_group("police_cars")
	add_to_group("pursuit_cruisers")
	collision_layer = 8
	collision_mask = 1 | 2 | 8
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	health = max_health
	_heading = rotation.y
	_build_body()


func is_wrecked() -> bool:
	return health <= 0.0


func take_damage(amount: float, _source: Node = null) -> void:
	if is_wrecked():
		return
	health -= amount
	if is_wrecked():
		_body_material.albedo_color = Color(0.15, 0.15, 0.15)
		wrecked.emit()
		bail()


## Sends the cops in this car out on foot (once).
func bail() -> void:
	if bailed_out:
		return
	bailed_out = true
	speed = 0.0
	var spawned: Array[Cop] = []
	for i in cops_per_car:
		var cop := Cop.new()
		var side := 1.0 if i % 2 == 0 else -1.0
		var at := global_transform * Vector3(1.8 * side, 0.2, 0.5 - i * 0.8)
		var parent: Node3D = response if response != null else get_parent()
		cop.position = parent.to_local(at)
		parent.add_child(cop)
		cop._alert_left = cop.alert_duration * 3.0
		if response != null:
			cop.search_at(response.last_seen)
			response.cops.append(cop)
		spawned.append(cop)
	bailed.emit(spawned)


func _physics_process(delta: float) -> void:
	_flash_lights(delta)
	if bailed_out:
		return
	var player := GameState.player
	if player == null:
		return
	var target: Node3D = player if player.is_on_foot() else player.current_vehicle
	if target == null:
		return
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	var dist := to_target.length()
	_report_sighting(target, dist)
	var target_speed_now := 0.0
	if player.current_vehicle != null:
		target_speed_now = player.current_vehicle.linear_velocity.length()
	if dist < bail_range and (player.is_on_foot() or target_speed_now < 4.0):
		bail()
		return

	_ram_cooldown = maxf(0.0, _ram_cooldown - delta)
	if _reverse_left > 0.0:
		_reverse_left -= delta
		speed = move_toward(speed, -6.0, acceleration * 2.0 * delta)
	else:
		var desired := atan2(to_target.x, to_target.z)
		_heading = rotate_toward(_heading, desired, turn_rate * delta)
		var facing_error := absf(angle_difference(_heading, desired))
		var cruise := max_speed * clampf(1.2 - facing_error, 0.35, 1.0)
		# Close in at the player's pace instead of overshooting.
		if dist < 25.0:
			cruise = minf(cruise, maxf(target_speed_now + 3.0, dist * 0.8))
		speed = move_toward(speed, cruise, acceleration * delta)
	rotation = Vector3(0.0, _heading, 0.0)
	velocity = Vector3(sin(_heading), 0.0, cos(_heading)) * speed
	move_and_slide()
	_handle_collisions(delta)


func _report_sighting(target: Node3D, dist: float) -> void:
	if response == null or not response.wanted or dist > sight_range:
		return
	var eye := global_position + Vector3(0.0, 1.4, 0.0)
	var query := PhysicsRayQueryParameters3D.create(eye, target.global_position + Vector3(0.0, 1.0, 0.0), 1)
	query.exclude = [get_rid()]
	if get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		response.last_seen = target.global_position
		response.unseen_time = 0.0


func _handle_collisions(delta: float) -> void:
	var blocked := false
	for i in get_slide_collision_count():
		var collider := get_slide_collision(i).get_collider()
		if collider is Vehicle and (collider as Vehicle).driver != null and _ram_cooldown <= 0.0:
			var car := collider as Vehicle
			_ram_cooldown = 1.5
			car.take_damage(ram_damage, self)
			var push := (car.global_position - global_position)
			push.y = 0.0
			car.apply_central_impulse(push.normalized() * car.mass * ram_impulse)
		elif collider is StaticBody3D:
			blocked = true
	if blocked and get_real_velocity().length() < 2.0:
		_stuck_time += delta
		if _stuck_time > 0.8:
			_stuck_time = 0.0
			_reverse_left = 1.2
	else:
		_stuck_time = 0.0


func _flash_lights(delta: float) -> void:
	_light_time += delta * 6.0
	var on := int(_light_time) % 2 == 0
	if _lights.size() == 2:
		_lights[0].emission_energy_multiplier = 3.0 if on else 0.2
		_lights[1].emission_energy_multiplier = 0.2 if on else 3.0


func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 1.2, 4.4)
	shape.shape = box
	shape.position.y = 0.95
	add_child(shape)
	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = Color(0.92, 0.92, 0.95)
	_add_box(Vector3(2.0, 0.8, 4.4), Vector3(0.0, 0.75, 0.0), _body_material)
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.05, 0.05, 0.08)
	_add_box(Vector3(1.8, 0.6, 2.2), Vector3(0.0, 1.45, -0.2), black)
	_add_box(Vector3(2.02, 0.3, 1.4), Vector3(0.0, 0.8, 0.0), black)
	for side in [-1.0, 1.0]:
		var light := StandardMaterial3D.new()
		light.albedo_color = Color(1.0, 0.1, 0.1) if side < 0.0 else Color(0.1, 0.3, 1.0)
		light.emission_enabled = true
		light.emission = light.albedo_color
		_lights.append(light)
		_add_box(Vector3(0.5, 0.16, 0.3), Vector3(0.3 * side, 1.83, -0.2), light)
	for x in [-0.95, 0.95]:
		for z in [-1.4, 1.4]:
			var wheel := CylinderMesh.new()
			wheel.top_radius = 0.38
			wheel.bottom_radius = 0.38
			wheel.height = 0.3
			wheel.material = black
			var visual := MeshInstance3D.new()
			visual.mesh = wheel
			visual.position = Vector3(x, 0.38, z)
			visual.rotation.z = PI / 2.0
			add_child(visual)


func _add_box(size: Vector3, at: Vector3, material: StandardMaterial3D) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position = at
	add_child(visual)
