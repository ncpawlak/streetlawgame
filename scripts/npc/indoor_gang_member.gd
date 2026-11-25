class_name IndoorGangMember
extends GangMember
## A rival that fights inside buildings. Uses a [NavigationAgent3D] to path through rooms, doors and
## stairs (so it can change floors), only shoots with line of sight, and holds a post until alerted.
## Needs a baked NavigationRegion3D in the world; without one it falls back to moving straight.

## What it does at its post and once the shooting starts.
enum Post {
	GUARD,      ## Stands at its post facing [member post_yaw]; chases once alerted.
	PATROL,     ## Walks [member patrol_points]; chases once alerted.
	HOLD,       ## Ambusher: stays in its room and only shoots what it can see.
	OVERWATCH,  ## Window lookout: stays put, long sight range.
}

enum State { IDLE, COMBAT, SEARCH }

signal alerted(member: IndoorGangMember)

@export var post: Post = Post.GUARD
## Facing (radians, like rotation.y) while idle at the post.
@export var post_yaw := 0.0
@export var patrol_points: Array[Vector3] = []
@export var sight_range := 24.0
## Sight range while idle (not yet alerted); -1 = [member sight_range]. Lets players sneak up.
@export var unaware_sight_range := -1.0
## Field of view while idle; alerted members see all around.
@export var fov_degrees := 130.0
## Delay between spotting the player and opening fire.
@export var reaction_time := 0.45
## Chasers stop closing in at this distance when they can see their target.
@export var close_distance := 7.0
## Seconds a SEARCH lasts before giving up and walking back to the post.
@export var search_time := 12.0

var state := State.IDLE
var last_known_position := Vector3.ZERO

var _agent: NavigationAgent3D
var _post_position := Vector3.ZERO
var _patrol_index := 0
var _sight_timer := 0.0
var _has_sight := false
var _react_left := 0.0
var _search_left := 0.0
var _repath_timer := 0.0


func _ready() -> void:
	super._ready()
	floor_snap_length = 0.45
	_post_position = global_position
	rotation.y = post_yaw
	_agent = NavigationAgent3D.new()
	_agent.name = "Agent"
	# Small enough that agents round door frames and stair rails instead of cutting into them.
	_agent.path_desired_distance = 0.3
	_agent.target_desired_distance = 0.8
	_agent.path_height_offset = 0.2
	_agent.radius = 0.4
	_agent.height = 1.8
	add_child(_agent)
	if post == Post.OVERWATCH:
		sight_range *= 1.6


func is_holding() -> bool:
	return post == Post.HOLD or post == Post.OVERWATCH


## Alive and still idle at its post: hasn't seen or heard the player.
func is_unaware() -> bool:
	return not _dead and state == State.IDLE


## Puts this member in combat with the player last seen/heard at [param at].
func alert(at: Vector3) -> void:
	if _dead:
		return
	last_known_position = at
	_search_left = search_time
	if state != State.COMBAT:
		state = State.COMBAT
		_react_left = reaction_time
		_alert_left = alert_duration
		alerted.emit(self)


## Drops back to idle and walks home (e.g. after the player died).
func stand_down() -> void:
	state = State.IDLE
	_has_sight = false


func post_position() -> Vector3:
	return _post_position


