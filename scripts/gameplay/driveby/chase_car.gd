class_name ChaseCar
extends Vehicle
## Rival car for drive-by retaliation. Parked (an ordinary stealable [Vehicle]) until [method roll_out],
## then drives the road grid after the player and its occupants shoot from the windows.

signal rolled_out

## Gang riding in it (colors the occupants, picks their guns).
@export var gang_id: StringName = &"vipers"
## Chasing a car, it pulls at least this share of that car's power-to-weight (or its own class's
## full engine, if that's stronger): close, but a bit short, so escaping is possible in any class.
@export var chase_throttle := 0.87
## Fixed engine force while chasing. Left negative, it's worked out by [method chase_force].
@export var chase_engine_force := -1.0
## Occupants shoot when the target is this close and in sight.
@export var gun_range := 32.0
## Drives straight at the target (instead of following roads) inside this range with a clear view.
@export var direct_chase_range := 70.0
## Distance at which an intersection counts as reached.
@export var waypoint_radius := 7.0
@export var occupant_damage_scale := 0.3
@export var occupant_extra_spread := 4.0

## Road grid used to route around blocks. Without one it always drives straight at the target.
var grid: StreetGrid
## What it's chasing; defaults to the player (or the player's car).
var target: Node3D
var active := false
var occupants: Array[WeaponInventory] = []

var _waypoint_node := Vector2i(-1, -1)
var _waypoint_age := 0.0
var _stuck_time := 0.0
var _reverse_left := 0.0
var _bursts: Array[Dictionary] = []
var _riders: Array[CarRider] = []
var _last_health := 0.0


func _ready() -> void:
	if body_color == DEFAULT_BODY_COLOR:
		body_color = GameState.gang_color(gang_id).darkened(0.55)
	super()
	_last_health = health
	health_changed.connect(_on_health_changed)
	exploded.connect(func() -> void:
		for rider in _riders:
			rider.die())


## Starts the chase with [param count] armed occupants.
func roll_out(count: int, chase_target: Node3D = null) -> void:
	if is_wrecked():
		return
	target = chase_target
	for i in count:
		_add_occupant()
	active = true
	_waypoint_node = Vector2i(-1, -1)
	rolled_out.emit()


func is_chasing() -> bool:
	return active and driver == null and not is_wrecked()


func _physics_process(delta: float) -> void:
	# The driverless base car eases steering back to center; keep the AI's own steering.
	var ai_steering := steering
	super(delta)
	if not is_chasing():
		return
	steering = ai_steering
	var chase := _current_target()
	if chase == null:
		engine_force = 0.0
		brake = max_brake_force
		return
	_drive(chase.global_position, delta)
	_shoot(chase, delta)


## Engine force used to chase [param chase] (the player on foot or the car they're in).
func chase_force(chase: Node3D) -> float:
	if chase_engine_force >= 0.0:
		return chase_engine_force
	if chase is Vehicle:
		var car := chase as Vehicle
		return maxf(max_engine_force, mass * car.max_engine_force / car.mass * chase_throttle)
	return max_engine_force


func _current_target() -> Node3D:
	if target != null and is_instance_valid(target):
		if target is Player:
			var player := target as Player
			return player if player.is_on_foot() else player.current_vehicle
		return target
	var player := GameState.player
	if player == null:
		return null
	return player if player.is_on_foot() else player.current_vehicle


func _drive(goal: Vector3, delta: float) -> void:
	var waypoint := _pick_waypoint(goal, delta)
	var local := global_transform.affine_inverse() * waypoint
	var angle := atan2(local.x, local.z)
	var forward_speed := linear_velocity.dot(global_basis.z)
	var distance := global_position.distance_to(goal)

	if _reverse_left > 0.0:
		_reverse_left -= delta
		engine_force = -chase_force(_current_target()) * 0.7
		brake = 0.0
		steering = move_toward(steering, -signf(angle) * max_steer, steer_speed * delta)
		return

	var throttle := 1.0
	if absf(angle) > 0.9 and forward_speed > 9.0:
		throttle = 0.0
	elif distance < 10.0:
		throttle = 0.5
	engine_force = throttle * chase_force(_current_target())
	brake = max_brake_force * 0.5 if throttle == 0.0 else 0.0
	steering = move_toward(steering, clampf(angle, -max_steer, max_steer), steer_speed * delta)

	if forward_speed < 1.0:
		_stuck_time += delta
		if _stuck_time > 1.5:
			_stuck_time = 0.0
			_reverse_left = 1.2
	else:
		_stuck_time = 0.0


