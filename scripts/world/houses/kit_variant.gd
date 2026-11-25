class_name KitVariant
extends RefCounted
## Seeded per-placement variation for the generated building kit, so one design placed many
## times doesn't look cloned. A seed picks a rotation inside each palette family in
## data/buildings/kit_palettes.json (siding, brick, roof, trim, door, awning, ...) and swaps every
## matching material on the building, and optionally mirrors the whole building across its lot's
## centre line (x -> -x). Works on the editable CSG scenes and on the baked scenes.
##
## Mirroring conjugates every local transform by M = diag(-1, 1, 1) and mirrors only leaf
## geometry (CSGPolygon3D points, ArrayMesh vertices, concave collision faces), so rotations stay
## proper and Label3D signs still read the right way round. Seed 0 is always the original design.

const PALETTES := "res://data/buildings/kit_palettes.json"
const MIRROR := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
const SUFFIXES: Array[String] = ["", "_x", "_z"]

static var _lists := {}
static var _dir := ""
static var _materials := {}
static var _mirrored_meshes := {}
static var _mirrored_shapes := {}


## Applies variant [param variant_seed] to the building root's subtree. Returns true when the
## building was mirrored.
static func apply(root: Node, variant_seed: int, allow_mirror := true) -> bool:
	if variant_seed == 0:
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = variant_seed
	var mirror := rng.randf() < 0.5 and allow_mirror
	var map := material_map(rng)
	for child in root.get_children(true):
		_apply_node(child, map, mirror)
	return mirror


## Material path -> replacement path for one seed. Uses [param rng] in a fixed family order.
static func material_map(rng: RandomNumberGenerator) -> Dictionary:
	_load()
	var map := {}
	var names := _lists.keys()
	names.sort()
	for family: String in names:
		var members: Array = _lists[family]
		var offset := rng.randi_range(0, members.size() - 1)
		if offset == 0:
			continue
		for i in members.size():
			var to: String = members[(i + offset) % members.size()]
			for suffix in SUFFIXES:
				var src: String = _dir + members[i] + suffix + ".tres"
				var dst: String = _dir + to + suffix + ".tres"
				if ResourceLoader.exists(src) and ResourceLoader.exists(dst):
					map[src] = dst
	return map


static func mirror_transform(t: Transform3D) -> Transform3D:
	return Transform3D(MIRROR * t.basis * MIRROR, Vector3(-t.origin.x, t.origin.y, t.origin.z))


static func _load() -> void:
	if not _lists.is_empty():
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PALETTES))
	_dir = data["material_dir"]
	_lists = data["families"]


static func _apply_node(node: Node, map: Dictionary, mirror: bool) -> void:
	if mirror and node is Node3D:
		node.transform = mirror_transform(node.transform)
		_mirror_geometry(node)
	if not map.is_empty():
		_swap(node, map)
	for child in node.get_children(true):
		_apply_node(child, map, mirror)


static func _mirror_geometry(node: Node) -> void:
	if node is CSGPolygon3D:
		var points: PackedVector2Array = node.polygon
		var out := PackedVector2Array()
		for i in range(points.size() - 1, -1, -1):
			out.append(Vector2(-points[i].x, points[i].y))
		node.polygon = out
	elif node is MeshInstance3D and node.mesh is ArrayMesh:
		node.mesh = _mirror_mesh(node.mesh)
	elif node is CollisionShape3D and node.shape is ConcavePolygonShape3D:
		node.shape = _mirror_shape(node.shape)
	elif node is CollisionShape3D and node.shape is ConvexPolygonShape3D:
		var convex := ConvexPolygonShape3D.new()
		var points: PackedVector3Array = node.shape.points
		for i in points.size():
			points[i].x = -points[i].x
		convex.points = points
		node.shape = convex


static func _mirror_mesh(mesh: ArrayMesh) -> ArrayMesh:
	if _mirrored_meshes.has(mesh):
		return _mirrored_meshes[mesh]
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in verts.size():
			verts[i].x = -verts[i].x
		arrays[Mesh.ARRAY_VERTEX] = verts
		if arrays[Mesh.ARRAY_NORMAL] != null:
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i in normals.size():
				normals[i].x = -normals[i].x
			arrays[Mesh.ARRAY_NORMAL] = normals
		if arrays[Mesh.ARRAY_TANGENT] != null:
			var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
			for i in range(0, tangents.size(), 4):
				tangents[i] = -tangents[i]
				tangents[i + 3] = -tangents[i + 3]
			arrays[Mesh.ARRAY_TANGENT] = tangents
		var indices := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			indices = arrays[Mesh.ARRAY_INDEX]
		else:
			indices.resize(verts.size())
			for i in verts.size():
				indices[i] = i
		for i in range(0, indices.size() - 2, 3):
			var swap := indices[i + 1]
			indices[i + 1] = indices[i + 2]
			indices[i + 2] = swap
		arrays[Mesh.ARRAY_INDEX] = indices
		out.add_surface_from_arrays(mesh.surface_get_primitive_type(s), arrays)
		out.surface_set_material(s, mesh.surface_get_material(s))
	_mirrored_meshes[mesh] = out
	return out


static func _mirror_shape(shape: ConcavePolygonShape3D) -> ConcavePolygonShape3D:
	if _mirrored_shapes.has(shape):
		return _mirrored_shapes[shape]
	var faces := shape.get_faces()
	for i in faces.size():
		faces[i].x = -faces[i].x
	for i in range(0, faces.size() - 2, 3):
		var swap := faces[i + 1]
		faces[i + 1] = faces[i + 2]
		faces[i + 2] = swap
	var out := ConcavePolygonShape3D.new()
	out.backface_collision = shape.backface_collision
	out.set_faces(faces)
	_mirrored_shapes[shape] = out
	return out


static func _swap(node: Node, map: Dictionary) -> void:
	if node is CSGShape3D and "material" in node:
		node.material = _swapped(node.material, map)
	if node is GeometryInstance3D:
		node.material_override = _swapped(node.material_override, map)
	if node is MeshInstance3D and node.mesh:
		for i in node.mesh.get_surface_count():
			var current: Material = node.get_surface_override_material(i)
			if current == null:
				current = node.mesh.surface_get_material(i)
			var swapped := _swapped(current, map)
			if swapped != current:
				node.set_surface_override_material(i, swapped)


static func _swapped(material: Material, map: Dictionary) -> Material:
	if material == null or not map.has(material.resource_path):
		return material
	var path: String = map[material.resource_path]
	if not _materials.has(path):
		_materials[path] = load(path)
	return _materials[path]
