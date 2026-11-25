extends RefCounted
## Building-kit phase 2 tests: the North End census buildings (scenes/buildings/) load, fit their
## lots and enterable ones can be walked into; data/buildings/building_kit.json covers every
## census archetype with existing scenes; KitVariant is deterministic and mirrors within the lot;
## baked scenes (scenes/baked/) match their CSG source in visual bounds and collision.

const BUILDING_DIRS := {
	"res://scenes/buildings/residential": 5, "res://scenes/buildings/special": 4,
	"res://scenes/buildings/locations": 12, "res://scenes/buildings/purchasable": 9,
}
const KIT_DIRS: Array[String] = [
	"res://scenes/houses/one_floor", "res://scenes/houses/two_floor",
	"res://scenes/businesses/closed", "res://scenes/businesses/shops",
	"res://scenes/buildings/residential", "res://scenes/buildings/special",
	"res://scenes/buildings/locations", "res://scenes/buildings/purchasable",
]
const MAPPING := "res://data/buildings/building_kit.json"
# Both copies sit far from anything other tests leave behind, side by side.
const CSG_OFFSET := Vector3(-3000, 0, 4000)
const BAKE_OFFSET := Vector3(3000, 0, 4000)
# Keeps grid rays off the round design coordinates where roof edges and wall faces sit.
const RAY_JITTER := 0.0371
const HouseTests := preload("res://tests/house_tests.gd")

var _runner: Node


func _init(runner: Node) -> void:
	_runner = runner


func run() -> void:
	await _census_buildings()
	_mapping()
	await _variants()
	await _bake_parity()


func _census_buildings() -> void:
	var walker := HouseTests.new(_runner)
	for dir: String in BUILDING_DIRS:
		var files := _scenes(dir)
		_check(files.size() == BUILDING_DIRS[dir], "%d census buildings in %s (found %d)" % [BUILDING_DIRS[dir], dir, files.size()])
		var bad: Array[String] = []
		for file in files:
			var root := (load(dir.path_join(file)) as PackedScene).instantiate() as Node3D
			if not (root is HouseExterior or root is BusinessExterior):
				bad.append("%s: not a kit building" % file)
				root.free()
				continue
			_runner.add_child(root)
			await _runner.get_tree().process_frame
			if String(root.get("archetype")).is_empty() or String(root.get("lot_type")).is_empty():
				bad.append("%s: missing archetype / lot type" % file)
			var shell := (root.get_node_or_null("House") if root is HouseExterior else root.get_node_or_null("Building")) as CSGCombiner3D
			if shell == null or not shell.use_collision:
				bad.append("%s: shell combiner missing or without collision" % file)
			else:
				var aabb := _csg_aabb(shell)
				var lot: Rect2 = (root.call("lot_rect") as Rect2).grow(0.05)
				if not aabb.has_volume() or not (lot.has_point(Vector2(aabb.position.x, aabb.position.z)) and lot.has_point(Vector2(aabb.end.x, aabb.end.z))):
					bad.append("%s: shell %s outside lot %s" % [file, aabb, lot])
				elif aabb.size.y < 2.8:
					bad.append("%s: only %.1f m tall" % [file, aabb.size.y])
			if root is BusinessExterior:
				var biz := root as BusinessExterior
				if biz.enterable and (biz.shop_type.is_empty() or biz.entrance() == null or biz.counter() == null):
					bad.append("%s: shop needs shop_type, Entrance and ShopCounter" % file)
				elif not biz.enterable and biz.entrance() != null:
					bad.append("%s: closed building has an Entrance" % file)
				elif biz.enterable:
					bad.append_array(await walker._walk_in(biz, file))
			root.queue_free()
		_check(bad.is_empty(), "census buildings in %s are valid shells on their lots %s" % [dir.get_file(), bad])