## Straight at the goal when it's close and visible, otherwise intersection to intersection.
func _pick_waypoint(goal: Vector3, delta: float) -> Vector3:
	if grid == null:
		return goal
	if global_position.distance_to(goal) < direct_chase_range and DriveByMission.line_of_sight(self, global_position + Vector3.UP * 1.2, goal + Vector3.UP):
		_waypoint_node = Vector2i(-1, -1)
		return goal
	var goal_node := grid.nearest_node(goal)
	_waypoint_age += delta
	if _waypoint_node.x < 0 or _waypoint_age > 8.0:
		_waypoint_node = grid.nearest_node(global_position)
		_waypoint_age = 0.0
	var waypoint := grid.node_position(_waypoint_node)
	if _flat_distance(global_position, waypoint) < waypoint_radius:
		if _waypoint_node == goal_node:
			return goal
		_waypoint_node = grid.step_toward(_waypoint_node, goal_node)
		_waypoint_age = 0.0
		waypoint = grid.node_position(_waypoint_node)
	return waypoint


## Each occupant fires bursts out of the windows when the target is close and visible.
func _shoot(chase: Node3D, delta: float) -> void:
	var aim := chase.global_position + Vector3.UP
	var muzzle := global_position + Vector3.UP * 1.7
	if muzzle.distance_to(aim) > gun_range or not DriveByMission.line_of_sight(self, muzzle, aim):
		for rider in _riders:
			rider.idle()
		return
	for rider in _riders:
		rider.aim_at(aim)
	var exclude: Array[RID] = [get_rid()]
	for i in occupants.size():
		var burst := _bursts[i]
		if burst.pause > 0.0:
			burst.pause -= delta
			continue
		var side := global_basis.x * (0.8 if i % 2 == 0 else -0.8)
		if not occupants[i].try_fire(self, muzzle + side, aim - (muzzle + side), exclude):
			continue
		_riders[i].fire()
		burst.left -= 1
		if burst.left <= 0:
			burst.left = randi_range(3, 6)
			burst.pause = randf_range(0.7, 1.5)


func _add_occupant() -> void:
	var arsenal: Array = GangMember.GANG_ARSENAL.get(gang_id, [&"pistol"])
	var weapons := WeaponInventory.new()
	weapons.name = "Occupant%d" % occupants.size()
	weapons.starting_weapon_ids = [&"smg" if arsenal.has(&"smg") else arsenal[0]]
	weapons.starting_magazines = 0
	weapons.infinite_reserve = true
	weapons.damage_scale = occupant_damage_scale
	weapons.extra_spread = occupant_extra_spread
	add_child(weapons)
	occupants.append(weapons)
	_bursts.append({"left": randi_range(3, 6), "pause": randf_range(0.2, 1.0)})

	var seat := occupants.size() - 1
	var rider := CarRider.create(&"gang", randi(), GameState.gang_color(gang_id), 1.0 if seat % 2 == 0 else -1.0, 0.2 - floorf(seat / 2.0), weapons.starting_weapon_ids[0])
	rider.name = "Rider%d" % seat
	add_child(rider)
	_riders.append(rider)


func _on_health_changed(current: float, _maximum: float) -> void:
	if current < _last_health:
		for rider in _riders:
			rider.hit()
	_last_health = current


## Running over its own gang doesn't hurt them.
func _on_body_entered(body: Node) -> void:
	if body is GangMember and (body as GangMember).gang_id == gang_id:
		return
	super(body)


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
