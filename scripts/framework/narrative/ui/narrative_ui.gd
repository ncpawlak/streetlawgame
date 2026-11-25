class_name NarrativeUI
extends CanvasLayer
## Overlay for narrative presentation, owned by the Narrative autoload: letterbox bars, subtitles,
## timed-dialogue choices (cutscenes / phone calls), the hold-to-skip bar, screen fades and the phone.

const SPEAKER_COLOR := Color(1.0, 0.85, 0.4)
const LETTERBOX_HEIGHT := 0.12

var phone_view: PhoneView
## 0 = no bars, 1 = full bars (each bar LETTERBOX_HEIGHT of the screen).
var letterbox_amount := 0.0:
	set(value):
		letterbox_amount = clampf(value, 0.0, 1.0)
		_layout_bars()
## Screen fade opacity (0 = clear, 1 = solid).
var fade_amount := 0.0:
	set(value):
		fade_amount = clampf(value, 0.0, 1.0)
		if _fade != null:
			_fade.color.a = fade_amount
			_fade.visible = fade_amount > 0.0
var selected := 0

var _top: ColorRect
var _bottom: ColorRect
var _subtitle: PanelContainer
var _speaker: Label
var _line: Label
var _choice_box: VBoxContainer
var _skip: VBoxContainer
var _skip_bar: ProgressBar
var _fade_layer: CanvasLayer
var _fade: ColorRect
var _letterbox_tween: Tween
var _fade_tween: Tween
var _line_left := 0.0
var _choice_playback: DialoguePlayback
var _choice_labels: PackedStringArray = []


func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	_top = _bar()
	_bottom = _bar()
	_build_subtitle()
	_build_skip()
	phone_view = PhoneView.new()
	phone_view.name = "PhoneView"
	add_child(phone_view)
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 100
	add_child(_fade_layer)
	_fade = ColorRect.new()
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade.visible = false
	_fade_layer.add_child(_fade)
	get_viewport().size_changed.connect(_layout_bars)
	_layout_bars()


func _process(delta: float) -> void:
	if _line_left > 0.0 and not get_tree().paused:
		_line_left -= delta
		if _line_left <= 0.0:
			clear_line()


func _input(event: InputEvent) -> void:
	if _choice_playback == null or not _choice_playback.waiting_for_choice() or get_tree().paused:
		return
	var count := _choice_labels.size()
	var picked := -1
	if event.is_action_pressed("interact"):
		picked = selected
	elif event.is_action_pressed("next_weapon"):
		selected = wrapi(selected + 1, 0, count)
		_draw_choices()
	elif event.is_action_pressed("prev_weapon"):
		selected = wrapi(selected - 1, 0, count)
		_draw_choices()
	else:
		for i in mini(count, InputSetup.WEAPON_HOTKEYS):
			if event.is_action_pressed("weapon_%d" % (i + 1)):
				picked = i
		if picked < 0:
			return
	if picked >= 0:
		_choice_playback.choose(picked)
	get_viewport().set_input_as_handled()


# --- Letterbox / fade --------------------------------------------------------------------------

func set_letterbox(amount: float, duration := 0.5) -> void:
	if _letterbox_tween != null:
		_letterbox_tween.kill()
	if duration <= 0.0:
		letterbox_amount = amount
		return
	_letterbox_tween = create_tween().set_trans(Tween.TRANS_SINE)
	_letterbox_tween.tween_property(self, "letterbox_amount", amount, duration)


## Fades the screen to [param amount] opacity of [param color].
func fade_to(amount: float, duration := 0.5, color := Color.BLACK) -> void:
	if _fade_tween != null:
		_fade_tween.kill()
	_fade.color = Color(color.r, color.g, color.b, fade_amount)
	if duration <= 0.0:
		fade_amount = amount
		return
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "fade_amount", amount, duration)


# --- Subtitles ---------------------------------------------------------------------------------

## Shows a subtitle. [param duration] 0 keeps it until [method clear_line].
func show_line(speaker: String, text: String, duration := 0.0, color := SPEAKER_COLOR) -> void:
	_speaker.text = speaker
	_speaker.visible = speaker != ""
	_speaker.modulate = color
	_line.text = text
	_subtitle.visible = text != ""
	_line_left = duration


func clear_line() -> void:
	_line_left = 0.0
	_subtitle.visible = false
	_line.text = ""
	_speaker.text = ""


func subtitle_text() -> String:
	return _line.text if _subtitle.visible else ""


func subtitle_speaker() -> String:
	return _speaker.text if _subtitle.visible else ""


# --- Timed-dialogue choices --------------------------------------------------------------------