func _mapping() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAPPING))
	var archetypes: Dictionary = data["archetypes"]
	var bad: Array[String] = []
	var census := 0
	for arch: String in archetypes:
		var info: Dictionary = archetypes[arch]
		if not info.get("kit_only", false):
			census += 1
			if (info["scenes"] as Array).is_empty():
				bad.append("%s: no scene" % arch)
		for entry: Dictionary in info["scenes"]:
			for key in ["scene", "baked"]:
				if not ResourceLoader.exists(entry[key]):
					bad.append("%s: missing %s" % [arch, entry[key]])
			if entry["enterable"] and String(entry["shop_type"]).is_empty():
				bad.append("%s: enterable %s without shop_type" % [arch, entry["id"]])
	_check(census >= 41, "building_kit.json lists all 41 census archetypes (found %d)" % census)
	_check(bad.is_empty(), "every census archetype maps to existing CSG + baked scenes %s" % [bad])


func _variants() -> void:
	var path := "res://scenes/houses/one_floor/house_1f_02.tscn"
	var mirror_seed := 0
	var swap_seed := 0
	for s in range(1, 40):
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var mirrors := rng.randf() < 0.5
		if mirrors and mirror_seed == 0:
			mirror_seed = s
		if not KitVariant.material_map(rng).is_empty() and swap_seed == 0:
			swap_seed = s
	_check(mirror_seed != 0 and swap_seed != 0, "some variant seeds mirror and some swap palettes")
	var original := await _placed(path, 0, Vector3.ZERO)
	var a := await _placed(path, swap_seed, Vector3(0, 0, 100))
	var b := await _placed(path, swap_seed, Vector3(0, 0, 200))
	_check(_materials(a.instance) == _materials(b.instance), "same variant seed gives the same palette")
	_check(_materials(a.instance) != _materials(original.instance), "variant seed %d swaps the palette" % swap_seed)
	var m := await _placed(path, mirror_seed, Vector3(0, 0, 300))
	var orig_box := _csg_aabb(original.instance.get_node("House"), original.instance)
	var mir_box := _csg_aabb(m.instance.get_node("House"), m.instance)
	var expected := AABB(Vector3(-orig_box.end.x, orig_box.position.y, orig_box.position.z), orig_box.size)
	_check(m.mirrored and _aabb_close(mir_box, expected, 0.02),
		"mirrored variant (seed %d) is the original reflected across the lot centre (%s vs %s)" % [mirror_seed, mir_box, expected])
	var kept := await _placed(path, mirror_seed, Vector3(0, 0, 400), false)
	_check(not kept.mirrored and _aabb_close(_csg_aabb(kept.instance.get_node("House"), kept.instance), orig_box, 0.02),
		"allow_mirror = false keeps the original orientation")
	for p in [original, a, b, m, kept]:
		p.queue_free()


func _placed(path: String, variant_seed: int, at: Vector3, mirror := true) -> KitPlacement:
	var p := KitPlacement.new()
	p.position = at
	p.allow_mirror = mirror
	p.variant_seed = variant_seed
	p.building = path
	_runner.add_child(p)
	await _runner.get_tree().process_frame
	await _runner.get_tree().process_frame
	return p


func _materials(root: Node) -> Array[String]:
	var out: Array[String] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is CSGShape3D and "material" in node and node.material:
			out.append(node.material.resource_path)
		if node is GeometryInstance3D and node.material_override:
			out.append(node.material_override.resource_path)
		stack.append_array(node.get_children(true))
	return out


func _bake_parity() -> void:
	var space := _runner.get_viewport().find_world_3d().direct_space_state
	var bad: Array[String] = []
	var count := 0
	for dir in KIT_DIRS:
		for file in _scenes(dir):
			var source := dir.path_join(file)
			var baked_path := "res://scenes/baked/" + source.trim_prefix("res://scenes/").get_basename() + ".scn"
			if not ResourceLoader.exists(baked_path):
				bad.append("%s: not baked" % file)
				continue
			count += 1
			var csg := (load(source) as PackedScene).instantiate() as Node3D
			var baked := (load(baked_path) as PackedScene).instantiate() as Node3D
			csg.position = CSG_OFFSET
			baked.position = BAKE_OFFSET
			_runner.add_child(csg)
			_runner.add_child(baked)
			for i in 2:
				await _runner.get_tree().process_frame
			await _runner.get_tree().physics_frame
			await _runner.get_tree().physics_frame
			bad.append_array(_compare(file, csg, baked, space))
			csg.free()
			baked.free()
	_check(count == 69, "all 69 kit scenes are baked (found %d)" % count)
	_check(bad.is_empty(), "baked scenes match their CSG source in bounds and collision %s" % [bad])


