class_name TurfCaptureHud
extends CanvasLayer
## Capture HUD: objective, capture bar, wave counter, Vipers remaining, wave banners, and an F1 debug panel
## (wave count, difficulty, guards, rival strength, restart). Once the block is yours it shows the income and
## counter-attack timers, and the bar turns into the Vipers' takeover meter during a counter-attack.

signal restart_requested(waves: int, difficulty: StringName, guards: int, strength: float)

const BANNER_TIME := 3.0

var _title_label: Label
var _block_label: Label
var _status_label: Label
var _progress_bar: ProgressBar
var _progress_label: Label
var _wave_label: Label
var _enemies_label: Label
var _banner: Label
var _banner_left := 0.0
var _debug_panel: PanelContainer
var _waves_spin: SpinBox
var _difficulty_option: OptionButton
var _guards_spin: SpinBox
var _strength_spin: SpinBox


func _ready() -> void:
	_build_objective()
	_build_banner()
	_build_debug_panel()
	var hint := _make_label("[F1] Debug options    [F2] Pay income now    [F3] Trigger counter-attack    [Esc] Free mouse", 14)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.offset_left = 20.0
	hint.offset_top = -244.0
	hint.modulate.a = 0.7
	add_child(hint)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F1:
		set_debug_visible(not _debug_panel.visible)
		get_viewport().set_input_as_handled()


func set_debug_visible(shown: bool) -> void:
	_debug_panel.visible = shown
	if shown:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func is_debug_visible() -> bool:
	return _debug_panel.visible


## Shows the debug values the run was started with.
func set_options(waves: int, difficulty: StringName, guards: int, strength := TurfBlockLedger.DEFAULT_STRENGTH) -> void:
	_waves_spin.value = waves
	_difficulty_option.select(maxi(0, TurfCaptureModel.DIFFICULTIES.find(difficulty)))
	_guards_spin.value = guards
	_strength_spin.value = strength


func refresh(model: TurfCaptureModel, block_text := "") -> void:
	_status_label.text = model.status_text()
	_block_label.text = block_text
	_block_label.visible = not block_text.is_empty()
	var held := model.is_held()
	_title_label.text = "5TH & PINE  -  your turf" if held else "TAKE THE CORNER  -  Red Vipers turf"
	_title_label.modulate = GameState.gang_color(GameState.PLAYER_GANG if held else &"vipers").lightened(0.35)
	var capturing := model.state == TurfCaptureModel.State.CAPTURING
	var attacked := model.state == TurfCaptureModel.State.UNDER_ATTACK or model.state == TurfCaptureModel.State.LOST
	if attacked:
		_progress_bar.value = model.takeover * 100.0
		_progress_label.text = "Vipers takeover %d%%" % roundi(model.takeover * 100.0)
		_progress_bar.modulate = GameState.gang_color(&"vipers").lightened(0.2)
	else:
		_progress_bar.value = model.progress * 100.0
		_progress_label.text = "Capture %d%%" % roundi(model.progress * 100.0)
		_progress_bar.modulate = GameState.gang_color(GameState.PLAYER_GANG).lightened(0.3)
	_progress_bar.visible = model.state != TurfCaptureModel.State.GUARDED
	_progress_label.visible = _progress_bar.visible
	if attacked:
		_wave_label.text = "Counter-attack"
	elif model.wave_index < 0:
		_wave_label.text = "Waves: %d incoming" % model.wave_count
	else:
		_wave_label.text = "Wave %d / %d" % [model.wave_index + 1, model.wave_count]
	_enemies_label.text = "Vipers left: %d" % model.enemies_remaining
	_enemies_label.modulate = Color(1.0, 0.5, 0.5) if model.enemies_remaining > 0 else Color(0.6, 1.0, 0.6)
	_status_label.modulate = Color(0.75, 1.0, 0.75) if model.state == TurfCaptureModel.State.CAPTURED \
		else (Color(1.0, 0.85, 0.4) if capturing else (Color(1.0, 0.55, 0.5) if attacked else Color.WHITE))


func block_text() -> String:
	return _block_label.text if _block_label.visible else ""


func title_text() -> String:
	return _title_label.text


