class_name PursuitCruiser
extends Vehicle
## A police car that drives itself toward [member target_position] (the latest tracker ping or
## sighting). Reuses [Vehicle] physics, damage and wrecks; only the steering/throttle is AI.

@export var cruise_force := 2600.0
## Stop this close to the target (m).
@export var arrive_radius := 7.0

var target_position := Vector3.ZERO
var has_target := false

var _stuck_time := 0.0
var _reverse_left := 0.0
var _siren: OmniLight3D


func _ready() -> void:
	body_color = Color(0.92, 0.92, 0.95)
	super._ready()
	add_to_group("police_cars")
	var bar := MeshInstance3D.new()
	var bar_mesh := BoxMesh.new()
	bar_mesh.size = Vector3(1.2, 0.15, 0.3)
	var bar_material := StandardMaterial3D.new()
	bar_material.albedo_color = Color(0.1, 0.2, 1.0)
	bar_material.emission_enabled = true
	bar_material.emission = Color(0.2, 0.3, 1.0)
	bar_mesh.material = bar_material
	bar.mesh = bar_mesh
	bar.position = Vector3(0.0, 2.1, -0.3)
	add_child(bar)
	_siren = OmniLight3D.new()
	_siren.omni_range = 8.0
	_siren.position = Vector3(0.0, 2.4, -0.3)
	add_child(_siren)


## Police cars can't be jacked in this driver.
func can_enter() -> bool:
	return false


func chase(point: Vector3) -> void:
	target_position = point
	has_target = true


func _process(delta: float) -> void:
	super._process(delta)
	var blink := fmod(Time.get_ticks_msec() / 200.0, 2.0) < 1.0
	_siren.light_color = Color(1.0, 0.1, 0.1) if blink else Color(0.1, 0.2, 1.0)


func _physics_process(delta: float) -> void:
	_check_crash()
	if damage_state == DamageState.BURNING:
		take_damage(burn_damage_per_second * delta, _last_attacker)
	if is_wrecked() or not has_target:
		engine_force = 0.0
		brake = 4.0
		return
	var local := global_basis.inverse() * (target_position - global_position)
	local.y = 0.0
	var distance := local.length()
	var speed := linear_velocity.length()
	if _reverse_left > 0.0:
		_reverse_left -= delta
		engine_force = -cruise_force
		brake = 0.0
		steering = -clampf(atan2(local.x, local.z), -max_steer, max_steer)
		return
	if distance <= arrive_radius:
		engine_force = 0.0
		brake = max_brake_force * 0.5
		steering = 0.0
		_stuck_time = 0.0
		return
	var angle := atan2(local.x, local.z)
	steering = move_toward(steering, clampf(angle, -max_steer, max_steer), steer_speed * delta)
	var sharp := absf(angle) > 1.2
	engine_force = cruise_force * (0.45 if sharp else 1.0)
	brake = 0.0
	if speed < 1.0:
		_stuck_time += delta
		if _stuck_time > 1.5:
			_stuck_time = 0.0
			_reverse_left = 1.2
	else:
		_stuck_time = 0.0
