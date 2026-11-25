extends Node
## Scripted camera flythrough benchmark of the North End. Run windowed (headless has no renderer):
##   godot --path . res://tools/benchmark_north_end.tscn -- <out.json> [label] [batched|naive|greybox]
## batched (default) is the shipped HLOD path; naive places the same kit scenes as individual nodes
## (CityGenerator.batch_kit off); greybox skips the kit (populate_kit off).
## Flies street level through Tamarack Row, Mangona and Northgrove, then an aerial sweep, with
## vsync off. Reports boot time, average FPS, 1% low FPS (average of the slowest 1% of frames),
## and average / peak draw calls, objects and primitives, plus the draw calls / objects at the fixed
## [constant VIEWPOINTS] (the budgets in tests/perf_budget_tests.gd). The perf overlay is on screen.

const MAIN := preload("res://scenes/main.tscn")
const STREET_SPEED := 22.0
const AIR_SPEED := 70.0
## [px, height m]: street level is a driver's eye line, then up over the district.
const PATH := [
	[Vector2(533.0, 770.0), 3.0], [Vector2(515.0, 790.0), 3.0], [Vector2(515.0, 1000.0), 3.0],
	[Vector2(420.0, 1000.0), 3.0], [Vector2(360.0, 1000.0), 3.0], [Vector2(360.0, 1060.0), 3.0],
	[Vector2(515.0, 1060.0), 3.0], [Vector2(515.0, 720.0), 3.0], [Vector2(515.0, 450.0), 3.0],
	[Vector2(515.0, 300.0), 3.0], [Vector2(575.0, 300.0), 3.0], [Vector2(575.0, 330.0), 3.0],
	[Vector2(740.0, 330.0), 3.0], [Vector2(740.0, 520.0), 3.0], [Vector2(740.0, 700.0), 3.0],
	[Vector2(740.0, 700.0), 60.0], [Vector2(541.0, 660.0), 260.0], [Vector2(300.0, 300.0), 140.0],
	[Vector2(300.0, 1100.0), 120.0], [Vector2(800.0, 1100.0), 120.0],
]

## Fixed viewpoints [name, eye px, eye height m, look-at px]: street level in each neighbourhood,
## the roster landmarks and an aerial view over the whole district.
const VIEWPOINTS := [
	["tamarack_street", Vector2(515.0, 1000.0), 1.7, Vector2(515.0, 900.0)],
	["the_spot", Vector2(515.0, 1035.0), 1.7, Vector2(546.0, 1035.0)],
	["gas_station", Vector2(360.0, 1060.0), 1.7, Vector2(343.0, 1086.0)],
	["northgrove_street", Vector2(740.0, 520.0), 1.7, Vector2(740.0, 420.0)],
	["bank", Vector2(680.0, 482.0), 1.7, Vector2(701.0, 482.0)],
	["mangona_street", Vector2(420.0, 222.0), 1.7, Vector2(520.0, 222.0)],
	["gun_hardware", Vector2(420.0, 222.0), 1.7, Vector2(378.0, 238.0)],
	["aerial", Vector2(560.0, 1250.0), 420.0, Vector2(560.0, 650.0)],
]

var _cam: Camera3D
var _samples: Array[Dictionary] = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://benchmark.json"
	var label := args[1] if args.size() > 1 else "run"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var t0 := Time.get_ticks_msec()
	var mode := args[2] if args.size() > 2 else "batched"
	var main: Node3D = MAIN.instantiate()
	var city := main.get_node("City") as CityGenerator
	city.batch_kit = mode == "batched"
	city.populate_kit = mode != "greybox"
	add_child(main)
	var boot_ms := Time.get_ticks_msec() - t0
	var player := main.get_node("Player") as Node3D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var overlay := PerfOverlay.new()
	add_child(overlay)
	overlay.visible = true
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.far = 4000.0
	add_child(_cam)
	_cam.make_current()
	for i in 30:
		await get_tree().process_frame
	var views := await _viewpoints()
	await _fly()
	var report := _report(boot_ms)
	report["viewpoints"] = views
	report["mode"] = mode
	report["label"] = label
	report["meters_per_px"] = CityGenerator.METERS_PER_PX
	var file := FileAccess.open(out, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("BENCHMARK %s" % JSON.stringify(report))
	get_tree().quit()


func _fly() -> void:
	var points: Array[Vector3] = []
	for p: Array in PATH:
		points.append(CityGenerator.px_to_world(p[0]) + Vector3(0.0, p[1], 0.0))
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var speed := STREET_SPEED if maxf(a.y, b.y) < 10.0 else AIR_SPEED
		var seconds := maxf(0.5, a.distance_to(b) / speed)
		var t := 0.0
		while t < seconds:
			var at := a.lerp(b, t / seconds)
			var flat := Vector3(b.x - a.x, 0.0, b.z - a.z)
			var dir := flat.normalized() if flat.length() > 1.0 else Vector3.FORWARD
			var ahead := at + dir * 10.0
			ahead.y = at.y - 0.6
			if at.y > 40.0:
				ahead = Vector3(at.x, 0.0, at.z) + dir * at.y * 0.8
			_cam.look_at_from_position(at, ahead)
			var delta := await _frame()
			t += delta


## Draw calls / objects / primitives at each [constant VIEWPOINTS] entry (max over 10 settled frames).
func _viewpoints() -> Dictionary:
	var out := {}
	for view: Array in VIEWPOINTS:
		var eye := CityGenerator.px_to_world(view[1]) + Vector3(0.0, view[2], 0.0)
		_cam.look_at_from_position(eye, CityGenerator.px_to_world(view[3]) + Vector3(0.0, 1.5, 0.0))
		var worst := {"draw_calls": 0, "objects": 0, "primitives": 0}
		for i in 20:
			await get_tree().process_frame
			if i >= 10:
				var s := PerfOverlay.snapshot()
				for k: String in worst:
					worst[k] = maxi(worst[k], s[k])
		out[view[0]] = worst
	return out


func _frame() -> float:
	await get_tree().process_frame
	var delta := get_process_delta_time()
	var s := PerfOverlay.snapshot()
	s["ms"] = delta * 1000.0
	_samples.append(s)
	return delta


func _report(boot_ms: int) -> Dictionary:
	var ms: Array[float] = []
	var draw := 0.0
	var peak := {"draw_calls": 0, "objects": 0, "primitives": 0}
	for s in _samples:
		ms.append(s["ms"])
		draw += s["draw_calls"]
		for k: String in peak:
			peak[k] = maxi(peak[k], s[k])
	var total := 0.0
	for m in ms:
		total += m
	var sorted := ms.duplicate()
	sorted.sort()
	var slow := sorted.slice(int(sorted.size() * 0.99))
	var slow_total := 0.0
	for m in slow:
		slow_total += m
	return {
		"boot_ms": boot_ms, "frames": ms.size(), "seconds": snappedf(total / 1000.0, 0.01),
		"avg_fps": snappedf(1000.0 * ms.size() / maxf(total, 0.001), 0.1),
		"low_1pct_fps": snappedf(1000.0 / maxf(slow_total / maxf(1.0, slow.size()), 0.001), 0.1),
		"avg_draw_calls": roundi(draw / maxf(1.0, ms.size())), "peak_draw_calls": peak["draw_calls"],
		"peak_objects": peak["objects"], "peak_primitives": peak["primitives"],
		"node_count": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"gpu": RenderingServer.get_video_adapter_name(),
	}
