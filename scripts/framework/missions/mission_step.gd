class_name MissionStep
extends Resource
## One objective in a [MissionDef]. Steps are authored as data (sub-resources in a mission .tres) and
## cloned for every run, so runtime state on them is per run.
##
## Lifecycle, driven by [MissionRun]: start() -> tick()/handle() until the step calls complete() or
## fail(). Subclasses override _begin, _tick, _handle (mission events, see [MissionService]), _end,
## _progress (e.g. "2/3") and _waypoint (Vector3 or null).

signal completed(step: MissionStep)
signal step_changed(step: MissionStep)

enum State { PENDING, ACTIVE, DONE, FAILED }

@export var id: StringName
## HUD objective text. Supports {vars} from the run's ActionContext.
@export_multiline var text := ""
## Optional steps don't block an [AllOfStep] or the mission; as side objectives they're bonuses.
@export var optional := false
## Hide this step's text from the HUD (e.g. silent bookkeeping steps).
@export var hidden := false
## Save a checkpoint when this step starts; retries resume here.
@export var checkpoint := false
## Waypoint override: a TriggerZone zone_id or a mission tag (see MissionService.locate).
@export var waypoint: StringName
## Seconds to finish this step; 0 = no limit.
@export var time_limit := 0.0
@export var time_limit_text := "You ran out of time."
@export var on_start: Array[Effect] = []
@export var on_complete: Array[Effect] = []
## Fail rules active only while this step runs.
@export var fail_conditions: Array[MissionFail] = []
## Given when the mission completes if this (side/optional) step was achieved.
@export var bonus_rewards: Array[Effect] = []

var state := State.PENDING
var run: MissionRun
var elapsed := 0.0
## Why the step failed (side objectives only; main steps fail the run).
var fail_reason := ""


## A fresh copy for a new run. Subclasses holding nested steps override _post_clone.
func clone() -> MissionStep:
	var copy: MissionStep = duplicate()
	var rules: Array[MissionFail] = []
	for rule in fail_conditions:
		if rule != null:
			rules.append(rule.clone())
	copy.fail_conditions = rules
	_post_clone(copy)
	return copy


func start(mission_run: MissionRun) -> void:
	run = mission_run
	state = State.ACTIVE
	elapsed = 0.0
	fail_reason = ""
	Effect.apply_all(on_start, run.ctx)
	_begin()


func tick(delta: float) -> void:
	if state != State.ACTIVE:
		return
	elapsed += delta
	if time_limit > 0.0 and elapsed >= time_limit:
		fail(time_limit_text)
		return
	for rule in fail_conditions:
		var reason := rule.check(run, delta)
		if reason != "":
			fail(reason)
			return
	_tick(delta)


func handle(event: Dictionary) -> void:
	if state != State.ACTIVE:
		return
	for rule in fail_conditions:
		var reason := rule.handle(event, run)
		if reason != "":
			fail(reason)
			return
	_handle(event)


func complete() -> void:
	if state != State.ACTIVE:
		return
	state = State.DONE
	_end()
	Effect.apply_all(on_complete, run.ctx)
	completed.emit(self)


## Main steps fail the whole mission; side objectives just mark themselves missed.
func fail(reason: String) -> void:
	if state != State.ACTIVE:
		return
	state = State.FAILED
	fail_reason = reason
	_end()
	if run != null and (run.is_side(self) or optional):
		step_changed.emit(self)
	elif run != null:
		run.fail(reason)


## Stops the step without completing it (mission ended, failed or retried).
func abort() -> void:
	if state == State.ACTIVE:
		state = State.PENDING
		_end()


func is_active() -> bool:
	return state == State.ACTIVE


func is_done() -> bool:
	return state == State.DONE


func display_text() -> String:
	var line := run.ctx.format(text) if run != null else text
	var progress := _progress()
	if progress != "":
		line += " (%s)" % progress
	if time_limit > 0.0 and state == State.ACTIVE:
		line += " [%d s]" % ceili(time_limit - elapsed)
	return line


## HUD lines: [{text, done, failed, optional}]. Groups return one per child.
func objective_lines() -> Array[Dictionary]:
	if hidden:
		return []
	return [{"text": display_text(), "done": state == State.DONE, "failed": state == State.FAILED, "optional": optional}]


## World position for the HUD waypoint, or null.
func waypoint_position() -> Variant:
	if waypoint != &"":
		return Missions.locate(waypoint)
	return _waypoint()


## Mark the HUD dirty after progress changes.
func notify_changed() -> void:
	step_changed.emit(self)


func _post_clone(_copy: MissionStep) -> void:
	pass


func _begin() -> void:
	pass


func _tick(_delta: float) -> void:
	pass


func _handle(_event: Dictionary) -> void:
	pass


func _end() -> void:
	pass


func _progress() -> String:
	return ""


func _waypoint() -> Variant:
	return null


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if text == "" and not hidden:
		problems.append("step %s has no text" % id)
	return problems
