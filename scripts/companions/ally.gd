class_name Ally
extends CharacterBody3D
## A friendly NPC of the player's gang (a "homie"): follows the player in formation, fights the
## player's enemies, rides along in the player's vehicle (shooting out of the window), can lead the
## way somewhere ([method lead_to]) and can drive ([method drive_to]). Join the crew with
## [method Party.recruit]; the [Party] autoload handles formation, commands and auto-boarding.
## Implements the vehicle occupant interface ([member current_vehicle], [member visual],
## [method play_moves], [method is_busy], [method cancel_moves], [method set_on_foot]).

## Emitted when a [method lead_to] or [method go_to] destination is reached.
signal arrived
signal mode_changed(mode: Mode)
signal boarded(vehicle: Vehicle, seat: int)
signal exited_vehicle(vehicle: Vehicle)
signal downed
signal revived
## Bled out while downed (then respawns at the safehouse, see [member Party.safehouse_position]).
signal died

enum Mode { IDLE, FOLLOW, HOLD, LEAD, DOWNED }

## Hips sit this far behind the target when following (formation offsets come from [Party]).
const FOLLOW_STOP := 1.2
## Within this distance a vehicle is boarded with the animated get-in (further: run there first).
const BOARD_RANGE := 7.0
const DETOUR_TIME := 0.8
const RETARGET_TIME := 0.25

@export var display_name := "Homie"
@export var gang_id: StringName = &"player"
@export var max_health := 120.0
@export var walk_speed := 2.0
@export var run_speed := 5.5
@export var sprint_speed := 8.0
@export var weapon_id: StringName = &"pistol"
@export var damage_scale := 0.5
@export var extra_spread := 2.0
@export var engage_range := 25.0
## Drive-by range from a passenger seat.
@export var drive_by_range := 30.0
## While following, warp behind the player when further than this, or when off screen beyond
## [member offscreen_teleport_distance] for [member offscreen_teleport_time] seconds.
@export var teleport_distance := 60.0
@export var offscreen_teleport_distance := 25.0
@export var offscreen_teleport_time := 3.0
@export var bleed_out_time := 30.0
@export var revive_time := 1.5
## Shows a "Recruit" prompt while not in the crew.
@export var recruitable := true
@export var visual_seed := -1

var mode := Mode.IDLE
var health := 0.0
var current_vehicle: Vehicle
var visual: CharacterVisual
var weapons: WeaponInventory
## Current enemy (null when none in range).
var target: Node3D
var interactable: Interactable

var _scripted: ScriptedMoves
var _collision: CollisionShape3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _hold_point := Vector3.ZERO
var _goal: Variant = null
var _goal_radius := 2.0
var _wait_radius := 8.0
var _wait_for_player := false
var _mode_before_goal := Mode.IDLE
var _board_vehicle: Vehicle
var _board_seat := -1
var _retarget := 0.0
var _burst_left := 0
var _burst_pause := 0.0
var _offscreen := 0.0
var _bleed_left := 0.0
var _blocked := 0.0
var _detour_left := 0.0
var _detour_side := 1.0


func _ready() -> void:
	add_to_group("allies")
	collision_layer = 4
	collision_mask = 15
	health = max_health
	_hold_point = global_position
	weapons = WeaponInventory.new()
	weapons.name = "Weapons"
	weapons.starting_weapon_ids = [weapon_id]
	weapons.starting_magazines = 0
	weapons.infinite_reserve = true
	weapons.damage_scale = damage_scale
	weapons.extra_spread = extra_spread
	add_child(weapons)
	_build_body()
	_scripted = ScriptedMoves.new(self, visual)
	_scripted.on_abort = cancel_moves
	_build_interactable()


func label() -> String:
	return display_name


func is_alive() -> bool:
	return mode != Mode.DOWNED


func is_on_foot() -> bool:
	return current_vehicle == null and not is_busy()


## Whether rivals can shoot at this ally (on foot and standing).
func is_targetable() -> bool:
	return is_alive() and current_vehicle == null


func in_party() -> bool:
	return Party.is_member(self)


func current_weapon() -> WeaponData:
	return weapons.current().data if weapons.current() else null


# --- Commands ------------------------------------------------------------------------------------

func set_mode(next: Mode) -> void:
	if mode == next:
		return
	if mode == Mode.DOWNED and next != Mode.DOWNED and health <= 0.0:
		return
	mode = next
	if next == Mode.HOLD:
		_hold_point = global_position
	if next != Mode.LEAD:
		_goal = null
	mode_changed.emit(next)


