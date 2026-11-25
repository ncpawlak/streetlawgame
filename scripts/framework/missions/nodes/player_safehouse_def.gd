class_name PlayerSafehouseDef
extends ContentDef
## A player safehouse (crib): where you save, heal, shake heat, respawn, store cars and change
## clothes. Data in data/player_safehouses/<id>.tres; the world piece is a [PlayerSafehouse] node.
## (Not the territory gang HQ - that's SafehouseData.)

const TYPE := &"player_safehouses"

## Street address, e.g. "1412 Tamarack Row".
@export var address := ""
@export var district_id: StringName
@export var starts_unlocked := false
## Restore the player's health when resting.
@export var heal := true
## Arriving at the door while nobody's watching (heat not "seen") clears the heat.
@export var clear_heat_when_unseen := true
## Heat removed on arrival while still seen (0 = none).
@export var heat_reduce := 0.0
@export var vehicle_slots := 2
## Leave a WardrobeSlot marker for the clothing system's Wardrobe interactable.
@export var has_wardrobe := true


func validate() -> PackedStringArray:
	var problems := super.validate()
	if vehicle_slots < 0:
		problems.append("%s: vehicle_slots can't be negative" % id)
	return problems
