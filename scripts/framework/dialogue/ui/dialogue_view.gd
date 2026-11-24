class_name DialogueView
extends Control
## Conversation panel. Opens on EventBus.dialogue_requested, pauses the game while open and drives a
## DialogueRunner. Keyboard-driven: 1-9 pick, wheel + E confirm, Esc leaves.

var runner := DialogueRunner.new()
var selected := 0

var _was_paused := false
var _speaker: Label
var _text: Label
var _list: VBoxContainer
var _choices: Array[DialogueChoice] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left = -420.0
	offset_right = 420.0
	offset_top = -300.0
	offset_bottom = -40.0
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_speaker = _make_label(20)
	_speaker.modulate = Color(1.0, 0.85, 0.4)
	box.add_child(_speaker)
	_text = _make_label(18)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_text)
	_list = VBoxContainer.new()
	box.add_child(_list)
	var keys := _make_label(14)
	keys.text = "[1-9 / wheel + E] Choose   [Esc] Leave"
	keys.modulate.a = 0.7
	box.add_child(keys)
	visible = false
	runner.node_entered.connect(_on_node_entered)
	runner.ended.connect(_on_ended)
	EventBus.dialogue_requested.connect(_on_dialogue_requested)


func is_open() -> bool:
	return runner.is_active()


func open(dialogue: DialogueDef, ctx: ActionContext) -> bool:
	if is_open():
		return false
	_was_paused = get_tree().paused
	if not runner.start(dialogue, ctx):
		return false
	get_tree().paused = true
	visible = true
	return true


## Picks visible choice [param index]. Returns the runner's result (true = went through and passed).
func pick(index: int) -> bool:
	if not is_open():
		return false
	if _choices.is_empty():
		runner.end()
		return true
	var passed := runner.choose(index)
	if is_open():
		_redraw()
	return passed


func close() -> void:
	if is_open():
		runner.end()


func _on_dialogue_requested(dialogue: DialogueDef, ctx: ActionContext) -> void:
	# Deferred so the key press that started the conversation can't also pick a choice.
	open.call_deferred(dialogue, ctx)


func _on_node_entered(_node: DialogueNode) -> void:
	selected = 0
	_redraw()


func _on_ended(_dialogue_id: StringName, _outcome: StringName) -> void:
	visible = false
	_choices.clear()
	get_tree().paused = _was_paused


func _input(event: InputEvent) -> void:
	if not is_open():
		return
	var count := maxi(_choices.size(), 1)
	if event.is_action_pressed("interact"):
		pick(selected)
	elif event.is_action_pressed("ui_cancel"):
		close()
	elif event.is_action_pressed("next_weapon"):
		selected = wrapi(selected + 1, 0, count)
		_redraw()
	elif event.is_action_pressed("prev_weapon"):
		selected = wrapi(selected - 1, 0, count)
		_redraw()
	else:
		var picked := -1
		for i in mini(count, InputSetup.WEAPON_HOTKEYS):
			if event.is_action_pressed("weapon_%d" % (i + 1)):
				picked = i
		if picked < 0:
			return
		pick(picked)
	get_viewport().set_input_as_handled()


func _redraw() -> void:
	if not is_open():
		return
	_speaker.text = runner.speaker_name()
	_text.text = runner.text()
	_choices = runner.choices()
	var rows: Array[String] = []
	var dims: Array[bool] = []
	for choice in _choices:
		var reason := runner.choice_state(choice)
		rows.append(choice.make_label(runner.ctx) + ("  - " + reason if reason != "" else ""))
		dims.append(reason != "")
	if rows.is_empty():
		rows.append("Leave")
		dims.append(false)
	while _list.get_child_count() < rows.size():
		_list.add_child(_make_label(18))
	for i in _list.get_child_count():
		var row := _list.get_child(i) as Label
		row.visible = i < rows.size()
		if row.visible:
			row.text = "%s%d. %s" % ["> " if i == selected else "   ", i + 1, rows[i]]
			row.modulate = Color(0.6, 0.6, 0.6) if dims[i] else Color.WHITE


func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	return label