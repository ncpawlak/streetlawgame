extends Node3D
## Missions showcase: a tiny lot wired to data/missions/showcase_delivery.tres. Built only from the
## mission building blocks, not a real story mission:
##   start marker -> talk to Dre (dialogue hook, adds a Lead) -> steal the grey sedan (checkpoint)
##   -> deliver it to the garage zone (clean bonus: no heat, little damage) -> Pedro's call (phone
##   hook) -> park in the driveway with zero heat -> safehouse unlocks.
## The red "speed trap" zone adds heat so you can see the clean bonus fail and the park step block.
##
## Run: godot --path . res://scenes/showcase/missions_showcase.tscn
## Scripted playthrough (headless OK): ... -- --autoplay
## Screenshots (needs a window; use the _console exe to see output):       ... -- --screenshots=<dir>

const MISSION_ID := &"showcase_delivery"
const SAFEHOUSE_ID := &"showcase_safehouse"

const CONTACT_AT := Vector3(4, 0, 8)
const CAR_AT := Vector3(-8, 1, 18)
const GARAGE_AT := Vector3(-28, 0, 48)
const DRIVEWAY_AT := Vector3(26, 0, 52)
const SAFEHOUSE_AT := Vector3(26, 0, 62)
const SPEED_TRAP_AT := Vector3(0, 0, 34)

var player: Player
var hud: CanvasLayer
var car: Vehicle
var safehouse: PlayerSafehouse
var garage_zone: TriggerZone
var driveway_zone: TriggerZone
## Set by the scripted playthrough: true once the mission completed and the safehouse unlocked.
var autoplay_ok := false


func _ready() -> void:
	Missions.reset()
	_build_ground()
	_build_lot()
	player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	player.position = Vector3(0, 0.5, 0)
	add_child(player)
	hud = CanvasLayer.new()
	hud.set_script(load("res://scripts/ui/hud.gd"))
	add_child(hud)
	var args := OS.get_cmdline_user_args()
	var shots := ""
	for arg in args:
		if arg.begins_with("--screenshots="):
			shots = arg.trim_prefix("--screenshots=")
	if shots != "" or args.has("--autoplay"):
		_autoplay.call_deferred(shots)


func _build_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.32, 0.34, 0.33)
	mesh.material_override = material
	ground.add_child(mesh)
	add_child(ground)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.7, 0.85)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	add_child(env)


func _build_lot() -> void:
	var start := MissionStartMarker.new()
	start.name = "MissionStart"
	start.mission_id = MISSION_ID
	start.position = Vector3(0, 0, 4)
	add_child(start)

	var contact := _figure("Dre", Color(0.85, 0.6, 0.2))
	contact.position = CONTACT_AT
	add_child(contact)
	var talk := Interactable.new()
	talk.prompt_name = "Dre"
	talk.radius = 2.5
	talk.add_action(InteractionAction.create(&"talk", "Talk"))
	contact.add_child(talk)
	Missions.tag(talk, &"showcase_contact")
	Missions.tag(contact, &"showcase_contact")

	car = Vehicle.new()
	car.name = "GreySedan"
	car.body_color = Color(0.55, 0.56, 0.6)
	car.position = CAR_AT
	add_child(car)
	Missions.tag(car, &"showcase_car")

	garage_zone = _zone(&"showcase_delivery", GARAGE_AT, Vector3(8, 4, 10), Color(0.3, 0.9, 0.4, 0.2))
	garage_zone.mode = TriggerZone.Mode.IN_VEHICLE
	_sign("GARAGE", GARAGE_AT + Vector3(0, 5, 0))
	driveway_zone = _zone(&"showcase_driveway", DRIVEWAY_AT, Vector3(5, 4, 8), Color(0.3, 0.6, 1.0, 0.2))
	_sign("PEDRO'S DRIVEWAY", DRIVEWAY_AT + Vector3(0, 5, 0))

	var trap := _zone(&"showcase_speed_trap", SPEED_TRAP_AT, Vector3(12, 4, 4), Color(1.0, 0.2, 0.2, 0.2))
	trap.mode = TriggerZone.Mode.IN_VEHICLE
	trap.triggered.connect(func(_actor: Node) -> void: EventBus.heat_raised.emit(25, trap))
	_sign("SPEED TRAP (+heat)", SPEED_TRAP_AT + Vector3(0, 4, 0))

	safehouse = PlayerSafehouse.new()
	safehouse.name = "Safehouse"
	safehouse.safehouse_id = SAFEHOUSE_ID
	safehouse.position = SAFEHOUSE_AT
	safehouse.rotation_degrees.y = 180
	safehouse.garage_offset = Vector3(-6, 0, 4)
	add_child(safehouse)
	_sign("SAFEHOUSE", SAFEHOUSE_AT + Vector3(0, 4.5, 0))


