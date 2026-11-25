class_name SkinRaycast
extends RefCounted
## Ray hits against the posed skin of an animated model (the collision capsule is much wider than
## the model, so a bullet's physics hit point floats in front of it). Works without a renderer,
## unlike MeshInstance3D.bake_mesh_from_current_skeleton_pose().
##
## Each mesh's rest-pose triangles are cached once, grouped by the bone that dominates them, as
## TriangleMesh BVHs. A query moves the segment into the rest space of each bone near it and
## queries those, then fully skins just the triangle it hit to get the exact posed point.

## Bones further than this (m) from the segment aren't searched.
const BONE_REACH := 0.5
## Imported models are often in tiny units (scaled up by the armature); TriangleMesh's epsilon
## rejects such small triangles, so the cached BVHs are built this many times larger.
const BVH_SCALE := 100.0

static var _cache := {}


## Nearest point where [param from] -> [param to] crosses the skinned meshes under
## [param skeleton]: {position, normal (facing [param from]), mesh}, or {} on a miss.
static func intersect(skeleton: Skeleton3D, from: Vector3, to: Vector3) -> Dictionary:
	var best := {}
	var best_distance := INF
	for node in skeleton.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.skin == null or not mesh.mesh is ArrayMesh or not mesh.is_visible_in_tree():
			continue
		var hit := _intersect_mesh(skeleton, mesh, from, to)
		if hit.is_empty():
			continue
		var distance := (hit["position"] as Vector3).distance_squared_to(from)
		if distance < best_distance:
			best_distance = distance
			best = hit
	return best


static func _intersect_mesh(skeleton: Skeleton3D, mesh: MeshInstance3D, from: Vector3, to: Vector3) -> Dictionary:
	var data := _mesh_data(mesh.mesh)
	var by_bind: Dictionary = data["by_bind"]
	var bones := _bind_bones(skeleton, mesh.skin)
	var matrices := {}
	var best := {}
	var best_distance := INF
	for bind: int in by_bind:
		var bone: int = bones[bind]
		if bone < 0 or _bone_distance(skeleton, bone, from, to) > BONE_REACH:
			continue
		var skinning := _skinning(skeleton, mesh, bones, bind, matrices)
		var to_rest := skinning.affine_inverse()
		to_rest = Transform3D(Basis.from_scale(Vector3.ONE * BVH_SCALE)) * to_rest
		var group: Array = by_bind[bind]
		var hit := (group[0] as TriangleMesh).intersect_segment(to_rest * from, to_rest * to)
		if hit.is_empty():
			continue
		var position: Vector3 = skinning * ((hit["position"] as Vector3) / BVH_SCALE)
		var normal: Vector3 = skinning.basis.inverse().transposed() * (hit["normal"] as Vector3)
		var exact := _skin_triangle(skeleton, mesh, bones, data, (group[1] as PackedInt32Array)[hit["face_index"]], matrices)
		var on_triangle: Variant = Geometry3D.segment_intersects_triangle(from, to, exact[0], exact[1], exact[2])
		if on_triangle != null:
			position = on_triangle
			normal = (exact[1] - exact[0]).cross(exact[2] - exact[0])
		var distance := position.distance_squared_to(from)
		if distance >= best_distance:
			continue
		normal = normal.normalized()
		if normal.dot(to - from) > 0.0:
			normal = -normal
		best_distance = distance
		best = {position = position, normal = normal, mesh = mesh}
	return best


## Rest vertex -> world for one bind (Godot skins as mesh transform * bone pose * bind pose).
static func _skinning(skeleton: Skeleton3D, mesh: MeshInstance3D, bones: PackedInt32Array, bind: int, matrices: Dictionary) -> Transform3D:
	if not matrices.has(bind):
		matrices[bind] = mesh.global_transform * skeleton.get_bone_global_pose(bones[bind]) * mesh.skin.get_bind_pose(bind)
	return matrices[bind]