## Routes [param playback]'s choices to this overlay (1-9 / wheel + E pick) and its lines to the
## subtitles. Pass null to unbind.
func bind_playback(playback: DialoguePlayback) -> void:
	if _choice_playback != null:
		for connection: Array in [[_choice_playback.line_shown, _on_playback_line], [_choice_playback.choices_shown, _on_playback_choices], [_choice_playback.finished, _on_playback_finished]]:
			if (connection[0] as Signal).is_connected(connection[1]):
				(connection[0] as Signal).disconnect(connection[1])
	_choice_playback = playback
	hide_choices()
	if playback != null:
		playback.line_shown.connect(_on_playback_line)
		playback.choices_shown.connect(_on_playback_choices)
		playback.finished.connect(_on_playback_finished)


func show_choices(labels: PackedStringArray) -> void:
	_choice_labels = labels
	selected = 0
	_draw_choices()


func hide_choices() -> void:
	_choice_labels = []
	_choice_box.visible = false


func choice_labels() -> PackedStringArray:
	return _choice_labels if _choice_box.visible else PackedStringArray()


func _on_playback_line(speaker: String, text: String, duration: float, _node: DialogueNode) -> void:
	show_line(speaker, text, duration + 0.5)
	hide_choices()


func _on_playback_choices(labels: PackedStringArray) -> void:
	_line_left = 0.0
	show_choices(labels)


func _on_playback_finished(_outcome: StringName) -> void:
	hide_choices()
	clear_line()
	bind_playback(null)


func _draw_choices() -> void:
	_choice_box.visible = not _choice_labels.is_empty()
	while _choice_box.get_child_count() < _choice_labels.size():
		_choice_box.add_child(_label(18))
	for i in _choice_box.get_child_count():
		var row := _choice_box.get_child(i) as Label
		row.visible = i < _choice_labels.size()
		if row.visible:
			row.text = "%s%d. %s" % ["> " if i == selected else "   ", i + 1, _choice_labels[i]]


# --- Skip --------------------------------------------------------------------------------------

## 0 hides the hold-to-skip bar; shows the hint while [param hint_visible].
func set_skip_progress(progress: float, hint_visible: bool) -> void:
	_skip.visible = hint_visible
	_skip_bar.value = progress * 100.0
	_skip_bar.visible = progress > 0.0


func reset() -> void:
	bind_playback(null)
	clear_line()
	set_skip_progress(0.0, false)
	set_letterbox(0.0, 0.0)
	fade_to(0.0, 0.0)
	phone_view.refresh()


# --- Building ----------------------------------------------------------------------------------

func _bar() -> ColorRect:
	var bar := ColorRect.new()
	bar.color = Color.BLACK
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	return bar


func _layout_bars() -> void:
	if _top == null:
		return
	var size := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280.0, 720.0)
	var height := size.y * LETTERBOX_HEIGHT * letterbox_amount
	_top.position = Vector2.ZERO
	_top.size = Vector2(size.x, height)
	_bottom.position = Vector2(0.0, size.y - height)
	_bottom.size = Vector2(size.x, height)
	_top.visible = height > 0.5
	_bottom.visible = height > 0.5


func _build_subtitle() -> void:
	var holder := VBoxContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	holder.offset_left = -460.0
	holder.offset_right = 460.0
	holder.offset_top = -230.0
	holder.offset_bottom = -24.0
	holder.alignment = BoxContainer.ALIGNMENT_END
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	_choice_box = VBoxContainer.new()
	_choice_box.visible = false
	holder.add_child(_choice_box)
	_subtitle = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.45)
	style.set_content_margin_all(10.0)
	style.set_corner_radius_all(4)
	_subtitle.add_theme_stylebox_override("panel", style)
	_subtitle.visible = false
	holder.add_child(_subtitle)
	var box := VBoxContainer.new()
	_subtitle.add_child(box)
	_speaker = _label(18)
	_speaker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_speaker)
	_line = _label(22)
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_line)


func _build_skip() -> void:
	_skip = VBoxContainer.new()
	_skip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip.offset_left = -230.0
	_skip.offset_top = -64.0
	_skip.offset_right = -20.0
	_skip.offset_bottom = -16.0
	_skip.alignment = BoxContainer.ALIGNMENT_END
	_skip.visible = false
	add_child(_skip)
	var hint := _label(14)
	hint.text = "Hold [Space] to skip"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.modulate.a = 0.75
	_skip.add_child(hint)
	_skip_bar = ProgressBar.new()
	_skip_bar.custom_minimum_size = Vector2(0.0, 6.0)
	_skip_bar.show_percentage = false
	_skip_bar.visible = false
	_skip.add_child(_skip_bar)


func _label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	return label
