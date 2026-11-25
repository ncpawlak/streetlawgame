class_name MapScreen
extends Control
## Full-screen pause map. [kbd]M[/kbd] opens it and pauses the game; M or Esc closes it. Drag or
## WASD/arrows pan, the wheel or Q/E zoom (whole North End down to a few blocks), clicking a marker
## shows its info card, right-click sets (or, on the pin, clears) a GPS waypoint shown on the
## minimap, Space/C recentres on the player. Markers come from [MapMarkers]; the legend filters them.

signal waypoint_changed

const MIN_ZOOM := 120.0
const CAMERA_HEIGHT := 200.0
const PAN_SPEED := 0.9
const ZOOM_SPEED := 1.6
const WHEEL_STEP := 1.15
const DRAG_THRESHOLD := 5.0
const MARKER_RADIUS := 10.0
const PICK_RADIUS := 14.0
## Below this zoom marker titles are drawn next to the pins.
const LABEL_ZOOM := 420.0
## Reaching the waypoint within this many metres clears it.
const ARRIVE_DISTANCE := 15.0
## The GPS route is recomputed once the player has moved this far from where it was computed.
const REROUTE_DISTANCE := 12.0
const PAN_KEYS := {
	KEY_W: Vector2.UP, KEY_UP: Vector2.UP, KEY_S: Vector2.DOWN, KEY_DOWN: Vector2.DOWN,
	KEY_A: Vector2.LEFT, KEY_LEFT: Vector2.LEFT, KEY_D: Vector2.RIGHT, KEY_RIGHT: Vector2.RIGHT,
}
const ROUTE_COLOR := Color(1.0, 0.3, 0.85)

var is_open := false
## Visible height of the map in metres (the ortho camera size).
var zoom := 600.0
## World XZ at the centre of the screen.
var center := Vector2.ZERO
var markers: Array[Dictionary] = []
var selected: Dictionary = {}
var waypoint := Vector3.ZERO
## Street route from the player to the waypoint (world points), refreshed by [method update_route].
var route := PackedVector3Array()

var _has_waypoint := false
var _route_from := Vector3.INF
var _hidden := {}
var _hovered: Dictionary = {}
var _was_paused := false
var _was_mouse_mode := Input.MOUSE_MODE_CAPTURED
var _press_at := Vector2.ZERO
var _left_down := false
var _dragging := false
var _font: Font

var _viewport: SubViewport
var _camera: Camera3D
var _overlay: Control
var _card: PanelContainer
var _card_title: Label
var _card_category: Label
var _card_body: Label
var _mission_label: Label
var _toggles := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_font = ThemeDB.fallback_font
	_build()


## Physical keys held while the map is open (pan/zoom), fed from [method _input] events.
var _held := {}


func _unhandled_input(event: InputEvent) -> void:
	if not is_open and event.is_action_pressed("toggle_map") and open():
		get_viewport().set_input_as_handled()


