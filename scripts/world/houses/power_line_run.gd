@tool
class_name PowerLineRun
extends Node3D
## A run of wooden power poles (scenes/props/street/power_pole*.tscn) along [member points] with
## sagging lines strung between the pole anchors (the "anchors" metadata on the pole scene). Poles
## turn so their crossarm is across the run; wires are one thin-box ArrayMesh (no collision).

const WIRE_MATERIAL := "res://assets/materials/houses/wire.tres"

@export var points: PackedVector3Array = PackedVector3Array():
	set(value):
		points = value
		_rebuild()
@export_file("*.tscn") var pole_scene := "res://scenes/props/street/power_pole.tscn":
	set(value):
		pole_scene = value
		_rebuild()
## Pole indices that use the transformer pole instead.
@export var transformer_every := 4:
	set(value):
		transformer_every = value
		_rebuild()
## Mid-span sag in metres.
@export_range(0.0, 3.0, 0.05) var sag := 0.9:
	set(value):
		sag = value
		_rebuild()

var poles: Array[Node3D] = []


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	for child in get_children(true):
		if child.has_meta("power_line_part"):
			remove_child(child)
			child.free()
	poles.clear()
	if points.size() < 2 or not ResourceLoader.exists(pole_scene):
		return
	var plain := load(pole_scene) as PackedScene
	var alt_path := pole_scene.replace("power_pole.tscn", "power_pole_transformer.tscn")
	var transformer := load(alt_path) as PackedScene if ResourceLoader.exists(alt_path) else plain
	var anchor_sets: Array[PackedVector3Array] = []
	for i in points.size():
		var dir := (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)])
		dir.y = 0
		var scene := transformer if transformer_every > 0 and i % transformer_every == transformer_every - 1 else plain
		var pole := scene.instantiate() as Node3D
		pole.set_meta("power_line_part", true)
		# Crossarm (local X) across the run: local Z along the run.
		pole.transform = Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), points[i])
		add_child(pole, false, Node.INTERNAL_MODE_BACK)
		poles.append(pole)
		var anchors: PackedVector3Array = pole.get_meta("anchors", PackedVector3Array())
		var world := PackedVector3Array()
		for a in anchors:
			world.append(pole.transform * a)
		anchor_sets.append(world)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	for i in points.size() - 1:
		var a_set := anchor_sets[i]
		var b_set := anchor_sets[i + 1]
		for k in mini(a_set.size(), b_set.size()):
			_wire(verts, normals, a_set[k], b_set[k], sag * (0.7 if k == 3 else 1.0))
	if verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "Wires"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if ResourceLoader.exists(WIRE_MATERIAL):
		mi.material_override = load(WIRE_MATERIAL)
	mi.set_meta("power_line_part", true)
	add_child(mi, false, Node.INTERNAL_MODE_BACK)


## Lowest point of the wire between two anchors (for tests / clearance checks).
static func sag_point(a: Vector3, b: Vector3, amount: float, t := 0.5) -> Vector3:
	return a.lerp(b, t) - Vector3(0, amount * 4.0 * t * (1.0 - t), 0)


static func _wire(verts: PackedVector3Array, normals: PackedVector3Array, a: Vector3, b: Vector3,
		amount: float, segments := 10, thick := 0.025) -> void:
	for s in segments:
		var p0 := sag_point(a, b, amount, float(s) / segments)
		var p1 := sag_point(a, b, amount, float(s + 1) / segments)
		var along := (p1 - p0).normalized()
		var side := along.cross(Vector3.UP).normalized() * thick
		var up := side.cross(along).normalized() * thick
		for q: Array in [[side, up], [up, -side], [-side, -up], [-up, side]]:
			var o0: Vector3 = q[0]
			var o1: Vector3 = q[1]
			var n := (o0 + o1).normalized()
			for v in [p0 + o0, p1 + o0, p1 + o1, p0 + o0, p1 + o1, p0 + o1]:
				verts.append(v)
				normals.append(n)
