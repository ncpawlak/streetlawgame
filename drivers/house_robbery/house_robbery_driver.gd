extends Node3D
## House robbery driver: a standalone street with a burglable house (three income tiers), neighbours,
## a stakeout bench, a getaway car and a stash. Not part of the city.
##
## Debug keys: F1/F2/F3 tier, F4 owners home, F5 re-roll loot (Shift: refill tools), F6 reset,
## F7 toggle roof (Shift: cut the power), F8 dog (Shift: safes locked), F9/F10/F11 lookout / driver /
## muscle, F12 +25 area heat (Shift: clear heat), X mask.
## Launch: godot --path . res://drivers/house_robbery/house_robbery_driver.tscn
## Screenshots: godot --path . res://drivers/house_robbery/house_robbery_driver.tscn -- --screenshots=<dir>

const STREET_Z := 10.0
const HOUSE_FRONT_Z := -2.0
const PLAYER_START := Vector3(-4.0, 1.0, 18.0)
const STASH_POS := Vector3(-95.0, 0.0, 19.0)
const SWAP_CAR_POS := Vector3(-80.0, 0.6, STREET_Z + 2.0)
const LOOKOUT_POST := Vector3(6.0, 0.2, STREET_Z + 6.5)
const HEAT_AREA := &"maple_street"
const COP_SPAWNS: Array[Vector3] = [Vector3(150.0, 1.0, 8.0), Vector3(-160.0, 1.0, 12.0), Vector3(150.0, 1.0, 12.0)]

var tier := HouseLayouts.Tier.MEDIUM
var owners_home := false

var house: House
var session: HitSession
var stakeout: StakeoutSpot
var stash: StashDropoff
var getaway: Vehicle
## A clean car parked down the street: leave the hit in it with the mask off to lose the heat fast.
var swap_car: Vehicle
var _help: Label
var _walkway: Node3D
var _result := ""

@onready var _player: Player = $Player


func _ready() -> void:
	_build_environment()
	_build_street()
	_build_neighbours()

	session = HitSession.new()
	session.name = "HitSession"
	add_child(session)
	house = House.new()
	house.name = "House"
	session.heat_area = HEAT_AREA
	session.setup(_player, COP_SPAWNS, house, HouseLayouts.NEIGHBOUR_SECONDS[tier])
	session.crew.lookout_post = LOOKOUT_POST
	house.police_call = session.police_call
	house.heat_map = session.heat_map
	house.heat_area = session.heat_area
	house.layout = {"pending": true}
	add_child(house)

	stakeout = StakeoutSpot.new()
	stakeout.name = "Stakeout"
	stakeout.position = Vector3(0.0, 0.0, STREET_Z + 7.5)
	stakeout.house = house
	add_child(stakeout)

	stash = StashDropoff.new()
	stash.name = "Stash"
	stash.prompt_name = "Lock-up garage"
	stash.position = STASH_POS
	add_child(stash)
	session.register_stash(stash)
	session.finished.connect(func(cash: int) -> void: _result = "Bag cashed in for $%d - F6 for another go" % cash)
	session.failed.connect(func(_why: StringName) -> void: _result = "Busted! The bag's gone - F6 to reset")

	_build_help()
	_refill_tools()
	_rebuild()
	_reset_player()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	EventBus.notify.emit.call_deferred("House robbery driver - F1-F3 tier, F4 owners home, F5 re-roll loot, F6 reset, X mask")

	var shots := _screenshot_dir()
	if shots != "":
		_take_screenshots.call_deferred(shots)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.shift_pressed and _shift_key(key.keycode):
			get_viewport().set_input_as_handled()
			return
		match key.keycode:
			KEY_F1:
				set_tier(HouseLayouts.Tier.LOW)
			KEY_F2:
				set_tier(HouseLayouts.Tier.MEDIUM)
			KEY_F3:
				set_tier(HouseLayouts.Tier.HIGH)
			KEY_F4:
				owners_home = not owners_home
				reset()
				EventBus.notify.emit("Owners %s" % ("home" if owners_home else "out"))
			KEY_F5:
				house.reroll_loot()
				house.set_safes_locked(house.safes_locked)
				EventBus.notify.emit("Loot re-rolled (seed %d)" % house.loot_seed)
			KEY_F6:
				reset()
				EventBus.notify.emit("Reset")
			KEY_F7:
				house.set_roof_hidden(not house._roof_forced_hidden)
			KEY_F8:
				house.dogs_enabled = not house.dogs_enabled
				reset()
				EventBus.notify.emit("Dogs %s (medium / high houses)" % ("on" if house.dogs_enabled else "off"))
			KEY_F9:
				_toggle_crew(CrewSlot.Role.LOOKOUT)
			KEY_F10:
				_toggle_crew(CrewSlot.Role.DRIVER)
			KEY_F11:
				_toggle_crew(CrewSlot.Role.MUSCLE)
			KEY_F12:
				session.heat_map.add_area_heat(session.heat_area, 25.0)
				EventBus.notify.emit(session.heat_map.describe(session.heat_area))
			KEY_X:
				HitIdentity.of(_player).toggle_mask()
			_:
				return
		get_viewport().set_input_as_handled()


