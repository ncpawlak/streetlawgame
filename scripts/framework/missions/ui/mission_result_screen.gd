class_name MissionResultScreen
extends Control
## "MISSION COMPLETE" / "MISSION FAILED" banner. Completion lists rewards and bonuses and fades out
## by itself. Failure shows the reason and pauses: [R] retries from the last checkpoint, [Esc] gives up.

const COMPLETE_TIME := 5.0

var is_showing := false
var is_failure := false
var _title: Label
var _name: Label
var _body: Label
var _hint: Label
var _hide_in := 0.0
var _paused_by_us := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build()
	Missions.mission_completed.connect(func(_id: StringName, run: MissionRun) -> void: show_complete(run))
	Missions.mission_failed.connect(func(_id: StringName, reason: String, run: MissionRun) -> void: show_failed(run, reason))
	Missions.mission_started.connect(func(_id: StringName) -> void: dismiss())


func _process(delta: float) -> void:
	if is_showing and not is_failure:
		_hide_in -= delta
		modulate.a = clampf(_hide_in, 0.0, 1.0)
		if _hide_in <= 0.0:
			dismiss()


func _input(event: InputEvent) -> void:
	if not is_showing or not is_failure or not event is InputEventKey or not event.is_pressed() or event.is_echo():
		return
	var key := (event as InputEventKey).physical_keycode
	if key == KEY_R:
		retry()
		get_viewport().set_input_as_handled()
	elif event.is_action("ui_cancel") or key == KEY_ESCAPE:
		dismiss()
		get_viewport().set_input_as_handled()


func show_complete(run: MissionRun) -> void:
	_show(false)
	_title.text = "MISSION COMPLETE"
	_title.modulate = Color(1.0, 0.8, 0.25)
	_name.text = run.def.label()
	var lines: PackedStringArray = []
	var rewards := run.def.reward_text()
	if rewards != "":
		lines.append("Rewards: %s" % rewards)
	for bonus in run.bonuses:
		lines.append("%s %s" % ["[x]" if bonus["achieved"] else "[ ]", bonus["label"]])
	_body.text = "\n".join(lines)
	_hint.text = ""
	_hide_in = COMPLETE_TIME


func show_failed(run: MissionRun, reason: String) -> void:
	if run.state == MissionRun.State.ABANDONED:
		return
	_show(true)
	_title.text = "MISSION FAILED"
	_title.modulate = Color(1.0, 0.35, 0.3)
	_name.text = run.def.label()
	_body.text = reason
	_hint.text = "[R] Retry from checkpoint    [Esc] Give up"
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_us = true


func retry() -> bool:
	dismiss()
	return Missions.retry()


func dismiss() -> void:
	if not is_showing:
		return
	is_showing = false
	visible = false
	modulate.a = 1.0
	if _paused_by_us:
		_paused_by_us = false
		get_tree().paused = false


func _show(failure: bool) -> void:
	dismiss()
	is_showing = true
	is_failure = failure
	visible = true
	modulate.a = 1.0


func _build() -> void:
	var band := ColorRect.new()
	band.color = Color(0, 0, 0, 0.6)
	band.set_anchors_preset(Control.PRESET_CENTER)
	band.anchor_left = 0.0
	band.anchor_right = 1.0
	band.offset_top = -120
	band.offset_bottom = 120
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(box)
	_title = _label(48)
	box.add_child(_title)
	_name = _label(24)
	box.add_child(_name)
	_body = _label(18)
	box.add_child(_body)
	_hint = _label(16)
	_hint.modulate = Color(0.8, 0.8, 0.8)
	box.add_child(_hint)


func _label(font_size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	return label
