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
const METAL := preload("res://assets/materials/houses/metal_dark.tres")
const STORM := preload("res://assets/materials/houses/storm_panel.tres")

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
## Florida jalousie window: rows of tilted glass louvres instead of a sash.
@export var jalousie := false:
	set(value):
		jalousie = value
		_rebuild()
## Hurricane protection: 0 none, 1 accordion (stacked at both jambs), 2 storm panel (bolted
## over the opening), 3 bahama (top-hinged awning shutter propped open).
@export_enum("None", "Accordion", "Panel", "Bahama") var storm := 0:
	set(value):
		storm = value
		_rebuild()
## Security bars bolted over the opening (poorer areas).
@export var bars := false:
	set(value):
		bars = value
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
	if muntins and not jalousie:
		_box(Vector3(0.04, h, 0.03), Vector3(0, 0, -recess + 0.05), trim)
		_box(Vector3(w, 0.04, 0.03), Vector3(0, 0, -recess + 0.05), trim)
	if jalousie:
		var slat := 0.11
		var rows := maxi(int(h / slat), 1)
		for i in rows:
			var slat_box := _box(Vector3(w - frame * 2.0, 0.015, 0.12),
					Vector3(0, -h * 0.5 + (i + 0.5) * h / rows, -recess + 0.09), GLASS)
			slat_box.rotation.x = deg_to_rad(-28.0)
		_box(Vector3(0.03, h, 0.03), Vector3(w * 0.5 - frame - 0.02, 0, -recess + 0.06), METAL)
		_box(Vector3(0.03, h, 0.03), Vector3(-w * 0.5 + frame + 0.02, 0, -recess + 0.06), METAL)
	if bars:
		var n := maxi(int(w / 0.13), 2)
		for i in range(1, n):
			_box(Vector3(0.025, h + 0.1, 0.025), Vector3(-w * 0.5 + i * w / n, 0, 0.06), METAL)
		for y in [-h * 0.5 + 0.08, 0.0, h * 0.5 - 0.08]:
			_box(Vector3(w + 0.1, 0.04, 0.02), Vector3(0, y, 0.06), METAL)
	match storm:
		1:
			var leaf := 0.09
			for side in [-1.0, 1.0]:
				_box(Vector3(w * 0.5, 0.05, 0.06), Vector3(side * w * 0.25, h * 0.5 + 0.12, 0.05), STORM)
				for i in 3:
					var fold := _box(Vector3(leaf, h + 0.15, 0.03),
							Vector3(side * (w * 0.5 + casing + 0.06 + i * 0.07), 0, 0.06 + (i % 2) * 0.02), STORM)
					fold.rotation.y = side * deg_to_rad(35.0 if i % 2 else -35.0)
		2:
			_box(Vector3(w + 0.3, h + 0.3, 0.02), Vector3(0, 0, 0.07), STORM)
			for i in range(1, int((w + 0.3) / 0.15)):
				_box(Vector3(0.03, h + 0.3, 0.025), Vector3(-w * 0.5 - 0.15 + i * 0.15, 0, 0.085), STORM)
		3:
			var mat: Material = shutter_material if shutter_material else SHUTTER
			var panel := _box(Vector3(w + 0.2, h + 0.1, 0.05), Vector3.ZERO, mat)
			panel.rotation.x = deg_to_rad(-35.0)
			panel.position = Vector3(0, h * 0.5 + 0.06 - cos(deg_to_rad(35.0)) * (h + 0.1) * 0.5,
					0.06 + sin(deg_to_rad(35.0)) * (h + 0.1) * 0.5)
			for side in [-1.0, 1.0]:
				var arm := _box(Vector3(0.025, 0.025, (h + 0.1) * 0.62), Vector3.ZERO, METAL)
				arm.rotation.x = deg_to_rad(-55.0)
				arm.position = Vector3(side * (w * 0.5 - 0.05), -h * 0.15,
						0.06 + sin(deg_to_rad(35.0)) * (h + 0.1) * 0.5 * 0.85)
	if shutters:
		var mat: Material = shutter_material if shutter_material else SHUTTER
		var sw := clampf(w * 0.45, 0.35, 0.6)
		for side in [-1.0, 1.0]:
			_box(Vector3(sw, h + 0.05, 0.04), Vector3(side * (w * 0.5 + casing + 0.03 + sw * 0.5), 0, 0.03), mat)


func _box(box_size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	add_child(instance, false, Node.INTERNAL_MODE_BACK)
	_parts.append(instance)
	return instance
