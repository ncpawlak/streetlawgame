class_name OperationsPanel
extends CanvasLayer
## Minimal management UI for the operations framework, built in code (greybox). Three views:
## overview (sites, contacts, crew), a site (stash, jobs, assigning crew, ordering supplies) and a
## plug (buy-in, relationship, supplies). Everything is generated from content and behaviours
## (param_options), so new jobs/recipes/plugs show up without UI changes. Pauses the game.

## Emitted after the panel changed the model; Operations forwards the resulting events.
signal changed

enum View { OVERVIEW, SITE, PLUG }

var model: OperationsModel
var is_open := false

var _view := View.OVERVIEW
var _target: StringName
var _message := ""
var _was_paused := false
var _previous_mouse_mode := Input.MOUSE_MODE_VISIBLE
## Pending choices in the assign form: {"crew_id", "job_id", <param keys>...}.
var _form := {}
var _drop_site: StringName

var _title: Label
var _body: VBoxContainer
var _back: Button


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(760, 580)
	center.add_child(frame)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	frame.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	_back = _button("< Back", func() -> void: _show(View.OVERVIEW, &""))
	header.add_child(_back)
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
	if not is_open:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed(&"operations_menu"):
		close()
		get_viewport().set_input_as_handled()


func open_overview() -> void:
	_open(View.OVERVIEW, &"")


func open_site(site_id: StringName) -> void:
	_open(View.SITE, site_id)


func open_plug(plug_id: StringName) -> void:
	_open(View.PLUG, plug_id)


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
	_back.visible = _view != View.OVERVIEW
	if not _message.is_empty():
		_body.add_child(_label(_message, Color(1.0, 0.8, 0.3)))
	match _view:
		View.OVERVIEW:
			_build_overview()
		View.SITE:
			_build_site()
		View.PLUG:
			_build_plug()


func _open(view: View, target: StringName) -> void:
	if not is_open:
		is_open = true
		visible = true
		_was_paused = get_tree().paused
		get_tree().paused = true
		_previous_mouse_mode = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show(view, target)


func _show(view: View, target: StringName) -> void:
	_view = view
	_target = target
	_message = ""
	_form = {}
	rebuild()


## Runs a model action that returns "" or a failure reason, then refreshes.
func _do(action: Callable) -> void:
	var result: Variant = action.call()
	_message = result if result is String else ""
	changed.emit()
	rebuild()


#region Views

func _build_overview() -> void:
	_title.text = "Operations"
	_body.add_child(_heading("Places"))
	for site_id in model.site_ids():
		var site_data := model.site(site_id)
		if site_data == null:
			continue
		var row := _row()
		var owned := model.is_site_acquired(site_id)
		var status := "%d working, %d in stash" % [model.workers_at(site_id), model.site_stash(site_id).total()] if owned else "not yours"
		row.add_child(_label("%s (%s) - %s" % [site_data.display_name, model.districts.display_name(site_data.district_id), status], Color.WHITE, true))
		if owned:
			row.add_child(_button("Manage", func() -> void: _show(View.SITE, site_id)))
		else:
			var reason := model.can_acquire_site(site_id)
			row.add_child(_button("Buy $%d" % site_data.acquire_price, func() -> void: _do(func() -> String: return model.acquire_site(site_id)), reason))
		_body.add_child(row)
	_body.add_child(_heading("Contacts"))
	var any_plug := false
	for plug_id in model.plug_ids():
		if not model.is_plug_revealed(plug_id):
			continue
		any_plug = true
		var row := _row()
		var state := "in business" if model.is_plug_established(plug_id) else "not met" if not model.has_met_plug(plug_id) else "ready to deal"
		row.add_child(_label("%s - %s (relationship %d)" % [model.plug(plug_id).display_name, state, roundi(model.plug_relationship(plug_id))], Color.WHITE, true))
		row.add_child(_button("Open", func() -> void: _show(View.PLUG, plug_id)))
		_body.add_child(row)
	if not any_plug:
		_body.add_child(_label("Nobody's vouched for you yet. Earn some respect.", Color(0.7, 0.7, 0.7)))
	_body.add_child(_heading("Crew"))
	for member in model.all_crew():
		var assignment := model.assignment_for_crew(member.id)
		var doing := "idle"
		if not member.is_available():
			doing = String(CrewMemberData.Status.keys()[member.status]).to_lower()
		elif assignment != null:
			doing = "%s at %s" % [model.job(assignment.job_id).display_name, model.site(assignment.site_id).display_name]
		_body.add_child(_label("%s - %s  [%s]" % [member.display_name, doing, _skills_text(member)]))


