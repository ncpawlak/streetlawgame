class_name InteractionMenu
extends Control
## Action list opened when the focused Interactable has several actions. Keyboard-driven so the mouse
## stays captured: 1-9 or the mouse wheel to pick, E to confirm, right-click / Esc to close.
## Doesn't pause the game; it closes when the player walks away.

var interactor: Interactor
var is_open := false
var selected := 0

var _interactable: Interactable
var _actions: Array[InteractionAction] = []
var _title: Label
var _list: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	offset_left = -420.0
	offset_right = -40.0
	offset_top = -160.0
	offset_bottom = 160.0
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_title = _make_label(22)
	box.add_child(_title)
	_list = VBoxContainer.new()
	box.add_child(_list)
	var keys := _make_label(14)
	keys.text = "[1-9 / wheel] Pick   [E] Confirm   [RMB / Esc] Close"
	keys.modulate.a = 0.7
	box.add_child(keys)
	visible = false


func _process(_delta: float) -> void:
	if interactor == null or not is_instance_valid(interactor):
		var player := GameState.player
		var found := player.get("interactor") as Interactor if player != null else null
		if found != null:
			bind(found)
	if is_open and (interactor == null or interactor.focused != _interactable or not is_instance_valid(_interactable)):
		close()
	elif is_open:
		_redraw()


func bind(target_interactor: Interactor) -> void:
	interactor = target_interactor
	interactor.menu_requested.connect(open)


func open(interactable: Interactable, listed: Array[InteractionAction]) -> void:
	_interactable = interactable
	_actions = listed
	selected = 0
	for i in _actions.size():
		if _actions[i].is_available(_context(_actions[i])):
			selected = i
			break
	is_open = true
	visible = true
	_redraw()


func close() -> void:
	is_open = false
	visible = false
	_interactable = null
	_actions.clear()


## Runs the action at [param index] through the Interactor (so channelling and costs apply).
func confirm(index: int) -> void:
	if index < 0 or index >= _actions.size():
		return
	var action := _actions[index]
	var on := _interactable
	close()
	interactor.start(action, on)


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("interact"):
		confirm(selected)
	elif event.is_action_pressed("aim") or event.is_action_pressed("ui_cancel"):
		close()
	elif event.is_action_pressed("next_weapon"):
		selected = wrapi(selected + 1, 0, _actions.size())
	elif event.is_action_pressed("prev_weapon"):
		selected = wrapi(selected - 1, 0, _actions.size())
	else:
		var picked := -1
		for i in mini(_actions.size(), InputSetup.WEAPON_HOTKEYS):
			if event.is_action_pressed("weapon_%d" % (i + 1)):
				picked = i
		if picked < 0:
			return
		confirm(picked)
	get_viewport().set_input_as_handled()


func _redraw() -> void:
	_title.text = _interactable.label() if _interactable != null else ""
	while _list.get_child_count() < _actions.size():
		_list.add_child(_make_label(18))
	for i in _list.get_child_count():
		var row := _list.get_child(i) as Label
		row.visible = i < _actions.size()
		if not row.visible:
			continue
		var ctx := _context(_actions[i])
		var reason := _actions[i].unavailable_reason(ctx)
		row.text = "%s%d. %s%s" % ["> " if i == selected else "   ", i + 1, _actions[i].make_label(ctx), "  - " + reason if reason != "" else ""]
		row.modulate = Color.WHITE if reason == "" else Color(0.6, 0.6, 0.6)


func _context(action: InteractionAction) -> ActionContext:
	return _interactable.make_context(interactor.actor, action)


func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	return label
