class_name LootItem
extends Node3D
## Something worth stealing: hold E to put it in the actor's [CarryBag]. Cash goes in the bag as cash
## (no slots); goods take [member slots] and are paid out at the stash.

signal taken(item: LootItem, actor: Node)

@export var item_name := "Watch"
@export var value := 100
@export var slots := 1
@export var is_cash := false
## Hold-E time in seconds.
@export var take_time := 0.8
@export var size := Vector3(0.3, 0.2, 0.3)
@export var color := Color(0.85, 0.75, 0.3)

var interactable: Interactable


static func create(loot_name: String, loot_value: int, loot_slots: int, cash: bool, at: Vector3) -> LootItem:
	var item := LootItem.new()
	item.item_name = loot_name
	item.value = loot_value
	item.slots = loot_slots
	item.is_cash = cash
	item.position = at
	if cash:
		item.color = Color(0.25, 0.75, 0.3)
		item.size = Vector3(0.25, 0.08, 0.15)
		item.take_time = 0.4
	else:
		item.size = Vector3(0.25, 0.2, 0.25) * (1.0 + 0.6 * (loot_slots - 1))
	return item


func _ready() -> void:
	add_to_group("loot")
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.4
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position.y = size.y * 0.5
	add_child(visual)

	interactable = Interactable.new()
	interactable.prompt_name = label()
	interactable.radius = 1.4
	interactable.position.y = size.y * 0.5
	var action := InteractionAction.create(&"take", "Grab {target}" if is_cash else "Steal {target}", [_effect()], [_condition()])
	action.duration = take_time
	action.progress_text = "Bagging {target}..."
	interactable.add_action(action)
	add_child(interactable)


func label() -> String:
	return "$%d" % value if is_cash else "%s ($%d%s)" % [item_name, value, "" if slots <= 1 else ", %d slots" % slots]


func can_take(actor: Node) -> bool:
	if is_cash:
		return true
	var bag := CarryBag.of(actor, false)
	return bag == null or bag.can_fit(slots)


func take_reason(actor: Node) -> String:
	var bag := CarryBag.of(actor, false)
	return "Bag full (%d/%d)" % [bag.used_slots(), bag.capacity] if bag != null else ""


## Puts this item in [param actor]'s bag and removes it from the world.
func take(actor: Node) -> bool:
	if is_queued_for_deletion():
		return false
	var bag := CarryBag.of(actor)
	if is_cash:
		bag.add_cash(value)
	elif not bag.add_item(item_name, value, slots):
		return false
	EventBus.notify.emit("+ %s" % label())
	taken.emit(self, actor)
	queue_free()
	return true


func _effect() -> Effect:
	var effect := MethodEffect.create(&"take")
	effect.pass_actor = true
	return effect


func _condition() -> Condition:
	var condition := MethodCondition.create(&"can_take")
	condition.pass_actor = true
	condition.reason_method = &"take_reason"
	return condition
