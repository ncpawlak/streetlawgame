class_name CombatReticle
extends Control
## Full-screen overlay for gunplay: a crosshair whose gap follows the current spread, hit and kill
## markers, and red arcs around the centre pointing at whoever just hurt you.

const HIT_MARKER_TIME := 0.15
const KILL_MARKER_TIME := 0.4
const DAMAGE_ARC_TIME := 1.6
const DAMAGE_ARC_WIDTH := 0.45
const MIN_GAP := 4.0
const LINE_LENGTH := 9.0

## Shown on foot with the mouse captured; the HUD toggles it.
var show_crosshair := true
## Current spread of the player's next shot, in degrees.
var spread_degrees := 0.0
var _hit_left := 0.0
var _kill_left := 0.0
## [origin (world), seconds left]
var _damage: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_hit_left = maxf(0.0, _hit_left - delta)
	_kill_left = maxf(0.0, _kill_left - delta)
	for entry: Array in _damage:
		entry[1] -= delta
	_damage = _damage.filter(func(entry: Array) -> bool: return entry[1] > 0.0)
	queue_redraw()


func show_hit() -> void:
	_hit_left = HIT_MARKER_TIME


func show_kill() -> void:
	_kill_left = KILL_MARKER_TIME


## Adds an arc pointing at [param origin] (merged with a recent arc from the same spot).
func show_damage_from(origin: Vector3) -> void:
	for entry: Array in _damage:
		if (entry[0] as Vector3).distance_to(origin) < 1.0:
			entry[1] = DAMAGE_ARC_TIME
			return
	_damage.append([origin, DAMAGE_ARC_TIME])


func has_damage_arcs() -> bool:
	return not _damage.is_empty()


## Gap in pixels between the centre and the crosshair lines for [param spread] degrees.
func gap_for(spread: float) -> float:
	var camera := get_viewport().get_camera_3d()
	var fov := camera.fov if camera else 70.0
	var half_height := get_viewport_rect().size.y * 0.5
	return maxf(MIN_GAP, tan(deg_to_rad(spread)) / tan(deg_to_rad(fov) * 0.5) * half_height)


func _draw() -> void:
	var center := size * 0.5
	if show_crosshair:
		var gap := gap_for(spread_degrees)
		var color := Color(1.0, 1.0, 1.0, 0.9)
		for direction: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_line(center + direction * gap, center + direction * (gap + LINE_LENGTH), Color(0, 0, 0, 0.6), 4.0)
			draw_line(center + direction * gap, center + direction * (gap + LINE_LENGTH), color, 2.0)
		draw_circle(center, 1.5, color)
	if _kill_left > 0.0:
		_draw_marker(center, 16.0, Color(1.0, 0.15, 0.15, _kill_left / KILL_MARKER_TIME), 3.5)
	elif _hit_left > 0.0:
		_draw_marker(center, 10.0, Color(1.0, 1.0, 1.0, _hit_left / HIT_MARKER_TIME), 2.5)
	_draw_damage_arcs(center)


func _draw_marker(center: Vector2, reach: float, color: Color, width: float) -> void:
	for corner: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		draw_line(center + corner * reach * 0.4, center + corner * reach, color, width)


func _draw_damage_arcs(center: Vector2) -> void:
	var camera := get_viewport().get_camera_3d()
	var player := GameState.player
	if camera == null or player == null or _damage.is_empty():
		return
	var radius := minf(size.x, size.y) * 0.32
	for entry: Array in _damage:
		var angle := screen_angle(camera, player.get_focus_position(), entry[0])
		var alpha := clampf(float(entry[1]) / DAMAGE_ARC_TIME, 0.0, 1.0)
		draw_arc(center, radius, angle - DAMAGE_ARC_WIDTH, angle + DAMAGE_ARC_WIDTH, 24, Color(0.9, 0.05, 0.05, 0.85 * alpha), 10.0)


## Screen angle (0 = right, -PI/2 = top) of the direction from [param from] toward [param origin],
## seen from above relative to where [param camera] faces (straight ahead is the top of the screen).
static func screen_angle(camera: Camera3D, from: Vector3, origin: Vector3) -> float:
	var local := camera.global_basis.inverse() * (origin - from)
	return atan2(local.z, local.x)
