class_name VehicleKitTests
extends RefCounted
## Tests for the vehicle kit: every registry vehicle (data/vehicles/vehicles.json) has a scene that
## loads with collision and a driver seat and matches its registry entry, every drivable one moves,
## steers and stays upright under scripted input, paint is seeded, and the showcase lot lists the
## whole line-up and resets it. Runs on its own ground far above the city and removes everything.

const TEST_ORIGIN := Vector3(0.0, 400.0, 0.0)
const SPACING := 9.0

var _runner: Node


func _init(runner: Node) -> void:
	_runner = runner


func _check(condition: bool, description: String) -> void:
	_runner.call("_check", condition, "vehicle kit: " + description)


func run(player: Player) -> void:
	_test_registry()
	_test_scenes()
	_test_paint()
	await _test_drive(player)
	await _test_showcase()


func _test_registry() -> void:
	var entries := VehicleCatalog.entries()
	_check(entries.size() >= 30, "registry lists %d vehicles (30+)" % entries.size())
	var names := {}
	var classes_used := {}
	var complete := true
	for entry: Dictionary in entries:
		names[entry["name"]] = true
		classes_used[entry["class"]] = true
		for key in ["id", "name", "class", "scene", "mass", "top_speed_kph", "acceleration", "handling", "health",
				"seats", "spawn_zones", "income_tier", "stealable", "palette", "trim_palette"]:
			if not entry.has(key):
				complete = false
				push_error("%s is missing %s" % [entry.get("id", "?"), key])
	_check(complete, "every registry entry has the gameplay fields")
	_check(names.size() == entries.size(), "vehicle names are unique")
	_check(classes_used.size() == VehicleCatalog.classes().size(), "every class has at least one vehicle")
	_check(not VehicleCatalog.query("police", "", "", true).is_empty() and VehicleCatalog.query("", "", "", true).size() < entries.size(),
		"queries filter by class and stealability")


func _test_scenes() -> void:
	var bad: Array[String] = []
	for entry: Dictionary in VehicleCatalog.entries():
		var problem := _scene_problem(entry)
		if problem != "":
			bad.append("%s: %s" % [entry["id"], problem])
	for line in bad:
		push_error(line)
	_check(bad.is_empty(), "every scene loads with collision and a driver seat and matches the registry (%s)" % ", ".join(bad))


func _scene_problem(entry: Dictionary) -> String:
	var scene := load(entry["scene"]) as PackedScene
	if scene == null:
		return "scene does not load"
	var root := scene.instantiate()
	var problem := ""
	var shapes := 0
	for child in root.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape != null:
			shapes += 1
	if shapes == 0:
		problem = "no collision"
	elif root.get_node_or_null("Seats/Driver") == null:
		problem = "no driver seat"
	elif root.get_node("Seats").get_child_count() != int(entry["seats"]):
		problem = "seat count"
	elif entry["drivable"]:
		var vehicle := root as Vehicle
		if vehicle == null:
			problem = "not a Vehicle"
		elif vehicle.model_id != StringName(entry["id"]):
			problem = "model_id"
		elif not is_equal_approx(vehicle.mass, float(entry["mass"])):
			problem = "mass"
		elif not is_equal_approx(vehicle.max_health, float(entry["health"])):
			problem = "health"
		elif not is_equal_approx(vehicle.max_speed, float(entry["max_speed"])):
			problem = "top speed"
		elif absf(vehicle.max_engine_force - float(entry["engine_force"])) > 0.5:
			problem = "engine force"
		elif root.find_children("*", "VehicleWheel3D", false).size() < 4:
			problem = "fewer than 4 wheels"
	elif not root is StaticBody3D:
		problem = "display vehicle is not a StaticBody3D"
	root.free()
	return problem


func _test_paint() -> void:
	var a := VehicleCatalog.paint_colors(&"meridian", 7)
	var b := VehicleCatalog.paint_colors(&"meridian", 7)
	_check(a.size() == 2 and a == b, "the same seed gives the same paint")
	var distinct := {}
	for seed_value in 12:
		distinct[VehicleCatalog.paint_colors(&"meridian", seed_value)[0].to_html()] = true
	_check(distinct.size() >= 4, "seeds vary the paint (%d colours from 12 seeds)" % distinct.size())

	var vehicle := VehicleCatalog.instantiate(&"meridian", 7) as Vehicle
	_runner.add_child(vehicle)
	vehicle.global_position = TEST_ORIGIN + Vector3(0.0, 50.0, 0.0)
	_check(vehicle.paint_color().is_equal_approx(a[0]), "a spawned vehicle wears its seeded paint")
	var other := VehicleCatalog.instantiate(&"meridian", 7) as Vehicle
	_runner.add_child(other)
	other.apply_paint(3)
	_check(vehicle.paint_color().is_equal_approx(a[0]), "repainting one vehicle leaves others alone")
	vehicle.free()
	other.free()


