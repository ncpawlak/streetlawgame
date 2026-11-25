extends Node3D
## Stick-up driver: a standalone street with a shop to hold up, neighbouring businesses, bystanders,
## a getaway car and a stash. Boots straight into the scenario; not part of the city.
## Shop type is picked in the debug panel (or F1/F2); F3 restarts. See README "Gameplay drivers".

const SHOPS := {
	&"corner_store": preload("res://drivers/stick_up/shops/corner_store.tres"),
	&"liquor_store": preload("res://drivers/stick_up/shops/liquor_store.tres"),
}
const SHOP_ORDER: Array[StringName] = [&"corner_store", &"liquor_store"]
## Shop interior: front wall on z = SHOP_FRONT, door in the middle.
const SHOP_WIDTH := 12.0
const SHOP_DEPTH := 12.0
const SHOP_FRONT := -10.0
const WALL_HEIGHT := 4.0
const DOOR_WIDTH := 2.4
const PLAYER_START := Vector3(-7.0, 0.1, -7.5)
const CAR_POSITION := Vector3(9.0, 0.6, -3.0)
const STASH_POSITION := Vector3(42.0, 0.0, 24.0)
const COP_SPAWNS: Array[Vector3] = [Vector3(-60.0, 0.6, 2.5), Vector3(60.0, 0.6, -2.5)]

## Survives scene reloads so "Restart" keeps the chosen shop.
static var selected_shop: StringName = &"corner_store"

var shop: StickUpShopDef
var controller: StickUpController
var session: HitSession
var stash: StashDropoff
var getaway_car: Vehicle
var clerk: StickUpNpc
var customers: Array[StickUpNpc] = []
var witnesses: Array[StickUpNpc] = []
var register: Node3D
var register_interactable: Interactable
var stands: Array[ShelfStand] = []

var _status: Label
var _shop_picker: OptionButton

@onready var player: Player = $Player


func _ready() -> void:
	shop = SHOPS.get(selected_shop, SHOPS[&"corner_store"])
	_build_environment()
	_build_street()
	_build_shop()
	_build_neighbours()
	_spawn_bystanders()
	_place_player()
	getaway_car = Vehicle.new()
	getaway_car.name = "GetawayCar"
	getaway_car.body_color = Color(0.15, 0.15, 0.2)
	getaway_car.position = CAR_POSITION
	getaway_car.rotation.y = PI / 2.0
	add_child(getaway_car)

	session = HitSession.new()
	session.name = "HitSession"
	add_child(session)
	var shop_center := Node3D.new()
	shop_center.name = "ShopCenter"
	shop_center.position = Vector3(0.0, 1.0, SHOP_FRONT - SHOP_DEPTH * 0.5)
	add_child(shop_center)
	session.setup(player, COP_SPAWNS, shop_center, shop.alarm_seconds)
	session.finished.connect(func(cash: int) -> void:
		EventBus.notify.emit("Stick-up done: +$%d stashed. [F3] to run it again." % cash)
		_set_objective("Done! +$%d. [F3] restart" % cash))
	session.failed.connect(func(_reason: StringName) -> void:
		EventBus.notify.emit("Busted. The bag's gone. [F3] to try again.")
		_set_objective("Busted. [F3] restart"))

	stash = StashDropoff.new()
	stash.name = "Stash"
	stash.position = STASH_POSITION
	add_child(stash)
	session.register_stash(stash)

	controller = StickUpController.new()
	controller.name = "StickUp"
	add_child(controller)
	var bounds := AABB(Vector3(-SHOP_WIDTH * 0.5, -0.5, SHOP_FRONT - SHOP_DEPTH), Vector3(SHOP_WIDTH, WALL_HEIGHT + 1.0, SHOP_DEPTH))
	controller.setup(shop, player, clerk, customers, witnesses, bounds, session.police_call)
	# The register's actions target the controller, which owns the cash in it.
	register_interactable.target = controller
	controller.gun_drawn.connect(func() -> void: _set_objective("Aim [RMB] at the clerk to hold them up"))
	controller.register_emptied.connect(func() -> void: _set_objective("Get away and stash the bag (green marker)"))
	clerk.died.connect(func(_npc: StickUpNpc, _killer: Node) -> void:
		if controller.register_cash > 0:
			_set_objective("Clerk's down - hold [E] on the register to grab the cash"))

	_build_debug_panel()
	_set_objective("Walk into the %s and draw a gun [1-9 / wheel]" % shop.label())
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	EventBus.notify.emit.call_deferred("Stick-up driver: %s. Esc frees the mouse for the debug panel." % shop.label())


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_F1:
				select_shop(&"corner_store")
			KEY_F2:
				select_shop(&"liquor_store")
			KEY_F3:
				restart()
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if not _panel_has_mouse():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _status == null or controller == null:
		return
	var call := session.police_call
	var police := "idle"
	if call.is_counting():
		police = "countdown %.0fs" % call.time_left
	elif call.is_called():
		police = "called (%s)" % call.reason
	if session.police_response.is_wanted():
		police += ", WANTED"
	var aimed := controller.aimed_npc.label() if controller.aimed_npc != null else "-"
	_status.text = "Gun out: %s\nAiming at: %s\nClerk: %s\nRegister: $%d   Taken: $%d\nBag: $%d (%d/%d slots)\nPolice: %s" % [
		"yes" if controller.is_gun_drawn else "no", aimed, StickUpNpc.State.keys()[clerk.state],
		controller.register_cash, controller.taken, session.bag.total_value(), session.bag.used_slots(), session.bag.capacity, police]