## Shift + F-key debug toggles. Returns true if handled.
func _shift_key(code: Key) -> bool:
	match code:
		KEY_F5:
			_refill_tools()
			EventBus.notify.emit("Tools refilled: %s" % HitTools.of(_player).summary())
		KEY_F7:
			house.cut_power()
		KEY_F8:
			house.set_safes_locked(not house.safes_locked)
			EventBus.notify.emit("Safes %s" % ("locked (crack them)" if house.safes_locked else "unlocked"))
		KEY_F12:
			session.heat_map.clear()
			EventBus.notify.emit("Heat cleared")
		_:
			return false
	return true


func _toggle_crew(role: CrewSlot.Role) -> void:
	var on := session.crew.toggle(role)
	EventBus.notify.emit("%s %s" % [CrewSlot.ROLE_NAMES[role], "joined the crew" if on else "went home"])


func _refill_tools() -> void:
	var tools := HitTools.of(_player)
	tools.counts[HitTools.DOG_TREAT] = 2
	tools.counts[HitTools.SPRAY_PAINT] = 2
	tools.changed.emit()


func _process(_delta: float) -> void:
	if not session.in_progress and session.state == HitSession.State.ACTIVE and _result == "" and house.on_property(_player.global_position):
		session.begin_hit()
	_update_objective()
	var identity := HitIdentity.of(_player)
	_help.text = "HOUSE ROBBERY DRIVER\n%s  |  owners %s  |  loot $%d (seed %d)\n%s  |  dogs %s  |  safes %s%s\n%s  |  tools: %s\n%s  |  payout x%.2f, +%d cops\nF1/F2/F3 tier   F4 owners home   F5 re-roll loot (Shift: refill tools)\nF6 reset   F7 roof (Shift: cut power)   F8 dog (Shift: lock safes)\nF9 lookout   F10 driver   F11 muscle   F12 +heat (Shift: clear)\nX mask   Esc free mouse" % [
		house.tier_name(), "HOME" if house.owners_home else "out", house.loot_value(), house.loot_seed,
		session.crew.summary(), "on" if house.dogs_enabled else "off", "locked" if house.safes_locked else "open",
		"  |  POWER OFF %d s" % ceili(house.power_off_left) if not house.is_power_on() else "",
		identity.status_text(), HitTools.of(_player).summary() if HitTools.of(_player).summary() != "" else "none",
		session.heat_map.describe(session.heat_area), session.heat_map.payout_multiplier(session.heat_area), session.heat_map.extra_cops(session.heat_area)]


func set_tier(new_tier: int) -> void:
	tier = new_tier
	reset()
	EventBus.notify.emit(HouseLayouts.TIER_NAMES[tier])


## Rebuilds the house, clears the police and the bag, and puts the player back at the start.
func reset() -> void:
	stakeout.end()
	session.reset()
	session.state = HitSession.State.ACTIVE
	session.police_call.countdown_seconds = HouseLayouts.NEIGHBOUR_SECONDS[tier]
	if session.bag != null:
		session.bag.empty()
	_result = ""
	_refill_tools()
	_rebuild()
	_reset_player()
	session.crew.place()


func _rebuild() -> void:
	house.build(tier, owners_home)
	house.position = Vector3(0.0, 0.0, HOUSE_FRONT_Z - house.size().y * 0.5)
	house.set_police_call(session.police_call)
	if _walkway != null:
		_walkway.position.x = house.front_door().global_position.x

