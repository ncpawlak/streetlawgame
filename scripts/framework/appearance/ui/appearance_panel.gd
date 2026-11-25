class_name AppearancePanel
extends CanvasLayer
## Greybox appearance UI built in code (opened through PlayerAppearance.open_panel). Modes:
## - &"wardrobe": change into clothes you own, free.
## - &"clothing": clothing store; every variant listed with its price, buying puts it on.
## - &"barber": hairstyle, hair colour, facial hair; each change is paid for.
## Selecting an entry previews it live on the player; an orbiting camera frames them ([Q]/[E] or
## the arrow buttons rotate). Nothing is charged or kept until [method confirm]. Pauses the game.

const MODE_TITLES := {&"wardrobe": "Wardrobe", &"clothing": "Clothing Store", &"barber": "Barber"}
const ACTION_LABELS := {&"wardrobe": "Change clothes", &"clothing": "Browse clothes", &"barber": "Sit in the chair"}
const REMOVABLE: Array[StringName] = [&"hat", &"accessory", &"facial_hair"]
## Orbit camera framing per mode: distance, height of the look-at point, height of the camera.
const FRAMING := {
	&"wardrobe": {"distance": 3.0, "target": 1.0, "height": 1.35},
	&"clothing": {"distance": 3.0, "target": 1.0, "height": 1.35},
	&"barber": {"distance": 1.15, "target": 1.6, "height": 1.7},
}
const ORBIT_SPEED := 1.6
## Barber chair: the camera only swings this far (radians) either side of the face.
const BARBER_ORBIT_LIMIT := 1.3

var is_open := false
var mode: StringName = &"wardrobe"
var site_id: StringName
var slot: StringName = &"top"
## Pending selection: {"item": StringName, "color": int} or empty.
var selection: Dictionary = {}

var _actor: Node3D
var _visual: CharacterVisual
var _anchor: Node3D
var _actor_restore: Variant = null
var _camera: Camera3D
var _previous_camera: Camera3D
var _yaw := 0.0
var _orbit_input := 0.0
var _message := ""
var _was_paused := false
var _previous_mouse_mode := Input.MOUSE_MODE_VISIBLE
var _title: Label
var _tabs: HBoxContainer
var _body: VBoxContainer
var _details: VBoxContainer


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	root.offset_left = -470
	for side in ["left", "right", "top", "bottom"]:
		root.add_theme_constant_override("margin_" + side, 16)
	add_child(root)
	var frame := PanelContainer.new()
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.08, 0.08, 0.1, 0.94)
	background.set_corner_radius_all(6)
	frame.add_theme_stylebox_override(&"panel", background)
	root.add_child(frame)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	frame.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var close_button := Button.new()
	close_button.text = "Done [Esc]"
	close_button.pressed.connect(close)
	header.add_child(close_button)
	_tabs = HBoxContainer.new()
	column.add_child(_tabs)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	_details = VBoxContainer.new()
	column.add_child(_details)
	var orbit := HBoxContainer.new()
	orbit.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(orbit)
	for step: float in [-1.0, 1.0]:
		var button := Button.new()
		button.text = "< Turn [Q]" if step < 0.0 else "Turn [E] >"
		button.button_down.connect(func() -> void: _orbit_input = step)
		button.button_up.connect(func() -> void: _orbit_input = 0.0)
		orbit.add_child(button)


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and (event.keycode == KEY_Q or event.keycode == KEY_E):
		_orbit_input = (-1.0 if event.keycode == KEY_Q else 1.0) if event.pressed else 0.0
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if is_open and _orbit_input != 0.0:
		orbit(_orbit_input * ORBIT_SPEED * delta)


## Opens the panel for [param actor] (the player). [param anchor] is where they stand / sit.
func open(new_mode: StringName, target_site: StringName = &"", actor: Node = null, anchor: Node3D = null) -> void:
	mode = new_mode if MODE_TITLES.has(new_mode) else &"wardrobe"
	site_id = target_site
	_actor = (actor if actor != null else GameState.player) as Node3D
	_visual = _actor.get("visual") as CharacterVisual if _actor != null and "visual" in _actor else null
	_anchor = anchor
	_message = ""
	selection = {}
	slot = slots()[0]
	if not is_open:
		is_open = true
		visible = true
		_was_paused = get_tree().paused
		get_tree().paused = true
		_previous_mouse_mode = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_place_actor()
		_start_camera()
	rebuild()


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	selection = {}
	_orbit_input = 0.0
	_apply_preview()
	if _camera != null:
		_camera.current = false
		_camera.queue_free()
		_camera = null
	if _previous_camera != null and is_instance_valid(_previous_camera):
		_previous_camera.current = true
	if _actor_restore != null and is_instance_valid(_actor):
		_actor.global_transform = _actor_restore
	_actor_restore = null
	get_tree().paused = _was_paused
	Input.mouse_mode = _previous_mouse_mode


