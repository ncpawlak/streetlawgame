class_name DistrictData
extends Resource
## A capturable district (data/districts/<id>.tres). Every district belongs to an area and has a safehouse.

@export var id: StringName
@export var display_name := ""
@export var area_id: StringName
@export var starting_owner: StringName = &"none"
@export var income_per_cycle := 200
@export var capture_respect := 100
## Capture rule id (data/capture_rules). Empty uses [constant Turf.DEFAULT_CAPTURE_RULE].
@export var capture_rule_id: StringName
## Safehouse id (data/safehouses). Empty uses [constant Turf.DEFAULT_SAFEHOUSE].
@export var safehouse_id: StringName
@export var defenders: DefenderConfig
## Free-form tags (&"industrial", &"stronghold"...) for other systems such as demand or spawning.
@export var tags: Array[StringName] = []

@export_group("Generator layout")
## Cell in the generator's district grid. Hand-built maps ignore the layout hints.
@export var grid_origin := Vector2i.ZERO
## Size in district-grid cells.
@export var grid_size := Vector2i.ONE
## Block (relative to the district) that holds the safehouse. Negative picks one from the city seed.
@export var safehouse_block := Vector2i(-1, -1)
