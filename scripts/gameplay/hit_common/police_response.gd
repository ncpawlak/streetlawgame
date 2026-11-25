class_name PoliceResponse
extends Node3D
## Sends cops when its [PoliceCall] fires and decides when the player has escaped.
## Spawn points are this node's [Marker3D] children (or [member spawn_points], in global space).
## Escape: be farther than [member search_radius] from where a cop last saw you AND stay unseen for
## [member lose_time] seconds. Dying while wanted is a bust: the bag is lost.

signal cops_arrived(count: int)
signal player_spotted
signal escaped
signal busted

@export var police_call: PoliceCall
@export var cops_per_wave := 3
## Extra cops on each wave after the first.
@export var wave_growth := 1
## Seconds before reinforcements when every cop is down.
@export var reinforcement_delay := 8.0
@export var search_radius := 50.0
@export var lose_time := 12.0
## Park a police cruiser at the first spawn point.
@export var spawn_cruiser := true
## Global positions cops spawn at (used when there are no Marker3D children).
@export var spawn_points: Array[Vector3] = []

var wanted := false
var last_seen := Vector3.ZERO
## Seconds since a cop last saw the player.
var unseen_time := 0.0
var cops: Array[Cop] = []
var waves := 0

var _seen := false
var _reinforce_left := -1.0
var _cruisers: Array[Node] = []


func _ready() -> void:
	if police_call != null:
		police_call.police_called.connect(func(_why: StringName) -> void: dispatch())
	EventBus.player_died.connect(_on_player_died)


func _physics_process(delta: float) -> void:
	if wanted:
		update(delta)


func is_wanted() -> bool:
	return wanted


func alive_cops() -> Array[Cop]:
	var result: Array[Cop] = []
	for cop in cops:
		if is_instance_valid(cop) and cop.is_alive():
			result.append(cop)
	return result


## Sends a wave of cops now (normally triggered by the police call).
func dispatch() -> void:
	var player := GameState.player
	if not wanted:
		wanted = true
		waves = 0
		unseen_time = 0.0
		last_seen = player.get_focus_position() if player != null else global_position
	var points := _spawn_points()
	var count := cops_per_wave + waves * wave_growth
	waves += 1
	for i in count:
		var point: Vector3 = points[i % points.size()] + Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5))
		var cop := Cop.new()
		cop.position = to_local(point) + Vector3(0.0, 0.2, 0.0)
		add_child(cop)
		cop.search_at(last_seen)
		cop._alert_left = cop.alert_duration * 3.0
		cops.append(cop)
	if spawn_cruiser and waves == 1:
		var cruiser := Vehicle.new()
		cruiser.body_color = Color(0.92, 0.92, 0.95)
		cruiser.position = to_local(points[0] + Vector3(3.0, 0.6, 0.0))
		add_child(cruiser)
		cruiser.add_to_group("police_cars")
		_cruisers.append(cruiser)
	EventBus.notify.emit("Cops on scene!" if waves == 1 else "Police reinforcements!")
	cops_arrived.emit(count)


## Advances the chase by [param delta] seconds (called every physics frame while wanted).
func update(delta: float) -> void:
	var player := GameState.player
	if player == null:
		return
	var target: Node3D = player if player.is_on_foot() else player.current_vehicle
	var seen := false
	for cop in alive_cops():
		if cop.can_see(target):
			seen = true
			break
	if seen:
		last_seen = target.global_position
		unseen_time = 0.0
		for cop in alive_cops():
			cop.search_at(last_seen)
		if not _seen:
			player_spotted.emit()
	else:
		unseen_time += delta
	_seen = seen
	if alive_cops().is_empty():
		if _reinforce_left < 0.0:
			_reinforce_left = reinforcement_delay
		_reinforce_left -= delta
		if _reinforce_left <= 0.0:
			_reinforce_left = -1.0
			dispatch()
	if unseen_time >= lose_time and target.global_position.distance_to(last_seen) > search_radius:
		_escape()


func is_seen() -> bool:
	return _seen


## Fraction toward losing the cops (0..1), for the HUD.
func escape_progress() -> float:
	return clampf(unseen_time / lose_time, 0.0, 1.0) if wanted else 0.0


func status_text() -> String:
	if not wanted:
		return ""
	if _seen:
		return "WANTED - you've been spotted"
	var player := GameState.player
	var far := player != null and player.get_focus_position().distance_to(last_seen) > search_radius
	return "WANTED - %s (%d%%)" % ["lying low" if far else "leave the search area", int(escape_progress() * 100.0)]


## Ends the chase: cops leave, the call resets.
func stand_down() -> void:
	wanted = false
	_seen = false
	unseen_time = 0.0
	_reinforce_left = -1.0
	for cop in cops:
		if is_instance_valid(cop):
			cop.queue_free()
	cops.clear()
	for cruiser in _cruisers:
		if is_instance_valid(cruiser) and (cruiser as Vehicle).driver == null:
			cruiser.queue_free()
	_cruisers.clear()
	if police_call != null:
		police_call.reset()


func _escape() -> void:
	stand_down()
	EventBus.notify.emit("You lost the cops")
	escaped.emit()


func _on_player_died() -> void:
	if not wanted and (police_call == null or not police_call.is_active()):
		return
	var bag := CarryBag.of(GameState.player, false)
	if bag != null:
		bag.drop()
	stand_down()
	EventBus.notify.emit("BUSTED - the bag is gone")
	busted.emit()


func _spawn_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for child in get_children():
		if child is Marker3D:
			points.append((child as Marker3D).global_position)
	if points.is_empty():
		points = spawn_points.duplicate()
	if points.is_empty():
		points.append(global_position)
	return points
