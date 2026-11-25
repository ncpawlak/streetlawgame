class_name SwingDoor
extends Node3D
## A hinged door that swings open when the player or an NPC comes near and shuts again once the
## doorway is clear. The node sits on the hinge; the panel extends along local +x by [member width].
## A [member locked] door only opens for NPCs; [method kick_in] breaches it for good.
## Added after the navmesh bake so pathing treats the doorway as open.

@export var width := 1.4
@export var height := 2.2
## +1 / -1: which side of the wall the door swings to.
@export var swing := 1.0
## Hinge yaw while closed (PI/2 for doors in walls that run along z).
@export var closed_yaw := 0.0
@export var open_angle := 1.75
@export var close_delay := 1.6

var is_open := false
## Locked doors ignore the player (NPCs still have keys). Unlock or [method kick_in] to get through.
var locked := false
## Kicked in: hangs open for good.
var jammed := false

var _hinge: Node3D
var _sensor: Area3D
var _close_left := 0.0
var _tween: Tween


func _ready() -> void:
	_hinge = Node3D.new()
	_hinge.name = "Hinge"
	_hinge.rotation.y = closed_yaw
	add_child(_hinge)
	var panel := AnimatableBody3D.new()
	panel.name = "Panel"
	panel.collision_layer = 1
	panel.collision_mask = 0
	panel.sync_to_physics = false
	panel.position = Vector3(width * 0.5, height * 0.5, 0.0)
	_hinge.add_child(panel)
	var size := Vector3(width - 0.04, height - 0.02, 0.06)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	panel.add_child(collision)
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.36, 0.22, 0.12)
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	panel.add_child(visual)
	var knob := MeshInstance3D.new()
	var knob_mesh := BoxMesh.new()
	knob_mesh.size = Vector3(0.08, 0.08, 0.16)
	knob.mesh = knob_mesh
	knob.position = Vector3(width * 0.4, -0.15, 0.0)
	panel.add_child(knob)

	# Sensor in the doorway, fixed to the wall (not the hinge) so it doesn't swing away.
	_sensor = Area3D.new()
	_sensor.name = "Sensor"
	_sensor.collision_layer = 0
	_sensor.collision_mask = 2 | 4
	_sensor.monitorable = false
	_sensor.rotation.y = closed_yaw
	var sensor_shape := BoxShape3D.new()
	sensor_shape.size = Vector3(width + 0.6, height, 3.2)
	var sensor_collision := CollisionShape3D.new()
	sensor_collision.shape = sensor_shape
	sensor_collision.position = Vector3(width * 0.5, height * 0.5, 0.0)
	_sensor.add_child(sensor_collision)
	add_child(_sensor)


func _physics_process(delta: float) -> void:
	if jammed:
		return
	var occupied := false
	for body in _sensor.get_overlapping_bodies():
		if not (locked and body is Player):
			occupied = true
			break
	if occupied:
		_close_left = close_delay
		if not is_open:
			_set_open(true)
	elif is_open:
		_close_left -= delta
		if _close_left <= 0.0:
			_set_open(false)


func open_now() -> void:
	_close_left = close_delay * 4.0
	_set_open(true)


## Breaches the door: unlocks it and leaves it hanging wide open.
func kick_in() -> void:
	locked = false
	jammed = true
	_set_open(true, 0.12)


## Shuts (and optionally locks) the door straight away, e.g. when the driver restarts.
func reset(lock := false) -> void:
	jammed = false
	locked = lock
	_close_left = 0.0
	if is_open:
		_set_open(false)


func _set_open(value: bool, seconds := 0.35) -> void:
	is_open = value
	if _tween:
		_tween.kill()
	_tween = create_tween()
	var target := closed_yaw + (swing * open_angle if value else 0.0)
	_tween.tween_property(_hinge, "rotation:y", target, seconds).set_trans(Tween.TRANS_SINE)