func _reset_player() -> void:
	if _player.current_vehicle != null:
		_player.current_vehicle.exit()
	_player.global_position = PLAYER_START
	_player.spawn_point = PLAYER_START
	_player.velocity = Vector3.ZERO
	_player.rotation.y = 0.0
	if getaway != null and is_instance_valid(getaway):
		getaway.queue_free()
	getaway = Vehicle.new()
	getaway.name = "Getaway"
	getaway.body_color = Color(0.55, 0.12, 0.1)
	getaway.position = Vector3(8.0, 0.6, STREET_Z + 2.0)
	getaway.rotation.y = PI * 0.5
	add_child(getaway)
	session.crew.getaway = getaway
	session.crew.getaway_spot = getaway.transform
	if swap_car != null and is_instance_valid(swap_car):
		swap_car.queue_free()
	swap_car = Vehicle.new()
	swap_car.name = "SwapCar"
	swap_car.body_color = Color(0.2, 0.35, 0.6)
	swap_car.position = SWAP_CAR_POS
	swap_car.rotation.y = PI * 0.5
	add_child(swap_car)


func _update_objective() -> void:
	if session.hud == null:
		return
	var text := ""
	var bag := session.bag
	if _result != "":
		text = _result
	elif session.police_response.is_wanted():
		text = "Lose the cops - get out of sight and far away"
	elif stakeout.active:
		text = "Staking out the house"
	elif not house.is_broken_into:
		text = "Stake out the house from the bench, then find a way in"
	elif house.contains_point(_player.global_position):
		text = "Search the house - steal what you can carry, then get out"
	elif bag != null and not bag.is_empty():
		text = "Take the bag to the lock-up garage (west end) - mask off + the blue swap car sheds heat fastest"
	else:
		text = "Nothing in the bag yet"
	session.hud.set_objective(text)


# --- world ------------------------------------------------------------------------------------

func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.32, 0.45, 0.7)
	sky_material.sky_horizon_color = Color(0.78, 0.62, 0.52)
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
	sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)


func _box(box_size: Vector3, at: Vector3, color: Color, solid := true) -> Node3D:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	if not solid:
		visual.position = at
		add_child(visual)
		return visual
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = box_size
	shape.shape = box
	body.add_child(shape)
	body.add_child(visual)
	add_child(body)
	return body


func _build_street() -> void:
	# Ground (grass), road, sidewalks, and a driveway to the house.
	_box(Vector3(400.0, 1.0, 200.0), Vector3(0.0, -0.5, 0.0), Color(0.3, 0.45, 0.25))
	_box(Vector3(360.0, 0.02, 8.0), Vector3(0.0, 0.01, STREET_Z), Color(0.18, 0.18, 0.2), false)
	for x in range(-176, 180, 8):
		_box(Vector3(3.0, 0.03, 0.2), Vector3(x, 0.02, STREET_Z), Color(0.9, 0.85, 0.4), false)
	for z: float in [STREET_Z - 5.0, STREET_Z + 5.0]:
		_box(Vector3(360.0, 0.15, 2.0), Vector3(0.0, 0.075, z), Color(0.62, 0.62, 0.6))
	_walkway = _box(Vector3(2.0, 0.04, 6.0), Vector3(-2.0, 0.02, 1.0), Color(0.55, 0.55, 0.52), false)
	var sign_label := Label3D.new()
	sign_label.text = "Maple Street"
	sign_label.font_size = 64
	sign_label.pixel_size = 0.01
	sign_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign_label.position = Vector3(14.0, 3.0, STREET_Z + 6.0)
	add_child(sign_label)
	# Lock-up garage around the stash.
	var garage := Color(0.4, 0.4, 0.45)
	_box(Vector3(8.0, 3.5, 0.3), STASH_POS + Vector3(0.0, 1.75, 4.0), garage)
	_box(Vector3(0.3, 3.5, 8.0), STASH_POS + Vector3(-4.0, 1.75, 0.0), garage)
	_box(Vector3(0.3, 3.5, 8.0), STASH_POS + Vector3(4.0, 1.75, 0.0), garage)
	_box(Vector3(8.6, 0.3, 8.6), STASH_POS + Vector3(0.0, 3.6, 0.0), garage.darkened(0.3), false)


