@tool
class_name KitPlacement
extends Node3D
## Places one building-kit scene (CSG source or baked) with a seeded [KitVariant]: palette swaps
## and optional mirroring, so repeated placements of the same design don't look cloned. The
## building is an internal child rebuilt whenever an export changes; edit the source scene to
## change the design itself. Seed 0 shows the original.

@export_file("*.tscn", "*.scn") var building := "":
	set(value):
		building = value
		_rebuild()
@export var variant_seed := 0:
	set(value):
		variant_seed = value
		_rebuild()
@export var allow_mirror := true:
	set(value):
		allow_mirror = value
		_rebuild()
@export var show_label := false:
	set(value):
		show_label = value
		_rebuild()

var instance: Node3D
var mirrored := false


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if instance:
		remove_child(instance)
		instance.queue_free()
		instance = null
	if building.is_empty() or not ResourceLoader.exists(building):
		return
	instance = (load(building) as PackedScene).instantiate() as Node3D
	add_child(instance, false, Node.INTERNAL_MODE_BACK)
	mirrored = KitVariant.apply(instance, variant_seed, allow_mirror)
	if "label_note" in instance:
		instance.label_note = "variant seed %d%s" % [variant_seed, " (mirrored)" if mirrored else ""]
		instance.show_label = show_label