func _build_site() -> void:
	var site_data := model.site(_target)
	if site_data == null:
		_show(View.OVERVIEW, &"")
		return
	_title.text = site_data.display_name
	if not model.is_site_acquired(_target):
		var reason := model.can_acquire_site(_target)
		_body.add_child(_button("Buy for $%d" % site_data.acquire_price, func() -> void: _do(func() -> String: return model.acquire_site(_target)), reason))
		return
	var stash := model.site_stash(_target)
	_body.add_child(_label("%s  |  Heat %d  |  Stash %d/%d" % [model.districts.display_name(site_data.district_id), roundi(model.site_heat(_target)), stash.total(), site_data.stash_capacity]))
	_body.add_child(_heading("Stash"))
	if stash.item_ids().is_empty():
		_body.add_child(_label("Empty", Color(0.7, 0.7, 0.7)))
	for item_id in stash.item_ids():
		var item_data := model.item(item_id)
		_body.add_child(_label("%s × %d" % [item_data.display_name if item_data != null else String(item_id), stash.count(item_id)]))
	_body.add_child(_heading("Jobs (%d/%d crew)" % [model.workers_at(_target), site_data.max_workers]))
	for assignment in model.assignments_at(_target):
		var row := _row()
		var member := model.crew(assignment.crew_id)
		var who := member.display_name if member != null else "-"
		var status := String(JobAssignment.Status.keys()[assignment.status])
		row.add_child(_label("%s: %s - %s [%s]" % [model.job(assignment.job_id).display_name, who, model.describe(assignment), status], Color.WHITE, true))
		var assignment_id := assignment.id
		row.add_child(_button("Stop", func() -> void: _do(func() -> bool: return model.unassign(assignment_id))))
		_body.add_child(row)
	_build_assign_form()
	_build_supply_orders(_target)


func _build_assign_form() -> void:
	_body.add_child(_heading("Put someone to work"))
	var jobs := model.available_jobs(_target)
	if jobs.is_empty():
		return
	if not _form.has("job_id"):
		_form["job_id"] = jobs[0].id
	var job_data := model.job(_form["job_id"])
	var row := _row()
	var job_choices: Array = []
	for candidate in jobs:
		job_choices.append([candidate.id, candidate.display_name])
	row.add_child(_choice(job_choices, "job_id", true))
	if job_data.requires_crew:
		var crew_choices: Array = []
		for member in model.all_crew():
			if member.is_available() and model.assignment_for_crew(member.id) == null:
				crew_choices.append([member.id, "%s (%s %d)" % [member.display_name, job_data.skill, member.skill_for(job_data.skill)]])
		row.add_child(_choice(crew_choices, "crew_id"))
	else:
		_form["crew_id"] = &""
	var options := job_data.behavior.param_options(model, _target)
	for key: String in options:
		row.add_child(_choice(options[key], key))
	_body.add_child(row)
	var params := _form.duplicate()
	params.erase("job_id")
	params.erase("crew_id")
	var crew_id: StringName = _form.get("crew_id", &"")
	var reason := model.can_assign(crew_id, _target, job_data.id, params)
	var job_id := job_data.id
	var site_id := _target
	var assign := func() -> String: return "" if model.assign(crew_id, site_id, job_id, params) != null else reason
	_body.add_child(_button("Assign", func() -> void: _do(assign), reason))


func _build_supply_orders(site_id: StringName) -> void:
	var any := false
	for plug_id in model.plug_ids():
		if not model.is_plug_established(plug_id):
			continue
		if not any:
			_body.add_child(_heading("Order supplies (delivered here)"))
			any = true
		_add_supply_buttons(plug_id, site_id)


