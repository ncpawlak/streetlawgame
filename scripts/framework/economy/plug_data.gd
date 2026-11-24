class_name PlugData
extends ContentDef
## A supplier. Revealed by conditions, met in the world (LocationDef with a MeetPlugEffect),
## established with a buy-in that grants unlocks (e.g. &"drug:weed"), then sells supplies at a
## price that follows the relationship.

## Unique LocationDef id where you meet them.
@export var location_id: StringName
@export var reveal_conditions: Array[Condition] = []
## When true the deal can only be struck in person (via MeetPlugEffect).
@export var requires_meeting := true
@export var buy_in_price := 0
@export var grants_unlocks: Array[StringName] = []
## What they sell; count is the order size offered in the UI.
@export var supplies: Array[ItemStack] = []
## Multiplier on ItemData.base_value for supply prices.
@export var price_multiplier := 1.0
@export_range(0.0, 100.0) var starting_relationship := 50.0
## Price multiplier at relationship 0 and 100.
@export var price_at_min_relationship := 1.5
@export var price_at_max_relationship := 0.75
## Below this relationship the plug refuses to sell.
@export var cutoff_relationship := 10.0
@export var relationship_per_order := 1.0
@export var visual: VisualSpec


func validate() -> PackedStringArray:
	var issues := super.validate()
	if grants_unlocks.is_empty() and supplies.is_empty():
		issues.append("%s: plug grants nothing and sells nothing" % id)
	return issues
