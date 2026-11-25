@tool
class_name HouseDoor
extends CSGBox3D
## Exterior-only house door (visual only; houses can't be entered). Like [HouseWindow] the box is a
## subtracted recess under the house's CSGCombiner3D; the slab, panels, casing, knob and optional
## glass lite are internal child meshes. Origin is the opening centre on the wall face, +Z outward.

const TRIM := preload("res://assets/materials/houses/trim_white.tres")
const SLAB := preload("res://assets/materials/houses/door_red.tres")
const GLASS := preload("res://assets/materials/houses/glass.tres")
const BRASS := preload("res://assets/materials/houses/brass.tres")

## Opening size; the 1.2 x 2.4 m default clears the 1.8 m character by 0.6 m (docs/design/SCALE.md).
@export var opening := Vector2(1.2, 2.4):
	set(value):
		opening = value
		_rebuild()
@export var recess := 0.15:
	set(value):
		recess = value
		_rebuild()
## 0 = four raised panels, 1 = half glass, 2 = flush/modern with a vertical glass strip.
@export_enum("Panel", "Half glass", "Modern") var style := 0:
	set(value):
		style = value
		_rebuild()
@export var door_material: Material:
	set(value):
		door_material = value
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
	var slab: Material = door_material if door_material else SLAB
	var w := opening.x
	var h := opening.y
	var face := -recess + 0.06
	_box(Vector3(w - 0.04, h - 0.02, 0.06), Vector3(0, -0.01, -recess + 0.03), slab)
	var casing := 0.14
	_box(Vector3(w + casing * 2.0, casing, 0.05), Vector3(0, h * 0.5 + casing * 0.5, 0.025), trim)
	_box(Vector3(casing, h, 0.05), Vector3(w * 0.5 + casing * 0.5, 0, 0.025), trim)
	_box(Vector3(casing, h, 0.05), Vector3(-w * 0.5 - casing * 0.5, 0, 0.025), trim)
	_box(Vector3(w, 0.04, recess), Vector3(0, -h * 0.5 + 0.02, -recess * 0.5), trim)
	match style:
		0:
			for row in 2:
				for col in 2:
					var ph := h * (0.38 if row == 0 else 0.3)
					var py := -h * 0.2 if row == 0 else h * 0.25
					_box(Vector3(w * 0.32, ph, 0.03), Vector3((col - 0.5) * w * 0.44, py, face + 0.01), slab)
		1:
			_box(Vector3(w * 0.7, h * 0.38, 0.03), Vector3(0, h * 0.22, face + 0.005), GLASS)
			_box(Vector3(w * 0.7, h * 0.3, 0.03), Vector3(0, -h * 0.22, face + 0.01), slab)
		2:
			_box(Vector3(0.16, h * 0.8, 0.03), Vector3(-w * 0.3, 0, face + 0.005), GLASS)
	_box(Vector3(0.07, 0.07, 0.08), Vector3(w * 0.36, -0.1, face + 0.04), BRASS)


func _box(box_size: Vector3, at: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	add_child(instance, false, Node.INTERNAL_MODE_BACK)
	_parts.append(instance)