func _compare(file: String, csg: Node3D, baked: Node3D, space: PhysicsDirectSpaceState3D) -> Array[String]:
	var out: Array[String] = []
	var csg_box := AABB()
	var first := true
	var tops: Array[CSGShape3D] = []
	_top_csg(csg, tops)
	for shape in tops:
		var box := _csg_aabb(shape, csg)
		if box.has_volume():
			csg_box = box if first else csg_box.merge(box)
			first = false
	var baked_box := AABB()
	first = true
	var stack: Array[Node] = [baked]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is CSGShape3D:
			out.append("%s: baked scene still has CSG node %s" % [file, node.name])
		if node is MeshInstance3D and node.name == "Mesh":
			var box: AABB = node.global_transform * node.mesh.get_aabb()
			box.position -= BAKE_OFFSET
			baked_box = box if first else baked_box.merge(box)
			first = false
		stack.append_array(node.get_children())
	if not _aabb_close(csg_box, baked_box, 0.02):
		out.append("%s: bounds %s vs baked %s" % [file, csg_box, baked_box])
	var lot: Rect2 = (csg.call("lot_rect") as Rect2).grow(-0.3)
	var misses := 0
	var rays := 0
	for i in 9:
		for j in 9:
			var x := lot.position.x + lot.size.x * (i + 0.5) / 9.0 + RAY_JITTER
			var z := lot.position.y + lot.size.y * (j + 0.5) / 9.0 + RAY_JITTER
			rays += 1
			if not _same_hit(space, Vector3(x, 80, z), Vector3(x, -5, z)):
				misses += 1
	for i in 7:
		for y in [1.0, 4.5]:
			var x := lot.position.x + lot.size.x * (i + 0.5) / 7.0 + RAY_JITTER
			rays += 1
			if not _same_hit(space, Vector3(x, y, 3.0), Vector3(x, y, lot.position.y - 1.0)):
				misses += 1
	# Allow the odd ray that grazes a triangle edge differently in the two triangulations.
	if misses > rays * 0.02:
		out.append("%s: %d / %d collision rays differ" % [file, misses, rays])
	return out


func _same_hit(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	var a := space.intersect_ray(PhysicsRayQueryParameters3D.create(from + CSG_OFFSET, to + CSG_OFFSET))
	var b := space.intersect_ray(PhysicsRayQueryParameters3D.create(from + BAKE_OFFSET, to + BAKE_OFFSET))
	if a.is_empty() or b.is_empty():
		return a.is_empty() == b.is_empty()
	return ((a["position"] as Vector3) - CSG_OFFSET).distance_to((b["position"] as Vector3) - BAKE_OFFSET) < 0.05


func _top_csg(node: Node, out: Array[CSGShape3D]) -> void:
	for child in node.get_children():
		if child is CSGShape3D:
			out.append(child)
		else:
			_top_csg(child, out)


func _csg_aabb(shape: CSGShape3D, relative_to: Node3D = null) -> AABB:
	var meshes := shape.get_meshes()
	if meshes.size() < 2 or meshes[1] == null:
		return AABB()
	var xf := shape.global_transform
	if relative_to:
		xf = relative_to.global_transform.affine_inverse() * xf
	return xf * (meshes[0] as Transform3D) * (meshes[1] as Mesh).get_aabb()


func _aabb_close(a: AABB, b: AABB, tol: float) -> bool:
	return a.position.distance_to(b.position) < tol and a.end.distance_to(b.end) < tol


func _scenes(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".tscn"):
			out.append(f)
	return out


func _check(condition: bool, description: String) -> void:
	_runner._check(condition, description)