func select_shop(id: StringName) -> void:
	if not SHOPS.has(id):
		return
	selected_shop = id
	restart()


func restart() -> void:
	get_tree().reload_current_scene()


func _set_objective(text: String) -> void:
	if session != null and session.hud != null:
		session.hud.set_objective(text)


func _place_player() -> void:
	player.global_position = PLAYER_START
	player.spawn_point = PLAYER_START
	player.rotation.y = 0.0
	# Walk in with the gun holstered (fists), so drawing it is the player's choice.
	player.weapons.add_weapon(GameState.weapon_data(&"smg"), 90)
	player.weapons.select(player.weapons.slots.find(player.weapons.find(&"fists")))


# --- World -------------------------------------------------------------------------------------

func _build_street() -> void:
	_box("Ground", Vector3(160.0, 1.0, 100.0), Vector3(0.0, -0.5, 0.0), Color(0.32, 0.36, 0.3))
	_box("Road", Vector3(160.0, 0.02, 12.0), Vector3(0.0, 0.01, 0.0), Color(0.18, 0.18, 0.2), false)
	for side: float in [-1.0, 1.0]:
		_box("Sidewalk", Vector3(160.0, 0.15, 4.0), Vector3(0.0, 0.075, side * 8.0), Color(0.55, 0.55, 0.52))
	for i in 16:
		_box("Lane", Vector3(4.0, 0.03, 0.25), Vector3(-75.0 + i * 10.0, 0.02, 0.0), Color(0.9, 0.85, 0.3), false)
	_label("$ STASH this way ->", Vector3(30.0, 3.0, 8.5), Color(0.5, 1.0, 0.6), 72)