## Drives every drivable vehicle at once on a flat test pad (the player is set as driver of all of
## them so they all read the same scripted input), then checks travel, steering and roll-over.
func _test_drive(player: Player) -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 200.0)
	shape.shape = box
	ground.add_child(shape)
	_runner.add_child(ground)
	ground.global_position = TEST_ORIGIN + Vector3(150.0, -0.5, 60.0)

	var vehicles: Array[Vehicle] = []
	var index := 0
	for entry: Dictionary in VehicleCatalog.entries():
		if not entry["drivable"]:
			continue
		var vehicle := VehicleCatalog.instantiate(StringName(entry["id"]), index) as Vehicle
		_runner.add_child(vehicle)
		vehicle.global_position = TEST_ORIGIN + Vector3(index * SPACING, 0.3, 0.0)
		vehicles.append(vehicle)
		index += 1
	await _runner.call("_physics_frames", 90)

	var tipped: Array[String] = []
	for vehicle in vehicles:
		if vehicle.global_basis.y.y < 0.9:
			tipped.append(String(vehicle.model_id))
	_check(tipped.is_empty(), "every vehicle settles upright on its wheels (%s)" % ", ".join(tipped))

	var starts: Array[Vector3] = []
	for vehicle in vehicles:
		starts.append(vehicle.global_position)
		vehicle.driver = player
	Input.action_press("move_forward")
	await _runner.call("_physics_frames", 120)
	var stuck: Array[String] = []
	for i in vehicles.size():
		var travelled := (vehicles[i].global_position - starts[i]).dot(Vector3.BACK)
		if travelled < 1.5:
			stuck.append("%s %.1fm" % [vehicles[i].model_id, travelled])
	_check(stuck.is_empty(), "scripted throttle drives every vehicle forward (%s)" % ", ".join(stuck))

	var yaws: Array[float] = []
	for vehicle in vehicles:
		yaws.append(vehicle.global_rotation.y)
	Input.action_press("move_left")
	await _runner.call("_physics_frames", 60)
	Input.action_release("move_left")
	Input.action_release("move_forward")
	var straight: Array[String] = []
	for i in vehicles.size():
		if absf(angle_difference(yaws[i], vehicles[i].global_rotation.y)) < 0.05:
			straight.append(String(vehicles[i].model_id))
	_check(straight.is_empty(), "steering turns every vehicle (%s)" % ", ".join(straight))

	tipped.clear()
	for vehicle in vehicles:
		if vehicle.global_basis.y.y < 0.8:
			tipped.append(String(vehicle.model_id))
	_check(tipped.is_empty(), "no vehicle rolls over in a turn (%s)" % ", ".join(tipped))

	var fast := 0
	for vehicle in vehicles:
		vehicle.driver = null
		if vehicle.max_speed > 0.0 and vehicle.linear_velocity.length() > vehicle.max_speed * 1.05:
			fast += 1
	_check(fast == 0, "no vehicle exceeds its top speed")
	for vehicle in vehicles:
		vehicle.free()
	ground.free()


func _test_showcase() -> void:
	var showcase := (load("res://scenes/vehicles/vehicle_showcase.tscn") as PackedScene).instantiate() as Node3D
	# The game's own player and HUD stay in charge; the lot is tested on its own.
	for child_name in ["Player", "HUD"]:
		var child := showcase.get_node(child_name)
		showcase.remove_child(child)
		child.free()
	showcase.position = TEST_ORIGIN + Vector3(0.0, 100.0, 0.0)
	_runner.add_child(showcase)
	var expected := VehicleCatalog.entries().size()
	var labelled := 0
	for marker: Marker3D in showcase.call("spawn_points"):
		var pad := marker.get_parent()
		if pad.find_children("*", "Label3D").size() >= 2 and not VehicleCatalog.find(StringName(marker.get_meta("vehicle_id"))).is_empty():
			labelled += 1
	_check(labelled == expected, "the showcase has a labelled pad for every vehicle (%d/%d)" % [labelled, expected])
	_check(showcase.call("vehicles").size() == expected, "the showcase spawns the whole line-up")
	await _runner.call("_physics_frames", 30)

	var first := showcase.call("vehicles")[0] as Node3D
	var home := (showcase.call("spawn_points")[0] as Marker3D).global_position
	first.global_position += Vector3(25.0, 2.0, 0.0)
	var before := (first as Vehicle).paint_seed
	var f5 := InputEventKey.new()
	f5.keycode = KEY_F5
	f5.pressed = true
	showcase.call("_input", f5)
	await _runner.call("_physics_frames", 2)
	var vehicles: Array = showcase.call("vehicles")
	var fresh := vehicles[0] as Vehicle
	_check(vehicles.size() == expected and fresh.global_position.distance_to(home) < 0.5, "F5 reset puts every vehicle back on its pad (%d, %.2f m off)" % [vehicles.size(), fresh.global_position.distance_to(home)])
	_check(fresh.paint_seed != before, "reset respawns with a fresh paint seed")
	showcase.free()
