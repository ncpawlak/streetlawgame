@tool
class_name GarageDoor
extends CSGBox3D
## Sectional garage door (visual only). Subtracted recess under the house combiner, with panel
## sections, optional window row and casing as internal child meshes. Origin is the opening centre
## on the wall face, +Z outward. A car is 1.9 m wide: use >= 2.7 m for one bay, >= 5.0 m for two.

const TRIM := preload("res://assets/materials/houses/trim_white.tres")
const PANEL := preload("res://assets/materials/houses/garage_panel.tres")
const GLASS := preload("res://assets/materials/houses/glass.tres")

@export var opening := Vector2(2.7, 2.3):
	set(value):
		opening = value
		_rebuild()
@export var recess := 0.15:
	set(value):
		recess = value
		_rebuild()
@export var window_row := false:
	set(value):
		window_row = value
		_rebuild()
@export var panel_material: Material:
	set(value):
		panel_material = value
		_rebuild()
@export var frame_material: Material:
	set(value):
		frame_material = value
		_rebuild()

var _parts: Array[Node] = []


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	for part in _parts:
		part.queue_free()
	_parts.clear()
	operation = CSGShape3D.OPERATION_SUBTRACTION
	size = Vector3(opening.x, opening.y, recess * 2.0)
	var trim: Material = frame_material if frame_material else TRIM
	var panel: Material = panel_material if panel_material else PANEL
	var w := opening.x
	var h := opening.y
	var sections := 4
	var sh := h / sections
	for i in sections:
		var y := -h * 0.5 + sh * (i + 0.5)
		_box(Vector3(w - 0.02, sh - 0.04, 0.05), Vector3(0, y, -recess + 0.03), panel)
		if window_row and i == sections - 1:
			var lites := maxi(2, int(w / 0.9))
			for l in lites:
				var x := -w * 0.5 + w * (l + 0.5) / lites
				_box(Vector3(w / lites - 0.25, sh * 0.5, 0.03), Vector3(x, y, -recess + 0.06), GLASS)
	var casing := 0.16
	_box(Vector3(w + casing * 2.0, casing, 0.05), Vector3(0, h * 0.5 + casing * 0.5, 0.025), trim)
	_box(Vector3(casing, h, 0.05), Vector3(w * 0.5 + casing * 0.5, 0, 0.025), trim)
	_box(Vector3(casing, h, 0.05), Vector3(-w * 0.5 - casing * 0.5, 0, 0.025), trim)


func _box(box_size: Vector3, at: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	add_child(instance, false, Node.INTERNAL_MODE_BACK)
	_parts.append(instance)
