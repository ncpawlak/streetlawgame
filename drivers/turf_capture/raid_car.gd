class_name RaidCar
extends Vehicle
## A rival car that drives itself to [member destination], brakes and lets its crew out. Can't be stolen until
## the crew is out. If it's wrecked first, the crew dies with it.

signal unloaded(members: Array[GangMember])
signal crew_lost(count: int)

@export var destination := Vector3.ZERO
@export var crew := 3
@export var cruise_force := 2200.0
## Start braking this far from the destination.
@export var brake_distance := 14.0
## Give up driving and bail out after this long (stuck on something).
@export var max_drive_time := 15.0

## Configures each crew member before it's added to the scene.
var crew_setup: Callable
var is_unloaded := false
var _drive_time := 0.0


func _ready() -> void:
	super._ready()
	exploded.connect(_on_exploded)


func can_enter() -> bool:
	return is_unloaded and super.can_enter()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if is_unloaded or is_wrecked() or driver != null:
		return
	_drive_time += delta
	var to_target := destination - global_position
	to_target.y = 0.0
	var speed := linear_velocity.length()
	if to_target.length() < brake_distance or _drive_time > max_drive_time:
		engine_force = 0.0
		brake = max_brake_force
		steering = 0.0
		if speed < 0.8 or _drive_time > max_drive_time + 3.0:
			_unload()
		return
	var local := global_basis.inverse() * to_target
	steering = clampf(atan2(local.x, local.z), -max_steer, max_steer)
	engine_force = cruise_force
	brake = 0.0


func _unload() -> void:
	is_unloaded = true
	var members: Array[GangMember] = []
	var parent := get_parent() as Node3D
	for i in crew:
		var member := GangMember.new()
		var side := 1.0 if i % 2 == 0 else -1.0
		var at := global_position + global_basis.x * side * 1.8 + global_basis.z * (1.2 - float(i / 2) * 1.4)
		member.position = parent.to_local(at + Vector3.UP * 0.2)
		if crew_setup.is_valid():
			crew_setup.call(member)
		members.append(member)
	unloaded.emit(members)
	for member in members:
		parent.add_child(member)


func _on_exploded() -> void:
	if not is_unloaded:
		is_unloaded = true
		crew_lost.emit(crew)