func _zone(zone_id: StringName, at: Vector3, size: Vector3, color: Color) -> TriggerZone:
	var zone := TriggerZone.new()
	zone.name = String(zone_id)
	zone.zone_id = zone_id
	zone.size = size
	zone.color = color
	zone.position = at + Vector3(0, size.y * 0.5, 0)
	add_child(zone)
	return zone


func _figure(title: String, color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = title
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	body.mesh = capsule
	body.position.y = 0.9
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	body.material_override = material
	root.add_child(body)
	var label := Label3D.new()
	label.text = title
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 2.2
	label.font_size = 48
	root.add_child(label)
	return root


func _sign(text: String, at: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 96
	label.outline_size = 12
	label.position = at
	add_child(label)


# --- Scripted playthrough --------------------------------------------------------------------------

func _autoplay(shots: String) -> void:
	Missions.hook_auto_complete_delay = 0.3
	if shots != "":
		DirAccess.make_dir_recursive_absolute(shots)
	await _frames(20)
	Missions.start_mission(MISSION_ID)
	player.global_position = CONTACT_AT + Vector3(0, 0.2, -3.5)
	await _frames(30)
	await _shot(shots, "mission_hud_objective.png")

	# Talk to Dre: the dialogue hook auto-finishes (no dialogue system in this branch).
	talk_to_contact()
	await _until(func() -> bool: return Missions.journal.has_lead(&"showcase_garage"), 120)
	hud.get("journal_screen").call("open", JournalScreen.TAB_LEADS)
	await _frames(10)
	await _shot(shots, "mission_journal.png")
	hud.get("journal_screen").call("close")
	await _frames(5)

	player.global_position = car.global_position + Vector3(2.5, 0, 0)
	await _frames(5)
	car.enter(player)
	await _until(func() -> bool: return _step_id() == &"deliver", 60)
	await _drive_to(GARAGE_AT)
	await _until(func() -> bool: return _step_id() == &"park" or _step_id() == &"", 300)
	await _drive_to(DRIVEWAY_AT)
	await _until(func() -> bool: return not Missions.is_active(), 300)
	await _frames(10)
	await _shot(shots, "mission_complete.png")

	hud.get("mission_result").call("dismiss")
	car.exit()
	player.global_position = SAFEHOUSE_AT + Vector3(0, 0.2, -4.5)
	await _frames(60)
	await _shot(shots, "mission_safehouse.png")
	autoplay_ok = Missions.is_completed(MISSION_ID) and Missions.is_safehouse_unlocked(SAFEHOUSE_ID)
	print("SHOWCASE %s (completed=%s, safehouse=%s, bonuses=%s)" % [
		"OK" if autoplay_ok else "FAILED", Missions.is_completed(MISSION_ID),
		Missions.is_safehouse_unlocked(SAFEHOUSE_ID), Missions.last_run.bonuses if Missions.last_run != null else []])
	get_tree().quit(0 if autoplay_ok else 1)


## What pressing "Talk" on Dre does.
func talk_to_contact() -> void:
	for node in Missions.tagged(&"showcase_contact"):
		if node is Interactable:
			EventBus.interaction_performed.emit(node, &"talk", player)
			return


func _step_id() -> StringName:
	var step := Missions.active.current_step() if Missions.active != null else null
	return step.id if step != null else &""


## Teleports the car (with the player in it) onto [param at] and lets it settle.
func _drive_to(at: Vector3) -> void:
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.global_transform = Transform3D(Basis.IDENTITY, at + Vector3(0, 0.8, 0))
	await _frames(40)


func _until(predicate: Callable, max_frames: int) -> void:
	for i in max_frames:
		if predicate.call():
			return
		await get_tree().physics_frame


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _shot(dir: String, file: String) -> void:
	if dir == "":
		return
	await get_tree().process_frame
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	var image := get_viewport().get_texture().get_image()
	var path := dir.path_join(file)
	image.save_png(path)
	print("screenshot: %s" % path)
