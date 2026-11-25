class_name KitBatcher
extends RefCounted
## Draw-call batching and distance tiers (HLOD) for the North End building kit and the greybox city.
##
## [NorthEndPopulator] harvests every placed kit building into this batcher; [method build] then
## emits, per [constant CELL] m cell:
## - "Shell": the building bodies (House / Building parts) merged into one mesh with one surface per
##   shared "uber" material. Kit materials that only differ in albedo colour collapse into one
##   material, the colour moving to vertex colours. Visible to [constant SHELL_RANGE].
## - "Detail": lots, fences, landscaping, trim. Visible to [constant DETAIL_RANGE].
## - Dressing props as one MultiMesh per (mesh, material); small props to [constant PROP_RANGE]
##   without shadows, trees and palms to [constant DETAIL_RANGE].
## - "Collision": one StaticBody3D, the buildings' concave faces merged into one shape plus the
##   props' primitive shapes.
## Per [constant FAR_CELL] m cell, beyond [constant FAR_BEGIN]: one vertex-coloured box impostor
## mesh and one merged [ArrayOccluder3D] of the big buildings for occlusion culling.
## [method merge_static] does the same for the greybox primitives (roads, pads, deck, props).

const CELL := 100.0
const FAR_CELL := 200.0
const DETAIL_RANGE := 260.0
const SHELL_RANGE := 900.0
## Impostors start before the shells end so cell-centre distances can never leave a gap.
const FAR_BEGIN := 680.0
const PROP_RANGE := 160.0
const LABEL_RANGE := 120.0
const LIGHT_RANGE := 90.0
const MARGIN := 15.0
const SHELL_PARTS := [&"House", &"Building"]
const TALL_PROP := 5.0
const OCCLUDER_AREA := 120.0
const STATIC_CELL := 200.0
const SMALL_STATIC := 4.0
const SMALL_STATIC_RANGE := 220.0

static var _uber := {}
static var _colored := {}
static var _impostor_material: StandardMaterial3D

var _cells := {}
var _far := {}
var building_count := 0


## Adds one kit building (not in the tree), placed at [param xform].
func add_building(building: Node3D, xform: Transform3D, info: Dictionary, _scene_id := "") -> void:
	building_count += 1
	var data := _cell(Vector2i(floori(xform.origin.x / CELL), floori(xform.origin.z / CELL)))
	var shell_color := {"sum": Color(0, 0, 0, 0), "weight": 0.0}
	for part in building.get_children(true):
		if not part is Node3D:
			continue
		var xf: Transform3D = xform * (part as Node3D).transform
		if part.name == KitDressing.NODE_NAME:
			_harvest_dressing(part, xf, data)
		else:
			_walk(part, xf, &"shell" if SHELL_PARTS.has(part.name) else &"detail", data, shell_color)
	var color: Color = shell_color["sum"] / maxf(shell_color["weight"], 1.0) if shell_color["weight"] > 0.0 else Color(0.7, 0.68, 0.62)
	var solid: Rect2 = info["solid"]
	var height: float = info["height"]
	var far := _far_cell(Vector2i(floori(xform.origin.x / FAR_CELL), floori(xform.origin.z / FAR_CELL)))
	(far["boxes"] as Array).append([xform, solid.grow(-0.3), height * 0.75, color])
	if solid.get_area() >= OCCLUDER_AREA and height >= 5.0:
		(far["occluders"] as Array).append([xform, solid.grow(-0.4), height * 0.8])


## Distance limits for the nodes a shop keeps live (sign, counter, light).
func tune_live(shop: Node3D) -> void:
	for node in shop.find_children("*", "", true, false):
		if node is Label3D:
			(node as Label3D).visibility_range_end = LABEL_RANGE
		elif node is Light3D:
			var light := node as Light3D
			light.shadow_enabled = false
			light.distance_fade_enabled = true
			light.distance_fade_begin = LIGHT_RANGE
			light.distance_fade_length = 20.0


