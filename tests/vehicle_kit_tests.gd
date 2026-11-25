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
	_test_stripes_clear_glass()
	_test_paint()
	await _test_bullet_holes()
	await _test_drive(player)
	await _test_boarding(player)
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
		else:
			problem = _ride_problem(root, entry["ride"])
	elif not root is StaticBody3D:
		problem = "display vehicle is not a StaticBody3D"
	root.free()
	return problem


## Seating markers match the registry's ride data: pedals, wheel / bars and a spot to board from,
## a hinged door with a handle exactly when the ride says so, and the bus's step.
func _ride_problem(root: Node, ride: Dictionary) -> String:
	if ride.get("pose", "none") == "none":
		return "no ride data"
	for path in ["Ride/Pedals", "Ride/Steer", "DoorStand"]:
		if root.get_node_or_null(path) == null:
			return "no %s marker" % path
	if bool(ride["door"]) != (root.get_node_or_null("Doors/Driver/Handle") != null):
		return "door does not match the registry"
	if ride["entry"] == "bus" and root.get_node_or_null("Ride/Step") == null:
		return "bus without a boarding step"
	if (ride["pose"] == "straddle") != (ride["entry"] == "straddle"):
		return "straddle pose without a straddle entry"
	var hip: Array = ride["hip"]
	if (root.get_node("Seats/Driver") as Node3D).position.distance_to(Vector3(hip[0], hip[1], hip[2])) > 0.01:
		return "seat does not match the registry hip"
	return ""


## Racing stripes must stop at the glass: no Stripe piece may overlap a window in any scene.
func _test_stripes_clear_glass() -> void:
	var bad: Array[String] = []
	var striped := 0
	for entry: Dictionary in VehicleCatalog.entries():
		var root := (load(entry["scene"]) as PackedScene).instantiate() as Node3D
		var stripes: Array[AABB] = []
		var glass: Array[AABB] = []
		for node in root.find_children("*", "MeshInstance3D", true, false):
			var instance := node as MeshInstance3D
			if instance.mesh == null:
				continue
			var box := (_to_root(root, instance) * instance.mesh.get_aabb()).grow(-0.006)
			if instance.name.begins_with("Stripe"):
				stripes.append(box)
			else:
				var material := instance.mesh.surface_get_material(0)
				if material != null and material.resource_name == BulletHoles.GLASS_MATERIAL:
					glass.append(box)
		if not stripes.is_empty():
			striped += 1
		for stripe in stripes:
			for pane in glass:
				if stripe.intersects(pane) and not bad.has(String(entry["id"])):
					bad.append(entry["id"])
		root.free()
	_check(striped > 0 and bad.is_empty(), "stripes stop at the glass on all %d striped vehicles (%s)" % [striped, ", ".join(bad)])


## Real Hitscan shots: a body shot leaves a hole on the bodywork, a window shot leaves a crack in
## the glass, melee leaves nothing, and old holes are recycled past the cap.
func _test_bullet_holes() -> void:
	var shooter := Node3D.new()
	_runner.add_child(shooter)
	var vehicle := VehicleCatalog.instantiate(&"meridian", 1) as Vehicle
	vehicle.freeze = true
	_runner.add_child(vehicle)
	vehicle.global_position = TEST_ORIGIN + Vector3(60.0, 0.0, 0.0)
	await _runner.get_tree().physics_frame
	await _runner.get_tree().physics_frame
	var pistol := (load("res://data/weapons/pistol.tres") as WeaponData).duplicate() as WeaponData
	pistol.spread_degrees = 0.0
	pistol.show_tracer = false
	var centre := vehicle.global_position
	var health := vehicle.health

	var door := centre + Vector3(0.0, 0.55, 0.0)
	Hitscan.fire(shooter, door + Vector3(6.0, 0.0, 0.0), Vector3.LEFT, pistol)
	var holes := BulletHoles.holes_on(vehicle)
	var hole: MeshInstance3D = holes[0] if holes.size() == 1 else null
	_check(hole != null and hole.name == "BulletHole" and not BulletHoles.is_glass(hole.get_parent())
		and hole.global_position.x > centre.x + 0.5 and absf(hole.global_position.y - door.y) < 0.05,
		"a body shot leaves one bullet hole on the bodywork where it struck")
	_check(vehicle.health < health, "the shot still damages the vehicle")

	var pane := _glass_centre(vehicle)
	Hitscan.fire(shooter, pane + Vector3(0.0, 0.6, 5.0), (pane - (pane + Vector3(0.0, 0.6, 5.0))).normalized(), pistol)
	holes = BulletHoles.holes_on(vehicle)
	_check(holes.size() == 2 and holes[1].name == "GlassCrack" and BulletHoles.is_glass(holes[1].get_parent()),
		"a window shot cracks the glass")

	var fists := load("res://data/weapons/fists.tres") as WeaponData
	Hitscan.fire(shooter, door + Vector3(6.0, 0.0, 0.0), Vector3.LEFT, fists)
	_check(BulletHoles.holes_on(vehicle).size() == 2, "melee hits leave no holes")

	for i in BulletHoles.MAX_PER_BODY + 10:
		vehicle.on_bullet_hit(door + Vector3(1.0, 0.0, -1.0 + i * 0.04), Vector3.LEFT, Vector3.RIGHT)
	await _runner.get_tree().process_frame
	var kept := BulletHoles.holes_on(vehicle).size()
	_check(kept == BulletHoles.MAX_PER_BODY, "holes are capped at %d per vehicle (%d)" % [BulletHoles.MAX_PER_BODY, kept])
	vehicle.free()
	shooter.free()


