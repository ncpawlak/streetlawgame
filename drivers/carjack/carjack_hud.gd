class_name CarjackHud
extends CanvasLayer
## Carjack overlay: objective line, police countdown / wanted status, tracker status and the F1 debug
## panel (current minigame, tracker and difficulty settings plus the debug keys).

var driver: CarjackDriver
var debug_visible := true

var _objective: Label
var _police: Label
var _tracker: Label
var _debug_panel: PanelContainer
var _debug_label: Label
var tuning_visible := true
var _tuning_panel: PanelContainer
var _sliders := {}
var _values := {}
var _syncing := false


func _ready() -> void:
	layer = 5
	_objective = _label(22, Color(0.95, 0.95, 0.95), 18.0)
	_police = _label(34, Color(1.0, 0.85, 0.3), 52.0)
	_tracker = _label(20, Color(1.0, 0.45, 0.35), 96.0)
	_debug_panel = PanelContainer.new()
	_debug_panel.position = Vector2(20.0, 160.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	style.set_content_margin_all(10)
	_debug_panel.add_theme_stylebox_override("panel", style)
	add_child(_debug_panel)
	_debug_label = Label.new()
	_debug_label.add_theme_font_size_override("font_size", 15)
	_debug_panel.add_child(_debug_label)
	_build_tuning_panel()


func toggle_debug() -> void:
	debug_visible = not debug_visible


func toggle_tuning() -> void:
	tuning_visible = not tuning_visible


## True when a click at [param point] lands on the tuning panel (so it doesn't recapture the mouse).
func is_over_panel(point: Vector2) -> bool:
	return _tuning_panel != null and _tuning_panel.visible and _tuning_panel.get_global_rect().has_point(point)


func _build_tuning_panel() -> void:
	_tuning_panel = PanelContainer.new()
	_tuning_panel.name = "TuningPanel"
	_tuning_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_tuning_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_tuning_panel.offset_right = -16.0
	_tuning_panel.offset_top = 268.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.65)
	style.set_content_margin_all(8)
	_tuning_panel.add_theme_stylebox_override("panel", style)
	add_child(_tuning_panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	_tuning_panel.add_child(rows)
	var title := Label.new()
	title.text = "CAR TUNING  [F7 hide]  -  [Esc] frees the mouse to drag"
	title.add_theme_font_size_override("font_size", 13)
	rows.add_child(title)
	for spec: Array in VehicleTuning.PARAMS:
		var row := HBoxContainer.new()
		rows.add_child(row)
		var name_label := Label.new()
		name_label.text = spec[1]
		name_label.custom_minimum_size.x = 190.0
		name_label.add_theme_font_size_override("font_size", 13)
		row.add_child(name_label)
		var slider := HSlider.new()
		slider.min_value = spec[2]
		slider.max_value = spec[3]
		slider.step = spec[4]
		slider.custom_minimum_size = Vector2(150.0, 18.0)
		slider.focus_mode = Control.FOCUS_NONE
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.value_changed.connect(_on_slider_changed.bind(spec[0]))
		row.add_child(slider)
		var value_label := Label.new()
		value_label.custom_minimum_size.x = 52.0
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.add_theme_font_size_override("font_size", 13)
		row.add_child(value_label)
		_sliders[spec[0]] = slider
		_values[spec[0]] = value_label
	var buttons := HBoxContainer.new()
	rows.add_child(buttons)
	buttons.add_child(_button("Copy values", func() -> void: driver.report_tuning()))
	buttons.add_child(_button("Reset defaults", func() -> void:
		driver.reset_tuning()
		sync_tuning()))


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 13)
	button.pressed.connect(action)
	return button


## Pulls the driver's current tuning into the sliders.
func sync_tuning() -> void:
	if driver == null or driver.tuning == null:
		return
	_syncing = true
	for spec: Array in VehicleTuning.PARAMS:
		var value: float = driver.tuning.get(spec[0])
		_sliders[spec[0]].value = value
		_update_value_label(spec, value)
	_syncing = false


func _on_slider_changed(value: float, property: StringName) -> void:
	if _syncing or driver == null:
		return
	driver.set_tuning(property, value)
	for spec: Array in VehicleTuning.PARAMS:
		if spec[0] == property:
			_update_value_label(spec, value)


func _update_value_label(spec: Array, value: float) -> void:
	var label: Label = _values[spec[0]]
	label.text = VehicleTuning.format_value(value, spec[4])
	var default_value: float = driver.default_tuning.get(spec[0])
	label.add_theme_color_override("font_color", Color.WHITE if is_equal_approx(value, default_value) else Color(1.0, 0.8, 0.3))


func _process(_delta: float) -> void:
	if driver == null:
		return
	if _sliders.size() > 0 and driver.tuning != null and _values[&"mass"].text == "":
		sync_tuning()
	_tuning_panel.visible = tuning_visible and not driver.is_minigame_open()
	_objective.text = objective_text()
	var response := driver.police_response
	var alarm := driver.police_call
	_police.text = response.status_text() if response.is_wanted() else alarm.status_text()
	var urgent := alarm.is_called() or (alarm.is_counting() and alarm.time_left < 10.0)
	var blink := fmod(Time.get_ticks_msec() / 300.0, 2.0) < 1.0
	_police.modulate = Color(1.0, 0.3, 0.25) if urgent and blink else Color.WHITE
	var car := driver.hot_car
	_tracker.text = car.tracker.status_text() if car != null and is_instance_valid(car) and car.tracker != null else ""
	_debug_panel.visible = debug_visible
	_debug_label.text = "CARJACK DEBUG  [F1 hide]\n[F2] Minigame:  %s\n[F3] Trackers:  %s\n[F4] Difficulty:  %s\n[F5] Reset scene    [F6] Jump to next car    [F7] Car tuning\nChop shop paid: $%d (%d cars)" % [
		driver.minigame_mode_name(), driver.tracker_mode_name(), String(driver.difficulty_level).capitalize(),
		driver.chop_shop.total_paid, driver.chop_shop.deliveries]


func objective_text() -> String:
	if driver.is_minigame_open():
		return "Jacking the %s..." % driver.minigame_car.car_name if driver.minigame_car != null else ""
	var car := driver.hot_car
	var player := driver.player
	if car != null and is_instance_valid(car):
		if player.current_vehicle != car:
			return "Get back in the %s" % car.car_name
		var blocked := driver.chop_shop.can_deliver(car)
		if blocked != "":
			return blocked
		if car.tracker != null and car.tracker.active:
			return "Outrun the tracker (or hide in the parking garage), then drive to the CHOP SHOP"
		return "Deliver the %s to the CHOP SHOP (orange beam) - est. $%d" % [car.car_name, driver.chop_shop.payout_for(car)]
	return "Find a car and press [E] to jack it"


func _label(font_size: int, color: Color, top: float) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.offset_top = top
	add_child(label)
	return label
