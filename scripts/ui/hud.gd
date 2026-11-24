extends CanvasLayer
## HUD: cash, respect, health, current turf, capture progress, interaction hints, notifications and minimap.

const MINIMAP_SIZE := 240.0
const MINIMAP_ZOOM := 160.0
const MAP_CAMERA_HEIGHT := 200.0
const NOTIFICATION_LIFETIME := 4.0

var _cash_label: Label
var _respect_label: Label
var _health_bar: ProgressBar
var _turf_label: Label
var _hint_label: Label
var _capture_bar: ProgressBar
var _crosshair: Label
var _feed: VBoxContainer
var _map_container: SubViewportContainer
var _map_camera: Camera3D
var _player_marker: MeshInstance3D
var _map_expanded := false


func _ready() -> void:
	_build_stats()
	_build_minimap()
	_build_center()
	EventBus.cash_changed.connect(func(amount: int) -> void: _cash_label.text = "$%d" % amount)
	EventBus.respect_changed.connect(func(amount: int) -> void: _respect_label.text = "Respect %d" % amount)
	EventBus.player_health_changed.connect(_on_health_changed)
	EventBus.notify.connect(_push_notification)
	_cash_label.text = "$%d" % GameState.cash
	_respect_label.text = "Respect %d" % GameState.respect


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_map"):
		_set_map_expanded(not _map_expanded)


func _process(_delta: float) -> void:
	var player := GameState.player
	if player == null:
		return
	var focus := player.get_focus_position()
	if _map_expanded:
		_map_camera.global_position = Vector3(0.0, MAP_CAMERA_HEIGHT, 0.0)
	else:
		_map_camera.global_position = Vector3(focus.x, MAP_CAMERA_HEIGHT, focus.z)
	_player_marker.global_position = Vector3(focus.x, 90.0, focus.z)
	_crosshair.visible = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not _map_expanded
	_update_turf(GameState.current_territory)
	_update_hint(player)


func _update_turf(territory: Territory) -> void:
	if territory == null:
		_turf_label.text = "No man's land"
		_capture_bar.visible = false
		return
	var text := "%s  -  %s" % [territory.display_name, GameState.gang_name(territory.owner_gang)]
	if territory.owner_gang != GameState.PLAYER_GANG:
		var defenders := territory.defenders_remaining()
		text += "\n%d defenders left" % defenders if defenders > 0 else "\nTurf is open - hold it on foot to take over!"
	_turf_label.text = text
	_turf_label.modulate = GameState.gang_color(territory.owner_gang).lightened(0.3)
	_capture_bar.visible = territory.capture_progress > 0.0 and territory.owner_gang != GameState.PLAYER_GANG
	_capture_bar.value = territory.capture_progress * 100.0


func _update_hint(player: Player) -> void:
	if not player.is_on_foot():
		_hint_label.text = "[E] Exit vehicle    [LMB] Drive-by    [Space] Handbrake"
	elif player.nearest_free_vehicle() != null:
		_hint_label.text = "[E] Steal vehicle"
	else:
		_hint_label.text = ""


func _on_health_changed(current: float, maximum: float) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current


func _push_notification(text: String) -> void:
	var label := _make_label(text, 20)
	_feed.add_child(label)
	get_tree().create_timer(NOTIFICATION_LIFETIME).timeout.connect(label.queue_free)


func _set_map_expanded(expanded: bool) -> void:
	_map_expanded = expanded
	if expanded:
		_map_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 60)
		_map_camera.size = maxf(GameState.city_extent, MINIMAP_ZOOM)
	else:
		_map_container.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_map_container.offset_left = -MINIMAP_SIZE - 16.0
		_map_container.offset_right = -16.0
		_map_container.offset_top = 16.0
		_map_container.offset_bottom = 16.0 + MINIMAP_SIZE
		_map_camera.size = MINIMAP_ZOOM


func _build_stats() -> void:
	var panel := VBoxContainer.new()
	panel.position = Vector2(20.0, 16.0)
	add_child(panel)
	_cash_label = _make_label("", 32)
	_cash_label.modulate = Color(0.5, 1.0, 0.5)
	panel.add_child(_cash_label)
	_respect_label = _make_label("", 20)
	panel.add_child(_respect_label)
	_health_bar = ProgressBar.new()
	_health_bar.custom_minimum_size = Vector2(220.0, 14.0)
	_health_bar.show_percentage = false
	_health_bar.value = 100.0
	_health_bar.modulate = Color(1.0, 0.35, 0.35)
	panel.add_child(_health_bar)
	_turf_label = _make_label("", 18)
	panel.add_child(_turf_label)


func _build_minimap() -> void:
	_map_container = SubViewportContainer.new()
	_map_container.stretch = true
	add_child(_map_container)
	var viewport := SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_map_container.add_child(viewport)
	_map_camera = Camera3D.new()
	_map_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_map_camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_map_camera.far = MAP_CAMERA_HEIGHT + 50.0
	viewport.add_child(_map_camera)
	_map_camera.make_current()
	_set_map_expanded(false)

	var marker_mesh := SphereMesh.new()
	marker_mesh.radius = 4.0
	marker_mesh.height = 8.0
	var marker_material := StandardMaterial3D.new()
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_material.albedo_color = Color.WHITE
	marker_mesh.material = marker_material
	_player_marker = MeshInstance3D.new()
	_player_marker.mesh = marker_mesh
	_player_marker.layers = GameState.MAP_LAYER
	_player_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_player_marker.top_level = true
	add_child(_player_marker)


func _build_center() -> void:
	_crosshair = _make_label("+", 28)
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_crosshair)

	_capture_bar = ProgressBar.new()
	_capture_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_capture_bar.custom_minimum_size = Vector2(400.0, 22.0)
	_capture_bar.offset_left = -200.0
	_capture_bar.offset_right = 200.0
	_capture_bar.offset_top = -120.0
	_capture_bar.offset_bottom = -98.0
	_capture_bar.modulate = GameState.gang_color(GameState.PLAYER_GANG).lightened(0.3)
	_capture_bar.visible = false
	add_child(_capture_bar)

	_hint_label = _make_label("", 20)
	_hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.offset_top = -70.0
	_hint_label.offset_left = -400.0
	_hint_label.offset_right = 400.0
	add_child(_hint_label)

	_feed = VBoxContainer.new()
	_feed.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_feed.offset_left = 20.0
	_feed.offset_top = -220.0
	_feed.offset_bottom = -20.0
	_feed.alignment = BoxContainer.ALIGNMENT_END
	add_child(_feed)


func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	return label