func follow() -> void:
	set_mode(Mode.FOLLOW)


## Stay here (fighting anything that comes close).
func hold(at: Variant = null) -> void:
	set_mode(Mode.HOLD)
	if at is Vector3:
		_hold_point = at


## Runs to [param target] (a point or node; a [Vehicle] means its passenger door), stopping to wait
## whenever the player lags more than [param wait_radius] behind. Returns [signal arrived], emitted
## once there with the player close, e.g. [code]await ally.lead_to(car)[/code].
func lead_to(destination: Variant, wait_radius := 8.0) -> Signal:
	return _start_goal(destination, wait_radius, true)


## Like [method lead_to] without waiting for the player.
func go_to(destination: Variant) -> Signal:
	return _start_goal(destination, 0.0, false)


## Walks to and boards [param vehicle] at [param seat] (-1: first free passenger seat). Returns
## false when there's no free seat. [signal boarded] fires once seated.
func enter_vehicle(vehicle: Vehicle, seat := -1) -> bool:
	if vehicle == null or not is_alive() or vehicle.is_wrecked():
		return false
	if current_vehicle == vehicle:
		return true
	if seat < 0:
		seat = _unclaimed_seat(vehicle)
	if seat < 0 or not vehicle.is_seat_free(seat):
		return false
	_board_vehicle = vehicle
	_board_seat = seat
	return true


## Climbs out of the current vehicle (animated) or cancels a pending boarding.
func exit_vehicle() -> void:
	_board_vehicle = null
	if current_vehicle != null:
		current_vehicle.begin_exit_seat(self)


func is_boarding() -> bool:
	return _board_vehicle != null


## Drives the current vehicle (must be in the driver's seat) to [param destination] with an
## [NpcDriver]; returns its [signal NpcDriver.arrived].
func drive_to(destination: Variant) -> Signal:
	assert(current_vehicle != null and current_vehicle.seat_of(self) == 0, "Ally must be driving")
	return NpcDriver.for_vehicle(current_vehicle).drive_to(destination)


func take_damage(amount: float, source: Node = null) -> void:
	if not is_alive() or _is_friendly(source):
		return
	health -= amount
	if health <= 0.0:
		health = 0.0
		go_down()
	elif visual != null:
		visual.hit()


## Knocked down: can be revived by the player (E) until the bleed-out timer runs out.
func go_down() -> void:
	if mode == Mode.DOWNED:
		return
	if current_vehicle != null:
		current_vehicle.exit_seat(self)
	cancel_moves()
	_board_vehicle = null
	target = null
	health = 0.0
	_bleed_left = bleed_out_time
	mode = Mode.DOWNED
	_collision.set_deferred("disabled", true)
	velocity = Vector3.ZERO
	visual.die()
	downed.emit()
	mode_changed.emit(mode)


func can_revive() -> bool:
	return mode == Mode.DOWNED


func revive() -> void:
	if mode != Mode.DOWNED:
		return
	health = max_health * 0.5
	visual.revive()
	mode = Mode.FOLLOW if in_party() else Mode.IDLE
	_hold_point = global_position
	_sync_collision()
	revived.emit()
	mode_changed.emit(mode)


func can_recruit() -> bool:
	return recruitable and is_alive() and not in_party() and Party.has_room()


func recruit() -> void:
	Party.recruit(self)


# --- Vehicle occupant interface -----------------------------------------------------------------

## Called by [Vehicle] when getting in or out.
func set_on_foot(on_foot: bool, vehicle: Vehicle = null) -> void:
	var previous := current_vehicle
	current_vehicle = null if on_foot else vehicle
	velocity = Vector3.ZERO
	_sync_collision()
	if on_foot:
		rotation = Vector3(0.0, rotation.y, 0.0)
		if not is_busy():
			visual.set_ride(null)
			visual.set_seated(0.0)
			visual.set_aiming(false)
		if previous != null:
			exited_vehicle.emit(previous)
	else:
		_board_vehicle = null
		visual.set_ride(vehicle, vehicle.ride_pose(maxi(0, vehicle.seat_of(self))))
		visual.set_seated(1.0)
		_follow_seat()
		if previous != vehicle:
			boarded.emit(vehicle, vehicle.seat_of(self))


