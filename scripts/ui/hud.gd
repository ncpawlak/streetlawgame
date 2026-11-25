extends CanvasLayer
## HUD: cash, respect, health, current turf, capture progress, interaction hints, notifications,
## the minimap (with the GPS route to the map waypoint) and the full-screen pause map ([MapScreen]).

const MINIMAP_SIZE := 240.0
const MINIMAP_ZOOM := 160.0
const MAP_CAMERA_HEIGHT := 200.0
const NOTIFICATION_LIFETIME := 4.0

var _cash_label: Label
var _respect_label: Label
var _health_bar: ProgressBar
var _vehicle_bar: ProgressBar
var _turf_label: Label
var _hint_label: Label
var _capture_bar: ProgressBar
var _crosshair: Label
var _feed: VBoxContainer
var _map_container: SubViewportContainer
var _map_camera: Camera3D
var _player_marker: MeshInstance3D
var _gps: Control
var _weapon_label: Label
var _ammo_label: Label
var _reload_bar: ProgressBar
var _keys_label: Label
var _damage_flash: ColorRect
var _hit_marker_left := 0.0
var _last_health := -1.0
var _connected_inventory: WeaponInventory
var weapon_wheel: WeaponWheel
var interaction_prompt: InteractionPrompt
var interaction_menu: InteractionMenu
var dialogue_view: DialogueView
var map_screen: MapScreen


func _ready() -> void:
	_build_stats()
	_build_minimap()
	_build_center()
	_build_weapon_panel()
	weapon_wheel = WeaponWheel.new()
	add_child(weapon_wheel)
	interaction_prompt = InteractionPrompt.new()
	add_child(interaction_prompt)
	interaction_menu = InteractionMenu.new()
	add_child(interaction_menu)
	dialogue_view = DialogueView.new()
	add_child(dialogue_view)
	map_screen = MapScreen.new()
	add_child(map_screen)
	map_screen.waypoint_changed.connect(_gps.queue_redraw)
	EventBus.cash_changed.connect(func(amount: int) -> void: _cash_label.text = "$%d" % amount)
	EventBus.respect_changed.connect(func(amount: int) -> void: _respect_label.text = "Respect %d" % amount)
	EventBus.player_health_changed.connect(_on_health_changed)
	EventBus.notify.connect(_push_notification)
	_cash_label.text = "$%d" % GameState.cash
	_respect_label.text = "Respect %d" % GameState.respect
	Narrative.hud_visibility_changed.connect(_refresh_visibility.unbind(1))
	EventBus.dialogue_started.connect(_refresh_visibility.unbind(2))
	EventBus.dialogue_ended.connect(_refresh_visibility.unbind(2))
	_refresh_visibility()


## Cutscenes hide the HUD (Narrative.hide_hud); a conversation keeps it so the DialogueView shows.
func _refresh_visibility() -> void:
	visible = Narrative.is_hud_visible() or dialogue_view.is_open()


func _process(delta: float) -> void:
	var player := GameState.player
	if player == null:
		return
	_update_weapon(player, delta)
	_update_vehicle(player.current_vehicle)
	_damage_flash.color.a = move_toward(_damage_flash.color.a, 0.0, delta * 1.5)
	var focus := player.get_focus_position()
	_map_camera.global_position = Vector3(focus.x, MAP_CAMERA_HEIGHT, focus.z)
	map_screen.update_route(focus)
	_gps.queue_redraw()
	_player_marker.global_position = Vector3(focus.x, 90.0, focus.z)
	_crosshair.visible = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not map_screen.is_open and not weapon_wheel.is_open
	_update_turf(Turf.current_district_id)
	_update_hint(player)


func _update_turf(district_id: StringName) -> void:
	if district_id == &"":
		_turf_label.text = "No man's land"
		_capture_bar.visible = false
		return
	var holder := Turf.owner_of(district_id)
	var text := "%s  -  %s  -  %s" % [Turf.display_name(district_id), Turf.area_display_name(Turf.area_of(district_id)), GameState.gang_name(holder)]
	var district := Turf.district_node(district_id)
	if district != null and holder != GameState.PLAYER_GANG:
		var status := district.capture_rule().status_text(district)
		if status != "":
			text += "\n" + status
	_turf_label.text = text
	_turf_label.modulate = GameState.gang_color(holder).lightened(0.3)
	var progress := Turf.district_state(district_id).capture_progress
	_capture_bar.visible = progress > 0.0 and holder != GameState.PLAYER_GANG
	_capture_bar.value = progress * 100.0


func _update_vehicle(vehicle: Vehicle) -> void:
	_vehicle_bar.visible = vehicle != null
	if vehicle == null:
		return
	_vehicle_bar.max_value = vehicle.max_health
	_vehicle_bar.value = vehicle.health
	match vehicle.damage_state:
		Vehicle.DamageState.BURNING:
			_vehicle_bar.modulate = Color(1.0, 0.45, 0.1) if fmod(Time.get_ticks_msec() / 250.0, 2.0) < 1.0 else Color(1.0, 0.1, 0.1)
		Vehicle.DamageState.SMOKING:
			_vehicle_bar.modulate = Color(0.9, 0.8, 0.3)
		_:
			_vehicle_bar.modulate = Color(0.5, 0.75, 1.0)


func _update_hint(player: Player) -> void:
	if not player.is_on_foot():
		_hint_label.text = "[E] Exit vehicle    [LMB] Drive-by (needs a gun)    [Space] Handbrake"
	elif interaction_prompt.has_prompt():
		_hint_label.text = ""
	elif player.nearest_free_vehicle() != null:
		_hint_label.text = "[E] Steal vehicle"
	else:
		_hint_label.text = ""