## Keys are taken before anything else while open so Q/E zoom instead of opening the weapon wheel
## or interacting. Mouse input goes through [method _gui_input] so the legend stays clickable.
func _input(event: InputEvent) -> void:
	if not is_open or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if key.pressed:
		_held[key.physical_keycode] = true
	else:
		_held.erase(key.physical_keycode)
	if key.pressed and not key.echo:
		if event.is_action("toggle_map") or event.is_action("ui_cancel"):
			close()
		elif key.physical_keycode in [KEY_SPACE, KEY_C]:
			recentre()
		elif key.physical_keycode == KEY_BACKSPACE:
			clear_waypoint()
	get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if button.pressed:
					zoom_by(1.0 / WHEEL_STEP, button.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					zoom_by(WHEEL_STEP, button.position)
			MOUSE_BUTTON_LEFT:
				if button.pressed:
					_left_down = true
					_dragging = false
					_press_at = button.position
				else:
					if _left_down and not _dragging:
						select_marker(marker_at(button.position))
					_left_down = false
					_dragging = false
			MOUSE_BUTTON_RIGHT:
				if button.pressed:
					_right_click(button.position)
		accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _left_down and (_dragging or motion.position.distance_to(_press_at) > DRAG_THRESHOLD):
			_dragging = true
			pan(-motion.relative / _scale())
		var hovered := marker_at(motion.position)
		if hovered != _hovered:
			_hovered = hovered
			_overlay.queue_redraw()
		accept_event()


func _process(delta: float) -> void:
	if not is_open:
		return
	var direction := Vector2.ZERO
	for keycode: Key in PAN_KEYS:
		if _held.has(keycode):
			direction += PAN_KEYS[keycode]
	if direction != Vector2.ZERO:
		pan(direction.normalized() * zoom * PAN_SPEED * delta)
	if _held.has(KEY_Q):
		zoom_by(exp(-ZOOM_SPEED * delta))
	if _held.has(KEY_E):
		zoom_by(exp(ZOOM_SPEED * delta))
	_overlay.queue_redraw()


## Opens the map and pauses the game. False when it's already open or something else (the weapon
## wheel, a dialogue) has the game paused.
func open() -> bool:
	if is_open or get_tree().paused:
		return false
	is_open = true
	visible = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	_was_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_apply_environment()
	refresh_markers()
	select_marker({})
	recentre()
	return true


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	_held.clear()
	_left_down = false
	_dragging = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	get_tree().paused = _was_paused
	Input.mouse_mode = _was_mouse_mode


func refresh_markers() -> void:
	markers = MapMarkers.collect(get_tree())
	var current := markers.filter(func(m: Dictionary) -> bool: return m["current"])
	_mission_label.text = "Current mission: %s" % current[0]["title"] if not current.is_empty() else "The North End is yours"
	if not selected.is_empty():
		var same := markers.filter(func(m: Dictionary) -> bool: return m["id"] == selected["id"])
		select_marker(same[0] if not same.is_empty() else {})
	_overlay.queue_redraw()


func max_zoom() -> float:
	return maxf(GameState.city_extent * 1.1, MIN_ZOOM * 2.0)


func set_zoom(value: float) -> void:
	zoom = clampf(value, MIN_ZOOM, max_zoom())
	_camera.size = zoom
	_clamp_center()


## Multiplies the zoom; with [param anchor] (screen px) the world point under it stays put.
func zoom_by(factor: float, anchor: Variant = null) -> void:
	var before := screen_to_world(anchor) if anchor is Vector2 else Vector3.ZERO
	set_zoom(zoom * factor)
	if anchor is Vector2:
		var after := screen_to_world(anchor)
		pan(Vector2(before.x - after.x, before.z - after.z))


## Moves the view by [param world_delta] metres (X east, Y south).
func pan(world_delta: Vector2) -> void:
	center += world_delta
	_clamp_center()


func recentre() -> void:
	var player := GameState.player
	if player != null:
		var at := player.get_focus_position()
		center = Vector2(at.x, at.z)
	else:
		center = Vector2.ZERO
	_clamp_center()


func has_waypoint() -> bool:
	return _has_waypoint


func set_waypoint(at: Vector3) -> void:
	waypoint = Vector3(at.x, 0.0, at.z)
	_has_waypoint = true
	route = PackedVector3Array()
	_route_from = Vector3.INF
	if GameState.player != null:
		update_route(GameState.player.get_focus_position(), true)
	waypoint_changed.emit()
	if _overlay != null:
		_overlay.queue_redraw()


func clear_waypoint() -> void:
	if not _has_waypoint:
		return
	_has_waypoint = false
	route = PackedVector3Array()
	_route_from = Vector3.INF
	waypoint_changed.emit()
	if _overlay != null:
		_overlay.queue_redraw()


## Recomputes the street route from [param from] when the player has moved enough (or [param force]).
## Clears the waypoint on arrival.
func update_route(from: Vector3, force := false) -> void:
	if not _has_waypoint:
		return
	if Vector2(from.x - waypoint.x, from.z - waypoint.z).length() < ARRIVE_DISTANCE:
		clear_waypoint()
		EventBus.notify.emit("Waypoint reached.")
		return
	if not force and _route_from != Vector3.INF and from.distance_to(_route_from) < REROUTE_DISTANCE:
		return
	_route_from = from
	route = RoadGraph.shared().route(from, waypoint)


func set_category_visible(category: StringName, shown: bool) -> void:
	if shown:
		_hidden.erase(category)
	else:
		_hidden[category] = true
	if _toggles.has(category):
		(_toggles[category] as CheckBox).set_pressed_no_signal(shown)
	if not selected.is_empty() and not is_marker_visible(selected):
		select_marker({})
	if _overlay != null:
		_overlay.queue_redraw()


func is_category_visible(category: StringName) -> bool:
	return not _hidden.has(category)


## A marker shows while any of its categories is enabled.
func is_marker_visible(marker: Dictionary) -> bool:
	for category: StringName in marker["categories"]:
		if is_category_visible(category):
			return true
	return false


func visible_markers() -> Array[Dictionary]:
	var shown: Array[Dictionary] = []
	for marker in markers:
		if is_marker_visible(marker):
			shown.append(marker)
	return shown


## Topmost visible marker within [constant PICK_RADIUS] of [param at] (screen px), or {}.
func marker_at(at: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := PICK_RADIUS
	for marker in visible_markers():
		var distance := marker_screen_position(marker).distance_to(at)
		if distance <= best_distance:
			best = marker
			best_distance = distance
	return best


func select_marker(marker: Dictionary) -> void:
	selected = marker
	_card.visible = not marker.is_empty()
	if marker.is_empty():
		return
	var primary: Dictionary = MapMarkers.category(marker["categories"][0])
	_card_title.text = marker["title"]
	_card_category.text = primary.get("label", "") + ("  -  COMING SOON" if marker["coming_soon"] else "")
	_card_category.modulate = marker["color"].lightened(0.2)
	var body: String = marker["info"]
	if GameState.player != null:
		body += "\n%d m away" % roundi(GameState.player.get_focus_position().distance_to(marker["position"]))
	_card_body.text = body
	_overlay.queue_redraw()


func world_to_screen(at: Vector3) -> Vector2:
	return _view_size() * 0.5 + (Vector2(at.x, at.z) - center) * _scale()


func screen_to_world(at: Vector2) -> Vector3:
	var world := center + (at - _view_size() * 0.5) / _scale()
	return Vector3(world.x, 0.0, world.y)


func marker_screen_position(marker: Dictionary) -> Vector2:
	return world_to_screen(marker["position"]) + (marker.get("offset", Vector2.ZERO) as Vector2)


func _right_click(at: Vector2) -> void:
	if _has_waypoint and world_to_screen(waypoint).distance_to(at) <= PICK_RADIUS:
		clear_waypoint()
		return
	var marker := marker_at(at)
	set_waypoint(marker["position"] if not marker.is_empty() else screen_to_world(at))


func _scale() -> float:
	return _view_size().y / zoom


func _view_size() -> Vector2:
	return size if size.y > 0.0 else Vector2(1600.0, 900.0)


func _clamp_center() -> void:
	var bounds := _bounds()
	var half := _view_size() * 0.5 / _scale()
	for axis in 2:
		var low: float = bounds.position[axis] + half[axis]
		var high: float = bounds.end[axis] - half[axis]
		center[axis] = (bounds.position[axis] + bounds.end[axis]) * 0.5 if low > high else clampf(center[axis], low, high)
	if _camera != null:
		_camera.position = Vector3(center.x, CAMERA_HEIGHT, center.y)


## Playable area in world XZ, with a margin so edge markers can be centred.
func _bounds() -> Rect2:
	var rect := CityGenerator.PLAY_RECT_PX
	var a := CityGenerator.px_to_world(rect.position)
	var b := CityGenerator.px_to_world(rect.end)
	return Rect2(Vector2(a.x, a.z), Vector2(b.x - a.x, b.z - a.z)).grow(120.0)


## The world environment without fog, so the top-down view stays crisp.
func _apply_environment() -> void:
	var world := _viewport.find_world_3d()
	if world == null or world.environment == null or _camera.environment != null:
		return
	var environment := world.environment.duplicate() as Environment
	environment.fog_enabled = false
	_camera.environment = environment


func _draw_overlay() -> void:
	if not is_open:
		return
	if is_category_visible(&"turf"):
		_draw_turf()
	if _has_waypoint:
		_draw_route()
	var labels := zoom <= LABEL_ZOOM
	for marker in visible_markers():
		_draw_marker(marker, labels)
	_draw_player()


func _draw_turf() -> void:
	for district_id in Turf.all_districts():
		var district := Turf.district_node(district_id)
		if district == null:
			continue
		var color := GameState.gang_color(Turf.owner_of(district_id))
		var half := Vector3(district.extents.x, 0.0, district.extents.y) * 0.5
		var top_left := world_to_screen(district.global_position - half)
		var rect := Rect2(top_left, world_to_screen(district.global_position + half) - top_left)
		_overlay.draw_rect(rect, Color(color, 0.18))
		_overlay.draw_rect(rect, Color(color, 0.8), false, 3.0)
		var text := "%s  (%s)" % [Turf.display_name(district_id).to_upper(), GameState.gang_name(Turf.owner_of(district_id))]
		var font_size := 22
		var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		_overlay.draw_string_outline(_font, Vector2(rect.get_center().x - width * 0.5, rect.position.y + 30.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6, Color.BLACK)
		_overlay.draw_string(_font, Vector2(rect.get_center().x - width * 0.5, rect.position.y + 30.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color.lightened(0.45))


func _draw_route() -> void:
	if route.size() >= 2:
		var points := PackedVector2Array()
		for point in route:
			points.append(world_to_screen(point))
		_overlay.draw_polyline(points, Color.BLACK, 8.0, true)
		_overlay.draw_polyline(points, ROUTE_COLOR, 4.5, true)
	var at := world_to_screen(waypoint)
	_overlay.draw_line(at, at + Vector2(0.0, -30.0), Color.BLACK, 4.0)
	_overlay.draw_line(at, at + Vector2(0.0, -30.0), Color.WHITE, 2.0)
	_overlay.draw_colored_polygon(PackedVector2Array([at + Vector2(1.0, -30.0), at + Vector2(20.0, -24.0), at + Vector2(1.0, -18.0)]), ROUTE_COLOR)
	_overlay.draw_circle(at, 5.0, ROUTE_COLOR)
	_overlay.draw_circle(at, 5.0, Color.BLACK, false, 1.5)


func _draw_marker(marker: Dictionary, label: bool) -> void:
	var anchor: Vector2 = world_to_screen(marker["position"])
	var at := marker_screen_position(marker)
	var color: Color = marker["color"]
	var radius := MARKER_RADIUS
	if marker.has("offset"):
		_overlay.draw_line(anchor, at, Color(0.0, 0.0, 0.0, 0.8), 3.0)
		_overlay.draw_line(anchor, at, color, 1.5)
	var highlighted: bool = marker == _hovered or (not selected.is_empty() and marker["id"] == selected["id"])
	if highlighted:
		radius += 3.0
	if marker["current"]:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 200.0)
		_overlay.draw_circle(at, radius + 6.0 + pulse * 4.0, Color(color, 0.9), false, 2.5)
	if marker["categories"][0] == &"objective":
		_overlay.draw_colored_polygon(_diamond(at, radius + 3.0), Color.BLACK)
		_overlay.draw_colored_polygon(_diamond(at, radius + 1.0), color)
	else:
		_overlay.draw_circle(at, radius + 1.5, Color.BLACK)
		_overlay.draw_circle(at, radius, color)
	if marker["coming_soon"]:
		_overlay.draw_arc(at, radius + 1.5, 0.0, TAU, 20, Color(1.0, 1.0, 1.0, 0.85), 1.5)
	if highlighted:
		_overlay.draw_circle(at, radius + 3.0, Color.WHITE, false, 2.0)
	var glyph: String = marker["glyph"]
	var glyph_size := 14
	var glyph_width := _font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, glyph_size).x
	var text_color := Color.BLACK if color.get_luminance() > 0.45 else Color.WHITE
	_overlay.draw_string(_font, at + Vector2(-glyph_width * 0.5, 5.0), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, glyph_size, text_color)
	if label or highlighted:
		var title: String = marker["title"]
		_overlay.draw_string_outline(_font, at + Vector2(radius + 5.0, 5.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 5, Color.BLACK)
		_overlay.draw_string(_font, at + Vector2(radius + 5.0, 5.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)


func _draw_player() -> void:
	var player := GameState.player
	if player == null:
		return
	var at := world_to_screen(player.get_focus_position())
	var forward := -player.global_basis.z
	if player.current_vehicle != null:
		forward = player.current_vehicle.global_basis.z
	var dir := Vector2(forward.x, forward.z).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.UP
	var side := dir.orthogonal()
	var arrow := PackedVector2Array([at + dir * 14.0, at - dir * 9.0 + side * 9.0, at - dir * 4.0, at - dir * 9.0 - side * 9.0])
	_overlay.draw_colored_polygon(arrow, Color.WHITE)
	_overlay.draw_polyline(arrow + PackedVector2Array([arrow[0]]), Color.BLACK, 2.0, true)


func _diamond(at: Vector2, radius: float) -> PackedVector2Array:
	return PackedVector2Array([at + Vector2(0.0, -radius), at + Vector2(radius, 0.0), at + Vector2(0.0, radius), at + Vector2(-radius, 0.0)])


func _build() -> void:
	var background := ColorRect.new()
	background.color = Color(0.08, 0.09, 0.1)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var container := SubViewportContainer.new()
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(container)
	_viewport = SubViewport.new()
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	container.add_child(_viewport)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_camera.far = CAMERA_HEIGHT + 50.0
	# World geometry only; markers and turf are drawn in 2D on the overlay.
	_camera.cull_mask = 1
	_camera.size = zoom
	_viewport.add_child(_camera)
	_camera.make_current()

	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)

	var header := ColorRect.new()
	header.color = Color(0.0, 0.0, 0.0, 0.55)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	header.offset_left = -330.0
	header.offset_right = 330.0
	header.offset_top = 8.0
	header.offset_bottom = 90.0
	add_child(header)
	var title := _label("NORTH END  -  PAUSED", 30)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.offset_left = -400.0
	title.offset_right = 400.0
	title.offset_top = 14.0
	add_child(title)
	_mission_label = _label("", 20)
	_mission_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_mission_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mission_label.offset_left = -400.0
	_mission_label.offset_right = 400.0
	_mission_label.offset_top = 54.0
	_mission_label.modulate = MapMarkers.category(&"objective")["color"]
	add_child(_mission_label)

	var help := _label("[M / Esc] Close    [Drag / WASD] Pan    [Wheel / Q E] Zoom    [Click] Info    [Right-click] Set / clear waypoint    [Space] Recentre", 16)
	help.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.offset_left = -700.0
	help.offset_right = 700.0
	help.offset_top = -40.0
	help.offset_bottom = -14.0
	add_child(help)

	_build_legend()
	_build_card()


func _build_legend() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(20.0, 20.0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(panel)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	panel.add_child(list)
	list.add_child(_label("LEGEND", 18))
	for entry: Dictionary in MapMarkers.CATEGORIES:
		var row := HBoxContainer.new()
		list.add_child(row)
		var swatch := Label.new()
		swatch.text = entry["glyph"] if entry["glyph"] != "" else "#"
		swatch.custom_minimum_size = Vector2(22.0, 0.0)
		swatch.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		swatch.add_theme_color_override("font_color", entry["color"])
		swatch.add_theme_font_size_override("font_size", 18)
		row.add_child(swatch)
		var toggle := CheckBox.new()
		toggle.text = entry["label"]
		toggle.button_pressed = true
		toggle.focus_mode = Control.FOCUS_NONE
		var id: StringName = entry["id"]
		toggle.toggled.connect(func(on: bool) -> void: set_category_visible(id, on))
		row.add_child(toggle)
		_toggles[id] = toggle
	var recentre_button := Button.new()
	recentre_button.text = "Recentre on me [Space]"
	recentre_button.focus_mode = Control.FOCUS_NONE
	recentre_button.pressed.connect(recentre)
	list.add_child(recentre_button)
	var clear_button := Button.new()
	clear_button.text = "Clear waypoint [Backspace]"
	clear_button.focus_mode = Control.FOCUS_NONE
	clear_button.pressed.connect(clear_waypoint)
	list.add_child(clear_button)


func _build_card() -> void:
	_card = PanelContainer.new()
	_card.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_card.offset_left = -380.0
	_card.offset_right = -20.0
	_card.offset_top = 20.0
	_card.add_theme_stylebox_override("panel", _panel_style())
	_card.visible = false
	add_child(_card)
	var list := VBoxContainer.new()
	_card.add_child(list)
	_card_title = _label("", 22)
	_card_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(_card_title)
	_card_category = _label("", 15)
	list.add_child(_card_category)
	_card_body = _label("", 16)
	_card_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_body.custom_minimum_size = Vector2(320.0, 0.0)
	list.add_child(_card_body)
	var buttons := HBoxContainer.new()
	list.add_child(buttons)
	var route_button := Button.new()
	route_button.text = "Set waypoint"
	route_button.focus_mode = Control.FOCUS_NONE
	route_button.pressed.connect(func() -> void:
		if not selected.is_empty():
			set_waypoint(selected["position"]))
	buttons.add_child(route_button)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(func() -> void: select_marker({}))
	buttons.add_child(close_button)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.07, 0.85)
	style.border_color = Color(1.0, 1.0, 1.0, 0.15)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12.0)
	return style


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	return label