func _glass_centre(vehicle: Vehicle) -> Vector3:
	for node in vehicle.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.name == "Windshield" or instance.name == "Glass":
			return instance.global_transform * instance.mesh.get_aabb().get_center()
	return vehicle.global_position + Vector3.UP


func _to_root(root: Node3D, node: Node3D) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform


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
	var door_panel := vehicle.get_node_or_null("Doors/Driver/Panel") as MeshInstance3D
	_check(door_panel != null and door_panel.material_override is StandardMaterial3D
			and (door_panel.material_override as StandardMaterial3D).albedo_color.is_equal_approx(a[0]),
			"the swinging driver door wears the body paint")
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


## Animated get-in / get-out on a door car (approached from the far side), a motorbike, the bus and
## the doorless 4x4: the player ends up driving with the hips on the seat, the door swings and shuts,
## and getting out leaves them standing beside the vehicle.
func _test_boarding(player: Player) -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120.0, 1.0, 40.0)
	shape.shape = box
	ground.add_child(shape)
	_runner.add_child(ground)
	var origin := TEST_ORIGIN + Vector3(0.0, 0.0, 150.0)
	ground.global_position = origin + Vector3(40.0, -0.5, 0.0)
	var home := player.global_position
	var index := 0
	for id: StringName in [&"regent", &"razorback", &"transit", &"palmetto"]:
		var vehicle := VehicleCatalog.instantiate(id, 7) as Vehicle
		_runner.add_child(vehicle)
		vehicle.global_position = origin + Vector3(index * 25.0, 0.3, 0.0)
		index += 1
		await _runner.call("_physics_frames", 60)
		var info := vehicle.ride_info()
		var far_side := -signf((vehicle.get_node("DoorStand") as Node3D).position.x)
		player.global_position = vehicle.global_transform * Vector3(far_side * 3.5, 0.0, 0.5)
		vehicle.begin_enter(player)
		var started := player.is_busy() and not vehicle.can_enter()
		var door := vehicle.get_node_or_null("Doors/Driver") as Node3D
		var swing := 0.0
		for frame in 900:
			if not player.is_busy():
				break
			await _runner.call("_physics_frames", 1)
			if door != null:
				swing = maxf(swing, absf(door.rotation.y))
		await _runner.call("_physics_frames", 30)
		var seat := vehicle.global_transform * (vehicle.get_node("Seats/Driver") as Node3D).position
		var hips := player.visual.hips_position()
		_check(started and vehicle.driver == player and not player.is_on_foot(), "%s: E starts an animated get-in that ends driving" % id)
		_check(hips.distance_to(seat) < 0.2, "%s: the driver sits on the seat (hips %.2f m off)" % [id, hips.distance_to(seat)])
		if info["door"]:
			_check(swing > 0.8 and absf(door.rotation.y) < 0.05, "%s: the driver's door opens and shuts (swung %.2f rad)" % [id, swing])
		if info["pose"] == "straddle":
			var feet := player.visual.global_transform.origin
			_check(absf(hips.y - feet.y) < 0.8, "%s: the rider straddles the bike, not standing" % id)

		vehicle.begin_exit()
		_check(vehicle.driver == null and player.is_busy(), "%s: E starts an animated get-out" % id)
		for frame in 900:
			if not player.is_busy():
				break
			await _runner.call("_physics_frames", 1)
		var stand := vehicle.global_transform * (vehicle.get_node("DoorStand") as Node3D).position
		var flat := Vector2(player.global_position.x - stand.x, player.global_position.z - stand.z).length()
		_check(player.is_on_foot() and flat < 1.0 and player.global_basis.y.y > 0.99, "%s: getting out leaves the player standing by the door (%.2f m)" % [id, flat])
		vehicle.free()
	player.global_position = home
	player.velocity = Vector3.ZERO
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
