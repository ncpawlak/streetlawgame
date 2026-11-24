class_name Inventory
extends RefCounted
## Item storage keyed by item id, with an optional total-unit capacity. Used for site stashes and
## reusable for player/vehicle/business storage.

signal changed(item_id: StringName, count: int)

## Total units across all items. 0 means unlimited.
var capacity := 0

var _items := {}


func count(item_id: StringName) -> int:
	return _items.get(item_id, 0)


func total() -> int:
	var sum := 0
	for amount: int in _items.values():
		sum += amount
	return sum


func free_space() -> int:
	return 1 << 30 if capacity <= 0 else maxi(0, capacity - total())


## Adds up to `amount`, limited by free space. Returns the amount actually added.
func add(item_id: StringName, amount: int) -> int:
	var added := mini(amount, free_space())
	if added <= 0:
		return 0
	_items[item_id] = count(item_id) + added
	changed.emit(item_id, _items[item_id])
	return added


## All-or-nothing removal.
func remove(item_id: StringName, amount: int) -> bool:
	if amount <= 0:
		return amount == 0
	var have := count(item_id)
	if have < amount:
		return false
	if have == amount:
		_items.erase(item_id)
	else:
		_items[item_id] = have - amount
	changed.emit(item_id, count(item_id))
	return true


func has_all(stacks: Array[ItemStack], multiplier: int = 1) -> bool:
	for stack in stacks:
		if count(stack.item_id) < stack.count * multiplier:
			return false
	return true


## Copy of the contents: item id -> count.
func items() -> Dictionary:
	return _items.duplicate()


## Item ids in stable (sorted) order.
func item_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_items.keys())
	ids.sort()
	return ids


func to_dict() -> Dictionary:
	var stored := {}
	for id: StringName in _items:
		stored[String(id)] = _items[id]
	return {"capacity": capacity, "items": stored}


static func from_dict(data: Dictionary) -> Inventory:
	var inventory := Inventory.new()
	inventory.capacity = int(data.get("capacity", 0))
	var stored: Dictionary = data.get("items", {})
	for id: String in stored:
		inventory._items[StringName(id)] = int(stored[id])
	return inventory
