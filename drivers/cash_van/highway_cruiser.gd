class_name HighwayCruiser
extends PursuitCruiser
## A cash-van pursuit cruiser: the carjack [PursuitCruiser] (a real [Vehicle] with the shared
## [VehicleClass] handling and a cop at the wheel) aimed at the player every frame. It keeps the
## [PoliceResponse] told where it last saw them, and bails its [Cop]s out when it catches the player
## on foot (or crawling along) or when it's set on fire. Blow it up outright and the crew go with it.

signal bailed(cops: Array[Cop])
## The car is out of the chase (burning or wrecked).
signal wrecked

## Police interceptor: the muscle-car row of [constant VehicleClass.TABLE].
const CLASS_ID := &"muscle"

@export var sight_range := 70.0
@export var bail_range := 14.0
@export var cops_per_car := 2
## Closing-speed budget (m/s per metre of gap) so it pulls up beside the player instead of ramming.
@export var approach_gain := 0.9
## The crew only jump out once the car has slowed below this (m/s).
@export var bail_speed := 3.0

var response: PoliceResponse
var bailed_out := false

var _out := false
## Pulling over to let the crew out.
var _pulling_over := false


func _init() -> void:
	vehicle_class_id = CLASS_ID
	cruise_force = 4200.0
	arrive_radius = 4.0


func _ready() -> void:
	super._ready()
	add_to_group("pursuit_cruisers")
	health_changed.connect(_on_health_changed)


## Out of the chase once it's on fire (the crew bail) or wrecked.
func is_disabled() -> bool:
	# Read off health, not damage_state: health_changed fires before the state updates.
	return health <= max_health * fire_threshold


## Sends the cops in this car out on foot (once).
func bail() -> void:
	if bailed_out:
		return
	bailed_out = true
	has_target = false
	if _cop != null:
		_cop.visible = false
	var spawned: Array[Cop] = []
	for i in cops_per_car:
		var cop := Cop.new()
		var side := 1.0 if i % 2 == 0 else -1.0
		var at := global_transform * Vector3(2.0 * side, 0.3, 0.5 - i * 0.8)
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
	if not bailed_out and not is_wrecked():
		_track_player()
	super._physics_process(delta)
	if is_wrecked():
		return
	if bailed_out or _pulling_over:
		# Parked (or stopping to let the crew out): stand on the brakes rather than coasting
		# driverless into the player.
		engine_force = 0.0
		brake = max_brake_force
		if _pulling_over and linear_velocity.length() < bail_speed:
			_pulling_over = false
			bail()
	elif has_target:
		_limit_closing_speed()


## Caps the closing speed on the target by the remaining gap, so the car pulls up on the player
## (or meets them head-on) without ploughing into them at full chat.
func _limit_closing_speed() -> void:
	var player := GameState.player
	var target_velocity := Vector3.ZERO
	if player != null and not player.is_on_foot() and player.current_vehicle != null:
		target_velocity = player.current_vehicle.linear_velocity
	var to_target := target_position - global_position
	to_target.y = 0.0
	var gap := maxf(to_target.length() - arrive_radius, 0.0)
	var closing := (linear_velocity - target_velocity).dot(to_target.normalized())
	if closing > 2.0 + gap * approach_gain:
		engine_force = 0.0
		brake = max_brake_force


func _track_player() -> void:
	var player := GameState.player
	if player == null:
		return
	var target: Node3D = player if player.is_on_foot() else player.current_vehicle
	if target == null:
		return
	var dist := global_position.distance_to(target.global_position)
	if not _can_see(target, dist):
		# Lost them: run to the last sighting the response has and look there. No radar.
		_pulling_over = false
		if response != null and response.wanted:
			chase(response.last_seen)
		return
	if response != null and response.wanted:
		response.last_seen = target.global_position
		response.unseen_time = 0.0
	var target_speed := 0.0 if player.is_on_foot() else player.current_vehicle.linear_velocity.length()
	if dist < bail_range and target_speed < 4.0:
		_pulling_over = true
		has_target = false
		return
	_pulling_over = false
	# Aim a little ahead of a moving target so it cuts in instead of trailing.
	var lead := Vector3.ZERO if player.is_on_foot() else player.current_vehicle.linear_velocity * 0.6
	chase(target.global_position + lead)


## In range with a clear line from the cab to the target (static world only).
func _can_see(target: Node3D, dist: float) -> bool:
	if dist > sight_range:
		return false
	var eye := global_position + Vector3(0.0, 1.6, 0.0)
	var query := PhysicsRayQueryParameters3D.create(eye, target.global_position + Vector3(0.0, 1.0, 0.0), 1)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _on_health_changed(_current: float, _maximum: float) -> void:
	if not is_disabled() or _out:
		return
	_out = true
	if not bailed_out:
		if health <= 0.0:
			# Blown up with the crew inside.
			bailed_out = true
			has_target = false
		else:
			bail()
	wrecked.emit()