## The three posed world corners of a cached triangle, with full weight blending.
static func _skin_triangle(skeleton: Skeleton3D, mesh: MeshInstance3D, bones: PackedInt32Array, data: Dictionary, id: int, matrices: Dictionary) -> Array[Vector3]:
	var surface: Array = data["surfaces"][id >> 24]
	var first := id & 0xFFFFFF
	var indices: PackedInt32Array = surface[1]
	var vertices: PackedVector3Array = surface[0]
	var vertex_bones: PackedInt32Array = surface[2]
	var weights: PackedFloat32Array = surface[3]
	var per_vertex: int = surface[4]
	var corners: Array[Vector3] = []
	for corner in 3:
		var index := indices[first + corner]
		var rest := vertices[index]
		var posed := Vector3.ZERO
		var total := 0.0
		for k in per_vertex:
			var weight := weights[index * per_vertex + k]
			if weight <= 0.0:
				continue
			var bind := vertex_bones[index * per_vertex + k]
			if bind >= bones.size() or bones[bind] < 0:
				continue
			posed += _skinning(skeleton, mesh, bones, bind, matrices) * rest * weight
			total += weight
		corners.append(posed / total if total > 0.0 else mesh.global_transform * rest)
	return corners


static func _bone_distance(skeleton: Skeleton3D, bone: int, from: Vector3, to: Vector3) -> float:
	var start := skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
	var ends: Array[Vector3] = [start]
	for child in skeleton.get_bone_children(bone):
		ends.append(skeleton.global_transform * skeleton.get_bone_global_pose(child).origin)
	var nearest := INF
	for end in ends:
		var points := Geometry3D.get_closest_points_between_segments(start, end, from, to)
		nearest = minf(nearest, points[0].distance_to(points[1]))
	return nearest


static func _bind_bones(skeleton: Skeleton3D, skin: Skin) -> PackedInt32Array:
	var bones := PackedInt32Array()
	for bind in skin.get_bind_count():
		var bone := skin.get_bind_bone(bind)
		if bone < 0:
			bone = skeleton.find_bone(skin.get_bind_name(bind))
		bones.append(bone)
	return bones


## Per mesh resource: its surfaces' arrays, and per dominant bind a rest-pose TriangleMesh plus the
## id (surface << 24 | first index) of each of its faces.
static func _mesh_data(source: Mesh) -> Dictionary:
	if _cache.has(source):
		return _cache[source]
	var surfaces: Array = []
	var faces := {}
	var ids := {}
	for s in source.get_surface_count():
		var arrays := source.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var vertex_bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if vertices.is_empty() or vertex_bones.is_empty():
			surfaces.append([])
			continue
		if indices.is_empty():
			indices = PackedInt32Array(range(vertices.size()))
		var per_vertex := vertex_bones.size() / vertices.size()
		surfaces.append([vertices, indices, vertex_bones, weights, per_vertex])
		var dominant := PackedInt32Array()
		dominant.resize(vertices.size())
		for v in vertices.size():
			var top := 0
			for k in range(1, per_vertex):
				if weights[v * per_vertex + k] > weights[v * per_vertex + top]:
					top = k
			dominant[v] = vertex_bones[v * per_vertex + top]
		for first in range(0, indices.size() - 2, 3):
			var bind := dominant[indices[first]]
			if not faces.has(bind):
				faces[bind] = PackedVector3Array()
				ids[bind] = PackedInt32Array()
			var list: PackedVector3Array = faces[bind]
			list.append(vertices[indices[first]] * BVH_SCALE)
			list.append(vertices[indices[first + 1]] * BVH_SCALE)
			list.append(vertices[indices[first + 2]] * BVH_SCALE)
			faces[bind] = list
			var id_list: PackedInt32Array = ids[bind]
			id_list.append((s << 24) | first)
			ids[bind] = id_list
	var by_bind := {}
	for bind: int in faces:
		var triangles := TriangleMesh.new()
		triangles.create_from_faces(faces[bind])
		by_bind[bind] = [triangles, ids[bind]]
	var data := {surfaces = surfaces, by_bind = by_bind}
	_cache[source] = data
	return data
