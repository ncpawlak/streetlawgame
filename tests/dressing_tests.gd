extends RefCounted
## West Palm Beach dressing tests: every prop in data/buildings/building_kit.json loads with the
## right collision policy (trunks, poles, fences, bins collide; brush, flowers, ground and decals
## don't); KitDressing is deterministic per seed, clears on seed 0, picks the tier's rules and keeps
## ground props on the lot, off the building and off paving (also when mirrored); PowerLineRun
## strings sagging wires between its poles.

const MAPPING := "res://data/buildings/building_kit.json"
const SOLID_CATEGORIES := ["palms", "trees", "street", "lots"]
const SOFT_CATEGORIES := ["shrubs", "flowers", "ground", "decals"]
const SAMPLES: Array[String] = [
	"res://scenes/houses/one_floor/house_1f_01.tscn", "res://scenes/houses/one_floor/house_1f_06.tscn",
	"res://scenes/houses/two_floor/house_2f_05.tscn", "res://scenes/businesses/closed/business_b_01.tscn",
	"res://scenes/baked/houses/one_floor/house_1f_03.scn",
]
const OFFSET := Vector3(-6000, 0, -6000)

var _runner: Node


func _init(runner: Node) -> void:
	_runner = runner


func run() -> void:
	_props()
	await _dressing()
	await _power_lines()


func _props() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAPPING))
	var props: Dictionary = data.get("props", {})
	_check(props.size() >= 40, "mapping lists the Florida props (%d)" % props.size())
	var bad: Array[String] = []
	for id: String in props:
		var entry: Dictionary = props[id]
		var path := String(entry["scene"])
		if not ResourceLoader.exists(path):
			bad.append("%s: missing %s" % [id, path])
			continue
		var info := KitDressing.prop_info(path)
		var collides := not (info["shapes"] as Array).is_empty()
		if collides != bool(entry["collision"]):
			bad.append("%s: collision %s, mapping says %s" % [id, collides, entry["collision"]])
		var cat := String(entry["category"])
		if cat in SOLID_CATEGORIES and not collides:
			bad.append("%s: %s prop without collision" % [id, cat])
		if cat in SOFT_CATEGORIES and collides:
			bad.append("%s: %s prop has collision" % [id, cat])
		if (info["parts"] as Array).is_empty():
			bad.append("%s: no meshes" % id)
	_check(bad.is_empty(), "prop scenes load with the collision policy %s" % [bad])
	var tiers := KitDressing.tiers()
	var missing: Array[String] = []
	for t in ["low", "medium", "high", "commercial", "civic"]:
		if (tiers.get(t, []) as Array).is_empty():
			missing.append(t)
		for rule: Dictionary in tiers.get(t, []):
			for key in ["scene", "alt_scene"]:
				if rule.has(key) and not ResourceLoader.exists(String(rule[key])):
					missing.append("%s: %s" % [t, rule[key]])
	_check(missing.is_empty(), "every dressing tier has rules with existing scenes %s" % [missing])