## True when nothing solid is between this member's eyes and [param target].
func can_see(target: Node3D) -> bool:
	if target == null or not is_inside_tree():
		return false
	var eye := global_position + Vector3(0.0, 1.5, 0.0)
	var point := target.global_position + Vector3(0.0, 1.2, 0.0)
	if eye.distance_to(point) > _sight_range_now():
		return false
	if state == State.IDLE:
		var to_target := point - eye
		to_target.y = 0.0
		var forward := -global_basis.z
		if to_target.length_squared() > 1.0 and rad_to_deg(forward.angle_to(to_target.normalized())) > fov_degrees * 0.5:
			return false
	var query := PhysicsRayQueryParameters3D.create(eye, point, 1)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func take_damage(amount: float, source: Node = null) -> void:
	super.take_damage(amount, source)
	if not _dead and source is Node3D and not (source is GangMember):
		alert((source as Node3D).global_position)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_alert_left = maxf(0.0, _alert_left - delta)
	if not is_on_floor():
		velocity.y -= _gravity * delta

	var target := _current_target()
	_sight_timer -= delta
	if _sight_timer <= 0.0:
		_sight_timer = 0.15
		_has_sight = target != null and can_see(target)
	if _has_sight:
		alert(target.global_position)

	var move_to := Vector3.INF
	var speed := move_speed
	match state:
		State.IDLE:
			move_to = _idle_destination()
			speed *= 0.45
		State.COMBAT:
			move_to = _combat(target, delta)
		State.SEARCH:
			_search_left -= delta
			if _search_left <= 0.0:
				state = State.IDLE
			elif not is_holding():
				move_to = target.global_position if target != null else last_known_position

	var direction := _direction_to(move_to, delta)
	if state == State.IDLE and move_to == Vector3.INF:
		rotation.y = lerp_angle(rotation.y, post_yaw, clampf(6.0 * delta, 0.0, 1.0))
	elif not (_has_sight and state == State.COMBAT):
		_face(direction)
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	move_and_slide()


func _combat(target: Node3D, delta: float) -> Vector3:
	if target == null:
		state = State.SEARCH
		return Vector3.INF
	if _has_sight:
		var to_target := target.global_position - global_position
		to_target.y = 0.0
		_face(to_target)
		if _react_left > 0.0:
			_react_left -= delta
		elif global_position.distance_to(target.global_position) <= _engage_range():
			_update_attack(target, delta)
		if is_holding() or to_target.length() <= close_distance:
			return Vector3.INF
		return target.global_position
	_react_left = maxf(_react_left, reaction_time * 0.5)
	_search_left -= delta
	if _search_left <= 0.0:
		state = State.SEARCH
		_search_left = search_time
		return Vector3.INF
	if is_holding():
		_face(last_known_position - global_position)
		return Vector3.INF
	# The crew calls out where the player is, so chasers home in on the real position.
	return target.global_position


func _idle_destination() -> Vector3:
	if post == Post.PATROL and patrol_points.size() > 0:
		var point := patrol_points[_patrol_index % patrol_points.size()]
		if _flat_distance(global_position, point) < 0.8:
			_patrol_index += 1
			point = patrol_points[_patrol_index % patrol_points.size()]
		return point
	if _flat_distance(global_position, _post_position) > 0.6 or absf(global_position.y - _post_position.y) > 1.0:
		return _post_position
	return Vector3.INF


## Horizontal direction toward [param destination] along the navmesh (ZERO when there).
func _direction_to(destination: Vector3, delta: float) -> Vector3:
	if destination == Vector3.INF:
		return Vector3.ZERO
	var next := destination
	if _uses_navigation():
		_repath_timer -= delta
		if _repath_timer <= 0.0 or _agent.target_position.distance_to(destination) > 1.5:
			_repath_timer = 0.5
			_agent.target_position = destination
		if _agent.is_navigation_finished():
			return Vector3.ZERO
		next = _agent.get_next_path_position()
	var offset := next - global_position
	offset.y = 0.0
	if offset.length() < 0.15:
		return Vector3.ZERO
	return offset.normalized()


func _uses_navigation() -> bool:
	return _agent != null and NavigationServer3D.map_get_iteration_id(_agent.get_navigation_map()) > 0


func _current_target() -> Node3D:
	var player := GameState.player
	if player == null or not is_instance_valid(player) or player.health <= 0.0:
		return null
	return player if player.is_on_foot() else player.current_vehicle


func _sight_range_now() -> float:
	if state != State.IDLE:
		return maxf(sight_range, alerted_range * 0.5)
	return unaware_sight_range if unaware_sight_range >= 0.0 else sight_range


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
