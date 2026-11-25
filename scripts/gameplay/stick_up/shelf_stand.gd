class_name ShelfStand
extends Node3D
## A stocked shop stand. Hold E to sweep product into your [CarryBag]: the stock meter drains while you
## hold, and each unit goes in the bag as an item worth [member unit_value] at the stash. Stops when
## you let go, the stand is empty or the bag is full.

signal unit_taken(stand: ShelfStand, actor: Node)
signal emptied(stand: ShelfStand)

const ACTION := &"grab_stock"

@export var product_name := "Cigarettes"
## Stash value per unit.
@export var unit_value := 25
## Bag slots per unit.
@export var unit_slots := 1
## Units on the stand.
@export var stock := 6
## Hold time per unit, in seconds.
@export var seconds_per_unit := 0.5
@export var size := Vector3(1.6, 1.4, 0.6)
@export var color := Color(0.8, 0.3, 0.3)

var stock_left := 0
## What the stock meter shows (0-1); drains smoothly while a unit is being bagged.
var meter := 1.0
var interactable: Interactable
var action: InteractionAction

var _meter_fill: MeshInstance3D
var _meter_label: Label3D
var _goods: Array[Node3D] = []


static func create(product: String, value: int, units: int, at: Vector3, tint: Color) -> ShelfStand:
	var stand := ShelfStand.new()
	stand.name = "Stand_" + product.validate_node_name().replace(" ", "")
	stand.product_name = product
	stand.unit_value = value
	stand.stock = units
	stand.position = at
	stand.color = tint
	return stand


func _ready() -> void:
	add_to_group("shelf_stands")
	stock_left = stock
	_build_visual()
	interactable = Interactable.new()
	interactable.name = "Interactable"
	interactable.prompt_name = product_name
	interactable.radius = maxf(size.x, size.z) * 0.5 + 1.0
	interactable.position.y = 1.0
	interactable.focus_priority = 2
	var effect := MethodEffect.create(&"grab")
	effect.pass_actor = true
	var condition := MethodCondition.create(&"can_grab")
	condition.pass_actor = true
	condition.reason_method = &"grab_reason"
	action = InteractionAction.create(ACTION, "Hold to bag {target} ($%d each)" % unit_value, [effect], [condition])
	action.duration = seconds_per_unit
	action.progress_text = "Bagging %s..." % product_name
	interactable.add_action(action)
	interactable.target = self
	add_child(interactable)
	_update_meter(float(stock_left))


func label() -> String:
	return "%s (%d/%d)" % [product_name, stock_left, stock]


func stock_fraction() -> float:
	return float(stock_left) / float(stock) if stock > 0 else 0.0


func can_grab(actor: Node = null) -> bool:
	return grab_reason(actor) == ""


func grab_reason(actor: Node = null) -> String:
	if stock_left <= 0:
		return "Shelf's empty"
	var bag := CarryBag.of(actor, false)
	if bag != null and not bag.can_fit(unit_slots):
		return "Bag full (%d/%d)" % [bag.used_slots(), bag.capacity]
	return ""


## Moves one unit into [param actor]'s bag. While the player keeps holding interact, the next unit
## starts straight away.
func grab(actor: Node) -> bool:
	if not can_grab(actor) or not CarryBag.of(actor).add_item(product_name, unit_value, unit_slots):
		return false
	stock_left -= 1
	_update_meter(float(stock_left))
	unit_taken.emit(self, actor)
	if stock_left <= 0:
		EventBus.notify.emit("%s shelf cleared" % product_name)
		emptied.emit(self)
	elif Input.is_action_pressed("interact"):
		_continue.call_deferred(actor)
	return true


func _continue(actor: Node) -> void:
	var interactor := _interactor_of(actor)
	if interactor == null or not Input.is_action_pressed("interact") or interactor.is_channelling():
		return
	if can_grab(actor):
		interactor.start(action, interactable)
	else:
		EventBus.notify.emit(grab_reason(actor))


