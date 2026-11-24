class_name WeaponWheel
extends Control
## Radial weapon selector. Hold the weapon_wheel action to open it: the game pauses, mouse movement
## picks a slice, and releasing the key (or clicking) equips it. Esc cancels.

const OUTER_RADIUS := 190.0
const INNER_RADIUS := 70.0
## Mouse travel needed before the cursor picks a slice.
const DEADZONE := 25.0
const SLICE_GAP := 0.04
const ARC_STEPS := 16

var is_open := false
var hovered := -1

var _inventory: WeaponInventory
var _cursor := Vector2.ZERO
var _was_paused := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		if event.is_action_pressed("weapon_wheel"):
			open()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		_move_cursor((event as InputEventMouseMotion).relative)
	elif event.is_action_released("weapon_wheel") or event.is_action_pressed("shoot"):
		close(true)
	elif event.is_action_pressed("ui_cancel"):
		close(false)
	elif event.is_action_pressed("next_weapon"):
		_step_hover(1)
	elif event.is_action_pressed("prev_weapon"):
		_step_hover(-1)
	get_viewport().set_input_as_handled()


func open() -> bool:
	var player := GameState.player
	if is_open or player == null or player.weapons == null or player.health <= 0.0:
		return false
	_inventory = player.weapons
	_cursor = Vector2.ZERO
	hovered = _inventory.current_index
	is_open = true
	visible = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	queue_redraw()
	return true


## Closes the wheel; when [param apply] is true the hovered weapon is equipped.
func close(apply: bool) -> void:
	if not is_open:
		return
	if apply and hovered >= 0:
		_inventory.select(hovered)
	is_open = false
	visible = false
	get_tree().paused = _was_paused


## Index of the slice in direction [param offset] from the wheel center (0 is at the top, clockwise).
func slice_at(offset: Vector2) -> int:
	var count := _inventory.slots.size() if _inventory else 0
	if count == 0 or offset.length() < DEADZONE:
		return hovered
	var angle := fposmod(atan2(offset.x, -offset.y), TAU)
	var slice := TAU / count
	return int(fposmod(angle + slice * 0.5, TAU) / slice) % count


func _move_cursor(relative: Vector2) -> void:
	_cursor = (_cursor + relative).limit_length(OUTER_RADIUS)
	var index := slice_at(_cursor)
	if index != hovered:
		hovered = index
		queue_redraw()


func _step_hover(step: int) -> void:
	if _inventory and not _inventory.slots.is_empty():
		hovered = posmod(hovered + step, _inventory.slots.size())
		_cursor = Vector2.ZERO
		queue_redraw()


func _draw() -> void:
	if not is_open or _inventory == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.45))
	var center := size * 0.5
	var font := ThemeDB.fallback_font
	var count := _inventory.slots.size()
	var slice := TAU / count
	var accent := GameState.gang_color(GameState.PLAYER_GANG)
	for i in count:
		var mid := i * slice
		var color := accent if i == hovered else Color(0.1, 0.1, 0.12, 0.85)
		if i == _inventory.current_index and i != hovered:
			color = Color(0.25, 0.25, 0.3, 0.9)
		draw_colored_polygon(_slice_polygon(center, mid - slice * 0.5 + SLICE_GAP, mid + slice * 0.5 - SLICE_GAP), color)
		var slot := _inventory.slots[i]
		var label_pos := center + _direction(mid) * (INNER_RADIUS + OUTER_RADIUS) * 0.5
		_draw_centered(font, label_pos + Vector2(0.0, -4.0), "%d  %s" % [i + 1, slot.data.display_name], 18, Color.WHITE)
		_draw_centered(font, label_pos + Vector2(0.0, 18.0), slot.ammo_text(), 15, Color(0.85, 0.85, 0.85))
	draw_circle(center, INNER_RADIUS - 6.0, Color(0.05, 0.05, 0.07, 0.9))
	var title := _inventory.slots[hovered].data.display_name if hovered >= 0 and hovered < count else ""
	_draw_centered(font, center + Vector2(0.0, -2.0), title, 16, Color.WHITE)
	_draw_centered(font, center + Vector2(0.0, 18.0), "PAUSED", 12, Color(1.0, 1.0, 1.0, 0.6))
	draw_circle(center + _cursor, 5.0, Color.WHITE)


func _slice_polygon(center: Vector2, from_angle: float, to_angle: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for step in ARC_STEPS + 1:
		points.append(center + _direction(lerpf(from_angle, to_angle, float(step) / ARC_STEPS)) * OUTER_RADIUS)
	for step in range(ARC_STEPS, -1, -1):
		points.append(center + _direction(lerpf(from_angle, to_angle, float(step) / ARC_STEPS)) * INNER_RADIUS)
	return points


func _direction(angle: float) -> Vector2:
	return Vector2(sin(angle), -cos(angle))


func _draw_centered(font: Font, at: Vector2, text: String, font_size: int, color: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string_outline(font, at - Vector2(width * 0.5, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color.BLACK)
	draw_string(font, at - Vector2(width * 0.5, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