func _dressing() -> void:
	var bad: Array[String] = []
	for path in SAMPLES:
		if not ResourceLoader.exists(path):
			bad.append("missing " + path)
			continue
		var root := (load(path) as PackedScene).instantiate() as Node3D
		root.position = OFFSET
		_runner.add_child(root)
		await _runner.get_tree().process_frame
		var name := path.get_file()
		var a_items := _items(KitDressing.apply(root, 5))
		var b_items := _items(KitDressing.apply(root, 5))
		if a_items.is_empty():
			bad.append("%s: seed 5 placed nothing" % name)
		elif str(b_items) != str(a_items):
			bad.append("%s: re-apply changed the dressing" % name)
		var first := str(b_items)
		KitDressing.apply(root, 6)
		var second := str(_items(_dressing_of(root)))
		KitDressing.apply(root, 5)
		if str(_items(_dressing_of(root))) != first:
			bad.append("%s: seed 5 is not deterministic" % name)
		if second == first:
			bad.append("%s: seeds 5 and 6 match" % name)
		bad.append_array(_bounds(root, name, false))
		var tier := String(root.get_meta("dress_tier", ""))
		if _dressing_of(root).get_meta("tier", "") != tier:
			bad.append("%s: auto tier is not the scene's %s" % [name, tier])
		KitDressing.apply(root, 9, "auto", true)
		bad.append_array(_bounds(root, name + " mirrored", true))
		KitDressing.apply(root, 0)
		if _dressing_of(root) != null:
			bad.append("%s: seed 0 left dressing" % name)
		root.queue_free()
	_check(bad.is_empty(), "KitDressing is seeded, stays on the lot and off the building %s" % [bad])
	# Tiers read differently: low lots get window bars / AC, high lots get pools and palms.
	var probe := (load(SAMPLES[1]) as PackedScene).instantiate() as Node3D
	probe.position = OFFSET
	_runner.add_child(probe)
	await _runner.get_tree().process_frame
	var seen := {"low": {}, "high": {}}
	for t: String in seen:
		for s in range(1, 9):
			for item: Dictionary in _items(KitDressing.apply(probe, s, t)):
				seen[t][item["prop"]] = true
	probe.queue_free()
	_check(seen["low"].has("window_bars") and not seen["low"].has("screened_pool")
			and not seen["high"].has("window_bars") and (seen["high"].has("royal_palm") or seen["high"].has("screened_pool")),
			"low and high tiers dress differently (low %s / high %s)" % [seen["low"].keys(), seen["high"].keys()])


func _bounds(root: Node3D, name: String, mirrored: bool) -> Array[String]:
	var out: Array[String] = []
	var lot: Rect2 = (root.call("lot_rect") as Rect2).grow(0.05)
	var solids := _rects(root.get_meta("dress_solids", PackedVector4Array()), mirrored)
	var dressing := _dressing_of(root)
	if dressing == null:
		return out
	for item: Dictionary in _items(dressing):
		var r: Rect2 = item["rect"]
		if item["mount"] != "ground" or r.size == Vector2.ZERO:
			continue
		if not lot.encloses(r):
			out.append("%s: %s %s off lot %s" % [name, item["prop"], r, lot])
		for s in solids:
			if r.grow(-0.05).intersects(s):
				out.append("%s: %s %s inside building %s" % [name, item["prop"], r, s])
				break
	return out


func _power_lines() -> void:
	var run := PowerLineRun.new()
	run.points = PackedVector3Array([Vector3(0, 0, 0), Vector3(30, 0, 0), Vector3(60, 0, 4)])
	run.position = OFFSET
	_runner.add_child(run)
	await _runner.get_tree().process_frame
	var poles := 0
	var wires: MeshInstance3D = null
	for child in run.get_children(true):
		if child is MeshInstance3D and child.name == "Wires":
			wires = child
		elif child.has_meta("power_line_part"):
			poles += 1
	var top := 0.0
	for child in run.get_children(true):
		if child != wires and child.has_meta("power_line_part"):
			for a: Vector3 in (child as Node3D).get_meta("anchors", PackedVector3Array()):
				top = maxf(top, a.y)
	var mid := PowerLineRun.sag_point(Vector3(0, 8, 0), Vector3(30, 8, 0), 0.9)
	_check(poles == 3 and wires != null and wires.mesh != null and wires.mesh.get_surface_count() > 0,
			"PowerLineRun builds 3 poles and a wire mesh (poles %d)" % poles)
	_check(top > 5.0 and is_equal_approx(mid.y, 7.1) and wires != null and wires.get_aabb().position.y < top - 0.5,
			"power lines hang from the pole anchors and sag between them (top %.1f, mid %.2f)" % [top, mid.y])
	run.queue_free()


func _dressing_of(root: Node) -> Node3D:
	for child in root.get_children(true):
		if child.name == KitDressing.NODE_NAME:
			return child
	return null


func _items(node: Node) -> Array:
	return node.get_meta("items", []) if node != null else []


func _rects(v4: PackedVector4Array, mirrored: bool) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for v in v4:
		var r := Rect2(v.x, v.y, v.z - v.x, v.w - v.y).abs()
		if mirrored:
			r = Rect2(-r.end.x, r.position.y, r.size.x, r.size.y)
		out.append(r)
	return out


func _check(condition: bool, description: String) -> void:
	_runner._check(condition, description)
