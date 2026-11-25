class_name AllOfStep
extends MissionStep
## Runs child [member steps] in parallel, in any order ("talk to all three"). Completes when every
## non-optional child is done, or when [member required] children are done if it's above 0.
## The HUD shows [member text] (if any) followed by one line per child.

@export var steps: Array[MissionStep] = []
@export var required := 0

var _done := 0


func _post_clone(copy: MissionStep) -> void:
	var children: Array[MissionStep] = []
	for child in steps:
		if child != null:
			children.append(child.clone())
	(copy as AllOfStep).steps = children


func _begin() -> void:
	_done = 0
	for child in steps:
		if not child.completed.is_connected(_on_child_completed):
			child.completed.connect(_on_child_completed)
			child.step_changed.connect(_on_child_changed)
		child.start(run)
	_check()


func _tick(delta: float) -> void:
	for child in steps:
		child.tick(delta)
		if state != State.ACTIVE:
			return


func _handle(event: Dictionary) -> void:
	for child in steps:
		child.handle(event)
		if state != State.ACTIVE:
			return


func _end() -> void:
	for child in steps:
		child.abort()


func _on_child_completed(_child: MissionStep) -> void:
	_done += 1
	notify_changed()
	_check()


func _on_child_changed(_child: MissionStep) -> void:
	notify_changed()


func _check() -> void:
	if state != State.ACTIVE:
		return
	if required > 0:
		if _done >= required:
			complete()
		return
	for child in steps:
		if not child.optional and not child.is_done():
			return
	complete()


func objective_lines() -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	if hidden:
		return lines
	if text != "":
		lines.append({"text": display_text(), "done": is_done(), "failed": state == State.FAILED, "optional": optional})
	for child in steps:
		for line in child.objective_lines():
			line["indent"] = text != ""
			lines.append(line)
	return lines


func _progress() -> String:
	var total := required if required > 0 else steps.filter(func(s: MissionStep) -> bool: return not s.optional).size()
	return "%d/%d" % [mini(_done, total), total] if total > 1 else ""


func _waypoint() -> Variant:
	var player := GameState.player
	var from := player.get_focus_position() if player != null else Vector3.ZERO
	var best: Variant = null
	var best_distance := INF
	for child in steps:
		if not child.is_active():
			continue
		var at: Variant = child.waypoint_position()
		if at is Vector3 and (at as Vector3).distance_to(from) < best_distance:
			best_distance = (at as Vector3).distance_to(from)
			best = at
	return best


func validate() -> PackedStringArray:
	var problems := super.validate() if text != "" else PackedStringArray()
	for child in steps:
		if child != null:
			problems.append_array(child.validate())
	return problems
