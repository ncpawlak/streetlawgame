class_name HitTools
extends Node
## Consumable gear the actor carries on a hit (dog treats, spray paint...). A child named "HitTools"
## on the actor ([method HitTools.of]), like [CarryBag].

signal changed

const NODE_NAME := &"HitTools"
const DOG_TREAT := &"dog_treat"
const SPRAY_PAINT := &"spray_paint"
const NAMES := {DOG_TREAT: "Dog treat", SPRAY_PAINT: "Spray paint"}

var counts: Dictionary = {}


static func of(actor: Node, create := true) -> HitTools:
	if actor == null:
		return null
	var tools := actor.get_node_or_null(NodePath(NODE_NAME)) as HitTools
	if tools == null and create:
		tools = HitTools.new()
		tools.name = NODE_NAME
		actor.add_child(tools)
	return tools


func count(tool: StringName) -> int:
	return int(counts.get(tool, 0))


func has(tool: StringName) -> bool:
	return count(tool) > 0


func give(tool: StringName, amount := 1) -> void:
	counts[tool] = count(tool) + amount
	changed.emit()


## Uses one. Returns false (and says so) if there's none left.
func use(tool: StringName) -> bool:
	if not has(tool):
		EventBus.notify.emit("No %s left" % String(NAMES.get(tool, tool)).to_lower())
		return false
	counts[tool] = count(tool) - 1
	changed.emit()
	return true


func summary() -> String:
	var parts: PackedStringArray = []
	for tool: StringName in counts.keys():
		if count(tool) > 0:
			parts.append("%s x%d" % [NAMES.get(tool, String(tool)), count(tool)])
	return ", ".join(parts)
