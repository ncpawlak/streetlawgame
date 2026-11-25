class_name ObjectiveHud
extends Control
## Top-centre mission panel: mission name, objective lines (done / optional / bonus styling) and
## heat stars. Feeds the active objective's position to the map waypoint/GPS and draws a 3D beacon
## column there.

const REFRESH := 0.2
## Re-route the GPS only when the objective moved this far.
const MOVE_THRESHOLD := 10.0
## Inside this range the beacon alone guides the player (the map clears waypoints at 15 m).
const NEAR_DISTANCE := 25.0
const BONUS_COLOR := Color(1.0, 0.85, 0.3)
const DONE_COLOR := Color(0.55, 0.9, 0.55)
const FAIL_COLOR := Color(1.0, 0.45, 0.4)
const OPTIONAL_COLOR := Color(0.75, 0.8, 0.9)

var map_screen: MapScreen
var _panel: PanelContainer
var _title: Label
var _lines: VBoxContainer
var _heat: Label
var _beacon: MeshInstance3D
var _wait := 0.0
var _dirty := true
var _set_waypoint: Variant = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.45)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 6
	style.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", style)
	_panel.position = Vector2(-220, 12)
	_panel.custom_minimum_size = Vector2(440, 0)
	add_child(_panel)
	var box := VBoxContainer.new()
	_panel.add_child(box)
	_title = _label("", 22)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.modulate = Color(1.0, 0.8, 0.3)
	box.add_child(_title)
	_lines = VBoxContainer.new()
	box.add_child(_lines)
	_heat = _label("", 22)
	_heat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heat.modulate = Color(1.0, 0.35, 0.3)
	box.add_child(_heat)
	_build_beacon()
	Missions.objective_changed.connect(func() -> void: _dirty = true)
	Missions.heat_changed.connect(func(_level: float) -> void: _dirty = true)
	refresh()


func _process(delta: float) -> void:
	_wait -= delta
	if _dirty or _wait <= 0.0:
		_wait = REFRESH
		_dirty = false
		refresh()
	if _beacon.visible:
		_beacon.rotate_y(delta * 1.5)


## Rebuilds the text and updates the waypoint/beacon.
func refresh() -> void:
	var run := Missions.active
	for child in _lines.get_children():
		child.queue_free()
	_title.text = run.def.label() if run != null else ""
	if run != null:
		for line in run.objective_lines():
			_lines.add_child(_line_label(line))
	var stars := Missions.heat.stars()
	_heat.text = "HEAT " + "* ".repeat(stars).strip_edges() if Missions.heat.is_hot() else ""
	if Missions.heat.is_hot() and stars == 0:
		_heat.text = "HEAT ."
	_heat.visible = _heat.text != ""
	_panel.visible = run != null or _heat.visible
	_update_waypoint(Missions.current_waypoint())


## Current objective text lines (for tests and debugging).
func line_texts() -> PackedStringArray:
	var out := PackedStringArray()
	if Missions.active != null:
		for line in Missions.active.objective_lines():
			out.append(line["text"])
	return out


func _line_label(line: Dictionary) -> Label:
	var prefix := "[x] " if line.get("done") else ("[!] " if line.get("failed") else "- ")
	var text := prefix + String(line["text"])
	if line.get("bonus"):
		text += "  (bonus)"
	elif line.get("optional"):
		text += "  (optional)"
	if line.get("indent"):
		text = "    " + text
	var label := _label(text, 18)
	if line.get("failed"):
		label.modulate = FAIL_COLOR
	elif line.get("done"):
		label.modulate = DONE_COLOR
	elif line.get("bonus"):
		label.modulate = BONUS_COLOR
	elif line.get("optional"):
		label.modulate = OPTIONAL_COLOR
	return label


func _update_waypoint(at: Variant) -> void:
	_beacon.visible = at is Vector3
	if not at is Vector3:
		if _set_waypoint != null and map_screen != null and map_screen.has_waypoint() and map_screen.waypoint.distance_to(_flat(_set_waypoint)) < 1.0:
			map_screen.clear_waypoint()
		_set_waypoint = null
		return
	var target: Vector3 = at
	_beacon.global_position = target + Vector3.UP * 30.0
	if map_screen == null or GameState.player == null:
		return
	var player_at := GameState.player.get_focus_position()
	if _flat(player_at).distance_to(_flat(target)) < NEAR_DISTANCE:
		return
	if _set_waypoint == null or _flat(_set_waypoint).distance_to(_flat(target)) > MOVE_THRESHOLD or not map_screen.has_waypoint():
		_set_waypoint = target
		map_screen.set_waypoint(target)


func _flat(at: Vector3) -> Vector3:
	return Vector3(at.x, 0.0, at.z)


func _build_beacon() -> void:
	_beacon = MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	mesh.height = 60.0
	_beacon.mesh = mesh
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.8, 0.15, 0.35)
	_beacon.material_override = material
	_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beacon.top_level = true
	_beacon.visible = false
	add_child(_beacon)


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