func _build_shop() -> void:
	var color := shop.color()
	var back := SHOP_FRONT - SHOP_DEPTH
	var half := SHOP_WIDTH * 0.5
	var wall := Color(0.75, 0.72, 0.65)
	_box("ShopFloor", Vector3(SHOP_WIDTH, 0.05, SHOP_DEPTH), Vector3(0.0, 0.03, SHOP_FRONT - SHOP_DEPTH * 0.5), shop.interior_color, false)
	_box("ShopBack", Vector3(SHOP_WIDTH, WALL_HEIGHT, 0.3), Vector3(0.0, WALL_HEIGHT * 0.5, back), wall)
	_box("ShopLeft", Vector3(0.3, WALL_HEIGHT, SHOP_DEPTH), Vector3(-half, WALL_HEIGHT * 0.5, SHOP_FRONT - SHOP_DEPTH * 0.5), wall)
	_box("ShopRight", Vector3(0.3, WALL_HEIGHT, SHOP_DEPTH), Vector3(half, WALL_HEIGHT * 0.5, SHOP_FRONT - SHOP_DEPTH * 0.5), wall)
	var front_piece := (SHOP_WIDTH - DOOR_WIDTH) * 0.5
	for side: float in [-1.0, 1.0]:
		_box("ShopFront", Vector3(front_piece, WALL_HEIGHT, 0.3), Vector3(side * (DOOR_WIDTH * 0.5 + front_piece * 0.5), WALL_HEIGHT * 0.5, SHOP_FRONT), wall)
	_box("ShopLintel", Vector3(DOOR_WIDTH, 1.0, 0.3), Vector3(0.0, WALL_HEIGHT - 0.5, SHOP_FRONT), wall)
	_box("ShopSign", Vector3(SHOP_WIDTH * 0.7, 0.9, 0.2), Vector3(0.0, WALL_HEIGHT + 0.5, SHOP_FRONT + 0.1), color)
	_label(shop.label().to_upper(), Vector3(0.0, WALL_HEIGHT + 0.5, SHOP_FRONT + 0.25), Color.WHITE, 96, false)

	var counter_z := back + 3.0
	_box("Counter", Vector3(6.0, 1.0, 0.8), Vector3(-2.0, 0.5, counter_z), color.darkened(0.4))
	_box("BackShelf", Vector3(8.0, 2.2, 0.5), Vector3(-1.0, 1.1, back + 0.5), color.darkened(0.2))
	var stand_spots: Array[Vector3] = [Vector3(3.0, 0.0, SHOP_FRONT - 4.0), Vector3(3.0, 0.0, SHOP_FRONT - 8.5), Vector3(-4.0, 0.0, SHOP_FRONT - 6.0)]
	for i in mini(shop.products.size(), stand_spots.size()):
		var product: Dictionary = shop.products[i]
		var stand := ShelfStand.create(product["name"], product["value"], product["stock"], stand_spots[i], product.get("color", color.lightened(0.2)))
		add_child(stand)
		stands.append(stand)

	register = Node3D.new()
	register.name = "Register"
	register.position = Vector3(-2.5, 1.0, counter_z)
	add_child(register)
	var till := MeshInstance3D.new()
	var till_mesh := BoxMesh.new()
	till_mesh.size = Vector3(0.6, 0.35, 0.45)
	till_mesh.material = _material(Color(0.2, 0.2, 0.22))
	till.mesh = till_mesh
	till.position.y = 0.18
	register.add_child(till)
	var interactable := Interactable.new()
	interactable.name = "Interactable"
	interactable.prompt_name = "Register"
	interactable.radius = 2.2
	interactable.focus_priority = 5
	var condition := MethodCondition.create(&"can_grab_register", &"target")
	condition.pass_actor = true
	condition.reason_method = &"grab_register_reason"
	var effect := MethodEffect.create(&"grab_register", &"target")
	effect.pass_actor = true
	var action := InteractionAction.create(&"grab_register", "Empty the register", [effect], [condition])
	action.duration = shop.self_grab_time
	action.progress_text = "Grabbing the cash..."
	interactable.add_action(action)
	register.add_child(interactable)
	register_interactable = interactable

	clerk = _spawn_npc("Clerk", StickUpNpc.Role.CLERK, Vector3(-2.5, 0.1, counter_z - 1.2), Color(0.25, 0.45, 0.8))
	clerk.wander_radius = 0.0
	clerk.weapon_id = shop.clerk_weapon_id
	var spots: Array[Vector3] = [Vector3(1.4, 0.1, SHOP_FRONT - 4.0), Vector3(3.6, 0.1, SHOP_FRONT - 6.5), Vector3(-3.0, 0.1, SHOP_FRONT - 3.5), Vector3(4.6, 0.1, SHOP_FRONT - 2.0)]
	for i in mini(shop.customer_count, spots.size()):
		var customer := _spawn_npc("Customer%d" % (i + 1), StickUpNpc.Role.CUSTOMER, spots[i], Color.from_hsv(randf(), 0.5, 0.75))
		customer.wander_radius = 0.8
		customers.append(customer)
	for npc: StickUpNpc in [clerk] + customers:
		add_child(npc)


