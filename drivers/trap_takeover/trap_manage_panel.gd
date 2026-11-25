class_name TrapManagePanel
extends CanvasLayer
## Customize a trap the player kept: upgrade its level, build rooms, pick the product and put crew
## on jobs there. Calls back into the TrapTakeoverDriver, which keeps the Operations site in sync.
## Built in code (greybox) and pauses the game while open, like the Operations panel.

const JOBS := [&"guard", &"cook", &"dealer"]

var driver: TrapTakeoverDriver
var is_open := false

var _message := ""
var _was_paused := false
var _previous_mouse_mode := Input.MOUSE_MODE_VISIBLE
var _title: Label
var _body: VBoxContainer


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(720, 560)
	center.add_child(frame)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	frame.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	header.add_child(_button("Close [Esc]", close))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)


func _unhandled_input(event: InputEvent) -> void:
	if is_open and (event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_T)):
		close()
		get_viewport().set_input_as_handled()


## [param pause] false keeps the game running (screenshots).
func open(pause := true) -> void:
	if not is_open:
		is_open = true
		visible = true
		_was_paused = get_tree().paused
		if pause:
			get_tree().paused = true
		_previous_mouse_mode = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_message = ""
	rebuild()


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	get_tree().paused = _was_paused
	Input.mouse_mode = _previous_mouse_mode


func rebuild() -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var custom := driver.customization
	if custom == null:
		return
	var info := custom.level_info()
	_title.text = "The Spot - Lv %d %s" % [custom.level + 1, info["name"]]
	if _message != "":
		_body.add_child(_label(_message, Color(1.0, 0.8, 0.3)))
	_body.add_child(_label("Cash $%d   Workers %d/%d   Stash %d   Safe cap $%d" % [
		GameState.cash, driver.site_workers(), info["workers"], info["stash"], info["safe"]]))

	_body.add_child(_heading("Upgrade"))
	var cost := custom.next_level_cost()
	if cost < 0:
		_body.add_child(_label("Fully upgraded."))
	else:
		var next: Dictionary = TrapCustomization.LEVELS[custom.level + 1]
		_body.add_child(_button("Upgrade to Lv %d %s ($%d): %d rooms, %d workers, stash %d" % [
			custom.level + 2, next["name"], cost, next["room_slots"], next["workers"], next["stash"]], _do.bind(driver.upgrade_trap)))

	_body.add_child(_heading("Rooms (%d/%d slots used)" % [custom.rooms.size(), info["room_slots"]]))
	for room_id: StringName in TrapCustomization.ROOMS:
		var room: Dictionary = TrapCustomization.ROOMS[room_id]
		var what: String = "makes %s" % room["product"] if room["product"] != "" else ("fewer raids" if room_id == &"security" else "bigger safe, auto pickup")
		if custom.rooms.has(room_id):
			_body.add_child(_label("  %s - built (%s)" % [room["name"], what], Color(0.6, 1.0, 0.6)))
			continue
		var button := _button("Build %s ($%d) - %s" % [room["name"], room["cost"], what], _do.bind(driver.buy_room.bind(room_id)))
		var reason := custom.room_block_reason(room_id)
		button.disabled = reason != ""
		button.tooltip_text = reason
		_body.add_child(button)

	_body.add_child(_heading("Product: %s" % custom.product_name()))
	var choices := HBoxContainer.new()
	for room_id in custom.product_rooms():
		var room: Dictionary = TrapCustomization.ROOMS[room_id]
		var label: String = room["product"] + ("" if room["recipe"] != &"" else " (soon)")
		var button := _button(label, _do.bind(driver.set_product.bind(room_id)))
		button.disabled = custom.product == room_id
		choices.add_child(button)
	if choices.get_child_count() == 0:
		_body.add_child(_label("Build a production room to pick a product."))
	else:
		_body.add_child(choices)

	_body.add_child(_heading("Crew"))
	var crew := driver.crew_members()
	if crew.is_empty():
		_body.add_child(_label("No crew yet."))
	for member: CrewMemberData in crew:
		var row := HBoxContainer.new()
		var name_label := _label("%s - %s" % [member.display_name, driver.crew_job_text(member.id)])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		for job_id: StringName in JOBS:
			row.add_child(_button(String(job_id).capitalize(), _do.bind(driver.assign_crew.bind(member.id, job_id))))
		row.add_child(_button("Pull", _do.bind(driver.unassign_crew.bind(member.id))))
		_body.add_child(row)
	_body.add_child(_button("Open full Operations panel (stash, supplies)", func() -> void:
		close()
		driver.open_operations()))


func _do(action: Callable) -> void:
	var result: Variant = action.call()
	_message = result if result is String else ""
	rebuild()


func _heading(text: String) -> Label:
	var label := _label(text)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	return label


func _label(text: String, color := Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(pressed)
	return button