func _build_plug() -> void:
	var plug_data := model.plug(_target)
	if plug_data == null:
		_show(View.OVERVIEW, &"")
		return
	_title.text = plug_data.display_name
	if not plug_data.description.is_empty():
		_body.add_child(_label(plug_data.description, Color(0.8, 0.8, 0.8)))
	_body.add_child(_label("Relationship: %d / 100" % roundi(model.plug_relationship(_target))))
	if not model.is_plug_established(_target):
		var reason := model.can_establish_plug(_target)
		_body.add_child(_button("Buy in ($%d)" % plug_data.buy_in_price, func() -> void: _do(func() -> String: return model.establish_plug(_target)), reason))
		return
	var owned: Array = []
	for site_id in model.site_ids():
		if model.is_site_acquired(site_id):
			owned.append([site_id, model.site(site_id).display_name])
	if owned.is_empty():
		_body.add_child(_label("You need a place to stash product first.", Color(0.7, 0.7, 0.7)))
		return
	if _drop_site.is_empty() or not model.is_site_acquired(_drop_site):
		_drop_site = owned[0][0]
	var row := _row()
	row.add_child(_label("Deliver to:"))
	var picker := OptionButton.new()
	for i in owned.size():
		picker.add_item(owned[i][1])
		if owned[i][0] == _drop_site:
			picker.select(i)
	picker.item_selected.connect(func(index: int) -> void:
		_drop_site = owned[index][0]
		rebuild())
	row.add_child(picker)
	_body.add_child(row)
	_add_supply_buttons(_target, _drop_site)


func _add_supply_buttons(plug_id: StringName, site_id: StringName) -> void:
	var plug_data := model.plug(plug_id)
	for stack in plug_data.supplies:
		var item_data := model.item(stack.item_id)
		var price := model.plug_price(plug_id, stack.item_id)
		var amount := stack.count
		var item_id := stack.item_id
		var label := "%s: %d× %s" % [plug_data.display_name, amount, item_data.display_name if item_data != null else String(item_id)]
		var reason := "" if price >= 0 else "%s won't deal with you" % plug_data.display_name
		var order := func() -> String: return model.buy_supplies(plug_id, item_id, amount, site_id)
		_body.add_child(_button("%s ($%d)" % [label, maxi(price, 0) * amount], func() -> void: _do(order), reason))

#endregion

#region Widgets

func _heading(text: String) -> Label:
	var label := _label(text, Color(0.55, 0.85, 1.0))
	label.add_theme_font_size_override("font_size", 18)
	return label


func _label(text: String, color := Color.WHITE, expand := false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if expand:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


## A button; disabled with a tooltip when `blocked_reason` isn't empty.
func _button(text: String, on_pressed: Callable, blocked_reason := "") -> Button:
	var button := Button.new()
	button.text = text
	button.disabled = not blocked_reason.is_empty()
	button.tooltip_text = blocked_reason
	button.pressed.connect(on_pressed)
	if button.disabled:
		button.text += "  (%s)" % blocked_reason
	return button


func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	return row


## Dropdown bound to _form[key]. choices: [[value, label], ...].
func _choice(choices: Array, key: String, resets_form := false) -> OptionButton:
	var picker := OptionButton.new()
	if choices.is_empty():
		picker.add_item("(none)")
		picker.disabled = true
		_form.erase(key)
		return picker
	var current: Variant = _form.get(key, choices[0][0])
	_form[key] = choices[0][0]
	for i in choices.size():
		picker.add_item(str(choices[i][1]))
		if choices[i][0] == current:
			picker.select(i)
			_form[key] = current
	picker.item_selected.connect(func(index: int) -> void:
		if resets_form:
			_form = {}
		_form[key] = choices[index][0]
		rebuild())
	return picker


func _skills_text(member: CrewMemberData) -> String:
	var parts: PackedStringArray = []
	var keys: Array = member.skills.keys()
	keys.sort()
	for skill_id: StringName in keys:
		parts.append("%s %d" % [skill_id, member.skill_for(skill_id)])
	return ", ".join(parts) if not parts.is_empty() else "skill %d" % member.skill

#endregion
