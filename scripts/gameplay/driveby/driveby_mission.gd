class_name DriveByMission
extends Node
## Drive-by flow: roll up on a rival corner, hit the crew from the car, then lose the retaliation.
##
## APPROACH   - drive to the corner. Shooting (or killing) any crew member sets it off.
## RETALIATION - the crew fights back; after [member pile_in_delay] survivors near the parked rival
##               cars jump in and chase. If nobody's left to drive, backup rolls out instead.
## Escape     - once [member required_kills] rivals are down, stay out of every pursuer's sight
##               (distance or a building in the way) for [member escape_time] seconds.
## COMPLETE / FAILED - escaped, or the player died.

signal phase_changed(phase: Phase)
signal completed(kills: int)
signal failed(reason: String)

enum Phase { APPROACH, RETALIATION, COMPLETE, FAILED }

@export var required_kills := 1
## Seconds out of every pursuer's sight needed to get away.
@export var escape_time := 5.0
## Pursuers further than this can't see you, walls or not.
@export var sight_range := 60.0
## Seconds after the hit before survivors pile into the cars.
@export var pile_in_delay := 2.0
## Survivors this close to a parked car can get in.
@export var board_radius := 25.0
@export var seats_per_car := 2
## Occupants of the backup car that rolls out when no survivor could reach a car.
@export var backup_occupants := 2
@export var reward_cash := 250
@export var reward_respect := 50

var phase := Phase.APPROACH
var crew: Array[GangMember] = []
var cars: Array[ChaseCar] = []
var kills := 0
## Seconds the player has been out of sight (0 while anyone can see them).
var unseen_time := 0.0

var _pile_in_left := -1.0


## Hooks the mission up to the corner crew and the rival cars parked by it.
func setup(corner_crew: Array[GangMember], rival_cars: Array[ChaseCar]) -> void:
	crew = corner_crew
	cars = rival_cars


func _ready() -> void:
	EventBus.gang_member_killed.connect(_on_gang_member_killed)
	EventBus.player_died.connect(_on_player_died)


func _physics_process(delta: float) -> void:
	match phase:
		Phase.APPROACH:
			if _crew_hit():
				start_retaliation()
		Phase.RETALIATION:
			if _pile_in_left > 0.0:
				_pile_in_left -= delta
				if _pile_in_left <= 0.0:
					_pile_in()
			if is_seen():
				unseen_time = 0.0
			else:
				unseen_time += delta
			if can_escape() and unseen_time >= escape_time:
				_complete()


func start_retaliation() -> void:
	if phase != Phase.APPROACH:
		return
	unseen_time = 0.0
	_set_phase(Phase.RETALIATION)
	EventBus.notify.emit("The Vipers are coming for you - get out of there!")
	_pile_in_left = pile_in_delay if not cars.is_empty() else -1.0


## Whether enough damage is done that getting away completes the job.
func can_escape() -> bool:
	return kills >= required_kills


func living_crew() -> Array[GangMember]:
	var alive: Array[GangMember] = []
	for member in crew:
		if is_instance_valid(member) and member.is_alive():
			alive.append(member)
	return alive


func chasing_cars() -> Array[ChaseCar]:
	var chasing: Array[ChaseCar] = []
	for car in cars:
		if is_instance_valid(car) and car.is_chasing():
			chasing.append(car)
	return chasing


## True while any surviving crew member or chasing car has the player in sight.
func is_seen() -> bool:
	var player := GameState.player
	if player == null:
		return false
	var focus := player.get_focus_position() + Vector3.UP
	var pursuers: Array[Node3D] = []
	pursuers.append_array(living_crew())
	pursuers.append_array(chasing_cars())
	for pursuer in pursuers:
		var eye := pursuer.global_position + Vector3.UP * 1.5
		if eye.distance_to(focus) <= sight_range and line_of_sight(self, eye, focus):
			return true
	return false


func objective_text() -> String:
	match phase:
		Phase.APPROACH:
			return "Roll up on the Red Vipers corner and light it up"
		Phase.RETALIATION:
			if not can_escape():
				return "Drop %d more Viper(s) - then get out of there" % (required_kills - kills)
			return "Lose the Vipers: stay out of sight (%.1f / %.0fs)" % [unseen_time, escape_time]
		Phase.COMPLETE:
			return "Drive-by complete - %d Viper(s) down. +$%d" % [kills, reward_cash]
		_:
			return "Drive-by failed"


## True when nothing hostile with line of sight is between [param from] and [param to]: only
## world geometry (buildings, walls, ground) blocks the view.
static func line_of_sight(context: Node, from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	return context.get_viewport().find_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _crew_hit() -> bool:
	for member in crew:
		if not is_instance_valid(member) or not member.is_alive() or member.health < member.max_health:
			return true
	return false


## Survivors near each parked car get in and it rolls out. If no car got anyone, backup takes
## the first car that still runs.
func _pile_in() -> void:
	var rolled := 0
	for car in cars:
		if not is_instance_valid(car) or car.is_wrecked() or car.driver != null:
			continue
		var riders := _board(car)
		if riders > 0:
			car.roll_out(riders)
			rolled += 1
	if rolled == 0:
		for car in cars:
			if is_instance_valid(car) and not car.is_wrecked() and car.driver == null:
				car.roll_out(backup_occupants)
				EventBus.notify.emit("Viper backup is rolling out!")
				return
	else:
		EventBus.notify.emit("The Vipers piled into their cars - %d on your tail" % rolled)


## Takes up to [member seats_per_car] living crew near [param car] off the street. Returns how many.
func _board(car: ChaseCar) -> int:
	var nearby := living_crew().filter(func(member: GangMember) -> bool:
		return member.global_position.distance_to(car.global_position) <= board_radius)
	nearby.sort_custom(func(a: GangMember, b: GangMember) -> bool:
		return a.global_position.distance_to(car.global_position) < b.global_position.distance_to(car.global_position))
	var count := mini(seats_per_car, nearby.size())
	for i in count:
		var member: GangMember = nearby[i]
		crew.erase(member)
		member.queue_free()
	return count


func _on_gang_member_killed(member: GangMember, _killer: Node) -> void:
	if crew.has(member) and phase != Phase.COMPLETE and phase != Phase.FAILED:
		kills += 1
		if phase == Phase.APPROACH:
			start_retaliation()


func _on_player_died() -> void:
	if phase == Phase.APPROACH or phase == Phase.RETALIATION:
		_set_phase(Phase.FAILED)
		failed.emit("You got smoked")


func _complete() -> void:
	GameState.add_cash(reward_cash)
	GameState.add_respect(reward_respect)
	_set_phase(Phase.COMPLETE)
	EventBus.notify.emit("Drive-by complete! +$%d, +%d respect" % [reward_cash, reward_respect])
	completed.emit(kills)


func _set_phase(next: Phase) -> void:
	phase = next
	phase_changed.emit(next)