## Emits the batched nodes under [param holder].
func build(holder: Node3D) -> void:
	for key: Vector2i in _cells:
		var data: Dictionary = _cells[key]
		var origin := Vector3((key.x + 0.5) * CELL, 0.0, (key.y + 0.5) * CELL)
		var cell := Node3D.new()
		cell.name = "Cell_%d_%d" % [key.x, key.y]
		cell.position = origin
		holder.add_child(cell)
		_emit_groups(cell, "Shell", data[&"shell"], SHELL_RANGE, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
		_emit_groups(cell, "Detail", data[&"detail"], DETAIL_RANGE, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
		_emit_props(cell, data[&"props"], origin)
		_emit_collision(cell, data, origin)
	for key: Vector2i in _far:
		_emit_far(holder, key, _far[key])
	_colored.clear()
	MeshMerge.clear_cache()


## Merges the greybox primitives (BoxMesh etc.) under [param city] and its static bodies into one
## mesh per (material, layers, shadow) per [constant STATIC_CELL] m cell; small pieces (posts,
## crossbucks) get [constant SMALL_STATIC_RANGE]. Collision shapes stay where they are.
static func merge_static(city: Node3D, skip: Array[Node] = []) -> int:
	var groups := {}
	var merged := 0
	var candidates: Array[MeshInstance3D] = []
	for child in city.get_children():
		if skip.has(child):
			continue
		if child is MeshInstance3D:
			candidates.append(child)
		elif child is StaticBody3D:
			for sub in child.get_children():
				if sub is MeshInstance3D:
					candidates.append(sub)
	for mi in candidates:
		if not mi.mesh is PrimitiveMesh or not mi.visible or mi.visibility_range_end > 0.0:
			continue
		var xf := mi.global_transform if mi.is_inside_tree() else _to(city, mi)
		var aabb := xf * mi.mesh.get_aabb()
		var small := aabb.size.x < SMALL_STATIC and aabb.size.z < SMALL_STATIC and aabb.size.y < 8.0
		var cell := Vector2i(floori(aabb.get_center().x / STATIC_CELL), floori(aabb.get_center().z / STATIC_CELL))
		var mat := mi.material_override if mi.material_override else mi.mesh.surface_get_material(0)
		var key := [cell, mat, mi.layers, mi.cast_shadow, small]
		if not groups.has(key):
			groups[key] = MeshMerge.new()
		var origin := Vector3((cell.x + 0.5) * STATIC_CELL, 0.0, (cell.y + 0.5) * STATIC_CELL)
		(groups[key] as MeshMerge).append(MeshMerge.arrays(mi.mesh, 0), Transform3D(Basis.IDENTITY, -origin) * xf)
		mi.get_parent().remove_child(mi)
		mi.queue_free()
		merged += 1
	var holder := Node3D.new()
	holder.name = "StaticBatches"
	city.add_child(holder)
	for key: Array in groups:
		var cell: Vector2i = key[0]
		var mesh := (groups[key] as MeshMerge).commit()
		var out := MeshInstance3D.new()
		out.mesh = mesh
		out.material_override = key[1]
		out.layers = key[2]
		out.cast_shadow = key[3]
		out.position = Vector3((cell.x + 0.5) * STATIC_CELL, 0.0, (cell.y + 0.5) * STATIC_CELL)
		if key[4]:
			out.visibility_range_end = SMALL_STATIC_RANGE
			out.visibility_range_end_margin = MARGIN
			out.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(out)
	MeshMerge.clear_cache()
	return merged


static func _to(ancestor: Node3D, node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != ancestor and n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


func _cell(key: Vector2i) -> Dictionary:
	if not _cells.has(key):
		_cells[key] = {&"shell": {}, &"detail": {}, &"props": {}, &"faces": [], &"shapes": []}
	return _cells[key]


func _far_cell(key: Vector2i) -> Dictionary:
	if not _far.has(key):
		_far[key] = {"boxes": [], "occluders": []}
	return _far[key]


func _walk(node: Node3D, xf: Transform3D, tier: StringName, data: Dictionary, shell_color: Dictionary) -> void:
	if not node.visible:
		return
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var color := _add_surface(data[tier], mi.mesh, s, mi.get_active_material(s), xf)
			if tier == &"shell":
				var weight := float(mi.mesh.surface_get_array_len(s))
				shell_color["sum"] += color * weight
				shell_color["weight"] += weight
	elif node is CollisionShape3D and (node as CollisionShape3D).shape != null and not (node as CollisionShape3D).disabled:
		var shape := (node as CollisionShape3D).shape
		if shape is ConcavePolygonShape3D:
			(data[&"faces"] as Array).append([xf, (shape as ConcavePolygonShape3D).get_faces()])
		else:
			(data[&"shapes"] as Array).append([shape, xf])
	for child in node.get_children(true):
		if child is Node3D:
			_walk(child, xf * (child as Node3D).transform, &"detail" if child.name == &"Details" else tier, data, shell_color)


func _harvest_dressing(dressing: Node3D, xf: Transform3D, data: Dictionary) -> void:
	for child in dressing.get_children():
		if child is MultiMeshInstance3D:
			var mmi := child as MultiMeshInstance3D
			var mm := mmi.multimesh
			if mm == null or mm.mesh == null:
				continue
			var key := [mm.mesh, mmi.material_override]
			if not data[&"props"].has(key):
				data[&"props"][key] = []
			var list: Array = data[&"props"][key]
			var base: Transform3D = xf * mmi.transform
			for i in mm.instance_count:
				list.append(base * mm.get_instance_transform(i))
		elif child is StaticBody3D:
			for cs in child.get_children():
				if cs is CollisionShape3D and (cs as CollisionShape3D).shape != null:
					(data[&"shapes"] as Array).append([(cs as CollisionShape3D).shape, xf * (child as Node3D).transform * (cs as Node3D).transform])


## Appends one surface to its uber-material group; returns the albedo colour moved into vertices.
func _add_surface(groups: Dictionary, mesh: Mesh, surface: int, material: Material, xf: Transform3D) -> Color:
	if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
		return Color.WHITE
	var uber := _uber_for(material)
	var color: Color = uber[1]
	var key: String = uber[0]
	if not groups.has(key):
		groups[key] = []
	(groups[key] as Array).append([_colored_arrays(mesh, surface, color, material), xf])
	return color


## [key, albedo colour] of the shared material a kit material folds into.
static func _uber_for(material: Material) -> Array:
	if not material is BaseMaterial3D:
		var id := "m%d" % (material.get_instance_id() if material else 0)
		if not _uber.has(id):
			_uber[id] = material
		return [id, Color.WHITE]
	var m := material as BaseMaterial3D
	var parts := [
		m.albedo_texture.get_instance_id() if m.albedo_texture else 0,
		m.normal_texture.get_instance_id() if m.normal_enabled and m.normal_texture else 0,
		m.roughness_texture.get_instance_id() if m.roughness_texture else 0,
		m.uv1_scale, m.uv1_offset, m.uv1_triplanar, m.uv1_world_triplanar, m.uv1_triplanar_sharpness,
		m.transparency, m.cull_mode, m.shading_mode, m.blend_mode, m.texture_filter,
		snappedf(m.roughness, 0.05), snappedf(m.metallic, 0.05), snappedf(m.metallic_specular, 0.1),
		m.emission_enabled, m.emission if m.emission_enabled else Color.BLACK, m.emission_energy_multiplier if m.emission_enabled else 0.0,
		m.alpha_scissor_threshold if m.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR else 0.0,
		m.no_depth_test, m.disable_receive_shadows, m.billboard_mode,
	]
	var key := str(parts)
	if not _uber.has(key):
		var shared := m.duplicate() as BaseMaterial3D
		shared.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
		shared.vertex_color_use_as_albedo = true
		shared.vertex_color_is_srgb = true
		shared.resource_local_to_scene = false
		_uber[key] = shared
	var color := m.albedo_color
	return [key, color]


## Arrays of [param mesh]'s surface with the albedo [param color] in its vertex colours.
static func _colored_arrays(mesh: Mesh, surface: int, color: Color, material: Material) -> Array:
	var key := "%d:%d:%s" % [mesh.get_instance_id(), surface, color.to_html()]
	if _colored.has(key):
		return _colored[key]
	var arrays := MeshMerge.arrays(mesh, surface).duplicate()
	var count := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var colors := PackedColorArray()
	var existing: Variant = arrays[Mesh.ARRAY_COLOR]
	var use_existing := material is BaseMaterial3D and (material as BaseMaterial3D).vertex_color_use_as_albedo and existing is PackedColorArray and (existing as PackedColorArray).size() == count
	if use_existing:
		colors = (existing as PackedColorArray).duplicate()
		for i in count:
			colors[i] = colors[i] * color
	else:
		colors.resize(count)
		colors.fill(color)
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_BONES] = null
	arrays[Mesh.ARRAY_WEIGHTS] = null
	arrays[Mesh.ARRAY_TEX_UV2] = null
	for c in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
		arrays[c] = null
	_colored[key] = arrays
	return arrays


func _emit_groups(cell: Node3D, label: String, groups: Dictionary, range_end: float, shadow: GeometryInstance3D.ShadowCastingSetting) -> void:
	if groups.is_empty():
		return
	var to_local := Transform3D(Basis.IDENTITY, -cell.position)
	var mesh := ArrayMesh.new()
	var keys := groups.keys()
	keys.sort()
	for key: String in keys:
		var merge := MeshMerge.new()
		for item: Array in groups[key]:
			merge.append(item[0], to_local * (item[1] as Transform3D))
		merge.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _uber[key])
	var mi := MeshInstance3D.new()
	mi.name = label
	mi.mesh = mesh
	mi.cast_shadow = shadow
	mi.visibility_range_end = range_end
	mi.visibility_range_end_margin = MARGIN
	cell.add_child(mi)


func _emit_props(cell: Node3D, props: Dictionary, origin: Vector3) -> void:
	var to_local := Transform3D(Basis.IDENTITY, -origin)
	for key: Array in props:
		var xfs: Array = props[key]
		var mesh: Mesh = key[0]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xfs.size()
		var tall := false
		for i in xfs.size():
			var xf: Transform3D = to_local * (xfs[i] as Transform3D)
			mm.set_instance_transform(i, xf)
			tall = tall or (xf * mesh.get_aabb()).size.y >= TALL_PROP
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Props"
		mmi.multimesh = mm
		mmi.material_override = key[1]
		mmi.visibility_range_end = DETAIL_RANGE if tall else PROP_RANGE
		mmi.visibility_range_end_margin = MARGIN
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if tall else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cell.add_child(mmi)


func _emit_collision(cell: Node3D, data: Dictionary, origin: Vector3) -> void:
	var faces_list: Array = data[&"faces"]
	var shapes: Array = data[&"shapes"]
	if faces_list.is_empty() and shapes.is_empty():
		return
	var to_local := Transform3D(Basis.IDENTITY, -origin)
	var body := StaticBody3D.new()
	body.name = "Collision"
	cell.add_child(body)
	if not faces_list.is_empty():
		var faces := PackedVector3Array()
		for item: Array in faces_list:
			var xf: Transform3D = to_local * (item[0] as Transform3D)
			faces.append_array(xf * (item[1] as PackedVector3Array))
		var concave := ConcavePolygonShape3D.new()
		concave.set_faces(faces)
		var cs := CollisionShape3D.new()
		cs.shape = concave
		body.add_child(cs)
	for item: Array in shapes:
		var cs := CollisionShape3D.new()
		cs.shape = item[0]
		cs.transform = to_local * (item[1] as Transform3D)
		body.add_child(cs)


func _emit_far(holder: Node3D, key: Vector2i, far: Dictionary) -> void:
	var origin := Vector3((key.x + 0.5) * FAR_CELL, 0.0, (key.y + 0.5) * FAR_CELL)
	var to_local := Transform3D(Basis.IDENTITY, -origin)
	if _impostor_material == null:
		_impostor_material = StandardMaterial3D.new()
		_impostor_material.vertex_color_use_as_albedo = true
		_impostor_material.vertex_color_is_srgb = true
		_impostor_material.roughness = 0.9
		_impostor_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for box: Array in far["boxes"]:
		_box(st, to_local * (box[0] as Transform3D), box[1], box[2], box[3])
	var mi := MeshInstance3D.new()
	mi.name = "Impostors_%d_%d" % [key.x, key.y]
	mi.mesh = st.commit()
	mi.material_override = _impostor_material
	mi.position = origin
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_begin = FAR_BEGIN
	mi.visibility_range_begin_margin = MARGIN
	holder.add_child(mi)
	if far["occluders"].is_empty():
		return
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	for box: Array in far["occluders"]:
		_occluder_box(verts, indices, to_local * (box[0] as Transform3D), box[1], box[2])
	var occluder := ArrayOccluder3D.new()
	occluder.set_arrays(verts, indices)
	var oi := OccluderInstance3D.new()
	oi.name = "Occluders_%d_%d" % [key.x, key.y]
	oi.occluder = occluder
	oi.position = origin
	holder.add_child(oi)


## Corners of a kit lot-space rect at heights 0 and [param h], through [param xf].
static func _corners(xf: Transform3D, r: Rect2, h: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for y: float in [0.0, h]:
		for p: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			out.append(xf * Vector3(p.x, y, p.y))
	return out


static func _box(st: SurfaceTool, xf: Transform3D, r: Rect2, h: float, color: Color) -> void:
	var c := _corners(xf, r, h)
	var center := (c[0] + c[6]) * 0.5
	st.set_color(color)
	# Four walls and the roof; the impostor material is double-sided so winding does not matter.
	for quad: Array in [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7], [4, 5, 6, 7]]:
		var a: Vector3 = c[quad[0]]
		var b: Vector3 = c[quad[1]]
		var d: Vector3 = c[quad[2]]
		var e: Vector3 = c[quad[3]]
		var outward := Vector3.UP if quad[0] == 4 else ((a + d) * 0.5 - center) * Vector3(1, 0, 1)
		st.set_normal(outward.normalized())
		for v: Vector3 in [a, b, d, a, d, e]:
			st.add_vertex(v)

static func _occluder_box(verts: PackedVector3Array, indices: PackedInt32Array, xf: Transform3D, r: Rect2, h: float) -> void:
	var base := verts.size()
	for v in _corners(xf, r, h):
		verts.append(v)
	for tri: Array in [[0, 1, 2], [0, 2, 3], [4, 6, 5], [4, 7, 6], [0, 4, 5], [0, 5, 1], [1, 5, 6], [1, 6, 2], [2, 6, 7], [2, 7, 3], [3, 7, 4], [3, 4, 0]]:
		for i: int in tri:
			indices.append(base + i)
