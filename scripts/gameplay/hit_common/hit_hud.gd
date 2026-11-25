class_name HitHud
extends CanvasLayer
## Hit overlay: the police countdown (top centre), wanted/escape status, the carry bag and an
## objective line. Sits above the normal HUD; bind it to the hit's components.

var bag: CarryBag
var police_call: PoliceCall
var police_response: PoliceResponse

var _timer_label: Label
var _status_label: Label
var _bag_label: Label
var _bag_items: Label
var _objective_label: Label
var _flash := 0.0


func _ready() -> void:
	layer = 5
	_timer_label = _label(40, Color(1.0, 0.85, 0.3))
	_timer_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_timer_label.offset_top = 60.0
	_timer_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label = _label(22, Color(0.6, 0.75, 1.0))
	_status_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_status_label.offset_top = 110.0
	_status_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective_label = _label(20, Color(0.95, 0.95, 0.95))
	_objective_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_objective_label.offset_top = 20.0
	_objective_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_right = -20.0
	panel.offset_bottom = -150.0
	var box := VBoxContainer.new()
	panel.add_child(box)
	_bag_label = _label(22, Color(0.5, 1.0, 0.6), box)
	_bag_items = _label(15, Color(0.85, 0.85, 0.85), box)
	add_child(panel)


func bind(carry_bag: CarryBag, call_timer: PoliceCall, response: PoliceResponse) -> void:
	bag = carry_bag
	police_call = call_timer
	police_response = response
	if police_call != null:
		police_call.police_called.connect(func(_why: StringName) -> void: _flash = 1.5)


func set_objective(text: String) -> void:
	_objective_label.text = text


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	_update_timer()
	_status_label.text = police_response.status_text() if police_response != null else ""
	_update_bag()


func _update_timer() -> void:
	if police_call == null:
		_timer_label.text = ""
		return
	_timer_label.text = police_call.status_text()
	var urgent := police_call.is_called() or (police_call.is_counting() and police_call.time_left < 10.0)
	var blink := fmod(Time.get_ticks_msec() / 300.0, 2.0) < 1.0
	_timer_label.modulate = Color(1.0, 0.25, 0.2) if urgent and (blink or _flash > 0.0) else Color(1.0, 0.85, 0.3)
	if police_response != null and police_response.is_wanted():
		_timer_label.text = ""


func _update_bag() -> void:
	if bag == null or not is_instance_valid(bag):
		bag = CarryBag.of(GameState.player, false) if GameState.player != null else null
	if bag == null:
		_bag_label.text = "Bag 0/8  -  $0"
		_bag_items.text = ""
		return
	_bag_label.text = bag.summary()
	var lines := PackedStringArray()
	for item in bag.items:
		lines.append("%s  $%d" % [item["name"], item["value"]])
	if bag.cash > 0:
		lines.append("Cash  $%d" % bag.cash)
	_bag_items.text = "\n".join(lines)


func _label(font_size: int, color: Color, parent: Node = null) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	(parent if parent != null else self).add_child(label)
	return label
