extends Node3D
## Sandbox for the companion building blocks (scripts/companions/, Party autoload, vehicle seats).
##   1  Pedro yells "Follow me!" and leads you to his car; get in (E) and drive, he rides shotgun.
##   2  Two homies join your crew next to a rival crew; they fight, then pile into your ride.
##   3  A row with one vehicle of every class, every passenger seat taken (bus: the first few rows).
## Hold E next to a car to ride along, X switches seats, tap H for follow / hold, hold H to dismiss.
## F5 restarts, Esc releases the mouse, a click recaptures it.

const LEAD_ORIGIN := Vector3(0.0, 0.0, 0.0)
const FIGHT_ORIGIN := Vector3(-60.0, 0.0, 0.0)
const ROW_ORIGIN := Vector3(60.0, 0.0, -10.0)
const ROW_SPACING := 14.0
const MAX_SEATED_PER_VEHICLE := 6

@export var capture_mouse := true
@export var auto_start_lead := true

var pedro: Ally
var pedro_car: Vehicle
var homies: Array[Ally] = []
var fight_car: Vehicle
var rivals: Array[GangMember] = []
## Vehicle id -> seated ally count for the class row.
var row: Dictionary = {}

var _seed := 1


func _ready() -> void:
	_build_environment()
	_build_ground()
	_spawn_lead()
	_spawn_fight()
	_spawn_row()
	var help := Label.new()
	help.text = "COMPANIONS   1 Pedro leads   2 crew fight   3 seat row   E enter / hold E ride along   X switch seat   H follow/hold (hold: dismiss)   F5 restart"
	help.position = Vector2(16.0, 12.0)
	help.add_theme_color_override("font_outline_color", Color.BLACK)
	help.add_theme_constant_override("outline_size", 6)
	var layer := CanvasLayer.new()
	layer.add_child(help)
	add_child(layer)
	if capture_mouse and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if auto_start_lead:
		get_tree().create_timer(1.0).timeout.connect(start_lead)


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		match key.keycode:
			KEY_1:
				_go_to_station(LEAD_ORIGIN + Vector3(-2.0, 0.0, -2.0))
				start_lead()
			KEY_2:
				_go_to_station(FIGHT_ORIGIN + Vector3(0.0, 0.0, -4.0))
				start_fight()
			KEY_3:
				_go_to_station(ROW_ORIGIN + Vector3(-10.0, 0.0, 0.0))
			KEY_F5:
				Party.clear()
				get_tree().reload_current_scene()
			_:
				return
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func player() -> Player:
	return get_node_or_null("Player") as Player


# --- 1: Pedro leads you to his car ---------------------------------------------------------------

## Pedro runs to his car (waiting when you lag behind), boards the passenger seat and joins the crew,
## so you drive with him riding along. This is the shape a mission script would use.
func start_lead() -> void:
	if pedro == null or not is_instance_valid(pedro) or pedro.current_vehicle != null or pedro.mode == Ally.Mode.LEAD:
		return
	EventBus.notify.emit("Pedro: Follow me!")
	await pedro.lead_to(pedro_car, 10.0)
	if not is_instance_valid(pedro):
		return
	pedro.enter_vehicle(pedro_car, 1)
	await pedro.boarded
	Party.recruit(pedro)
	EventBus.notify.emit("Pedro: Get in, you're driving!")


func _spawn_lead() -> void:
	pedro_car = _vehicle(&"regent", LEAD_ORIGIN + Vector3(8.0, 0.0, 40.0), PI * 0.5)
	pedro = _ally("Pedro", LEAD_ORIGIN + Vector3(2.0, 0.0, 3.0), 7)
	pedro.recruitable = false
	_sign("PEDRO'S CAR", pedro_car.global_position + Vector3(0.0, 3.2, 0.0))


# --- 2: crew fight -------------------------------------------------------------------------------

## Recruits both homies (the crew caps at Party.max_followers) and wakes the rival crew up.
func start_fight() -> void:
	for homie in homies:
		if is_instance_valid(homie) and homie.can_recruit():
			Party.recruit(homie)
	for rival in rivals:
		if is_instance_valid(rival):
			rival.aggro_range = 30.0
	EventBus.notify.emit("Take them out, then grab the car")


