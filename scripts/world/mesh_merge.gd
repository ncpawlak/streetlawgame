class_name MeshMerge
extends RefCounted
## CPU-side triangle-mesh merger used by [KitBatcher]. Under a real renderer,
## [method Mesh.surface_get_arrays] (and [method SurfaceTool.append_from], which calls it) reads
## the vertex buffers back from the GPU on every call, which made the North End merges take ~20 s
## at boot. [method arrays] reads each source surface once and caches it; [method append]
## concatenates with packed-array transforms, so merging never touches the GPU.

## Mesh -> {surface: arrays}. Holds the meshes alive; [method clear_cache] after a build pass.
static var _cache := {}
## Subdivisions (Vector3i) -> arrays of a 1 m [BoxMesh].
static var _unit_boxes := {}

var _verts := PackedVector3Array()
var _normals := PackedVector3Array()
var _tangents := PackedFloat32Array()
var _colors := PackedColorArray()
var _uvs := PackedVector2Array()
var _indices := PackedInt32Array()
var _has_tangents := false
var _has_colors := false
var _has_uvs := false


## Surface arrays of [param mesh], read once. [method PrimitiveMesh.get_mesh_arrays] is a GPU
## read-back too, so boxes (the greybox bulk) scale one cached unit box per subdivision instead.
static func arrays(mesh: Mesh, surface: int) -> Array:
	if mesh is BoxMesh and not (mesh as BoxMesh).add_uv2:
		var box := mesh as BoxMesh
		var key := Vector3i(box.subdivide_width, box.subdivide_height, box.subdivide_depth)
		if not _unit_boxes.has(key):
			var unit := BoxMesh.new()
			unit.subdivide_width = key.x
			unit.subdivide_height = key.y
			unit.subdivide_depth = key.z
			_unit_boxes[key] = unit.get_mesh_arrays()
		var out: Array = (_unit_boxes[key] as Array).duplicate()
		out[Mesh.ARRAY_VERTEX] = Transform3D(Basis.from_scale(box.size), Vector3.ZERO) * (out[Mesh.ARRAY_VERTEX] as PackedVector3Array)
		return out
	if mesh is PrimitiveMesh:
		if not _cache.has(mesh):
			_cache[mesh] = {0: (mesh as PrimitiveMesh).get_mesh_arrays()}
		return _cache[mesh][0]
	if not _cache.has(mesh):
		_cache[mesh] = {}
	var surfaces: Dictionary = _cache[mesh]
	if not surfaces.has(surface):
		surfaces[surface] = mesh.surface_get_arrays(surface)
	return surfaces[surface]


## Seeds the cache with arrays a caller just built [param mesh] from, so it is never read back.
static func remember(mesh: Mesh, surface: int, data: Array) -> void:
	if not _cache.has(mesh):
		_cache[mesh] = {}
	_cache[mesh][surface] = data


static func clear_cache() -> void:
	_cache.clear()


func is_empty() -> bool:
	return _verts.is_empty()


## Appends a PRIMITIVE_TRIANGLES surface [param src] (indexed or not) transformed by [param xf].
func append(src: Array, xf: Transform3D) -> void:
	var verts: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var count := verts.size()
	if count == 0:
		return
	var base := _verts.size()
	_verts.append_array(xf * verts)
	var normals: Variant = src[Mesh.ARRAY_NORMAL]
	if normals is PackedVector3Array and (normals as PackedVector3Array).size() == count:
		# Octahedral normal encoding normalises on upload, so scaled normals need no renormalising.
		_normals.append_array(Transform3D(xf.basis.inverse().transposed(), Vector3.ZERO) * (normals as PackedVector3Array))
	else:
		_normals.append_array(_filled_v3(count, Vector3.UP))
	_append_tangents(src[Mesh.ARRAY_TANGENT], count, base, xf.basis)
	var colors: Variant = src[Mesh.ARRAY_COLOR]
	var has_colors := colors is PackedColorArray and (colors as PackedColorArray).size() == count
	if has_colors and not _has_colors:
		_has_colors = true
		_colors = _filled_color(base, Color.WHITE)
	if _has_colors:
		_colors.append_array(colors if has_colors else _filled_color(count, Color.WHITE))
	var uvs: Variant = src[Mesh.ARRAY_TEX_UV]
	var has_uvs := uvs is PackedVector2Array and (uvs as PackedVector2Array).size() == count
	if has_uvs and not _has_uvs:
		_has_uvs = true
		_uvs.resize(base)
	if _has_uvs:
		if has_uvs:
			_uvs.append_array(uvs)
		else:
			_uvs.resize(_uvs.size() + count)
	var start := _indices.size()
	var src_indices: Variant = src[Mesh.ARRAY_INDEX]
	if src_indices is PackedInt32Array and not (src_indices as PackedInt32Array).is_empty():
		var idx: PackedInt32Array = src_indices
		_indices.resize(start + idx.size())
		for i in idx.size():
			_indices[start + i] = idx[i] + base
	else:
		_indices.resize(start + count)
		for i in count:
			_indices[start + i] = base + i
	if xf.basis.determinant() < 0.0:
		for i in range(start, _indices.size() - 2, 3):
			var swap := _indices[i + 1]
			_indices[i + 1] = _indices[i + 2]
			_indices[i + 2] = swap


## Adds the merged triangles as one surface of [param mesh] (a new [ArrayMesh] when null).
func commit(mesh: ArrayMesh = null) -> ArrayMesh:
	if mesh == null:
		mesh = ArrayMesh.new()
	if is_empty():
		return mesh
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = _verts
	out[Mesh.ARRAY_NORMAL] = _normals
	out[Mesh.ARRAY_INDEX] = _indices
	if _has_tangents:
		out[Mesh.ARRAY_TANGENT] = _tangents
	if _has_colors:
		out[Mesh.ARRAY_COLOR] = _colors
	if _has_uvs:
		out[Mesh.ARRAY_TEX_UV] = _uvs
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return mesh


func _append_tangents(src: Variant, count: int, base: int, basis: Basis) -> void:
	var has := src is PackedFloat32Array and (src as PackedFloat32Array).size() == count * 4
	if has and not _has_tangents:
		_has_tangents = true
		_tangents = _default_tangents(base)
	if not _has_tangents:
		return
	if not has:
		_tangents.append_array(_default_tangents(count))
		return
	var t: PackedFloat32Array = src
	var flip := -1.0 if basis.determinant() < 0.0 else 1.0
	var start := _tangents.size()
	_tangents.resize(start + t.size())
	for i in range(0, t.size(), 4):
		var v := (basis * Vector3(t[i], t[i + 1], t[i + 2])).normalized()
		_tangents[start + i] = v.x
		_tangents[start + i + 1] = v.y
		_tangents[start + i + 2] = v.z
		_tangents[start + i + 3] = t[i + 3] * flip


static func _default_tangents(count: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(count * 4)
	for i in count:
		out[i * 4] = 1.0
		out[i * 4 + 3] = 1.0
	return out


static func _filled_v3(count: int, value: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(count)
	out.fill(value)
	return out


static func _filled_color(count: int, value: Color) -> PackedColorArray:
	var out := PackedColorArray()
	out.resize(count)
	out.fill(value)
	return out
