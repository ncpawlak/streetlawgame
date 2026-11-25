extends RefCounted
## North End performance budget. Structural checks on the HLOD build (no live CSG, every census
## lot has a kit asset, merged cell meshes with visibility ranges, far impostors, occluders, merged
## greybox) plus per-viewpoint budgets at the fixed [code]VIEWPOINTS[/code] of
## tools/benchmark_north_end.gd. Headless has no renderer, so the viewpoint check counts what the
## renderer would draw: geometry instances whose AABB is in the camera frustum and inside its
## visibility range (objects), and their surfaces (draw calls, before shadow passes). Run windowed,
## it also checks the real render monitors. Re-baseline with the benchmark when the kit changes.

const VIEWPOINTS: Array = preload("res://tools/benchmark_north_end.gd").VIEWPOINTS
## Estimated (frustum + visibility range) budgets per viewpoint. The naive path (one node per
## building part, batch_kit off) is ~8-20x these.
const EST_OBJECTS := 1100
const EST_SURFACES := 1500
## Render-monitor budgets (windowed only; shadow passes included). Batched peaks ~2030 / ~2770.
const DRAW_CALLS := 2600
const OBJECTS := 3400
const NODE_BUDGET := 16000
const MERGED_MESH_BUDGET := 400
## One prop MultiMesh per (prop mesh, material) per 100 m cell, culled at 160-260 m.
const PROP_MULTIMESH_BUDGET := 6000
## Enterable shops / businesses keep signs, entrance, counter and lights live.
const LIVE_SHOP_BUDGET := 120

var _runner: Node


func _init(runner: Node) -> void:
	_runner = runner


func run(main: Node, city: CityGenerator) -> void:
	var holder := city.get_node_or_null(^"KitBuildings") as Node3D
	_runner._check(holder != null, "North End kit buildings are populated")
	if holder == null:
		return
	_structure(city, holder)
	await _viewpoints(main, city)


func _structure(city: CityGenerator, holder: Node3D) -> void:
	_runner._check(city.find_children("*", "CSGShape3D", true, false).is_empty(), "no live CSG at runtime (baked meshes only)")
	var missing := city.building_lots.filter(func(lot: Dictionary) -> bool: return not lot.has("kit_scene"))
	_runner._check(missing.is_empty(), "every census lot has a kit asset (%d missing)" % missing.size())
	var cells := 0
	var impostors := 0
	var occluders := 0
	var merged := 0
	var props := 0
	var unranged := 0
	var shops := 0
	for child in holder.get_children():
		var n := String(child.name)
		if n.begins_with("Cell_"):
			cells += 1
			for gi: GeometryInstance3D in child.find_children("*", "GeometryInstance3D", true, false):
				if gi is MultiMeshInstance3D:
					props += 1
				else:
					merged += 1
				if gi.visibility_range_end <= 0.0:
					unranged += 1
		elif child is GeometryInstance3D and n.begins_with("Impostors_"):
			impostors += 1
			if (child as GeometryInstance3D).visibility_range_begin <= 0.0:
				unranged += 1
		elif child is OccluderInstance3D:
			occluders += 1
		elif n.begins_with("Kit_"):
			shops += 1
	_runner._check(cells > 0 and impostors > 0 and occluders > 0, "HLOD tiers built (%d cells, %d impostor cells, %d occluders)" % [cells, impostors, occluders])
	_runner._check(unranged == 0, "every merged cell mesh fades by distance and impostors only draw far (%d unranged)" % unranged)
	_runner._check(merged <= MERGED_MESH_BUDGET and merged < city.building_lots.size(), "kit merged into %d cell meshes for %d lots" % [merged, city.building_lots.size()])
	_runner._check(props <= PROP_MULTIMESH_BUDGET, "%d prop MultiMeshes (budget %d)" % [props, PROP_MULTIMESH_BUDGET])
	_runner._check(shops <= LIVE_SHOP_BUDGET, "%d live shop nodes (budget %d)" % [shops, LIVE_SHOP_BUDGET])
	_runner._check(city.get_node_or_null(^"StaticBatches") != null, "greybox primitives merged into static batches")
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	_runner._check(nodes < NODE_BUDGET, "scene node count %d under budget %d" % [nodes, NODE_BUDGET])


func _viewpoints(main: Node, city: CityGenerator) -> void:
	var windowed := DisplayServer.get_name() != "headless"
	var previous := main.get_viewport().get_camera_3d()
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 4000.0
	main.add_child(cam)
	cam.make_current()
	var geometry: Array[GeometryInstance3D] = []
	geometry.assign(city.find_children("*", "GeometryInstance3D", true, false))
	for view: Array in VIEWPOINTS:
		var eye := CityGenerator.px_to_world(view[1]) + Vector3(0.0, view[2], 0.0)
		cam.look_at_from_position(eye, CityGenerator.px_to_world(view[3]) + Vector3(0.0, 1.5, 0.0))
		var est := _estimate(cam, geometry)
		_runner._check(est.x <= EST_OBJECTS and est.y <= EST_SURFACES,
				"%s: ~%d objects / ~%d surfaces in view (budget %d / %d)" % [view[0], est.x, est.y, EST_OBJECTS, EST_SURFACES])
		if windowed:
			var worst := {"draw_calls": 0, "objects": 0}
			for i in 20:
				await _runner.get_tree().process_frame
				if i >= 10:
					var s := PerfOverlay.snapshot()
					worst["draw_calls"] = maxi(worst["draw_calls"], s["draw_calls"])
					worst["objects"] = maxi(worst["objects"], s["objects"])
			_runner._check(worst["draw_calls"] <= DRAW_CALLS and worst["objects"] <= OBJECTS,
					"%s: %d draw calls / %d objects rendered (budget %d / %d)" % [view[0], worst["draw_calls"], worst["objects"], DRAW_CALLS, OBJECTS])
	cam.queue_free()
	if previous != null:
		previous.make_current()


## (objects, surfaces) the camera would draw: visible instances in the frustum and visibility range.
func _estimate(cam: Camera3D, geometry: Array[GeometryInstance3D]) -> Vector2i:
	var planes := cam.get_frustum()
	var eye := cam.global_position
	var objects := 0
	var surfaces := 0
	for gi in geometry:
		if not is_instance_valid(gi) or not gi.is_visible_in_tree():
			continue
		var box := gi.global_transform * gi.get_aabb()
		var d := eye.distance_to(box.get_center())
		if gi.visibility_range_end > 0.0 and d > gi.visibility_range_end + gi.visibility_range_end_margin:
			continue
		if d < gi.visibility_range_begin - gi.visibility_range_begin_margin:
			continue
		if not _in_frustum(planes, box):
			continue
		objects += 1
		surfaces += _surfaces(gi)
	return Vector2i(objects, surfaces)


static func _in_frustum(planes: Array[Plane], box: AABB) -> bool:
	for plane in planes:
		var far := box.position + Vector3(
				box.size.x if plane.normal.x < 0.0 else 0.0,
				box.size.y if plane.normal.y < 0.0 else 0.0,
				box.size.z if plane.normal.z < 0.0 else 0.0)
		if plane.is_point_over(far):
			return false
	return true


static func _surfaces(gi: GeometryInstance3D) -> int:
	if gi is MeshInstance3D:
		var mesh := (gi as MeshInstance3D).mesh
		return mesh.get_surface_count() if mesh != null else 0
	if gi is MultiMeshInstance3D:
		var mm := (gi as MultiMeshInstance3D).multimesh
		return mm.mesh.get_surface_count() if mm != null and mm.mesh != null and mm.visible_instance_count != 0 else 0
	return 1