func _spawn_fight() -> void:
	homies.append(_ally("Lil Tre", FIGHT_ORIGIN + Vector3(-2.0, 0.0, 0.0), 21))
	homies.append(_ally("Dice", FIGHT_ORIGIN + Vector3(2.0, 0.0, 0.0), 22))
	homies[1].weapon_id = &"smg"
	fight_car = _vehicle(&"rustbucket", FIGHT_ORIGIN + Vector3(-12.0, 0.0, 6.0), 0.0)
	for i in 3:
		var rival := GangMember.new()
		rival.gang_id = &"vipers"
		rival.weapon_id = &"pistol"
		rival.aggro_range = 0.0
		add_child(rival)
		rival.global_position = FIGHT_ORIGIN + Vector3(-6.0 + i * 6.0, 0.2, 32.0)
		rivals.append(rival)
	_sign("CREW FIGHT (press 2)", FIGHT_ORIGIN + Vector3(0.0, 3.5, 10.0))


# --- 3: passenger seats for every class ----------------------------------------------------------

func _spawn_row() -> void:
	var picks := _row_vehicle_ids()
	for i in picks.size():
		var id: StringName = picks[i]
		var at := ROW_ORIGIN + Vector3(0.0, 0.0, i * ROW_SPACING)
		var vehicle := _vehicle(id, at, -PI * 0.5)
		var entry := VehicleCatalog.find(id)
		var seated := 0
		for seat in range(1, mini(vehicle.seat_count(), MAX_SEATED_PER_VEHICLE + 1)):
			var rider := _ally("%s %d" % [id, seat], at + Vector3(-4.0, 0.0, seat * 0.5), 100 + i * 10 + seat)
			rider.recruitable = false
			vehicle.enter_seat(rider, seat)
			seated += 1
		row[id] = seated
		_sign("%s  %s  %d seats" % [str(entry.get("class_name", entry.get("class", ""))).to_upper(), str(entry.get("name", id)), vehicle.seat_count()], at + Vector3(0.0, 3.6, 0.0))


## One drivable vehicle per class that has passenger seats, plus the bus.
static func _row_vehicle_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	var seen := {}
	for entry: Dictionary in VehicleCatalog.entries():
		var ride: Dictionary = entry.get("ride", {})
		var passengers: Array = ride.get("passengers", [])
		if passengers.is_empty() or not entry.get("drivable", true):
			continue
		var cls := str(entry.get("class", ""))
		var is_bus := passengers.any(func(p: Dictionary) -> bool: return p.get("entry", "") == "bus")
		if seen.has(cls) and not is_bus:
			continue
		if is_bus and seen.has("bus"):
			continue
		seen[cls] = true
		if is_bus:
			seen["bus"] = true
		result.append(StringName(entry["id"]))
	return result


# --- Helpers -------------------------------------------------------------------------------------

func _go_to_station(at: Vector3) -> void:
	var who := player()
	if who == null:
		return
	if who.current_vehicle != null:
		who.current_vehicle.exit_seat(who)
	who.cancel_moves()
	who.global_position = at + Vector3.UP * 0.2
	who.velocity = Vector3.ZERO


func _vehicle(id: StringName, at: Vector3, yaw: float) -> Vehicle:
	var node := VehicleCatalog.instantiate(id, 4000 + _seed)
	_seed += 1
	add_child(node)
	node.global_transform = Transform3D(Basis(Vector3.UP, yaw), at + Vector3.UP * 0.3)
	return node as Vehicle


func _ally(ally_name: String, at: Vector3, look_seed: int) -> Ally:
	var ally := Ally.new()
	ally.display_name = ally_name
	ally.visual_seed = look_seed
	add_child(ally)
	ally.global_position = at + Vector3.UP * 0.1
	return ally


func _sign(text: String, at: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	label.outline_size = 12
	label.pixel_size = 0.01
	add_child(label)
	label.global_position = at


func _build_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	shape.shape = box
	ground.add_child(shape)
	var mesh := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = box.size
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.22, 0.22, 0.24)
	material.roughness = 1.0
	plane.material = material
	mesh.mesh = plane
	ground.add_child(mesh)
	add_child(ground)
	ground.position = Vector3(0.0, -0.5, 100.0)


func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.35, 0.5, 0.75)
	sky_material.sky_horizon_color = Color(0.8, 0.65, 0.55)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 160.0
	add_child(sun)
