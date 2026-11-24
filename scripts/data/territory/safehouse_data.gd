class_name SafehouseData
extends Resource
## A safehouse type (data/safehouses/<id>.tres): visual, footprint and claim tuning.
##
## Scene contract for [member scene_path] (every part optional):
## - [code]Door[/code] (Marker3D): interaction point.
## - [code]GuardPoints/*[/code] (Marker3D): guard spawn points.
## - Nodes in group [code]owner_tinted[/code] (GeometryInstance3D): tinted with the owner gang's color.

@export var id: StringName
@export var display_name := "Safehouse"
## Optional visual scene. Empty or missing builds the greybox.
@export_file("*.tscn", "*.scn") var scene_path := ""
## Greybox size on the XZ plane, in meters.
@export var footprint := Vector2(16.0, 16.0)
@export var height := 8.0
@export var greybox_color := Color(0.42, 0.36, 0.3)
## Seconds the claimant must hold the door.
@export var claim_time := 6.0
## How far from the door the claimant may stray while claiming.
@export var claim_radius := 6.0
## Features unlocked when owned (&"gang_management", &"upgrades", &"respawn", &"save"). Safehouse management reads these.
@export var features: Array[StringName] = []
