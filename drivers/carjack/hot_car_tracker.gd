class_name HotCarTracker
extends Node
## A LoJack-style tracker on a stolen car. While active it pings the car's position every
## [member ping_interval] seconds (the driver forwards pings to the police). It goes dead when its
## [member duration] runs out (you outran it) or after the car sits in a signal dead zone (group
## "tracker_jammers", anything with contains_point(Vector3) -> bool) for [member jam_time] seconds.

signal pinged(position: Vector3)
## [param reason]: &"expired", &"jammed", &"chopped" or &"stopped".
signal lost(reason: StringName)

@export var ping_interval := 5.0
## Seconds the tracker keeps transmitting before it gives up.
@export var duration := 40.0
@export var jam_time := 3.0

var car: Node3D
var active := false
var time_left := 0.0
var jammed_for := 0.0
var pings := 0

var _next_ping := 0.0


func _init(tracked: Node3D = null) -> void:
	car = tracked


func start() -> void:
	active = true
	time_left = duration
	jammed_for = 0.0
	pings = 0
	_next_ping = 0.0


func stop(reason: StringName = &"stopped") -> void:
	if not active:
		return
	active = false
	lost.emit(reason)


func _physics_process(delta: float) -> void:
	update(delta)


## Advances the tracker by [param delta] seconds.
func update(delta: float) -> void:
	if not active or car == null or not is_instance_valid(car):
		return
	if is_jammed():
		jammed_for += delta
		if jammed_for >= jam_time:
			stop(&"jammed")
		return
	jammed_for = 0.0
	time_left -= delta
	if time_left <= 0.0:
		stop(&"expired")
		return
	_next_ping -= delta
	if _next_ping <= 0.0:
		_next_ping = ping_interval
		pings += 1
		pinged.emit(car.global_position)


func is_jammed() -> bool:
	if car == null or not car.is_inside_tree():
		return false
	for jammer in car.get_tree().get_nodes_in_group("tracker_jammers"):
		if jammer.call("contains_point", car.global_position):
			return true
	return false


func status_text() -> String:
	if not active:
		return ""
	if jammed_for > 0.0:
		return "TRACKER - losing signal %d%%" % int(jammed_for / jam_time * 100.0)
	return "TRACKER ACTIVE - pinging the cops (%d s left)" % ceili(time_left)
