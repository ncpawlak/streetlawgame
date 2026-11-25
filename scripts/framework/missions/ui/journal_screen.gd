class_name JournalScreen
extends Control
## Mission journal (J): Active mission + available missions, Leads (with map markers you can route
## to), and Completed missions/leads. Pauses the game while open, like the map.

const TAB_ACTIVE := 0
const TAB_LEADS := 1
const TAB_COMPLETED := 2

var is_open := false
var map_screen: MapScreen
var _tabs: TabContainer
var _active: VBoxContainer
var _leads: VBoxContainer
var _completed: VBoxContainer
var _was_paused := false
var _was_mouse_mode := Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()
	Missions.lead_changed.connect(func(_id: StringName) -> void: _refresh_if_open())
	Missions.objective_changed.connect(_refresh_if_open)


func _unhandled_input(event: InputEvent) -> void:
	if not is_open and event.is_action_pressed("toggle_journal") and open():
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not is_open or not event is InputEventKey or not event.is_pressed() or event.is_echo():
		return
	if event.is_action("toggle_journal") or event.is_action("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif (event as InputEventKey).physical_keycode in [KEY_TAB, KEY_RIGHT]:
		show_tab((_tabs.current_tab + 1) % _tabs.get_tab_count())
		get_viewport().set_input_as_handled()
	elif (event as InputEventKey).physical_keycode == KEY_LEFT:
		show_tab((_tabs.current_tab + _tabs.get_tab_count() - 1) % _tabs.get_tab_count())
		get_viewport().set_input_as_handled()


func open(tab := -1) -> bool:
	if is_open or get_tree().paused:
		return false
	is_open = true
	visible = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	_was_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()
	if tab >= 0:
		show_tab(tab)
	return true


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	get_tree().paused = _was_paused
	Input.mouse_mode = _was_mouse_mode


func show_tab(index: int) -> void:
	_tabs.current_tab = clampi(index, 0, _tabs.get_tab_count() - 1)


func refresh() -> void:
	_fill_active()
	_fill_leads()
	_fill_completed()


## Lead titles listed on the Leads tab (open first, for tests).
func listed_leads() -> PackedStringArray:
	var out := PackedStringArray()
	for lead in Missions.journal.leads(MissionJournal.OPEN):
		out.append(lead["title"])
	return out


func _refresh_if_open() -> void:
	if is_open:
		refresh()


func _fill_active() -> void:
	_clear(_active)
	var run := Missions.active
	if run == null:
		_active.add_child(_label("No active mission.", 20, Color(0.7, 0.7, 0.7)))
	else:
		_active.add_child(_label(run.def.label(), 26, Color(1.0, 0.8, 0.3)))
		if run.def.giver != "":
			_active.add_child(_label("From: %s" % run.def.giver, 16, Color(0.75, 0.75, 0.75)))
		if run.def.description != "":
			_active.add_child(_label(run.def.description, 17))
		for line in run.objective_lines():
			var mark := "[x] " if line.get("done") else "[ ] "
			var suffix := "  (bonus)" if line.get("bonus") else ("  (optional)" if line.get("optional") else "")
			var color := Color(0.55, 0.9, 0.55) if line.get("done") else (Color(1.0, 0.85, 0.3) if line.get("bonus") else Color.WHITE)
			_active.add_child(_label(("    " if line.get("indent") else "") + mark + String(line["text"]) + suffix, 18, color))
		var rewards := run.def.reward_text()
		if rewards != "":
			_active.add_child(_label("Reward: %s" % rewards, 16, Color(0.6, 1.0, 0.6)))
	var available: Array[String] = []
	for def: MissionDef in ContentDB.all(MissionDef.TYPE):
		if Missions.can_start(def):
			available.append(def.label())
	if not available.is_empty():
		_active.add_child(HSeparator.new())
		_active.add_child(_label("Available: " + ", ".join(available), 16, Color(0.8, 0.85, 1.0)))


func _fill_leads() -> void:
	_clear(_leads)
	var open_leads := Missions.journal.leads(MissionJournal.OPEN)
	if open_leads.is_empty():
		_leads.add_child(_label("No leads yet. Talk to people.", 20, Color(0.7, 0.7, 0.7)))
	for lead in open_leads:
		_leads.add_child(_lead_row(lead))


func _fill_completed() -> void:
	_clear(_completed)
	if Missions.completed.is_empty() and Missions.journal.leads(MissionJournal.DONE).is_empty():
		_completed.add_child(_label("Nothing finished yet.", 20, Color(0.7, 0.7, 0.7)))
	for mission_id: StringName in Missions.completed:
		var def := Missions.get_mission(mission_id)
		var times: int = Missions.completed[mission_id]
		_completed.add_child(_label("[x] %s%s" % [def.label() if def != null else String(mission_id), "  x%d" % times if times > 1 else ""], 20, Color(0.55, 0.9, 0.55)))
	for lead in Missions.journal.leads(MissionJournal.DONE):
		_completed.add_child(_label("[x] Lead: %s" % lead["title"], 17, Color(0.7, 0.8, 0.7)))


func _lead_row(lead: Dictionary) -> Control:
	var row := VBoxContainer.new()
	var head := HBoxContainer.new()
	row.add_child(head)
	var title := _label(String(lead["title"]), 21, Color(1.0, 0.9, 0.6))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	if lead.get("has_marker"):
		if Missions.journal.is_marker_visible(lead["id"]):
			var button := Button.new()
			button.text = "Set waypoint"
			var at: Vector3 = lead["marker"]
			button.pressed.connect(func() -> void:
				if map_screen != null:
					map_screen.set_waypoint(at)
					EventBus.notify.emit("Waypoint set: %s" % lead["title"]))
			head.add_child(button)
		else:
			head.add_child(_label("(location unknown)", 15, Color(0.6, 0.6, 0.6)))
	if String(lead.get("note", "")) != "":
		row.add_child(_label(String(lead["note"]), 17))
	row.add_child(HSeparator.new())
	return row


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 160)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 60)
	add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	column.add_child(_label("JOURNAL", 34, Color(1.0, 0.8, 0.3)))
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_tabs)
	_active = _tab("Active")
	_leads = _tab("Leads")
	_completed = _tab("Completed")
	column.add_child(_label("[J / Esc] Close    [Tab / Left / Right] Switch tab", 15, Color(0.7, 0.7, 0.7)))


func _tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	return box


func _clear(box: Container) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _label(text: String, font_size: int, color := Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = color
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	return label