func _process(_delta: float) -> void:
	var interactor := _interactor_of(GameState.player)
	if interactor == null or interactor.channel_target != interactable:
		return
	if not Input.is_action_pressed("interact"):
		interactor.cancel_channel("")
		_update_meter(float(stock_left))
		return
	# Drain smoothly while the current unit is being bagged.
	_update_meter(float(stock_left) - interactor.channel_fraction())


func _interactor_of(actor: Node) -> Interactor:
	if actor == null or not is_instance_valid(actor):
		return null
	return actor.get("interactor") as Interactor if "interactor" in actor else null


func _update_meter(units: float) -> void:
	var fraction := clampf(units / float(stock), 0.0, 1.0) if stock > 0 else 0.0
	meter = fraction
	if _meter_fill != null:
		_meter_fill.scale.x = maxf(fraction, 0.001)
		_meter_fill.position.x = -size.x * 0.5 * (1.0 - fraction)
		(_meter_fill.mesh.surface_get_material(0) as StandardMaterial3D).albedo_color = Color(0.9, 0.25, 0.2).lerp(Color(0.3, 0.9, 0.35), fraction)
	if _meter_label != null:
		_meter_label.text = label()
	for i in _goods.size():
		_goods[i].visible = i < ceili(units)


func _build_visual() -> void:
	var unit := _material(color.darkened(0.35))
	var frame_mesh := BoxMesh.new()
	frame_mesh.size = Vector3(size.x, 0.08, size.z)
	frame_mesh.material = unit
	for y: float in [0.3, size.y * 0.5 + 0.15, size.y]:
		var shelf := MeshInstance3D.new()
		shelf.mesh = frame_mesh
		shelf.position.y = y
		add_child(shelf)
	var collider := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = size.y * 0.5
	collider.add_child(shape)
	add_child(collider)
	for side: float in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.08, size.y, size.z)
		post_mesh.material = unit
		post.mesh = post_mesh
		post.position = Vector3(side * size.x * 0.5, size.y * 0.5, 0.0)
		add_child(post)

	# One box of product per unit, spread over the two shelves; they vanish as the stand empties.
	var goods_material := _material(color)
	var per_row := ceili(stock / 2.0)
	for i in stock:
		var item := MeshInstance3D.new()
		var item_mesh := BoxMesh.new()
		item_mesh.size = Vector3(minf(0.3, size.x / per_row - 0.06), 0.28, size.z * 0.7)
		item_mesh.material = goods_material
		item.mesh = item_mesh
		var row := floori(float(i) / per_row)
		var column := i % per_row
		var shelf_y: float = [0.3, size.y * 0.5 + 0.15][row]
		item.position = Vector3(-size.x * 0.5 + (column + 0.5) * size.x / per_row, shelf_y + 0.18, 0.0)
		add_child(item)
		_goods.append(item)

	var meter_back := MeshInstance3D.new()
	var back_mesh := BoxMesh.new()
	back_mesh.size = Vector3(size.x, 0.14, 0.05)
	back_mesh.material = _material(Color(0.1, 0.1, 0.1))
	meter_back.mesh = back_mesh
	meter_back.position = Vector3(0.0, size.y + 0.35, 0.0)
	add_child(meter_back)
	_meter_fill = MeshInstance3D.new()
	var fill_mesh := BoxMesh.new()
	fill_mesh.size = Vector3(size.x, 0.1, 0.07)
	var fill_material := _material(Color(0.3, 0.9, 0.35))
	fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mesh.material = fill_material
	_meter_fill.mesh = fill_mesh
	meter_back.add_child(_meter_fill)
	_meter_label = Label3D.new()
	_meter_label.font_size = 40
	_meter_label.outline_size = 10
	_meter_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_meter_label.position = Vector3(0.0, size.y + 0.65, 0.0)
	add_child(_meter_label)


func _material(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	return material
