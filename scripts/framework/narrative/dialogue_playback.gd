class_name DialoguePlayback
extends RefCounted
## Plays a DialogueDef hands-free on a timer: each line shows for its display time, then advances.
## Nodes with choices wait for [method choose] (or auto-pick [member default_choice] after
## [member choice_timeout]). Used for cutscene conversations and phone calls, where the world keeps
## running and the modal DialogueView would get in the way. Call [method tick] every frame.

signal line_shown(speaker: String, text: String, duration: float, node: DialogueNode)
signal choices_shown(labels: PackedStringArray)
signal finished(outcome: StringName)

var runner := DialogueRunner.new()
## Choice auto-picked on timeout or fast-forward; out of range = first available.
var default_choice := 0
## Seconds to wait at a choice before auto-picking; 0 = wait forever.
var choice_timeout := 0.0
## Line speed multiplier.
var speed := 1.0

var _left := 0.0
var _choice_wait := 0.0
var _waiting := false
var _done := true


func _init() -> void:
	runner.node_entered.connect(_on_node)
	runner.ended.connect(_on_ended)


func start(dialogue: DialogueDef, ctx: ActionContext) -> bool:
	_done = false
	_waiting = false
	if not runner.start(dialogue, ctx):
		_done = true
		return false
	return true


func is_playing() -> bool:
	return not _done


func waiting_for_choice() -> bool:
	return _waiting and not _done


## Labels of the choices currently offered.
func choice_labels() -> PackedStringArray:
	var labels := PackedStringArray()
	for choice in runner.choices():
		labels.append(choice.make_label(runner.ctx))
	return labels


func tick(delta: float) -> void:
	if _done:
		return
	if _waiting:
		if choice_timeout > 0.0:
			_choice_wait += delta
			if _choice_wait >= choice_timeout:
				_pick_default()
		return
	_left -= delta * speed
	if _left <= 0.0:
		skip_line()


## Ends the current line early (moves on, or opens its choices).
func skip_line() -> void:
	if _done or _waiting:
		return
	if not runner.choices().is_empty():
		_waiting = true
		_choice_wait = 0.0
		choices_shown.emit(choice_labels())
		return
	if not runner.advance():
		runner.end()


func choose(index: int) -> bool:
	if not waiting_for_choice():
		return false
	_waiting = false
	runner.choose(index)
	return true


## Resolves the rest of the conversation instantly (cutscene skip): picks the default choice at
## every branch so the same effects and outcome apply as if it had been watched.
func fast_forward() -> void:
	var guard := 0
	while not _done and guard < 256:
		guard += 1
		var before := runner.current()
		if _waiting or not runner.choices().is_empty():
			_waiting = true
			_pick_default()
		else:
			skip_line()
		if not _done and runner.current() == before and not _waiting:
			runner.end()


func stop() -> void:
	if not _done:
		runner.end()


func _pick_default() -> void:
	var options := runner.choices()
	var index := default_choice if default_choice >= 0 and default_choice < options.size() else -1
	if index >= 0 and runner.choice_state(options[index]) != "":
		index = -1
	if index < 0:
		for i in options.size():
			if runner.choice_state(options[i]) == "":
				index = i
				break
	if index < 0:
		_waiting = false
		runner.end()
		return
	_waiting = false
	runner.choose(index)


func _on_node(node: DialogueNode) -> void:
	_waiting = false
	var text := runner.text()
	_left = node.display_time(text)
	line_shown.emit(runner.speaker_name(), text, _left / maxf(speed, 0.01), node)
	Narrative.play_voice(node.voice)


func _on_ended(_id: StringName, outcome: StringName) -> void:
	if _done:
		return
	_done = true
	_waiting = false
	finished.emit(outcome)
