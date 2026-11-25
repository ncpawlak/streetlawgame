class_name MissionRun
extends RefCounted
## One playthrough of a [MissionDef]: cloned steps, the shared ActionContext/vars, side objectives,
## bonuses and the last checkpoint. Owned and ticked by the Missions autoload ([MissionService]).

signal objective_changed
signal finished(run: MissionRun)

enum State { RUNNING, COMPLETED, FAILED, ABANDONED }

var def: MissionDef
var steps: Array[MissionStep] = []
var side: Array[MissionStep] = []
var fail_rules: Array[MissionFail] = []
var index := -1
var state := State.RUNNING
var ctx: ActionContext
var elapsed := 0.0
var fail_reason := ""
## [{id, label, achieved}] - clean deliveries, side objectives... shown on the result screen.
var bonuses: Array[Dictionary] = []
## {index, vars, position, items} saved when a checkpoint step starts.
var checkpoint: Dictionary = {}
## Number of retries so far.
var attempt := 0


func _init(mission: MissionDef) -> void:
	def = mission
	for step in mission.steps:
		if step != null:
			steps.append(step.clone())
	for step in mission.side_objectives:
		if step != null:
			side.append(step.clone())
	for rule in mission.fail_conditions:
		if rule != null:
			fail_rules.append(rule.clone())
	if mission.fail_on_death:
		var died := PlayerDiedFail.new()
		fail_rules.append(died)
	ctx = ActionContext.new(GameState.player)


## Starts at [param start_index] (0, or a checkpoint on retry) with [param vars] restored.
func begin(start_index := 0, vars: Dictionary = {}) -> void:
	ctx.vars.merge(vars, true)
	ctx.vars["mission"] = def.label()
	for step in side:
		step.step_changed.connect(_on_step_changed)
		step.completed.connect(_on_side_completed)
		step.start(self)
	_enter(start_index)


func current_step() -> MissionStep:
	return steps[index] if index >= 0 and index < steps.size() else null


func find_step(step_id: StringName) -> MissionStep:
	for step in steps + side:
		if step.id == step_id:
			return step
	return null


func is_running() -> bool:
	return state == State.RUNNING


func is_side(step: MissionStep) -> bool:
	return side.has(step)


func tick(delta: float) -> void:
	if state != State.RUNNING:
		return
	elapsed += delta
	for rule in fail_rules:
		var reason := rule.check(self, delta)
		if reason != "":
			fail(reason)
			return
	for step in side:
		step.tick(delta)
	var step := current_step()
	if step != null:
		step.tick(delta)


func handle(event: Dictionary) -> void:
	if state != State.RUNNING:
		return
	for rule in fail_rules:
		var reason := rule.handle(event, self)
		if reason != "":
			fail(reason)
			return
	for step in side:
		step.handle(event)
		if state != State.RUNNING:
			return
	var step := current_step()
	if step != null:
		step.handle(event)


## HUD lines for the current objective and side objectives: [{text, done, failed, optional, bonus}].
func objective_lines() -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	var step := current_step()
	if step != null:
		lines.append_array(step.objective_lines())
	for side_step in side:
		for line in side_step.objective_lines():
			line["bonus"] = true
			lines.append(line)
	return lines


func waypoint_position() -> Variant:
	var step := current_step()
	return step.waypoint_position() if step != null else null


func add_bonus(bonus_id: StringName, label: String, achieved: bool) -> void:
	for bonus in bonuses:
		if bonus["id"] == bonus_id:
			bonus["label"] = label
			bonus["achieved"] = achieved
			objective_changed.emit()
			return
	bonuses.append({"id": bonus_id, "label": label, "achieved": achieved})
	objective_changed.emit()


func fail(reason: String) -> void:
	if state != State.RUNNING:
		return
	state = State.FAILED
	fail_reason = reason
	_stop_steps()
	finished.emit(self)


func abandon() -> void:
	if state != State.RUNNING:
		return
	state = State.ABANDONED
	fail_reason = "Abandoned."
	_stop_steps()
	finished.emit(self)


func _enter(step_index: int) -> void:
	if state != State.RUNNING:
		return
	index = step_index
	var step := current_step()
	if step == null:
		_complete()
		return
	if step.checkpoint or checkpoint.is_empty():
		_save_checkpoint(step_index)
	step.completed.connect(_on_step_completed, CONNECT_ONE_SHOT)
	step.step_changed.connect(_on_step_changed)
	objective_changed.emit()
	step.start(self)


func _on_step_completed(step: MissionStep) -> void:
	if state != State.RUNNING or step != current_step():
		return
	Missions.step_completed.emit(def.id, step.id)
	_enter(index + 1)


func _on_side_completed(step: MissionStep) -> void:
	add_bonus(step.id, step.display_text(), true)
	Missions.step_completed.emit(def.id, step.id)


func _on_step_changed(_step: MissionStep) -> void:
	objective_changed.emit()


func _complete() -> void:
	for step in side:
		if step.state != MissionStep.State.DONE:
			add_bonus(step.id, step.display_text(), false)
		step.abort()
	state = State.COMPLETED
	finished.emit(self)


func _stop_steps() -> void:
	for step in steps + side:
		step.abort()


func _save_checkpoint(step_index: int) -> void:
	var vars := {}
	for key in ctx.vars:
		var value: Variant = ctx.vars[key]
		if not value is Object:
			vars[key] = value
	var at: Variant = null
	if GameState.player != null and GameState.player.is_inside_tree():
		at = GameState.player.global_position
	checkpoint = {"index": step_index, "vars": vars, "position": at, "items": Missions.items.items()}
