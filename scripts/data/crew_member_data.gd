class_name CrewMemberData
extends Resource
## A recruited gang member who can be assigned to jobs such as dealing or guarding a territory.

enum Assignment { IDLE, FOLLOW, DEALING, GUARDING }

@export var display_name := ""
@export_range(1, 10) var skill := 1
@export var assignment := Assignment.IDLE
@export var assigned_territory: StringName