func _build_neighbours() -> void:
	var colors := [Color(0.7, 0.62, 0.5), Color(0.6, 0.66, 0.72), Color(0.75, 0.7, 0.6), Color(0.66, 0.55, 0.58)]
	var index := 0
	for x: float in [-56.0, -30.0, 30.0, 56.0]:
		_neighbour_house(Vector3(x, 0.0, HOUSE_FRONT_Z - 6.0), colors[index % colors.size()], 0.0)
		index += 1
	for x: float in [-44.0, -18.0, 18.0, 44.0]:
		_neighbour_house(Vector3(x, 0.0, STREET_Z + 18.0), colors[index % colors.size()], PI)
		index += 1


func _neighbour_house(at: Vector3, color: Color, yaw: float) -> void:
	var holder := Node3D.new()
	holder.position = at
	holder.rotation.y = yaw
	add_child(holder)
	var body := _box(Vector3(12.0, 4.0, 10.0), Vector3.ZERO, color)
	body.reparent(holder, false)
	body.position = Vector3(0.0, 2.0, 0.0)
	var roof := _box(Vector3(12.8, 0.4, 10.8), Vector3.ZERO, color.darkened(0.5), false)
	roof.reparent(holder, false)
	roof.position = Vector3(0.0, 4.2, 0.0)
	var window_material := StandardMaterial3D.new()
	window_material.albedo_color = Color(1.0, 0.85, 0.55)
	window_material.emission_enabled = true
	window_material.emission = Color(1.0, 0.8, 0.5)
	window_material.emission_energy_multiplier = 0.6
	for x: float in [-3.5, 3.5]:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.4, 1.1, 0.05)
		mesh.material = window_material
		var window := MeshInstance3D.new()
		window.mesh = mesh
		window.position = Vector3(x, 1.8, 5.03)
		holder.add_child(window)


func _build_help() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	_help = Label.new()
	_help.position = Vector2(16.0, 160.0)
	_help.add_theme_font_size_override("font_size", 14)
	_help.add_theme_color_override("font_color", Color(1.0, 1.0, 0.8))
	_help.add_theme_color_override("font_outline_color", Color.BLACK)
	_help.add_theme_constant_override("outline_size", 5)
	layer.add_child(_help)


# --- screenshots ------------------------------------------------------------------------------

func _screenshot_dir() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshots="):
			return arg.trim_prefix("--screenshots=")
	return ""


