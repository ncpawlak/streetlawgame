class_name PhoneView
extends Control
## Phone overlay (inside NarrativeUI): incoming-call card, in-call indicator, missed-call badge and
## the contacts list ([phone] P to open, 1-9 to call).

var service: PhoneService:
	set(value):
		if service != null and service.state_changed.is_connected(_on_state):
			service.state_changed.disconnect(_on_state)
			service.missed_changed.disconnect(refresh)
		service = value
		if service != null:
			service.state_changed.connect(_on_state)
			service.missed_changed.connect(refresh)
		refresh()

var _card: PanelContainer
var _title: Label
var _caller: Label
var _hint: Label
var _ring_bar: ProgressBar
var _badge: Label
var _contacts_panel: PanelContainer
var _contacts_box: VBoxContainer
var _contacts: Array[ContactDef] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = _panel(Control.PRESET_TOP_RIGHT, Vector2(-300.0, 90.0), Vector2(-20.0, 200.0))
	var box := VBoxContainer.new()
	_card.add_child(box)
	_title = _label(14, "Incoming call")
	box.add_child(_title)
	_caller = _label(22, "")
	box.add_child(_caller)
	_hint = _label(14, "")
	box.add_child(_hint)
	_ring_bar = ProgressBar.new()
	_ring_bar.custom_minimum_size = Vector2(0.0, 4.0)
	_ring_bar.show_percentage = false
	box.add_child(_ring_bar)
	_badge = _label(14, "")
	_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_badge.offset_left = -300.0
	_badge.offset_right = -20.0
	_badge.offset_top = 64.0
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_badge)
	_contacts_panel = _panel(Control.PRESET_CENTER_RIGHT, Vector2(-320.0, -160.0), Vector2(-20.0, 160.0))
	_contacts_box = VBoxContainer.new()
	_contacts_panel.add_child(_contacts_box)
	refresh()


func _process(_delta: float) -> void:
	if service != null and service.is_ringing() and service.current_call != null:
		_ring_bar.value = service.ring_left / maxf(service.current_call.ring_time, 0.01) * 100.0
		var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.012)
		_caller.modulate = service.caller_color() * Color(1.0, 1.0, 1.0, pulse)


func _input(event: InputEvent) -> void:
	if service == null or get_tree().paused:
		return
	if event.is_action_pressed(&"phone"):
		if contacts_open():
			close_contacts()
		elif service.state == PhoneService.State.IDLE and not Narrative.is_input_locked():
			open_contacts()
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if not contacts_open():
		return
	if event.is_action_pressed(&"ui_cancel"):
		close_contacts()
		get_viewport().set_input_as_handled()
		return
	for i in mini(_contacts.size(), InputSetup.WEAPON_HOTKEYS):
		if event.is_action_pressed("weapon_%d" % (i + 1)):
			close_contacts()
			service.call_contact(_contacts[i].id)
			get_viewport().set_input_as_handled()
			return


func open_contacts() -> void:
	_contacts = service.contacts()
	for child in _contacts_box.get_children():
		child.queue_free()
	_contacts_box.add_child(_label(16, "Contacts  [P] close"))
	if _contacts.is_empty():
		_contacts_box.add_child(_label(16, "  (no contacts)"))
	for i in _contacts.size():
		var contact := _contacts[i]
		var row := _label(18, "%d. %s%s" % [i + 1, contact.label(), "  (missed call)" if service.has_missed_from(contact.id) else ""])
		row.modulate = contact.color
		_contacts_box.add_child(row)
	_contacts_panel.visible = true


func close_contacts() -> void:
	_contacts_panel.visible = false


func contacts_open() -> bool:
	return _contacts_panel != null and _contacts_panel.visible


func refresh() -> void:
	if _card == null:
		return
	var state := service.state if service != null else PhoneService.State.IDLE
	_card.visible = state != PhoneService.State.IDLE
	_ring_bar.visible = state == PhoneService.State.RINGING
	if service != null and state != PhoneService.State.IDLE:
		_caller.text = service.caller_name()
		_caller.modulate = service.caller_color()
		if state == PhoneService.State.RINGING:
			_title.text = "Incoming call"
			_hint.text = "[Y] Answer    [N] Decline"
		else:
			_title.text = "On call"
			_hint.text = "[N] Hang up"
	var missed := service.missed_calls().size() if service != null else 0
	_badge.visible = missed > 0 and state == PhoneService.State.IDLE
	_badge.text = "%d missed call%s  [P] Phone" % [missed, "" if missed == 1 else "s"]
	if state != PhoneService.State.IDLE:
		close_contacts()


## Card text for tests / debugging.
func card_text() -> String:
	return "%s|%s|%s" % [_title.text, _caller.text, _hint.text] if _card.visible else ""


func _on_state(_state: PhoneService.State) -> void:
	refresh()


func _panel(preset: Control.LayoutPreset, top_left: Vector2, bottom_right: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(preset)
	panel.offset_left = top_left.x
	panel.offset_top = top_left.y
	panel.offset_right = bottom_right.x
	panel.offset_bottom = bottom_right.y
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.08, 0.85)
	style.set_content_margin_all(12.0)
	style.set_corner_radius_all(8)
	style.border_color = Color(0.35, 0.75, 1.0, 0.6)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	return panel


func _label(font_size: int, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	return label
