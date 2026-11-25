class_name ScriptedMoves
extends RefCounted
## Plays scripted moves on a character body (getting in and out of vehicles), shared by the player
## and NPC occupants. Each step is a Dictionary:
## [code]to[/code] (Transform3D, in [code]frame[/code]'s space when given, else world),
## [code]time[/code] (seconds), [code]walk[/code] (animate walking), [code]arc[/code] (hop height),
## [code]seated[/code] (0..1, see [method CharacterVisual.set_seated]),
## [code]reach[/code] ([side, Node3D, weight]: a hand to a moving target such as a door handle) and
## [code]call[/code] (Callable run as the step starts).

var body: Node3D
var visual: CharacterVisual
## Called when a move's frame vanishes mid-sequence (e.g. the vehicle was freed).
var on_abort := Callable()

var _moves: Array[Dictionary] = []
var _move := {}
var _move_t := 0.0
var _move_from := Transform3D.IDENTITY
var _done := Callable()
var _reach_from := 0.0
var _reach_weight := 0.0


## Turns a character's collision off at once, or back on one physics frame later. A body that was
## teleported out of a seat while its shape was off would otherwise sweep from the seat to its new
## spot during the next physics step (kinematic bodies move to their target) and fling the vehicle.
## [param wanted] is re-checked before enabling so a quick re-entry keeps it off.
static func sync_collision(shape: CollisionShape3D, enabled: bool, wanted: Callable) -> void:
	if shape == null:
		return
	if not enabled:
		shape.set_deferred("disabled", true)
		return
	if not shape.disabled or not shape.is_inside_tree():
		return
	await shape.get_tree().physics_frame
	if is_instance_valid(shape) and wanted.call():
		shape.set_deferred("disabled", false)


func _init(owner_body: Node3D, owner_visual: CharacterVisual) -> void:
	body = owner_body
	visual = owner_visual


func play(steps: Array[Dictionary], done: Callable = Callable()) -> void:
	_moves = steps.duplicate()
	_move = {}
	_done = done


func is_busy() -> bool:
	return not _move.is_empty() or not _moves.is_empty()


## Drops queued moves (without calling their completion) and lets go of reaches.
func cancel() -> void:
	_moves.clear()
	_move = {}
	_done = Callable()
	_reach_weight = 0.0
	for side: StringName in [&"L", &"R"]:
		visual.set_reach(side, Vector3.ZERO, 0.0)


## Advances the current move. Returns the completion Callable once the last move ends (the caller
## restores collision first, then calls it), otherwise an invalid Callable.
func step(delta: float) -> Callable:
	if _move.is_empty():
		if _moves.is_empty():
			return Callable()
		_move = _moves.pop_front()
		_move_t = 0.0
		if _move.has("frame") and not is_instance_valid(_move["frame"]):
			_abort()
			return Callable()
		var start_frame := _move.get("frame") as Node3D
		_move_from = start_frame.global_transform.affine_inverse() * body.global_transform if start_frame else body.global_transform
		if _move.has("call"):
			(_move["call"] as Callable).call()
		if _move.has("seated"):
			visual.set_seated(_move["seated"])
		_reach_from = _reach_weight
	if _move.is_empty() or _move.has("frame") and not is_instance_valid(_move["frame"]):
		_abort()
		return Callable()
	var frame := _move.get("frame") as Node3D
	_move_t = minf(1.0, _move_t + delta / maxf(0.01, _move.get("time", 0.3)))
	var eased := smoothstep(0.0, 1.0, _move_t)
	var local: Transform3D = _move_from.interpolate_with(_move.get("to", _move_from), eased)
	local.origin.y += _move.get("arc", 0.0) * sin(PI * _move_t)
	var before := body.global_position
	body.global_transform = frame.global_transform * local if frame else local
	visual.set_aiming(false)
	visual.update_motion((body.global_position - before) / delta if _move.get("walk", false) and delta > 0.0 else Vector3.ZERO, delta)
	if _move.has("reach"):
		var reach: Array = _move["reach"]
		_reach_weight = lerpf(_reach_from, reach[2], eased)
		visual.set_reach(reach[0], (reach[1] as Node3D).global_position, _reach_weight)
		if _reach_weight <= 0.0:
			visual.set_reach(reach[0], Vector3.ZERO, 0.0)
	if _move_t < 1.0:
		return Callable()
	_move = {}
	if not _moves.is_empty():
		return Callable()
	var done := _done
	_done = Callable()
	# A valid no-op tells the caller the sequence finished even without a completion callback.
	return done if done.is_valid() else _noop


func _abort() -> void:
	cancel()
	if on_abort.is_valid():
		on_abort.call()


func _noop() -> void:
	pass
