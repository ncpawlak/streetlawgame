class_name DistrictData
extends ContentDef
## A capturable district (data/districts/<id>.tres). Every district belongs to an area and has a safehouse.
## [member ContentDef.tags] (&"industrial", &"wealthy"...) are free-form hints for other systems (demand, spawning).

@export var area_id: StringName
@export var starting_owner: StringName = &"none"
@export var income_per_cycle := 200
@export var capture_respect := 100
## Capture rule id (data/capture_rules). Empty uses [constant Turf.DEFAULT_CAPTURE_RULE].
@export var capture_rule_id: StringName
## Safehouse id (data/safehouses). Empty uses [constant Turf.DEFAULT_SAFEHOUSE].
@export var safehouse_id: StringName
@export var defenders: DefenderConfig

@export_group("Generator layout")
## Cell in the generator's district grid. Hand-built maps ignore the layout hints.
@export var grid_origin := Vector2i.ZERO
## Size in district-grid cells.
@export var grid_size := Vector2i.ONE
## Block (relative to the district) that holds the safehouse. Negative picks one from the city seed.
@export var safehouse_block := Vector2i(-1, -1)


func validate() -> PackedStringArray:
	var issues := PackedStringArray()
	if area_id == &"":
		issues.append("district has no area_id")
	if grid_size.x < 1 or grid_size.y < 1:
		issues.append("grid_size must be at least 1x1")
	return issues
