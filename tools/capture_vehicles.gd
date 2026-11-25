extends Node
## Screenshot tool for the vehicle kit. Run windowed:
##   godot --path . res://tools/capture_vehicles.tscn -- <output_dir> [vehicle ids...]
## Saves lot overviews, the test loop, one shot per class (its whole line-up from the aisle) and
## front three-quarter (with the player alongside for scale), side and rear three-quarter close-ups
## of every listed vehicle (all of them by default).

const SHOWCASE := preload("res://scenes/vehicles/vehicle_showcase.tscn")


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else "user://vehicle_shots"
	var only := args.slice(1)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var lot: Node3D = SHOWCASE.instantiate()
	lot.set("capture_mouse", false)
	add_child(lot)
	var player := lot.get_node("Player") as Node3D
	player.set_physics_process(false)
	var hud := lot.get_node("HUD") as CanvasLayer
	hud.visible = false
	var cam := Camera3D.new()
	cam.fov = 55.0
	add_child(cam)
	for i in 90:
		await get_tree().physics_frame
	cam.make_current()

	var vehicles: Array[Node3D] = []
	vehicles.assign(lot.call("vehicles"))
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for v in vehicles:
		lo = lo.min(v.global_position)
		hi = hi.max(v.global_position)
	var mid := (lo + hi) * 0.5
	var span := hi.x - lo.x
	cam.look_at_from_position(Vector3(lo.x - 25.0, 38.0, 55.0), Vector3(mid.x * 0.6, 0.0, 0.0))
	await _shot(out_dir.path_join("overview_lot.png"))
	cam.look_at_from_position(Vector3(hi.x + 25.0, 38.0, -55.0), Vector3(mid.x * 0.6, 0.0, 0.0))
	await _shot(out_dir.path_join("overview_lot_reverse.png"))
	cam.look_at_from_position(Vector3(lo.x - 30.0, 7.0, 0.0), Vector3(mid.x, 1.0, 0.0))
	await _shot(out_dir.path_join("overview_aisle.png"))
	cam.look_at_from_position(Vector3(0.0, 130.0, 95.0), Vector3(0.0, 0.0, 0.0))
	await _shot(out_dir.path_join("overview_track.png"))
	cam.fov = 40.0
	cam.look_at_from_position(Vector3(span * 0.0 + 18.0, 6.0, -42.0 + 14.0), Vector3(30.0, 0.5, -45.0))
	await _shot(out_dir.path_join("overview_ramp.png"))
	cam.fov = 55.0

	var by_class := {}
	for v in vehicles:
		var entry := VehicleCatalog.find(_id(v))
		by_class.get_or_add(entry["class"], []).append(v)
	for cls: String in by_class:
		var group: Array = by_class[cls]
		_isolate(lot, group)
		await _class_shot(cam, group, out_dir.path_join("class_%s.png" % cls))

	for v in vehicles:
		var id := String(_id(v))
		if not only.is_empty() and not only.has(id):
			continue
		_isolate(lot, [v])
		var size: Array = VehicleCatalog.find(_id(v))["size_m"]
		var length: float = size[2]
		var height: float = size[1]
		var b := v.global_basis
		var o := v.global_position
		player.global_position = o + b * Vector3(-(float(size[0]) * 0.5 + 0.8), 0.05, length * 0.15)
		player.global_rotation = Vector3(0.0, v.global_rotation.y, 0.0)
		var dist := clampf(length * 0.95, 5.0, 9.0)
		var aim := o + b * Vector3(0.0, height * 0.45, -length * 0.08)
		var eye := o + b * Vector3(dist * 0.75, height * 0.5 + 1.1, dist * 0.7 + length * 0.2)
		cam.look_at_from_position(eye, aim)
		await _shot(out_dir.path_join("vehicle_%s.png" % id))
		player.visible = false
		aim = o + b * Vector3(0.0, height * 0.45, 0.0)
		cam.look_at_from_position(o + b * Vector3(length * 0.75 + 4.0, height * 0.45 + 0.4, 0.0), aim)
		await _shot(out_dir.path_join("vehicle_%s_side.png" % id))
		eye = o + b * Vector3(-dist * 0.75, height * 0.5 + 1.1, -(dist * 0.7 + length * 0.2))
		cam.look_at_from_position(eye, aim)
		await _shot(out_dir.path_join("vehicle_%s_rear.png" % id))
		player.visible = true
	get_tree().quit()


## Shows only [param keep] and their pads (kiosks stay readable, nothing blocks the view).
func _isolate(lot: Node, keep: Array) -> void:
	var ids := {}
	for v: Node3D in lot.call("vehicles"):
		v.visible = keep.has(v)
		if v.visible:
			ids[_id(v)] = true
	for marker: Marker3D in lot.call("spawn_points"):
		marker.get_parent().visible = ids.has(StringName(marker.get_meta("vehicle_id")))


## Frames a class's vehicles from the aisle, three-quarter on (they share a row or straddle it).
func _class_shot(cam: Camera3D, group: Array, path: String) -> void:
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for v: Node3D in group:
		lo = lo.min(v.global_position)
		hi = hi.max(v.global_position)
	var center := (lo + hi) * 0.5
	var width := hi.x - lo.x + 8.0
	var side := 1.0 if center.z < 0.0 else -1.0
	var eye := Vector3(center.x - width * 0.25, 3.0 + width * 0.12, center.z + side * (width * 0.5 + 6.0))
	if absf(hi.z - lo.z) > 5.0:
		eye = Vector3(center.x - width * 0.6 - 12.0, 6.0, 0.0)
	cam.look_at_from_position(eye, center + Vector3(0.0, 0.8, 0.0))
	await _shot(path)


func _id(v: Node) -> StringName:
	return v.get("model_id") if v.get("model_id") != null else StringName(v.get_meta("model_id"))


func _shot(path: String) -> void:
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
