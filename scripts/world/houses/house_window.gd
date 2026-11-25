@tool
class_name HouseWindow
extends CSGBox3D
## Exterior-only house window. The box itself is the recess: it is parented under a house's
## CSGCombiner3D with OPERATION_SUBTRACTION so it cuts [member recess] metres into the wall it sits
## on. Frame, casing, glass, sill, muntins and optional shutters are internal child meshes rebuilt
## whenever an export changes. The node origin is the opening centre on the wall face; local +Z
## points out of the wall.

const TRIM := preload("res://assets/materials/houses/trim_white.tres")
const GLASS := preload("res://assets/materials/houses/glass.tres")
const SHUTTER := preload("res://assets/materials/houses/shutter_dark.tres")

@export var opening := Vector2(1.1, 1.5):
	set(value):
		opening = value
		_rebuild()
@export var recess := 0.12:
	set(value):
		recess = value
		_rebuild()
@export var muntins := true:
	set(value):
		muntins = value
		_rebuild()
@export var shutters := false:
	set(value):
		shutters = value
		_rebuild()
@export var sill := true:
	set(value):
		sill = value
		_rebuild()
@export var frame_material: Material:
	set(value):
		frame_material = value
		_rebuild()
@export var shutter_material: Material:
	set(value):
		shutter_material = value
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
	var w := opening.x
	var h := opening.y
	var frame := 0.07
	_box(Vector3(w, h, 0.02), Vector3(0, 0, -recess + 0.03), GLASS)
	_box(Vector3(w, frame, recess), Vector3(0, h * 0.5 - frame * 0.5, -recess * 0.5), trim)
	_box(Vector3(w, frame, recess), Vector3(0, -h * 0.5 + frame * 0.5, -recess * 0.5), trim)
	_box(Vector3(frame, h, recess), Vector3(w * 0.5 - frame * 0.5, 0, -recess * 0.5), trim)
	_box(Vector3(frame, h, recess), Vector3(-w * 0.5 + frame * 0.5, 0, -recess * 0.5), trim)
	var casing := 0.1
	_box(Vector3(w + casing * 2.0, casing, 0.04), Vector3(0, h * 0.5 + casing * 0.5, 0.02), trim)
	_box(Vector3(casing, h, 0.04), Vector3(w * 0.5 + casing * 0.5, 0, 0.02), trim)
	_box(Vector3(casing, h, 0.04), Vector3(-w * 0.5 - casing * 0.5, 0, 0.02), trim)
	if sill:
		_box(Vector3(w + 0.3, 0.06, 0.2), Vector3(0, -h * 0.5 - 0.03, 0.04), trim)
	else:
		_box(Vector3(w + casing * 2.0, casing, 0.04), Vector3(0, -h * 0.5 - casing * 0.5, 0.02), trim)
	if muntins:
		_box(Vector3(0.04, h, 0.03), Vector3(0, 0, -recess + 0.05), trim)
		_box(Vector3(w, 0.04, 0.03), Vector3(0, 0, -recess + 0.05), trim)
	if shutters:
		var mat: Material = shutter_material if shutter_material else SHUTTER
		var sw := clampf(w * 0.45, 0.35, 0.6)
		for side in [-1.0, 1.0]:
			_box(Vector3(sw, h + 0.05, 0.04), Vector3(side * (w * 0.5 + casing + 0.03 + sw * 0.5), 0, 0.03), mat)


func _box(box_size: Vector3, at: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	add_child(instance, false, Node.INTERNAL_MODE_BACK)
	_parts.append(instance)
