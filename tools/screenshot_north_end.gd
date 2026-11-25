extends Node
## Windowed in-game screenshots of the populated North End (perf overlay on screen):
##   godot --path . res://tools/screenshot_north_end.tscn -- <out_dir>
## Street level in each neighbourhood, the roster landmarks (camera in front of each building's
## door, found from the census lot or the live shop's Entrance), an aerial view, and a top-down
## orthographic view of the whole play area with distance LOD and fog lifted so every building is
## at full detail.

const MAIN := preload("res://scenes/main.tscn")
const STREETS: Array = [
	["street_tamarack_row", Vector2(515.0, 1000.0), 2.0, Vector2(515.0, 900.0)],
	["street_northgrove", Vector2(740.0, 520.0), 2.0, Vector2(740.0, 420.0)],
	["street_mangona", Vector2(420.0, 222.0), 2.0, Vector2(520.0, 222.0)],
]
## [shot, census rect key, camera distance m, eye height m]
const LANDMARKS: Array = [
	["the_spot", "534.6,1025.2,23.7,19.2", 26.0, 4.0],
	["gas_station", "333.0,1071.0,20.0,30.0", 30.0, 4.0],
	["bank", "692.0,474.0,18.0,16.0", 28.0, 4.0],
	["gun_store", "372.0,230.0,12.0,15.0", 24.0, 3.5],
	["hardware_store", "462.0,231.0,15.0,17.0", 26.0, 3.5],
]

var _main: Node3D
var _city: CityGenerator
var _cam: Camera3D
var _out := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://screenshots"
	DirAccess.make_dir_recursive_absolute(_out)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	_main = MAIN.instantiate()
	add_child(_main)
	_city = _main.get_node("City")
	(_main.get_node("Player") as Node).process_mode = Node.PROCESS_MODE_DISABLED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var overlay := PerfOverlay.new()
	add_child(overlay)
	overlay.visible = true
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.far = 4000.0
	add_child(_cam)
	_cam.make_current()
	for view: Array in STREETS:
		var eye := CityGenerator.px_to_world(view[1]) + Vector3(0.0, view[2], 0.0)
		await _shot(view[0], eye, CityGenerator.px_to_world(view[3]) + Vector3(0.0, 3.0, 0.0))
	for view: Array in LANDMARKS:
		var center := CityGenerator.px_to_world(_rect(view[1]).get_center())
		var door := _door(view[1], center)
		var out := Vector3(door.x - center.x, 0.0, door.z - center.z).normalized()
		var side := out.cross(Vector3.UP) * float(view[2]) * 0.35
		await _shot(view[0], door + out * float(view[2]) + side + Vector3(0.0, view[3], 0.0), center + Vector3(0.0, 3.0, 0.0))
	await _shot("aerial_tamarack_row", CityGenerator.px_to_world(Vector2(610.0, 1160.0)) + Vector3(0.0, 150.0, 0.0), CityGenerator.px_to_world(Vector2(520.0, 960.0)))
	await _shot("aerial_northgrove", CityGenerator.px_to_world(Vector2(800.0, 640.0)) + Vector3(0.0, 150.0, 0.0), CityGenerator.px_to_world(Vector2(700.0, 460.0)))
	await _top_down()
	print("SCREENSHOTS %s" % ProjectSettings.globalize_path(_out))
	get_tree().quit()


func _shot(shot: String, eye: Vector3, target: Vector3) -> void:
	_cam.look_at_from_position(eye, target)
	for i in 45:
		await get_tree().process_frame
	var path := _out.path_join(shot + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT %s" % path)


func _top_down() -> void:
	for gi: GeometryInstance3D in _city.find_children("*", "GeometryInstance3D", true, false):
		if gi.visibility_range_begin > 0.0:
			gi.visible = false
		gi.visibility_range_end = 0.0
	for env: WorldEnvironment in _main.find_children("*", "WorldEnvironment", true, false):
		env.environment.fog_enabled = false
		env.environment.volumetric_fog_enabled = false
	var rect := CityGenerator.PLAY_RECT_PX
	var center := CityGenerator.px_to_world(rect.get_center())
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = rect.size.y * CityGenerator.METERS_PER_PX * 1.02
	_cam.near = 1.0
	_cam.transform = Transform3D(Basis.from_euler(Vector3(-PI * 0.5, 0.0, 0.0)), center + Vector3(0.0, 1500.0, 0.0))
	DisplayServer.window_set_size(Vector2i(1200, 1560))
	await _shot_current("top_down")


func _shot_current(shot: String) -> void:
	for i in 45:
		await get_tree().process_frame
	var path := _out.path_join(shot + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT %s" % path)


static func _rect(key: String) -> Rect2:
	var v := key.split_floats(",")
	return Rect2(v[0], v[1], v[2], v[3])


## World door position of the building on census lot [param key]; the shop's Entrance otherwise.
func _door(key: String, center: Vector3) -> Vector3:
	for lot: Dictionary in _city.building_lots:
		if NorthEndCensus.rect_key(lot["rect_px"]) == key and lot.has("door"):
			return (lot["door"] as Transform3D).origin
	var kit := _city.get_node_or_null(^"KitBuildings")
	var live := kit.get_node_or_null("Kit_%s" % key.validate_node_name().replace(".", "_")) if kit else null
	if live != null:
		var entrance := live.find_child("Entrance", true, false) as Node3D
		if entrance != null:
			return entrance.global_position
	return center + Vector3(0.0, 0.0, 20.0)