## Slots this mode edits.
func slots() -> Array[StringName]:
	return Appearance.HAIR_SLOTS if mode == &"barber" else Appearance.CLOTHING_SLOTS


func select_slot(new_slot: StringName) -> void:
	if not slots().has(new_slot):
		return
	slot = new_slot
	selection = {}
	_message = ""
	_apply_preview()
	rebuild()


## Previews [param item_id] (&"" = take it off) in [param color] on the player.
func select(item_id: StringName, color: int = 0) -> void:
	selection = {"item": item_id, "color": color}
	_message = ""
	_apply_preview()
	rebuild()


## The look shown on the player: the current look plus the pending selection.
func preview_look() -> Appearance:
	var look := PlayerAppearance.look()
	if not selection.is_empty():
		look.set_slot(slot, selection["item"], selection["color"])
	return look


## Price of the pending selection (0 if owned / wardrobe / unchanged).
func selection_price() -> int:
	if selection.is_empty() or selection["item"] == &"" or mode == &"wardrobe":
		return 0
	var item := Appearance.find_item(slot, selection["item"])
	if mode == &"clothing" and PlayerAppearance.owns(selection["item"], selection["color"]):
		return 0
	if mode == &"barber" and _is_current(selection["item"], selection["color"]):
		return 0
	return PlayerAppearance.price_of(item, site_id)


## Buys / equips / pays for the pending selection. Returns "" or why not.
func confirm() -> String:
	if selection.is_empty():
		return "Pick something first"
	var item_id: StringName = selection["item"]
	var color: int = selection["color"]
	var reason := ""
	var price := selection_price()
	if item_id == &"":
		reason = PlayerAppearance.get_haircut(slot, &"") if mode == &"barber" else PlayerAppearance.unequip(slot)
	else:
		match mode:
			&"clothing":
				reason = PlayerAppearance.buy(slot, item_id, color, site_id)
			&"barber":
				reason = PlayerAppearance.get_haircut(slot, item_id, color, site_id)
			_:
				reason = PlayerAppearance.equip(slot, item_id, color)
	if reason == "":
		_message = ("Paid $%d" % price) if price > 0 else "Looking good"
		selection = {}
	else:
		_message = reason
	_apply_preview()
	rebuild()
	return reason


## Rotates the preview camera around the player.
func orbit(radians: float) -> void:
	_yaw += radians
	if mode == &"barber":
		_yaw = clampf(_yaw, -BARBER_ORBIT_LIMIT, BARBER_ORBIT_LIMIT)
	_update_camera()


func camera() -> Camera3D:
	return _camera


func rebuild() -> void:
	if _body == null:
		return
	_title.text = _title_text()
	for container: Node in [_tabs, _body, _details]:
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()
	for tab_slot in slots():
		var tab := Button.new()
		tab.text = Appearance.SLOT_NAMES[tab_slot]
		tab.toggle_mode = true
		tab.button_pressed = tab_slot == slot
		tab.pressed.connect(select_slot.bind(tab_slot))
		_tabs.add_child(tab)
	_body.add_child(_label("Cash: $%d" % GameState.cash, Color(0.7, 0.9, 0.7)))
	if REMOVABLE.has(slot):
		_body.add_child(_entry_row("None", &"", [0], "", Color.WHITE))
	for item in Appearance.catalog(slot):
		var colors := _listed_colors(item)
		if colors.is_empty():
			continue
		var tag := ""
		if mode == &"clothing" and colors.all(func(c: int) -> bool: return PlayerAppearance.owns(item.id, c)):
			tag = "owned"
		elif mode != &"wardrobe":
			tag = "$%d" % PlayerAppearance.price_of(item, site_id)
		_body.add_child(_entry_row(item.label(), item.id, colors, tag, Color.WHITE))
	_build_details()


func _build_details() -> void:
	var worn := PlayerAppearance.look()
	var current_item := worn.item_def(slot)
	_details.add_child(_label("Wearing: %s" % (current_item.variant_label(worn.get_color(slot)) if current_item != null else "nothing"),
		Color(0.75, 0.75, 0.8)))
	if not selection.is_empty():
		var item := Appearance.find_item(slot, selection["item"])
		var text := item.variant_label(selection["color"]) if item != null else "None"
		var price := selection_price()
		var row := HBoxContainer.new()
		var name_label := _label(text + ("  -  $%d" % price if price > 0 else ""), Color.WHITE)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var button := Button.new()
		button.text = _confirm_text(price)
		button.disabled = price > GameState.cash
		button.pressed.connect(func() -> void: confirm())
		row.add_child(button)
		_details.add_child(row)
	if _message != "":
		_details.add_child(_label(_message, Color(1.0, 0.8, 0.3)))
	var preview := preview_look()
	for resource in ContentDB.all(FactionStyleDef.TYPE):
		var style := resource as FactionStyleDef
		if style == null or not PlayerAppearance.has_known_look(style.id):
			continue
		var score := preview.similarity(PlayerAppearance.known_look(style.id))
		var recognised := score >= style.recognition_threshold
		_details.add_child(_label("%s: %s (%d%% match)" % [style.label(), "would recognise you" if recognised else "won't recognise you",
			roundi(score * 100.0)], Color(1.0, 0.45, 0.4) if recognised else Color(0.55, 0.95, 0.6)))