func banner(text: String, color := Color.WHITE, duration := BANNER_TIME) -> void:
	_banner.text = text
	_banner.modulate = color
	_banner_left = duration


func banner_text() -> String:
	return _banner.text if _banner_left > 0.0 else ""


func _process(delta: float) -> void:
	_banner_left = maxf(0.0, _banner_left - delta)
	_banner.modulate.a = clampf(_banner_left, 0.0, 1.0)


func _on_restart_pressed() -> void:
	var difficulty := TurfCaptureModel.DIFFICULTIES[maxi(0, _difficulty_option.selected)]
	restart_requested.emit(int(_waves_spin.value), difficulty, int(_guards_spin.value), _strength_spin.value)
	set_debug_visible(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_objective() -> void:
	var panel := VBoxContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.offset_left = -300.0
	panel.offset_right = 300.0
	panel.offset_top = 14.0
	panel.add_theme_constant_override("separation", 4)
	add_child(panel)
	_title_label = _make_label("TAKE THE CORNER  -  Red Vipers turf", 22)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.modulate = GameState.gang_color(&"vipers").lightened(0.35)
	panel.add_child(_title_label)
	_block_label = _make_label("", 15)
	_block_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_block_label.modulate = Color(0.85, 0.9, 1.0)
	panel.add_child(_block_label)
	_status_label = _make_label("", 18)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_status_label)

	var bar_box := Control.new()
	bar_box.custom_minimum_size = Vector2(0.0, 24.0)
	panel.add_child(bar_box)
	_progress_bar = ProgressBar.new()
	_progress_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_progress_bar.offset_left = 80.0
	_progress_bar.offset_right = -80.0
	_progress_bar.show_percentage = false
	_progress_bar.modulate = GameState.gang_color(GameState.PLAYER_GANG).lightened(0.3)
	bar_box.add_child(_progress_bar)
	_progress_label = _make_label("", 15)
	_progress_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar_box.add_child(_progress_label)

	var counters := HBoxContainer.new()
	counters.alignment = BoxContainer.ALIGNMENT_CENTER
	counters.add_theme_constant_override("separation", 40)
	panel.add_child(counters)
	_wave_label = _make_label("", 20)
	counters.add_child(_wave_label)
	_enemies_label = _make_label("", 20)
	counters.add_child(_enemies_label)


func _build_banner() -> void:
	_banner = _make_label("", 44)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.offset_left = -500.0
	_banner.offset_right = 500.0
	_banner.offset_top = -170.0
	_banner.offset_bottom = -110.0
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_constant_override("outline_size", 10)
	_banner.modulate.a = 0.0
	add_child(_banner)


func _build_debug_panel() -> void:
	_debug_panel = PanelContainer.new()
	_debug_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_debug_panel.offset_left = 20.0
	_debug_panel.offset_top = -110.0
	_debug_panel.visible = false
	add_child(_debug_panel)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	_debug_panel.add_child(grid)

	grid.add_child(_make_label("Debug", 18))
	grid.add_child(Control.new())
	grid.add_child(_make_label("Waves", 16))
	_waves_spin = SpinBox.new()
	_waves_spin.min_value = 1
	_waves_spin.max_value = 12
	grid.add_child(_waves_spin)
	grid.add_child(_make_label("Difficulty", 16))
	_difficulty_option = OptionButton.new()
	for id in TurfCaptureModel.DIFFICULTIES:
		_difficulty_option.add_item(String(id).capitalize())
	grid.add_child(_difficulty_option)
	grid.add_child(_make_label("Guards", 16))
	_guards_spin = SpinBox.new()
	_guards_spin.min_value = 0
	_guards_spin.max_value = 10
	grid.add_child(_guards_spin)
	grid.add_child(_make_label("Vipers strength", 16))
	_strength_spin = SpinBox.new()
	_strength_spin.min_value = TurfBlockLedger.MIN_STRENGTH
	_strength_spin.max_value = TurfBlockLedger.MAX_STRENGTH
	_strength_spin.step = 0.5
	grid.add_child(_strength_spin)
	var restart := Button.new()
	restart.text = "Restart capture"
	restart.pressed.connect(_on_restart_pressed)
	grid.add_child(restart)


func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
