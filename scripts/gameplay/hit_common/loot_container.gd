class_name LootContainer
extends StaticBody3D
## Furniture you can search (dresser, desk, safe...). Hold E: whatever it holds goes into the actor's
## [CarryBag]; it may hold nothing. Re-fill with [method set_contents].

signal searched(container: LootContainer, actor: Node, found: Dictionary)

@export var container_name := "Dresser"
@export var size := Vector3(1.0, 0.9, 0.5)
@export var color := Color(0.45, 0.32, 0.2)
@export var search_time := 1.5

## {"name": String, "value": int, "slots": int, "cash": bool} or {} for nothing.
var contents: Dictionary = {}
var is_searched := false
var interactable: Interactable

var _material: StandardMaterial3D


func _ready() -> void:
	add_to_group("loot_containers")
	collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = size.y * 0.5
	add_child(shape)
	var mesh := BoxMesh.new()
	mesh.size = size
	_material = StandardMaterial3D.new()
	_material.albedo_color = color
	mesh.material = _material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position.y = size.y * 0.5
	add_child(visual)

	interactable = Interactable.new()
	interactable.prompt_name = container_name
	interactable.radius = maxf(size.x, size.z) * 0.5 + 1.0
	interactable.position.y = size.y * 0.5
	var effect := MethodEffect.create(&"search")
	effect.pass_actor = true
	var condition := MethodCondition.create(&"can_search")
	condition.reason_text = "Already searched"
	condition.hide_when_unmet = true
	var action := InteractionAction.create(&"search", "Search {target}", [effect], [condition])
	action.duration = search_time
	action.progress_text = "Searching {target}..."
	interactable.add_action(action)
	add_child(interactable)


func label() -> String:
	return container_name


func set_contents(found: Dictionary) -> void:
	contents = found
	is_searched = false
	if _material != null:
		_material.albedo_color = color


func can_search() -> bool:
	return not is_searched


## Searches the container. Returns what was bagged ({} for nothing or no room).
func search(actor: Node) -> Dictionary:
	if is_searched:
		return {}
	var bag := CarryBag.of(actor)
	var found := contents
	if found.is_empty():
		EventBus.notify.emit("%s: nothing worth taking" % container_name)
	elif bool(found.get("cash", false)):
		bag.add_cash(int(found["value"]))
		EventBus.notify.emit("+ $%d (from the %s)" % [int(found["value"]), container_name.to_lower()])
	elif not bag.add_item(String(found["name"]), int(found["value"]), int(found.get("slots", 1))):
		EventBus.notify.emit("No room in the bag for the %s" % String(found["name"]).to_lower())
		return {}
	else:
		EventBus.notify.emit("+ %s ($%d)" % [found["name"], int(found["value"])])
	is_searched = true
	contents = {}
	_material.albedo_color = color.darkened(0.45)
	searched.emit(self, actor, found)
	return found
