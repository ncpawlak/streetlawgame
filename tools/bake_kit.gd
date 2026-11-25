extends Node
## Bakes the building kit's editable CSG scenes into static meshes for the populated map:
##   godot --headless --path . res://tools/bake_kit.tscn [-- <res:// scene or dir> ...]
## Every top-level CSG tree (Lot, House/Building, Fences, trees, ...) becomes a Node3D of the
## same name holding a MeshInstance3D ("Mesh"), a merged "Details" mesh for the window/door/
## garage part trims (their internal meshes) and, when the CSG had collision, a StaticBody3D with
## a ConcavePolygonShape3D. Root scripts, markers, labels, areas and lights are kept. Output goes
## to scenes/baked/<same path>.scn. The CSG scenes stay the source of truth: re-run after edits.

const SOURCES: Array[String] = [
	"res://scenes/houses/one_floor", "res://scenes/houses/two_floor",
	"res://scenes/businesses/closed", "res://scenes/businesses/shops",
	"res://scenes/buildings/residential", "res://scenes/buildings/special",
	"res://scenes/buildings/locations", "res://scenes/buildings/purchasable",
]
const OUT_ROOT := "res://scenes/baked/"


static func baked_path(source: String) -> String:
	return OUT_ROOT + source.trim_prefix("res://scenes/").get_basename() + ".scn"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var files: Array[String] = []
	for src in (Array(args) if not args.is_empty() else SOURCES):
		if String(src).ends_with(".tscn"):
			files.append(src)
		else:
			for f in DirAccess.get_files_at(src):
				if f.ends_with(".tscn"):
					files.append(String(src).path_join(f))
	var failed := 0
	for path in files:
		var err := await bake_scene(path, baked_path(path))
		if err != OK:
			failed += 1
			printerr("bake failed: %s (%s)" % [path, error_string(err)])
	print("baked %d scenes, %d failed" % [files.size() - failed, failed])
	get_tree().quit(1 if failed else 0)


func bake_scene(source: String, target: String) -> Error:
	var root := (load(source) as PackedScene).instantiate() as Node3D
	add_child(root)
	for i in 2:
		await get_tree().process_frame
	var tops: Array[CSGShape3D] = []
	_find_top_csg(root, tops)
	for csg in tops:
		_bake(root, csg)
	remove_child(root)
	root.scene_file_path = ""
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		err = ResourceSaver.save(packed, target, ResourceSaver.FLAG_COMPRESS)
	root.free()
	return err


func _find_top_csg(node: Node, out: Array[CSGShape3D]) -> void:
	for child in node.get_children():
		if child is CSGShape3D:
			out.append(child)
		else:
			_find_top_csg(child, out)


func _bake(root: Node3D, csg: CSGShape3D) -> void:
	var parent := csg.get_parent()
	var index := csg.get_index()
	var holder := Node3D.new()
	holder.name = csg.name
	holder.transform = csg.transform
	holder.visible = csg.visible
	var to_local := csg.global_transform.affine_inverse()
	var mesh := csg.bake_static_mesh()
	if mesh and mesh.get_surface_count() > 0:
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = mesh
		mi.cast_shadow = csg.cast_shadow
		holder.add_child(mi)
	var details := _merge_part_meshes(csg, to_local)
	if details:
		var di := MeshInstance3D.new()
		di.name = "Details"
		di.mesh = details
		holder.add_child(di)
	if csg.use_collision:
		var shape := csg.bake_collision_shape()
		if shape and not shape.get_faces().is_empty():
			var body := StaticBody3D.new()
			body.name = "StaticBody3D"
			body.collision_layer = csg.collision_layer
			body.collision_mask = csg.collision_mask
			var cs := CollisionShape3D.new()
			cs.name = "CollisionShape3D"
			cs.shape = shape
			body.add_child(cs)
			holder.add_child(body)
	var keep: Array[Node] = []
	_find_non_csg(csg, keep)
	var keep_xf: Array[Transform3D] = []
	for n in keep:
		keep_xf.append(to_local * (n as Node3D).global_transform if n is Node3D else Transform3D())
	parent.remove_child(csg)
	parent.add_child(holder)
	parent.move_child(holder, index)
	for n in [holder] + _descendants(holder):
		n.owner = root
	for i in keep.size():
		var n := keep[i]
		n.get_parent().remove_child(n)
		holder.add_child(n)
		if n is Node3D:
			n.transform = keep_xf[i]
		n.owner = root
	csg.free()


## Non-CSG children hanging off the CSG tree (labels, markers, ...); computed while still in tree.
func _find_non_csg(node: Node, out: Array[Node]) -> void:
	for child in node.get_children():
		if child is CSGShape3D:
			_find_non_csg(child, out)
		else:
			out.append(child)


func _descendants(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in node.get_children():
		out.append(child)
		out.append_array(_descendants(child))
	return out


## Merges the internal MeshInstance3D children of CSG part scenes (window frames, glass, door
## panels, ...) into one mesh with a surface per material, in [param to_local] space.
func _merge_part_meshes(csg: CSGShape3D, to_local: Transform3D) -> ArrayMesh:
	var tools := {}
	var stack: Array[Node] = [csg]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var normal := node.get_children()
		for child in node.get_children(true):
			if child in normal:
				if child is CSGShape3D:
					stack.append(child)
				continue
			if child is MeshInstance3D and child.visible and child.mesh:
				var mat: Material = child.material_override
				if mat == null:
					mat = child.mesh.surface_get_material(0)
				if not tools.has(mat):
					var st := SurfaceTool.new()
					st.begin(Mesh.PRIMITIVE_TRIANGLES)
					st.set_material(mat)
					tools[mat] = st
				for s in child.mesh.get_surface_count():
					tools[mat].append_from(child.mesh, s, to_local * child.global_transform)
	if tools.is_empty():
		return null
	var out := ArrayMesh.new()
	for mat in tools:
		tools[mat].commit(out)
	return out
