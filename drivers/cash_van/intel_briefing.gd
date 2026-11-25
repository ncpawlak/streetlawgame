class_name IntelBriefing
extends CanvasLayer
## Pre-hit intel briefing for the cash van driver: a top-down map of I-59 with the van's route and
## on-ramp (when known) plus the intel card (route, schedule, guards, cargo). [Enter] starts the
## hit, [I] shows the card again later, and [F6] toggles intel (debug).

signal confirmed

var intel: CashVanIntel
var route: HighwayRoute
## Local-space (route) points of interest drawn on the map.
var player_start := Vector3.ZERO
var stash_point := Vector3.ZERO
## Crew / heat / mask lines the driver adds under the intel ([method set_extra]).
var extra_lines: PackedStringArray = []

var _panel: PanelContainer
var _title: Label
var _body: Label
var _footer: Label
var _map: _RouteMap


func _ready() -> void:
	layer = 20
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.08, 0.9)
	style.border_color = Color(0.95, 0.65, 0.15)
	style.set_border_width_all(2)
	style.set_content_margin_all(18)
	style.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(980.0, 520.0)
	_panel.position = -_panel.custom_minimum_size * 0.5
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_panel.add_child(column)
	_title = _label(26, Color(0.95, 0.7, 0.2))
	column.add_child(_title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(row)
	_map = _RouteMap.new()
	_map.briefing = self
	_map.custom_minimum_size = Vector2(480.0, 380.0)
	row.add_child(_map)
	_body = _label(15, Color(0.92, 0.92, 0.92))
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(440.0, 0.0)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_body)
	_footer = _label(16, Color(0.7, 0.85, 1.0))
	column.add_child(_footer)
	refresh()


func show_intel(new_intel: CashVanIntel, new_route: HighwayRoute, start: Vector3, stash: Vector3) -> void:
	intel = new_intel
	route = new_route
	player_start = start
	stash_point = stash
	visible = true
	refresh()


func refresh(departs_in := -1.0) -> void:
	if _body == null or intel == null:
		return
	_title.text = "INTEL - Viper cash van, I-59" if intel.known else "NO INTEL - Viper cash van, I-59"
	var text := "\n\n".join(intel.lines())
	if intel.known:
		text += "\n\nPlan: wait near the orange on-ramp beacon, tail the van and shoot out all 4 tires. Release the rear doors from the cab, bag what fits and lose the cops."
	else:
		text += "\n\nNo tip on this one. The van will join I-59 somewhere along the loop and you won't know when. Cruise the highway and find it. Buy intel next time (F6 = debug toggle)."
	if not extra_lines.is_empty():
		text += "\n\n" + "\n".join(extra_lines)
	if departs_in >= 0.0 and intel.known:
		text += "\n\nVan leaves in %ds." % ceili(departs_in)
	_body.text = text
	_footer.text = "[Enter] start the hit    [I] show/hide intel    [F6] debug: intel %s (restarts)" % ("ON" if intel.known else "OFF")
	_map.queue_redraw()
	_recenter.call_deferred()


## The card grows with its text: keep it centred on screen.
func _recenter() -> void:
	if _panel == null:
		return
	_panel.reset_size()
	_panel.position = (_panel.get_viewport_rect().size - _panel.size) * 0.5


func set_extra(lines: PackedStringArray) -> void:
	extra_lines = lines
	refresh()


func dismiss() -> void:
	if not visible:
		return
	visible = false
	confirmed.emit()


func _label(size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	return label


## Top-down drawing of the highway loop with the known route, on-ramp and points of interest.
class _RouteMap:
	extends Control

	var briefing: IntelBriefing

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.15, 0.12, 0.95))
		if briefing == null or briefing.route == null or briefing.intel == null:
			return
		var route := briefing.route
		var intel := briefing.intel
		var bounds := Rect2(-route.straight_length * 0.5 - route.turn_radius - 20.0, -route.turn_radius - 30.0, route.straight_length + route.turn_radius * 2.0 + 40.0, route.turn_radius * 2.0 + 60.0)
		var scale := minf(size.x / bounds.size.x, size.y / bounds.size.y)
		var offset := (size - bounds.size * scale) * 0.5
		var to_map := func(local: Vector3) -> Vector2:
			return offset + (Vector2(local.x, local.z) - bounds.position) * scale
		var total := route.length()
		var points := PackedVector2Array()
		var steps := 120
		for i in steps + 1:
			points.append(to_map.call(route.sample(total * i / steps).origin))
		draw_polyline(points, Color(0.35, 0.35, 0.38), maxf(4.0, route.road_width * scale), true)
		draw_string(ThemeDB.fallback_font, to_map.call(Vector3(0.0, 0.0, route.turn_radius + 22.0)) - Vector2(16.0, 0.0), "I-59", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.4, 0.6, 1.0))
		if intel.known:
			draw_polyline(points, Color(0.95, 0.65, 0.15), 3.0, true)
			for i in 10:
				var d := fposmod(intel.start_distance + total * i / 10.0, total)
				var at: Vector2 = to_map.call(route.sample(d).origin)
				var ahead: Vector2 = to_map.call(route.sample(d + 8.0).origin)
				_arrow(at, (ahead - at).normalized(), Color(1.0, 0.8, 0.3))
			var ramp: Vector2 = to_map.call(route.sample(intel.start_distance).origin)
			draw_circle(ramp, 8.0, Color(1.0, 0.55, 0.1))
			draw_string(ThemeDB.fallback_font, ramp + Vector2(10.0, -10.0), "Van on-ramp", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.0, 0.7, 0.3))
		else:
			draw_string(ThemeDB.fallback_font, size * 0.5 - Vector2(60.0, 40.0), "ROUTE ?", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.9, 0.4, 0.4))
		var you: Vector2 = to_map.call(briefing.player_start)
		draw_circle(you, 6.0, Color(0.9, 0.2, 0.2))
		draw_string(ThemeDB.fallback_font, you + Vector2(8.0, 16.0), "You", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.0, 0.5, 0.5))
		var stash: Vector2 = to_map.call(briefing.stash_point)
		draw_rect(Rect2(stash - Vector2(6.0, 6.0), Vector2(12.0, 12.0)), Color(0.3, 0.9, 0.4))
		draw_string(ThemeDB.fallback_font, stash + Vector2(10.0, 5.0), "Stash garage", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.5, 1.0, 0.6))

	func _arrow(at: Vector2, direction: Vector2, color: Color) -> void:
		var side := Vector2(-direction.y, direction.x)
		draw_colored_polygon(PackedVector2Array([at + direction * 7.0, at - direction * 5.0 + side * 5.0, at - direction * 5.0 - side * 5.0]), color)
