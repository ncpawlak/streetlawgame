extends Node
## The player's crew (Saints Row style homies): up to [member max_followers] [Ally] NPCs that follow
## in formation, take commands and pile into the player's vehicle with them. Missions recruit with
## [method recruit] and steer individual allies directly ([method Ally.lead_to], ...).
## Crew command key (H): tap toggles follow / hold, hold [constant COMMAND_HOLD_TIME] s to dismiss.

signal member_joined(ally: Ally)
signal member_left(ally: Ally)
signal command_issued(command: StringName)

const COMMAND_HOLD_TIME := 0.8
## Formation slots behind the player, in the player's space (+Z is behind; +X the player's right).
const FORMATION: Array[Vector3] = [Vector3(-1.6, 0.0, 1.8), Vector3(1.6, 0.0, 1.8), Vector3(0.0, 0.0, 3.2),
	Vector3(-2.6, 0.0, 3.6), Vector3(2.6, 0.0, 3.6)]

var max_followers := 3
## Where allies who bleed out turn up (placeholder until safehouses own respawns).
var safehouse_position := Vector3.ZERO
## Followers get in (and out) with the player.
var auto_board := true
var members: Array[Ally] = []

var _player_vehicle: Vehicle
var _command_held := -1.0


func has_room() -> bool:
	_prune()
	return members.size() < max_followers


func is_member(ally: Ally) -> bool:
	return members.has(ally)


## Adds [param ally] to the crew and has them follow. False when full, dead or already in.
func recruit(ally: Ally) -> bool:
	if ally == null or is_member(ally) or not has_room() or not ally.is_alive():
		return false
	members.append(ally)
	ally.follow()
	member_joined.emit(ally)
	EventBus.notify.emit("%s joined your crew" % ally.display_name)
	return true


## Lets [param ally] go: they get out of the player's ride and idle where they are.
func dismiss(ally: Ally) -> void:
	if not is_member(ally):
		return
	members.erase(ally)
	if is_instance_valid(ally):
		if ally.is_boarding() or ally.current_vehicle != null and ally.current_vehicle == _player_vehicle:
			ally.exit_vehicle()
		ally.set_mode(Ally.Mode.IDLE)
	member_left.emit(ally)


func dismiss_all() -> void:
	for ally in members.duplicate():
		dismiss(ally)


## [code]&"follow"[/code], [code]&"hold"[/code], [code]&"dismiss"[/code] or [code]&"toggle"[/code]
## (hold if anyone follows, else follow).
func command_all(command: StringName) -> void:
	_prune()
	if command == &"toggle":
		command = &"hold" if members.any(func(a: Ally) -> bool: return a.mode == Ally.Mode.FOLLOW) else &"follow"
	match command:
		&"follow":
			for ally in members:
				if ally.is_alive():
					ally.follow()
			EventBus.notify.emit("Crew: follow me")
		&"hold":
			for ally in members:
				if ally.is_alive() and ally.current_vehicle == null:
					ally.hold()
			EventBus.notify.emit("Crew: hold here")
		&"dismiss":
			dismiss_all()
			EventBus.notify.emit("Crew dismissed")
	command_issued.emit(command)


func formation_slot(ally: Ally) -> int:
	return maxi(0, members.find(ally))


## World point [param ally] follows: their slot behind the player (their own position with no player).
func formation_point(ally: Ally) -> Vector3:
	var player := GameState.player
	if player == null or not is_instance_valid(player):
		return ally.global_position
	var slot := FORMATION[formation_slot(ally) % FORMATION.size()]
	return player.global_position + Basis(Vector3.UP, player.global_rotation.y) * slot


func on_member_died(ally: Ally) -> void:
	dismiss(ally)
	EventBus.notify.emit("%s is out of action" % ally.display_name)


## Drops everyone without side effects (tests, new game).
func clear() -> void:
	members.clear()
	_player_vehicle = null
	_command_held = -1.0


func _process(delta: float) -> void:
	if members.is_empty() or not InputMap.has_action("crew_command"):
		_command_held = -1.0
		return
	if Input.is_action_just_pressed("crew_command"):
		_command_held = 0.0
	elif _command_held >= 0.0:
		if Input.is_action_pressed("crew_command"):
			_command_held += delta
			if _command_held >= COMMAND_HOLD_TIME:
				_command_held = -1.0
				command_all(&"dismiss")
		else:
			_command_held = -1.0
			command_all(&"toggle")


func _physics_process(_delta: float) -> void:
	_prune()
	var player := GameState.player
	if not auto_board or player == null or not is_instance_valid(player):
		return
	var vehicle := player.current_vehicle
	if vehicle == null and player.is_busy():
		vehicle = _vehicle_reserved_by(player)
	if vehicle == _player_vehicle:
		return
	var previous := _player_vehicle
	_player_vehicle = vehicle
	if vehicle != null:
		_board_followers(vehicle)
	elif is_instance_valid(previous):
		_unload_followers(previous)


func _board_followers(vehicle: Vehicle) -> void:
	for ally in members:
		if ally.mode != Ally.Mode.FOLLOW or ally.current_vehicle == vehicle:
			continue
		if not ally.enter_vehicle(vehicle):
			EventBus.notify.emit("No room for %s" % ally.display_name)


func _unload_followers(vehicle: Vehicle) -> void:
	for ally in members:
		if ally.mode != Ally.Mode.FOLLOW:
			continue
		if ally.current_vehicle == vehicle or ally.is_boarding():
			ally.exit_vehicle()


## The vehicle [param who] is climbing into, or null.
func _vehicle_reserved_by(who: Node3D) -> Vehicle:
	for node in get_tree().get_nodes_in_group("vehicles"):
		var vehicle := node as Vehicle
		if vehicle != null and vehicle.reserved_seat_of(who) >= 0:
			return vehicle
	return null


func _prune() -> void:
	for i in range(members.size() - 1, -1, -1):
		if not is_instance_valid(members[i]):
			members.remove_at(i)
