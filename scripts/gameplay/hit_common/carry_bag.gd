class_name CarryBag
extends Node
## The bag the player fills on a hit. Goods take slots and are worth [code]value[/code] once cashed
## in at a [StashDropoff]. Loose cash goes in the bag too, takes no slots, and is paid out at the stash.
## Lives as a child named "CarryBag" on the actor; use [method CarryBag.of] to find or create it.

signal changed
signal item_added(item: Dictionary)
## A pickup that didn't fit ([param reason] is shown to the player).
signal rejected(item_name: String, reason: String)
## The bag was cashed in ([param total]) or dropped (total 0).
signal emptied(total: int)

const NODE_NAME := &"CarryBag"

## Goods slots. Small items take 1, a TV takes 2 or 3.
@export var capacity := 8

## Each item: {"name": String, "value": int, "slots": int}.
var items: Array[Dictionary] = []
var cash := 0


## The bag carried by [param actor], created on demand.
static func of(actor: Node, create := true) -> CarryBag:
	if actor == null:
		return null
	var bag := actor.get_node_or_null(NodePath(NODE_NAME)) as CarryBag
	if bag == null and create:
		bag = CarryBag.new()
		bag.name = NODE_NAME
		actor.add_child(bag)
	return bag


func used_slots() -> int:
	var used := 0
	for item in items:
		used += int(item["slots"])
	return used


func free_slots() -> int:
	return maxi(0, capacity - used_slots())


func can_fit(slots: int) -> bool:
	return slots <= free_slots()


func is_full() -> bool:
	return free_slots() <= 0


func is_empty() -> bool:
	return items.is_empty() and cash <= 0


func goods_value() -> int:
	var total := 0
	for item in items:
		total += int(item["value"])
	return total


## What the stash pays for everything in the bag.
func total_value() -> int:
	return goods_value() + cash


func add_item(item_name: String, value: int, slots := 1) -> bool:
	if not can_fit(slots):
		rejected.emit(item_name, "Bag full (%d/%d)" % [used_slots(), capacity])
		return false
	var item := {"name": item_name, "value": value, "slots": slots}
	items.append(item)
	item_added.emit(item)
	changed.emit()
	return true


func add_cash(amount: int) -> void:
	if amount <= 0:
		return
	cash += amount
	changed.emit()


## Clears the bag and returns what it was worth.
func empty() -> int:
	var total := total_value()
	items.clear()
	cash = 0
	emptied.emit(total)
	changed.emit()
	return total


## Loses everything (death or getting busted).
func drop() -> void:
	items.clear()
	cash = 0
	emptied.emit(0)
	changed.emit()


func summary() -> String:
	return "Bag %d/%d  -  $%d" % [used_slots(), capacity, total_value()]
