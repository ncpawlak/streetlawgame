class_name Occupant
extends Node3D
## A friendly person in a location (clerk, resident, informant...). Inside a streamed interior it has its
## own Interactable; for door-only locations it has no body and its actions are offered on the door.

var def: OccupantDef
var location: Location
var interactable: Interactable


static func create(occupant_def: OccupantDef, owner_location: Location, with_body: bool) -> Occupant:
	var occupant := Occupant.new()
	occupant.def = occupant_def
	occupant.location = owner_location
	occupant.name = "Occupant_%s" % occupant_def.role
	if with_body:
		occupant._build_body()
	return occupant


func label() -> String:
	return def.label()


func role() -> StringName:
	return def.role


## This occupant's actions: its own plus a Talk action when it has a dialogue.
func get_actions() -> Array[InteractionAction]:
	var result := def.all_actions()
	var talk := Location.talk_action_for(def)
	if talk != null:
		result.push_front(talk)
	return result


## The location's memory slot for this occupant (cooldowns are per person, not per door).
func memory() -> Dictionary:
	var key := "occupant:%s" % def.role
	if not location.state.memory.has(key):
		location.state.memory[key] = {}
	return location.state.memory[key]


func _build_body() -> void:
	var visual := def.visual.instantiate() if def.visual != null else VisualSpec.greybox(&"capsule", Vector3(0.8, 1.8, 0.8), def.color)
	if def.visual == null:
		visual.position.y = 0.9
	add_child(visual)
	interactable = Interactable.new()
	interactable.name = "Interactable"
	interactable.prompt_name = def.label()
	interactable.radius = 2.2
	interactable.focus_priority = 1
	interactable.target = self
	interactable.occupant = self
	interactable.location = location
	interactable.memory = memory()
	interactable.actions = get_actions()
	interactable.position.y = 1.0
	add_child(interactable)
