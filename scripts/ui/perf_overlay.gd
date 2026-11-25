class_name PerfOverlay
extends CanvasLayer
## Debug performance overlay (F3): FPS, frame time (avg and worst over the last half second), draw
## calls, primitives, objects and static memory from the [Performance] monitors. Shown at start
## with the `--perf` user arg (godot ... -- --perf).

const TOGGLE_KEY := KEY_F3
const WINDOW := 0.5

var _label: Label
var _frames: PackedFloat32Array = []
var _elapsed := 0.0


static func snapshot() -> Dictionary:
	return {
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"video_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
	}


func _ready() -> void:
	layer = 100
	name = "PerfOverlay"
	process_mode = Node.PROCESS_MODE_ALWAYS
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	style.set_content_margin_all(8.0)
	panel.add_theme_stylebox_override(&"panel", style)
	# Top right, under the minimap, clear of the money / district HUD at the top left.
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = -16.0
	panel.offset_right = -16.0
	panel.offset_top = 270.0
	_label = Label.new()
	_label.add_theme_font_size_override(&"font_size", 15)
	_label.add_theme_color_override(&"font_color", Color(0.75, 1.0, 0.75))
	panel.add_child(_label)
	add_child(panel)
	visible = "--perf" in OS.get_cmdline_user_args()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == TOGGLE_KEY:
		visible = not visible


func _process(delta: float) -> void:
	_frames.append(delta * 1000.0)
	_elapsed += delta
	if _elapsed < WINDOW or not visible:
		if _elapsed >= WINDOW:
			_frames.clear()
			_elapsed = 0.0
		return
	var total := 0.0
	var worst := 0.0
	for ms in _frames:
		total += ms
		worst = maxf(worst, ms)
	var avg := total / maxf(1.0, _frames.size())
	var s := snapshot()
	_label.text = "PERF (F3)\nFPS %d   frame %.2f ms (worst %.2f)\ndraw calls %d\nprimitives %s\nobjects %d\nnodes %d\nprocess %.2f ms  physics %.2f ms\nvideo mem %.0f MB" % [
		roundi(1000.0 / maxf(avg, 0.001)), avg, worst, s["draw_calls"], String.num_int64(s["primitives"]),
		s["objects"], s["nodes"], s["process_ms"], s["physics_ms"], s["video_mb"]]
	_frames.clear()
	_elapsed = 0.0