func play_moves(steps: Array[Dictionary], done: Callable = Callable()) -> void:
	_scripted.play(steps, done)
	velocity = Vector3.ZERO
	_sync_collision()


func is_busy() -> bool:
	return _scripted != null and _scripted.is_busy()


func cancel_moves() -> void:
	_scripted.cancel()
	if current_vehicle == null:
		visual.set_ride(null)
		visual.set_seated(0.0)
	_sync_collision()


# --- Update -------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if current_vehicle != null and not is_busy():
		_follow_seat()
		visual.update_motion(Vector3.ZERO, delta)


func _physics_process(delta: float) -> void:
	if is_busy():
		var done := _scripted.step(delta)
		if done.is_valid():
			_sync_collision()
			done.call()
		return
	if current_vehicle != null:
		_ride_update(delta)
		return
	if mode == Mode.DOWNED:
		_downed_update(delta)
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_update_target(delta)

	var move := Vector3.ZERO
	var speed := run_speed
	if _board_vehicle != null:
		move = _board_update()
	elif mode == Mode.LEAD:
		move = _lead_update()
	elif mode == Mode.FOLLOW:
		var player := GameState.player
		if player != null and _maybe_teleport(player, delta):
			return
		var spot := Party.formation_point(self)
		var gap := _flat(spot - global_position).length()
		if gap > FOLLOW_STOP * 0.5:
			move = _flat(spot - global_position).normalized()
			speed = sprint_speed if gap > 10.0 else (run_speed if gap > 3.0 else walk_speed)
	elif mode == Mode.HOLD:
		var offset := _flat(_hold_point - global_position)
		if offset.length() > 1.0:
			move = offset.normalized()
			speed = walk_speed if offset.length() < 3.0 else run_speed
	if mode == Mode.LEAD and _wait_for_player and move == Vector3.ZERO:
		var player := GameState.player
		if player != null:
			_face(_flat(player.global_position - global_position))
	move = _detour(move, delta)
	velocity.x = move.x * speed
	velocity.z = move.z * speed
	var before := global_position
	move_and_slide()
	_track_progress(move, speed, before, delta)

	var fighting := target != null and _board_vehicle == null and mode != Mode.LEAD
	if fighting:
		var to_target := _flat(target.global_position - global_position)
		_face(to_target)
		var exclude: Array[RID] = [get_rid()]
		_update_attack(global_position + Vector3(0.0, 1.4, 0.0), exclude, delta)
	else:
		_face(move)
	visual.set_aiming(fighting)
	visual.update_motion(velocity, delta)


func _ride_update(delta: float) -> void:
	_update_target(delta)
	var seat := current_vehicle.seat_of(self)
	var shooting := seat > 0 and target != null and not current_vehicle.is_wrecked() \
			and current_vehicle.global_position.distance_to(target.global_position) <= drive_by_range
	visual.set_aiming(shooting)
	if shooting:
		var exclude: Array[RID] = [current_vehicle.get_rid()]
		for who in current_vehicle.occupants():
			if who is CollisionObject3D:
				exclude.append((who as CollisionObject3D).get_rid())
		_update_attack(current_vehicle.seat_muzzle(self), exclude, delta)