func _capture(dir: String, file: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(dir.path_join(file))
	print("screenshot: ", dir.path_join(file))


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _take_screenshots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var overhead := Camera3D.new()
	overhead.fov = 50.0
	add_child(overhead)
	# Top-down floor plans, one per tier, roof off, owners home so they show up.
	for t in [HouseLayouts.Tier.LOW, HouseLayouts.Tier.MEDIUM, HouseLayouts.Tier.HIGH]:
		tier = t
		owners_home = true
		reset()
		house.set_roof_hidden(true)
		house.set_reveal(true)
		var span := maxf(house.size().x, house.size().y * 1.6) + 6.0
		overhead.look_at_from_position(house.global_position + Vector3(0.0, span * 1.05, span * 0.35), house.global_position, Vector3.UP)
		overhead.make_current()
		await _wait(20)
		await _capture(dir, "layout_%s.png" % ["low", "medium", "high"][t])
		house.set_reveal(false)
		house.set_roof_hidden(false)
	overhead.queue_free()
	_player.get_node("CameraPivot/SpringArm/Camera").make_current()
	# Stakeout view on the high-income house with people home.
	_player.global_position = stakeout.global_position + Vector3(0.0, 0.5, 1.0)
	await _wait(5)
	stakeout.begin(_player)
	await _wait(20)
	await _capture(dir, "stakeout.png")
	stakeout.end()

	# Walking in the front door of the medium house, camera over the shoulder.
	tier = HouseLayouts.Tier.MEDIUM
	owners_home = false
	reset()
	var door := house.front_door()
	door.locked = false
	door._set_open(true)
	var inward := -(house.global_basis * door.outward).normalized()
	_player.global_position = door.global_position - inward * 0.3 + Vector3(0.0, 0.1, 0.0)
	_player.rotation.y = atan2(-inward.x, -inward.z)
	var walk_pivot: Node3D = _player.get_node("CameraPivot")
	walk_pivot.rotation.y = _player.rotation.y
	_player.get_node("CameraPivot/SpringArm").rotation.x = deg_to_rad(-10.0)
	await _wait(40)
	await _capture(dir, "doorway.png")
	# Standing in the high-income living room looking across to the foyer and kitchen.
	tier = HouseLayouts.Tier.HIGH
	owners_home = true
	reset()
	_player.global_position = house.to_global(Vector3(-11.5, 0.1, 6.5))
	walk_pivot.rotation.y = atan2(-1.0, 0.45)
	_player.rotation.y = walk_pivot.rotation.y
	_player.get_node("CameraPivot/SpringArm").rotation.x = deg_to_rad(-12.0)
	await _wait(40)
	await _capture(dir, "interior.png")

	# Looting: low-income house, owners out, broken in through the front door, a few things bagged.
	tier = HouseLayouts.Tier.LOW
	owners_home = false
	reset()
	house.front_door().pick_lock(_player)
	var items := house.loot_items()
	for i in mini(2, items.size()):
		items[i].take(_player)
	var target: LootContainer = house.containers[0]
	var to_target := target.global_position - house.global_position
	_player.global_position = target.global_position + Vector3(0.0, 0.1, 1.4 if to_target.z < 0 else -1.4)
	await _wait(10)
	var pivot: Node3D = _player.get_node("CameraPivot")
	pivot.rotation.y = atan2(-(target.global_position.x - _player.global_position.x), -(target.global_position.z - _player.global_position.z))
	_player.get_node("CameraPivot/SpringArm").rotation.x = deg_to_rad(-30.0)
	await _wait(40)
	await _capture(dir, "looting_hud.png")

	# Safe cracking: medium house, safes locked, the minigame mid-streak.
	tier = HouseLayouts.Tier.MEDIUM
	reset()
	house.set_safes_locked(true)
	var safe: LootContainer = house.safes()[0]
	_player.global_position = safe.global_position + (house.global_basis.x * -1.3) + Vector3(0.0, 0.1, 0.0)
	await _wait(5)
	var game := safe.crack(_player)
	game.auto_step = false
	game.pin = (game.sweet_start + game.sweet_end) * 0.5
	game.press()
	game.pin = game.sweet_start * 0.6
	game.step(0.0)
	await _wait(20)
	await _capture(dir, "safe_minigame.png")
	game.cancel()

	# Security extras from above: high house, roof off, dog, breaker box and recorder, crew in place.
	tier = HouseLayouts.Tier.HIGH
	reset()
	HitIdentity.of(_player).set_masked(true)
	session.crew.assign(CrewSlot.Role.LOOKOUT)
	session.crew.assign(CrewSlot.Role.DRIVER)
	session.crew.assign(CrewSlot.Role.MUSCLE)
	_player.global_position = house.to_global(Vector3(-house.size().x * 0.5 - 1.5, 0.1, 0.0))
	session.crew.place()
	house.cut_power()
	house.set_roof_hidden(true)
	house.set_reveal(true)
	var top := Camera3D.new()
	top.fov = 50.0
	add_child(top)
	var span := maxf(house.size().x, house.size().y * 1.6) + 6.0
	top.look_at_from_position(house.global_position + Vector3(0.0, span * 1.05, span * 0.45), house.global_position + Vector3(0.0, 0.0, 3.0), Vector3.UP)
	top.make_current()
	await _wait(30)
	await _capture(dir, "security_extras.png")
	top.queue_free()
	_player.get_node("CameraPivot/SpringArm/Camera").make_current()
	house.set_reveal(false)
	house.set_roof_hidden(false)

	# The crew from the street: masked player, muscle at their side, lookout on the corner.
	_player.global_position = Vector3(0.0, 0.5, STREET_Z + 3.0)
	session.crew.place()
	pivot.rotation.y = PI * 0.85
	_player.get_node("CameraPivot/SpringArm").rotation.x = deg_to_rad(-12.0)
	await _wait(40)
	await _capture(dir, "crew_mask.png")
	session.crew.clear()
	HitIdentity.of(_player).set_masked(false)
	get_tree().quit()
