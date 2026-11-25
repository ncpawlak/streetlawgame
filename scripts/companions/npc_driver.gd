class_name NpcDriver
extends Node
## Minimal AI chauffeur for a [Vehicle]: steers along waypoints (a [RoadGraph] route when the
## vehicle is on the street network, else straight at the target) by setting the vehicle's
## [member Vehicle.ai_control] inputs. Whoever sits in the driver's seat is cosmetic; the player can
## ride along as a passenger. Add with [method for_vehicle], then [code]await drive_to(point)[/code].

signal arrived

## Route ends further than this from the start or goal mean we're off the network (e.g. showcases).
const ROAD_SNAP := 40.0
## Seconds of throttle without moving before backing up for [constant REVERSE_TIME].
const STUCK_TIME := 2.0
const REVERSE_TIME := 1.2

@export var cruise_speed := 14.0
@export var corner_speed := 6.0
@export var arrive_radius := 6.0
@export var waypoint_radius := 5.0
@export var use_roads := true

var vehicle: Vehicle
var path := PackedVector3Array()
var _index := 0
var _active := false
var _stuck := 0.0
var _reverse_left := 0.0


## The vehicle's driver node, created on first use.
static func for_vehicle(target_vehicle: Vehicle) -> NpcDriver:
	var existing := target_vehicle.get_node_or_null("NpcDriver") as NpcDriver
	if existing != null:
		return existing
	var driver := NpcDriver.new()
	driver.name = "NpcDriver"
	driver.vehicle = target_vehicle
	target_vehicle.add_child(driver)
	return driver


## Waypoints from [param from] to [param to] (y = 0): a road route when both ends are near the
## network, otherwise the straight line.
static func plan(from: Vector3, to: Vector3, roads := true) -> PackedVector3Array:
	if roads:
		var route := RoadGraph.shared().route(from, to)
		if route.size() >= 3 and _flat(route[1]).distance_to(_flat(from)) < ROAD_SNAP \
				and _flat(route[route.size() - 2]).distance_to(_flat(to)) < ROAD_SNAP:
			return route
	return PackedVector3Array([_flat(from), _flat(to)])


## Drives to [param target] (a point or node) and returns [signal arrived]; parks there.
func drive_to(target: Variant) -> Signal:
	var goal: Vector3 = (target as Node3D).global_position if target is Node3D else target
	return drive_path(plan(_vehicle().global_position, goal, use_roads))


func drive_path(points: PackedVector3Array) -> Signal:
	var car := _vehicle()
	path = points
	_index = mini(1, path.size() - 1)
	_active = not path.is_empty()
	_stuck = 0.0
	_reverse_left = 0.0
	car.ai_control = true
	car.ai_handbrake = false
	return arrived


func is_driving() -> bool:
	return _active


## Stops steering. [param release] hands the controls back (parked) instead of holding the handbrake.
func stop(release := true) -> void:
	_active = false
	var car := _vehicle()
	if car == null:
		return
	car.ai_throttle = 0.0
	car.ai_steer = 0.0
	car.ai_handbrake = not release
	car.ai_control = not release


func _physics_process(delta: float) -> void:
	if not _active:
		return
	var car := _vehicle()
	if car == null or car.is_wrecked():
		stop()
		return
	var at := _flat(car.global_position)
	while _index < path.size() - 1 and at.distance_to(path[_index]) < waypoint_radius:
		_index += 1
	var goal := path[path.size() - 1]
	var remaining := at.distance_to(goal)
	if remaining < arrive_radius:
		_active = false
		car.ai_throttle = 0.0
		car.ai_steer = 0.0
		car.ai_handbrake = true
		arrived.emit()
		return
	var point := path[_index]
	var local := car.global_transform.affine_inverse() * Vector3(point.x, car.global_position.y, point.z)
	var angle := atan2(local.x, local.z)
	var forward_speed := car.linear_velocity.dot(car.global_basis.z)
	var want := lerpf(cruise_speed, corner_speed, clampf(absf(angle) / 1.2, 0.0, 1.0))
	want = minf(want, maxf(3.0, remaining * 0.6))
	var steer := clampf(angle / maxf(0.1, car.max_steer), -1.0, 1.0)
	var throttle := clampf((want - forward_speed) * 0.4, -1.0, 1.0)
	if _reverse_left > 0.0:
		_reverse_left -= delta
		throttle = -1.0
		steer = -steer
	elif throttle > 0.3 and absf(forward_speed) < 0.5:
		_stuck += delta
		if _stuck > STUCK_TIME:
			_stuck = 0.0
			_reverse_left = REVERSE_TIME
	else:
		_stuck = 0.0
	car.ai_throttle = throttle
	car.ai_steer = steer
	car.ai_handbrake = false


func _vehicle() -> Vehicle:
	if vehicle == null:
		vehicle = get_parent() as Vehicle
	return vehicle if is_instance_valid(vehicle) else null


static func _flat(point: Vector3) -> Vector3:
	return Vector3(point.x, 0.0, point.z)