func _confirm_text(price: int) -> String:
	if selection["item"] == &"":
		return "Take off" if mode != &"barber" else "Shave off"
	if price > 0:
		return "Pay $%d" % price if mode == &"barber" else "Buy & wear $%d" % price
	return "Wear"


func _entry_row(text: String, item_id: StringName, colors: Array[int], tag: String, color: Color) -> Control:
	var column := VBoxContainer.new()
	var row := HBoxContainer.new()
	column.add_child(row)
	var button := Button.new()
	button.text = text + ("   " + tag if tag != "" else "")
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_color_override("font_color", color)
	var selected: bool = not selection.is_empty() and selection["item"] == item_id
	var worn := _is_current(item_id, -1)
	if selected or (selection.is_empty() and worn):
		button.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	button.pressed.connect(select.bind(item_id, colors[0]))
	row.add_child(button)
	var item := Appearance.find_item(slot, item_id) if item_id != &"" else null
	if item != null and not item.colors.is_empty():
		var swatches := HBoxContainer.new()
		swatches.add_theme_constant_override("separation", 3)
		for index in colors:
			swatches.add_child(_swatch(item, index))
		column.add_child(swatches)
	return column


func _swatch(item: AppearanceItemDef, index: int) -> Button:
	var swatch := Button.new()
	swatch.custom_minimum_size = Vector2(26, 20)
	swatch.tooltip_text = item.color_name(index)
	var style := StyleBoxFlat.new()
	style.bg_color = item.colors[index]
	var chosen: bool = not selection.is_empty() and selection["item"] == item.id and selection["color"] == index
	style.set_border_width_all(3 if chosen else 1)
	style.border_color = Color(1.0, 0.85, 0.35) if chosen else Color(0.1, 0.1, 0.1)
	for state in ["normal", "hover", "pressed", "focus"]:
		swatch.add_theme_stylebox_override(state, style)
	swatch.pressed.connect(select.bind(item.id, index))
	return swatch


## Colour variants to list: owned ones in the wardrobe, all of them elsewhere.
func _listed_colors(item: AppearanceItemDef) -> Array[int]:
	var result: Array[int] = []
	for index in item.variant_count():
		if mode != &"wardrobe" or PlayerAppearance.owns(item.id, index):
			result.append(index)
	return result


func _is_current(item_id: StringName, color: int) -> bool:
	var worn := PlayerAppearance.look()
	return worn.get_item(slot) == item_id and (color < 0 or item_id == &"" or worn.get_color(slot) == color)


func _title_text() -> String:
	var title: String = MODE_TITLES[mode]
	var business_site := Businesses.site(site_id) if site_id != &"" else null
	if business_site != null:
		title = business_site.label() + (" (yours, 50% off)" if Businesses.is_owned(site_id) else "")
	return title


func _apply_preview() -> void:
	if _visual != null and is_instance_valid(_visual):
		_visual.apply_appearance(preview_look() if is_open else PlayerAppearance.look())


func _place_actor() -> void:
	_actor_restore = null
	if _actor == null or _anchor == null or not _anchor.is_inside_tree():
		return
	if mode == &"barber":
		_actor_restore = _actor.global_transform
	_actor.global_position = _anchor.global_position
	_actor.global_rotation = Vector3(0.0, _anchor.global_rotation.y, 0.0)


func _start_camera() -> void:
	if _actor == null or not _actor.is_inside_tree():
		return
	_previous_camera = get_viewport().get_camera_3d()
	_camera = Camera3D.new()
	_camera.name = "AppearanceCamera"
	_camera.fov = 50.0 if mode == &"barber" else 60.0
	add_child(_camera)
	_yaw = 0.0
	_update_camera()
	_camera.current = true


func _update_camera() -> void:
	if _camera == null or _actor == null or not is_instance_valid(_actor):
		return
	var framing: Dictionary = FRAMING[mode]
	var facing := -_actor.global_basis.z
	facing.y = 0.0
	facing = facing.normalized() if facing.length() > 0.01 else Vector3.FORWARD
	# Offset sideways so the character isn't hidden behind the panel on the right.
	var side := facing.cross(Vector3.UP).normalized()
	var direction := facing.rotated(Vector3.UP, _yaw)
	var base := _actor.global_position
	var target := base + Vector3.UP * float(framing["target"]) - side * float(framing["distance"]) * 0.18
	_camera.global_position = base + direction * float(framing["distance"]) + Vector3.UP * float(framing["height"]) \
		- side * float(framing["distance"]) * 0.18
	_camera.look_at(target, Vector3.UP)


func _label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", color)
	return label
