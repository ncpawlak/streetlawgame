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


func toggle_debug() -> void:
	debug_visible = not debug_visible


func _process(_delta: float) -> void:
	if driver == null:
		return
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
	_debug_label.text = "CARJACK DEBUG  [F1 hide]\n[F2] Minigame:  %s\n[F3] Trackers:  %s\n[F4] Difficulty:  %s\n[F5] Reset scene    [F6] Jump to next car\nChop shop paid: $%d (%d cars)" % [
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
