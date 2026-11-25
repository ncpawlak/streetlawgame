class_name ParallelStep
extends CutsceneStep
## Runs several steps at once (e.g. a camera dolly while an actor walks and a line plays).

@export var steps: Array[CutsceneStep] = []
## True = done when every child is done; false = done when the first finishes (the rest are skipped
## to their end state).
@export var wait_for_all := true


func begin(director: CutsceneDirector, state: Dictionary) -> void:
	var running: Array = []
	for step in steps:
		if step == null:
			continue
		var child := {}
		step.begin(director, child)
		running.append([step, child, false])
	state["running"] = running


func tick(director: CutsceneDirector, state: Dictionary, delta: float) -> bool:
	var running: Array = state["running"]
	var any_done := false
	var all_done := true
	for entry: Array in running:
		if not entry[2]:
			entry[2] = (entry[0] as CutsceneStep).tick(director, entry[1], delta)
		any_done = any_done or entry[2]
		all_done = all_done and entry[2]
	if not wait_for_all and any_done and not all_done:
		skip(director, state)
		return true
	return all_done or running.is_empty()


func skip(director: CutsceneDirector, state: Dictionary) -> void:
	if state.is_empty():
		for step in steps:
			if step != null:
				step.skip(director, {})
		return
	for entry: Array in state["running"]:
		if not entry[2]:
			(entry[0] as CutsceneStep).skip(director, entry[1])
			entry[2] = true


func validate() -> PackedStringArray:
	var issues := PackedStringArray()
	for step in steps:
		if step == null:
			issues.append("empty child step")
		else:
			for issue in step.validate():
				issues.append("%s: %s" % [step.kind(), issue])
	return issues