## Two neighbouring businesses next door and one across the road, each with a shopkeeper out front.
func _build_neighbours() -> void:
	var neighbours := [
		["Fresh Cutz", Vector3(-17.0, 0.0, SHOP_FRONT - 5.0), Color(0.3, 0.4, 0.9), Vector3(-17.0, 0.2, SHOP_FRONT + 1.0)],
		["Northgrove Pawn", Vector3(17.0, 0.0, SHOP_FRONT - 5.0), Color(0.8, 0.6, 0.2), Vector3(17.0, 0.2, SHOP_FRONT + 1.0)],
		["Gas-N-Go", Vector3(-4.0, 0.0, -SHOP_FRONT + 5.0), Color(0.9, 0.3, 0.3), Vector3(-4.0, 0.2, -SHOP_FRONT - 1.0)],
	]
	for entry: Array in neighbours:
		var at: Vector3 = entry[1]
		var color: Color = entry[2]
		_box("Neighbour", Vector3(10.0, 5.0, 10.0), at + Vector3(0.0, 2.5, 0.0), color.darkened(0.45))
		var facing := signf(-at.z)
		_box("NeighbourSign", Vector3(6.0, 0.8, 0.2), at + Vector3(0.0, 4.0, facing * 5.1), color)
		_label(entry[0], at + Vector3(0.0, 4.0, facing * 5.25), Color.WHITE, 72, false, facing < 0.0)
		var keeper := _spawn_npc("Shopkeeper", StickUpNpc.Role.NEIGHBOUR, entry[3], color.lightened(0.2))
		keeper.wander_radius = 1.0
		add_child(keeper)
		witnesses.append(keeper)


func _spawn_bystanders() -> void:
	var spots: Array[Vector3] = [Vector3(-12.0, 0.2, -8.0), Vector3(11.0, 0.2, -8.5), Vector3(6.0, 0.2, 8.0), Vector3(-22.0, 0.2, 8.5)]
	for i in spots.size():
		var npc := _spawn_npc("Bystander%d" % (i + 1), StickUpNpc.Role.BYSTANDER, spots[i], Color.from_hsv(0.08 * i + 0.3, 0.4, 0.7))
		npc.wander_radius = 4.0
		add_child(npc)
		witnesses.append(npc)


func _spawn_npc(npc_name: String, role: StickUpNpc.Role, at: Vector3, color: Color) -> StickUpNpc:
	var npc := StickUpNpc.new()
	npc.name = npc_name
	npc.role = role
	npc.body_color = color
	npc.position = at
	return npc


func _box(box_name: String, size: Vector3, at: Vector3, color: Color, collide := true) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _material(color)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	if not collide:
		instance.name = box_name
		instance.position = at
		add_child(instance)
		return
	var body := StaticBody3D.new()
	body.name = box_name
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.add_child(instance)
	add_child(body)


func _label(text: String, at: Vector3, color: Color, size := 64, billboard := true, flip := false) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.outline_size = 10
	label.modulate = color
	label.position = at
	if billboard:
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	elif flip:
		label.rotation.y = PI
	add_child(label)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material


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
	sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)


# --- Debug panel -------------------------------------------------------------------------------

func _build_debug_panel() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DebugPanel"
	layer.layer = 20
	add_child(layer)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.position = Vector2(20.0, 250.0)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "STICK-UP DRIVER"
	box.add_child(title)
	_shop_picker = OptionButton.new()
	for id in SHOP_ORDER:
		_shop_picker.add_item("%s [F%d]" % [(SHOPS[id] as StickUpShopDef).label(), SHOP_ORDER.find(id) + 1])
	_shop_picker.selected = SHOP_ORDER.find(selected_shop)
	_shop_picker.item_selected.connect(func(index: int) -> void: select_shop(SHOP_ORDER[index]))
	box.add_child(_shop_picker)
	var restart_button := Button.new()
	restart_button.text = "Restart [F3]"
	restart_button.pressed.connect(restart)
	box.add_child(restart_button)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 14)
	box.add_child(_status)
	var help := Label.new()
	help.add_theme_font_size_override("font_size", 12)
	help.modulate.a = 0.75
	help.text = "Draw: 1-9 / wheel   Hold up: RMB on clerk\nShoot: LMB   Car: E   Stash: hold E\nShelves / bodies: hold E   Esc: free mouse"
	box.add_child(help)


func _panel_has_mouse() -> bool:
	var panel := get_node_or_null("DebugPanel/Panel") as Control
	return panel != null and panel.get_global_rect().has_point(get_viewport().get_mouse_position())