func _on_health_changed(current: float, maximum: float) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current
	if _last_health >= 0.0 and current < _last_health:
		_damage_flash.color.a = clampf(_damage_flash.color.a + (_last_health - current) / maximum * 3.0, 0.15, 0.6)
	_last_health = current


func _update_weapon(player: Player, delta: float) -> void:
	var inventory := player.weapons
	if inventory == null:
		return
	if inventory != _connected_inventory:
		_connected_inventory = inventory
		inventory.hit_confirmed.connect(func() -> void: _hit_marker_left = 0.12)
	var slot := inventory.current()
	_weapon_label.text = slot.data.display_name if slot else ""
	_ammo_label.text = slot.ammo_text() if slot and slot.data.uses_ammo() else ""
	if slot and slot.data.uses_ammo() and slot.magazine == 0 and not inventory.is_reloading and slot.reserve == 0:
		_ammo_label.text = "NO AMMO"
	_ammo_label.modulate = Color(1.0, 0.4, 0.4) if slot and slot.data.uses_ammo() and slot.magazine <= slot.data.magazine_size * 0.25 else Color.WHITE
	_reload_bar.visible = inventory.is_reloading and slot != null and not slot.data.thrown
	_reload_bar.value = inventory.reload_progress() * 100.0
	var detonate_hint := "  [G] Detonate (%d)" % inventory.placed_charges.size() if not inventory.placed_charges.is_empty() else ""
	_keys_label.text = "[Q] Weapon wheel  [R] Reload  [1-9] Select  [M] Map" + detonate_hint
	_hit_marker_left = maxf(0.0, _hit_marker_left - delta)
	_crosshair.text = "x" if _hit_marker_left > 0.0 else "+"
	_crosshair.modulate = Color(1.0, 0.3, 0.3) if _hit_marker_left > 0.0 else Color.WHITE


func _push_notification(text: String) -> void:
	var label := _make_label(text, 20)
	_feed.add_child(label)
	get_tree().create_timer(NOTIFICATION_LIFETIME).timeout.connect(label.queue_free)


## GPS line on the minimap: the street route to the pause-map waypoint, and the waypoint pin
## (clamped to the minimap edge when it's out of range).
func _draw_gps() -> void:
	var player := GameState.player
	if player == null or map_screen == null or not map_screen.has_waypoint():
		return
	var focus := player.get_focus_position()
	var half := _gps.size * 0.5
	var px_per_m := _gps.size.y / MINIMAP_ZOOM
	var to_screen := func(at: Vector3) -> Vector2: return half + Vector2(at.x - focus.x, at.z - focus.z) * px_per_m
	if map_screen.route.size() >= 2:
		var points := PackedVector2Array()
		for point in map_screen.route:
			points.append(to_screen.call(point))
		points[0] = half
		_gps.draw_polyline(points, Color.BLACK, 6.0, true)
		_gps.draw_polyline(points, MapScreen.ROUTE_COLOR, 3.5, true)
	var pin: Vector2 = to_screen.call(map_screen.waypoint)
	var inner := Rect2(Vector2(8.0, 8.0), _gps.size - Vector2(16.0, 16.0))
	if not inner.has_point(pin):
		pin = half + (pin - half) * minf(absf((half.x - 8.0) / (pin.x - half.x + 0.001)), absf((half.y - 8.0) / (pin.y - half.y + 0.001)))
	_gps.draw_circle(pin, 7.0, Color.BLACK)
	_gps.draw_circle(pin, 5.5, MapScreen.ROUTE_COLOR)


func _place_minimap(control: Control) -> void:
	control.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	control.offset_left = -MINIMAP_SIZE - 16.0
	control.offset_right = -16.0
	control.offset_top = 16.0
	control.offset_bottom = 16.0 + MINIMAP_SIZE


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
	_vehicle_bar = ProgressBar.new()
	_vehicle_bar.custom_minimum_size = Vector2(220.0, 10.0)
	_vehicle_bar.show_percentage = false
	_vehicle_bar.visible = false
	panel.add_child(_vehicle_bar)
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
	_map_camera.size = MINIMAP_ZOOM
	viewport.add_child(_map_camera)
	_map_camera.make_current()
	_place_minimap(_map_container)
	_gps = Control.new()
	_gps.clip_contents = true
	_gps.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gps.draw.connect(_draw_gps)
	add_child(_gps)
	_place_minimap(_gps)

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


func _build_weapon_panel() -> void:
	var panel := VBoxContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.offset_left = -260.0
	panel.offset_top = -120.0
	panel.offset_right = -20.0
	panel.offset_bottom = -20.0
	panel.alignment = BoxContainer.ALIGNMENT_END
	add_child(panel)
	_weapon_label = _make_label("", 24)
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(_weapon_label)
	_ammo_label = _make_label("", 30)
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(_ammo_label)
	_reload_bar = ProgressBar.new()
	_reload_bar.custom_minimum_size = Vector2(0.0, 8.0)
	_reload_bar.show_percentage = false
	_reload_bar.visible = false
	panel.add_child(_reload_bar)
	_keys_label = _make_label("", 14)
	_keys_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_keys_label.modulate.a = 0.7
	panel.add_child(_keys_label)

	_damage_flash = ColorRect.new()
	_damage_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage_flash.color = Color(0.8, 0.0, 0.0, 0.0)
	add_child(_damage_flash)
	move_child(_damage_flash, 0)


func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	return label
