class_name SafehouseData
extends ContentDef
## A safehouse type (data/safehouses/<id>.tres): visual, footprint and claim tuning.
##
## Scene contract for [member visual] (every part optional):
## - [code]Door[/code] (Marker3D): interaction point.
## - [code]GuardPoints/*[/code] (Marker3D): guard spawn points.
## - Nodes in group [code]owner_tinted[/code] (GeometryInstance3D): tinted with the owner gang's color.

## Optional visual (scene or mesh, swappable through ContentDB asset overrides). Null, or a spec with no
## scene/mesh, builds the code greybox from the fields below.
@export var visual: VisualSpec
## Greybox size on the XZ plane, in meters (also places the default door and guard points).
@export var footprint := Vector2(16.0, 16.0)
@export var height := 8.0
@export var greybox_color := Color(0.42, 0.36, 0.3)
## Seconds the claimant must hold the door.
@export var claim_time := 6.0
## How far from the door the claimant may stray while claiming.
@export var claim_radius := 6.0
## Features unlocked when owned (&"gang_management", &"upgrades", &"respawn", &"save"). Safehouse management reads these.
@export var features: Array[StringName] = []
