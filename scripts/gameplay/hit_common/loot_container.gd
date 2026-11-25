class_name LootContainer
extends StaticBody3D
## Furniture you can search (dresser, desk, safe...). Hold E: whatever it holds goes into the actor's
## [CarryBag]; it may hold nothing. Re-fill with [method set_contents].

signal searched(container: LootContainer, actor: Node, found: Dictionary)
signal unlocked(container: LootContainer, actor: Node)

@export var container_name := "Dresser"
@export var size := Vector3(1.0, 0.9, 0.5)
@export var color := Color(0.45, 0.32, 0.2)
@export var search_time := 1.5

## {"name": String, "value": int, "slots": int, "cash": bool} or {} for nothing.
var contents: Dictionary = {}
var is_searched := false
var interactable: Interactable
## Locked containers (safes) must be cracked with a [TimingMinigame] before they can be searched.
var locked := false
var lock_hits := 3
var lock_speed := 0.5
var minigame: TimingMinigame

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
	var crack_effect := MethodEffect.create(&"crack")
	crack_effect.pass_actor = true
	var crack_condition := MethodCondition.create(&"can_crack")
	crack_condition.hide_when_unmet = true
	interactable.add_action(InteractionAction.create(&"crack", "Crack {target}", [crack_effect], [crack_condition]))
	add_child(interactable)


func label() -> String:
	return container_name


func set_contents(found: Dictionary) -> void:
	contents = found
	is_searched = false
	if _material != null:
		_material.albedo_color = color


func can_search() -> bool:
	return not is_searched and not locked


func can_crack() -> bool:
	return locked and not is_searched and (minigame == null or not minigame.active)


## Locks it behind a [TimingMinigame] ([param hits] in a row at [param speed]).
func set_locked(value: bool, hits := 3, speed := 0.5) -> void:
	locked = value
	lock_hits = hits
	lock_speed = speed


## Opens the lock minigame for [param actor]; on success it unlocks and searches. Returns it.
func crack(actor: Node) -> TimingMinigame:
	if not can_crack():
		return null
	if minigame == null:
		minigame = TimingMinigame.new()
		minigame.name = "LockMinigame"
		minigame.title = "Crack the %s" % container_name.to_lower()
		add_child(minigame)
		minigame.succeeded.connect(func() -> void:
			locked = false
			unlocked.emit(self, minigame.actor)
			search(minigame.actor))
	minigame.hits_needed = lock_hits
	minigame.speed = lock_speed
	minigame.start(actor)
	return minigame


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