func _downed_update(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
		move_and_slide()
	_bleed_left -= delta
	if _bleed_left <= 0.0:
		_bleed_out()


## Gone for good (placeholder for a hospital/safehouse respawn): leaves the crew and turns up at
## the safehouse.
func _bleed_out() -> void:
	died.emit()
	Party.on_member_died(self)
	global_position = Party.safehouse_position
	revive()
	set_mode(Mode.IDLE)


func _update_target(delta: float) -> void:
	_retarget -= delta
	if _retarget > 0.0 and _valid_target(target):
		return
	_retarget = RETARGET_TIME
	target = _find_target()


## Nearest living rival within range of this ally or the player (the player's fight is ours).
func _find_target() -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	var player := GameState.player
	var origin := current_vehicle.global_position if current_vehicle != null else global_position
	var reach := drive_by_range if current_vehicle != null else engage_range
	for node in get_tree().get_nodes_in_group("gang_members"):
		var rival := node as GangMember
		if not _valid_target(rival):
			continue
		var distance := origin.distance_to(rival.global_position)
		var near_player := player != null and player.global_position.distance_to(rival.global_position) < engage_range
		if (distance < reach or near_player and distance < reach * 1.5) and distance < best_distance:
			best = rival
			best_distance = distance
	return best


func _valid_target(candidate: Node3D) -> bool:
	if candidate == null or not is_instance_valid(candidate):
		return false
	var rival := candidate as GangMember
	return rival != null and rival.is_alive() and rival.gang_id != gang_id


## Fires in bursts like [GangMember] so NPCs don't hold the trigger down.
func _update_attack(muzzle: Vector3, exclude: Array[RID], delta: float) -> void:
	if _burst_pause > 0.0:
		_burst_pause -= delta
		return
	var player := GameState.player
	if player != null:
		exclude.append(player.get_rid())
	for node in get_tree().get_nodes_in_group("allies"):
		exclude.append((node as CollisionObject3D).get_rid())
	var aim := target.global_position + Vector3(0.0, 1.0, 0.0) - muzzle
	visual.set_aim_pitch(atan2(aim.y, Vector2(aim.x, aim.z).length()))
	if not weapons.try_fire(self, muzzle, aim, exclude):
		return
	visual.fire()
	_burst_left -= 1
	if _burst_left <= 0:
		var weapon := current_weapon()
		_burst_left = randi_range(3, 6) if weapon != null and weapon.automatic else randi_range(1, 2)
		_burst_pause = randf_range(0.5, 1.2)


func _start_goal(destination: Variant, wait_radius: float, wait: bool) -> Signal:
	if mode != Mode.LEAD:
		_mode_before_goal = mode if mode != Mode.DOWNED else Mode.IDLE
	_goal = destination
	_wait_radius = wait_radius
	_wait_for_player = wait
	_goal_radius = 1.0 if destination is Vehicle else 2.0
	mode = Mode.LEAD
	mode_changed.emit(mode)
	return arrived


func _goal_point() -> Vector3:
	if _goal is Vehicle:
		var vehicle := _goal as Vehicle
		var seat := vehicle.free_seat(true)
		var info := vehicle.seat_info(maxi(seat, 1))
		var local: Vector3 = info.get("stand", Vector3(1.8, 0.0, 0.0))
		return vehicle.global_transform * local
	if _goal is Node3D:
		return (_goal as Node3D).global_position
	return _goal


func _lead_update() -> Vector3:
	if _goal is Object and not is_instance_valid(_goal):
		set_mode(_mode_before_goal)
		return Vector3.ZERO
	var offset := _flat(_goal_point() - global_position)
	var player := GameState.player
	var player_gap := _flat(player.global_position - global_position).length() if player != null else 0.0
	var player_close := not _wait_for_player or player_gap <= _wait_radius
	if offset.length() <= _goal_radius:
		if player_close:
			set_mode(_mode_before_goal if _mode_before_goal != Mode.LEAD else Mode.IDLE)
			_hold_point = global_position
			arrived.emit()
		return Vector3.ZERO
	if not player_close:
		return Vector3.ZERO
	return offset.normalized()


## Heads to the pending vehicle's door and starts the animated get-in once near; jumps straight in
## if the ride is already moving or out of sight.
func _board_update() -> Vector3:
	var vehicle := _board_vehicle
	if not is_instance_valid(vehicle) or vehicle.is_wrecked() or not vehicle.is_seat_free(_board_seat):
		var fallback := _unclaimed_seat(vehicle) if is_instance_valid(vehicle) and not vehicle.is_wrecked() else -1
		if fallback < 0:
			_board_vehicle = null
			return Vector3.ZERO
		_board_seat = fallback
	var info := vehicle.seat_info(_board_seat)
	var stand: Vector3 = vehicle.global_transform * (info.get("stand", Vector3.ZERO) as Vector3)
	var gap := _flat(stand - global_position).length()
	if vehicle.linear_velocity.length() > 4.0 or (gap > BOARD_RANGE * 3.0 and not _on_screen()):
		vehicle.enter_seat(self, _board_seat)
		return Vector3.ZERO
	if gap <= BOARD_RANGE:
		vehicle.begin_enter_seat(self, _board_seat)
		_board_vehicle = null
		return Vector3.ZERO
	return _flat(stand - global_position).normalized() * (sprint_speed / run_speed)


## Very small obstacle handling (there's no navmesh): when walking into something (a parked car, a
## wall) makes no progress for a moment, sidestep for a bit, then try straight again.
func _detour(move: Vector3, delta: float) -> Vector3:
	if move == Vector3.ZERO:
		_detour_left = 0.0
		return move
	if _detour_left > 0.0:
		_detour_left -= delta
		return (move.normalized() * 0.35 + move.cross(Vector3.UP).normalized() * _detour_side).normalized() * move.length()
	return move


func _track_progress(move: Vector3, speed: float, before: Vector3, delta: float) -> void:
	var wanted := _flat(move).length() * speed * delta
	if wanted <= 0.0 or _detour_left > 0.0:
		_blocked = 0.0
		return
	if _flat(global_position - before).length() < wanted * 0.3:
		_blocked += delta
		if _blocked > 0.25:
			_blocked = 0.0
			_detour_left = DETOUR_TIME
			_detour_side = 1.0 if randf() < 0.5 else -1.0
	else:
		_blocked = 0.0


## First free passenger seat no other ally is already heading for.
func _unclaimed_seat(vehicle: Vehicle) -> int:
	for seat in range(1, vehicle.seat_count()):
		if not vehicle.is_seat_free(seat):
			continue
		var claimed := false
		for node in get_tree().get_nodes_in_group("allies"):
			var other := node as Ally
			if other != self and other._board_vehicle == vehicle and other._board_seat == seat:
				claimed = true
		if not claimed:
			return seat
	return -1


func _maybe_teleport(player: Player, delta: float) -> bool:
	var distance := global_position.distance_to(player.global_position)
	if distance > offscreen_teleport_distance and not _on_screen():
		_offscreen += delta
	else:
		_offscreen = 0.0
	if distance < teleport_distance and _offscreen < offscreen_teleport_time:
		return false
	_offscreen = 0.0
	if not player.is_on_foot():
		return false
	global_position = Party.formation_point(self) + Vector3.UP * 0.3
	velocity = Vector3.ZERO
	return true


func _on_screen() -> bool:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	return camera == null or camera.is_position_in_frustum(global_position + Vector3.UP)


func _is_friendly(source: Node) -> bool:
	if source == null:
		return false
	if source is Player or source is Ally:
		return true
	if source is GangMember:
		return (source as GangMember).gang_id == gang_id
	return source is Vehicle and ((source as Vehicle).has_player() or (source as Vehicle).seat_of(self) >= 0)


func _follow_seat() -> void:
	global_transform = current_vehicle.global_transform * current_vehicle.seat_transform(maxi(0, current_vehicle.seat_of(self)))


func _sync_collision() -> void:
	ScriptedMoves.sync_collision(_collision, _collision_wanted(), _collision_wanted)


func _collision_wanted() -> bool:
	return current_vehicle == null and not is_busy() and mode != Mode.DOWNED


func _face(direction: Vector3) -> void:
	if direction.length_squared() > 0.01:
		rotation.y = atan2(-direction.x, -direction.z)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _build_body() -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	_collision = CollisionShape3D.new()
	_collision.shape = capsule
	_collision.position.y = 0.9
	add_child(_collision)
	var color := GameState.gang_color(gang_id)
	visual = CharacterVisual.create(&"crew", visual_seed if visual_seed >= 0 else randi())
	visual.set_tint(color.darkened(0.2))
	visual.set_bandana(color)
	visual.set_weapon(current_weapon())
	add_child(visual)


func _build_interactable() -> void:
	interactable = Interactable.new()
	interactable.name = "Interactable"
	interactable.radius = 2.0
	interactable.prompt_name = display_name
	var revive_condition := MethodCondition.create(&"can_revive")
	revive_condition.hide_when_unmet = true
	var revive_conditions: Array[Condition] = [revive_condition]
	var revive_effects: Array[Effect] = [MethodEffect.create(&"revive")]
	var revive_action := InteractionAction.create(&"revive", "Revive", revive_effects, revive_conditions)
	revive_action.duration = revive_time
	revive_action.progress_text = "Reviving..."
	revive_action.priority = 10
	interactable.add_action(revive_action)
	var recruit_condition := MethodCondition.create(&"can_recruit")
	recruit_condition.hide_when_unmet = true
	var recruit_conditions: Array[Condition] = [recruit_condition]
	var recruit_effects: Array[Effect] = [MethodEffect.create(&"recruit")]
	interactable.add_action(InteractionAction.create(&"recruit", "Recruit", recruit_effects, recruit_conditions))
	add_child(interactable)
