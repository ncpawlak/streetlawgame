class_name NorthEndPopulator
extends RefCounted
## Puts a baked building-kit scene (data/buildings/building_kit.json) on every North End lot of a
## [CityGenerator]: the census design archetype (data/areas/north_end_buildings.json) picks the
## scenes, a hash of the lot key picks the variant, palette / mirroring ([KitVariant]) and the West
## Palm Beach dressing ([KitDressing], per the scene's income tier).
##
## The building faces the street its census lot fronts ([method frontage]: the nearest kerb with no
## other lot in between, preferring a side the kit lot fits; a roster spot's [code]face[/code]
## point wins). The kit lot front sits at the back of the sidewalk ([constant CityGenerator.SIDEWALK_M]
## from the kerb), centred on the frontage, so the wireframe's block inset never leaves a building
## stranded behind a dead strip. A variant whose lot fits is preferred; otherwise the
## yard parts that overhang the census lot are cropped and, as a last resort, the building is scaled
## down (never below [constant MIN_SCALE]). The census lot, stretched to the sidewalk on every
## street side, gets a grass or paved yard.
##
## With a [KitBatcher] the scenes are only harvested (merged meshes, MultiMesh dressing, merged
## collision, distance tiers); without one each scene is added as-is (the naive baseline that
## tools/benchmark_north_end.tscn compares against).
##
## Each lot gets "door" (front door transform, used by [LocationPlacer] and main.gd),
## "kit_footprint" (world X/Z extents of the building body, m), "kit_height" and "kit_scene".

const KIT := "res://data/buildings/building_kit.json"
## Kit root height: the kit lot surface (+0.05) sits just above the block sidewalk pad (0.1).
const ROOT_Y := 0.13
const YARD_Y := 0.115
const MIN_SCALE := 0.7
## Yard parts may overhang the census lot by this much before they are dropped.
const OVERHANG := 0.25
## Deepest front yard (lot front to house body, m) a street-fronting house prefers; deeper variants
## are only picked when none of the archetype's fitting variants is closer.
const MAX_SETBACK_M := 7.0
const YARD_PARTS := [&"Fence", &"Landscape", &"Site"]
const LIVE_TYPES := ["Label3D", "Marker3D", "Area3D", "OmniLight3D", "SpotLight3D"]
const COMMERCIAL := [&"purchasable_business", &"large_building", &"specialized_location", &"special_building"]

static var _kit := {}
static var _scenes := {}
static var _census := {}
static var _setbacks := {}


## Populates [param city]. Returns the node holding the buildings.
static func populate(city: CityGenerator, batch := true) -> Node3D:
	var holder := Node3D.new()
	holder.name = "KitBuildings"
	city.add_child(holder)
	var batcher: KitBatcher = KitBatcher.new() if batch else null
	var census := census_archetypes()
	var spots := NorthEndCensus.spots_by_lot(city)
	var yards := {}
	var obstacles: Array[Rect2] = city._reserved_rects()
	for lot: Dictionary in city.building_lots:
		obstacles.append(lot["rect_px"])
	for node in city.get_children():
		if node.is_in_group(NorthEndCensus.GROUP) and node.get_meta(&"census_kind", &"") == &"landmark":
			obstacles.append(node.get_meta(&"rect_px"))
	for lot: Dictionary in city.building_lots:
		var spot: Dictionary = spots.get(lot["index"], {})
		var key := NorthEndCensus.rect_key(lot["rect_px"])
		var entry: Dictionary = census.get(key, {})
		var archetype: String = entry.get("design_archetype", lot.get("archetype", ""))
		if archetype == "":
			archetype = _fallback_archetype(lot, spot)
		var paved := lot.has("archetype") or COMMERCIAL.has(StringName(entry.get("category", "")))
		# Facing uses the census-independent archetype: the census derives street, archetype and
		# stand-ins from the facing, so feeding its archetype back in would never settle.
		_place(holder, batcher, lot, archetype, frontage(lot, spot, _fallback_archetype(lot, spot), obstacles), key, paved, yards)
	for node in city.get_children():
		if node.is_in_group(NorthEndCensus.GROUP) and node.get_meta(&"census_kind", &"") == &"landmark":
			var rect: Rect2 = node.get_meta(&"rect_px")
			var lot := {"rect_px": rect, "center": CityGenerator.px_to_world(rect.get_center()), "census_node": node}
			var archetype := String(node.get_meta(&"archetype", "grove_general_hospital"))
			_place(holder, batcher, lot, archetype, frontage(lot, {}, archetype, obstacles), NorthEndCensus.rect_key(rect), true, yards)
	for district: District in city.districts:
		if district.safehouse != null and district.safehouse.data != null and district.get_parent() == city:
			_place_safehouse(holder, batcher, district)
	_build_yards(holder, yards, batch)
	if batcher != null:
		batcher.build(holder)
	return holder


## Kit lot-space building for one archetype, scaled to a census lot: {path, entry, scale}.
static func pick(archetype: String, frontage: float, depth: float, variant_seed: int, max_setback := INF) -> Dictionary:
	var scenes: Array = kit()["archetypes"].get(archetype, kit()["archetypes"]["house_1f_small_yard"])["scenes"]
	var fits: Array = []
	var solid_fits: Array = []
	for scene: Dictionary in scenes:
		var lot := Vector2(scene["lot_m"][0], scene["lot_m"][1])
		if lot.x <= frontage + 0.01 and lot.y <= depth + 0.01:
			fits.append(scene)
		var solid := Vector2(scene["footprint_m"][0], scene["footprint_m"][1])
		if solid.x <= frontage - 1.0 and solid.y <= depth - 4.0:
			solid_fits.append(scene)
	var closest := INF
	for scene: Dictionary in fits:
		closest = minf(closest, setback(scene["baked"]))
	var close := fits.filter(func(s: Dictionary) -> bool: return setback(s["baked"]) <= maxf(max_setback, closest + 0.5))
	var pool: Array = close if not close.is_empty() else (fits if not fits.is_empty() else (solid_fits if not solid_fits.is_empty() else scenes))
	var chosen: Dictionary = pool[posmod(variant_seed, pool.size())]
	var scale := 1.0
	if fits.is_empty() and solid_fits.is_empty():
		var lot := Vector2(chosen["lot_m"][0], chosen["lot_m"][1])
		scale = maxf(MIN_SCALE, minf(1.0, minf(frontage / lot.x, depth / lot.y)))
	return {"path": chosen["baked"], "entry": chosen, "scale": scale}


## Front yard depth (m) of a kit scene: its lot front (z = 0) to the front of its solid body.
static func setback(path: String) -> float:
	if not _setbacks.has(path):
		var building := (_scene(path)).instantiate() as Node3D
		_setbacks[path] = maxf(0.0, -(_building_info(building, false)["solid"] as Rect2).end.y)
		building.free()
	return _setbacks[path]


static func kit() -> Dictionary:
	if _kit.is_empty():
		_kit = JSON.parse_string(FileAccess.get_file_as_string(KIT))
	return _kit


## Census key -> census entry (only buildings); empty when the census file is missing.
static func census_archetypes() -> Dictionary:
	if _census.is_empty():
		for entry: Dictionary in NorthEndCensus.load_census().get("buildings", []):
			_census[entry["key"]] = entry
	return _census


## Street frontage of a lot: {outward: Vector3 (unit axis the building faces, +Z of the kit root),
## reach: float (m the kit lot front sits beyond the census lot: up to the back of the sidewalk),
## gap: float (census lot front to kerb, m; INF without a street), yard: Rect2 (px, the census lot
## stretched to the back of the sidewalk on every open street side)}. Streets behind another lot,
## landmark or reserved rect don't count. Among the open sides the closest kerb wins, with a
## penalty when the archetype's kit lot can't fit that way round or the frontage is the long side.
static func frontage(lot: Dictionary, spot: Dictionary, archetype: String, obstacles: Array[Rect2]) -> Dictionary:
	var rect: Rect2 = lot["rect_px"]
	var sides: Array[Dictionary] = []
	for side in CityGenerator.street_sides(rect):
		if not CityGenerator.street_blocked(rect, side, obstacles):
			sides.append(side)
	var yard := CityGenerator.to_kerb(rect, CityGenerator.SIDEWALK_M, sides) if not sides.is_empty() else rect
	var forced := _spot_outward(rect, spot)
	if not sides.any(func(s: Dictionary) -> bool: return Vector3((s["out"] as Vector2).x, 0.0, (s["out"] as Vector2).y).is_equal_approx(forced)):
		forced = Vector3.ZERO  # a spot only pins the facing toward an open street
	var size_m := rect.size * CityGenerator.METERS_PER_PX
	var best := {}
	var best_score := INF
	for side in sides:
		var axis: Vector2 = side["out"]
		var out3 := Vector3(axis.x, 0.0, axis.y)
		if forced != Vector3.ZERO and not out3.is_equal_approx(forced):
			continue
		var reach := maxf(0.0, float(side["gap_m"]) - CityGenerator.SIDEWALK_M)
		var front_m := size_m.y if axis.x != 0.0 else size_m.x
		var depth := (size_m.x if axis.x != 0.0 else size_m.y) + reach
		var score: float = side["gap_m"] + (0.0 if _fits(archetype, front_m, depth) else 100.0) + (3.0 if front_m > depth else 0.0)
		if score < best_score:
			best_score = score
			best = {"outward": out3, "reach": reach, "gap": side["gap_m"], "yard": yard}
	if best.is_empty():
		best = {"outward": _spot_outward(rect, spot) if not spot.is_empty() and _spot_outward(rect, spot) != Vector3.ZERO else _outward(lot), "reach": 0.0, "gap": INF, "yard": yard}
	return best


static func _fits(archetype: String, front_m: float, depth: float) -> bool:
	var scenes: Array = kit()["archetypes"].get(archetype, kit()["archetypes"]["house_1f_small_yard"])["scenes"]
	return scenes.any(func(s: Dictionary) -> bool: return s["lot_m"][0] <= front_m + 0.01 and s["lot_m"][1] <= depth + 0.01)


## Axis toward the roster spot's face point (or the spot itself when it sits off the lot); ZERO
## when the spot doesn't pin a facing.
static func _spot_outward(rect: Rect2, spot: Dictionary) -> Vector3:
	if not spot.is_empty() and not spot.get("free", false):
		var px: Vector2 = spot["px"]
		if spot.has("face") or not rect.has_point(px):
			var away: Vector2 = (spot.get("face", px) as Vector2) - rect.get_center()
			if away.length() > 0.01:
				return Vector3(signf(away.x), 0.0, 0.0) if absf(away.x) >= absf(away.y) else Vector3(0.0, 0.0, signf(away.y))
	return Vector3.ZERO


## Fallback facing for a lot with no open street: away from the block centre.
static func _outward(lot: Dictionary) -> Vector3:
	var center: Vector3 = lot["center"]
	var away3: Vector3 = center - (lot.get("block_center", center) as Vector3)
	if absf(away3.x) > 0.5 or absf(away3.z) > 0.5:
		return Vector3(signf(away3.x), 0.0, 0.0) if absf(away3.x) >= absf(away3.z) else Vector3(0.0, 0.0, signf(away3.z))
	return Vector3.BACK


static func _fallback_archetype(lot: Dictionary, spot: Dictionary) -> String:
	var key := NorthEndCensus.spot_key(spot)
	if NorthEndCensus.ROSTER.has(key):
		return NorthEndCensus.ROSTER[key]["archetype"]
	if spot.get("kind") == &"site":
		return NorthEndCensus.SITE_ARCHETYPES.get(String(spot["id"]), "storefront_1f")
	if (lot.get("block", Vector2i.ZERO) as Vector2i).x < 0:
		return "trailer_1f"
	return "industrial_shed" if lot.get("district", &"") == &"mangona" else "house_1f_small_yard"


static func _place(holder: Node3D, batcher: KitBatcher, lot: Dictionary, archetype: String, street: Dictionary, key: String, paved: bool, yards: Dictionary) -> void:
	var rect: Rect2 = lot["rect_px"]
	var outward: Vector3 = street["outward"]
	var reach: float = street["reach"]
	var size_m := rect.size * CityGenerator.METERS_PER_PX
	var frontage := size_m.y if outward.x != 0.0 else size_m.x
	var lot_depth := size_m.x if outward.x != 0.0 else size_m.y
	var depth := lot_depth + reach
	var center := CityGenerator.px_to_world(rect.get_center())
	var basis := Basis.looking_at(-outward)
	var front := center + outward * (lot_depth * 0.5 + reach)
	lot["street"] = {"outward": outward, "gap": street["gap"]}
	var variant_seed := (hash(key) & 0x3fffffff) | 1
	var choice := pick(archetype, frontage, depth, variant_seed >> 3, INF if paved else MAX_SETBACK_M)
	var scale: float = choice["scale"]
	var building := (_scene(choice["path"])).instantiate() as Node3D
	if "dress_seed" in building:
		building.dress_seed = 0
	var mirrored := KitVariant.apply(building, variant_seed, true)
	var limit := Vector2(frontage, depth) / scale
	_crop(building, limit)
	var kit_lot: Vector2 = building.get("lot_size") if "lot_size" in building else Vector2(choice["entry"]["lot_m"][0], choice["entry"]["lot_m"][1])
	if "lot_size" in building:
		building.lot_size = Vector2(minf(kit_lot.x, limit.x), minf(kit_lot.y, limit.y))
	var xform := Transform3D(basis.scaled_local(Vector3.ONE * scale), front + Vector3(0.0, ROOT_Y, 0.0))
	var tier: String = choice["entry"].get("dress_tier", "auto")
	var info := _building_info(building, mirrored)
	var door_local: Vector3 = info["door"]
	var door_at := xform * Vector3(door_local.x, 0.0, door_local.z)
	door_at.y = 0.0
	lot["door"] = Transform3D(basis, door_at + outward * 0.15)
	var solid: Rect2 = info["solid"]
	var front_edge := xform * Vector3(solid.get_center().x, 0.0, solid.end.y)
	lot["front_edge"] = Vector3(front_edge.x, 0.0, front_edge.z)
	var solid_size := solid.size * scale
	lot["kit_footprint"] = Vector2(solid_size.y, solid_size.x) if outward.x != 0.0 else solid_size
	lot["kit_height"] = snappedf(float(info["height"]) * scale, 0.01)
	lot["kit_scene"] = choice["entry"]["id"]
	var marker: Node = lot.get("census_node")
	if marker != null:
		marker.set_meta(&"footprint_m", lot["kit_footprint"])
		marker.set_meta(&"height_m", lot["kit_height"])
		marker.set_meta(&"kit_scene", lot["kit_scene"])
	_add_yard(yards, street["yard"], paved)
	_finish(holder, batcher, building, xform, info, choice["entry"], variant_seed, tier, mirrored, key)


## A safehouse kit shell (SH-01..03 by the safehouse's data) with its body front on the door plane.
static func _place_safehouse(holder: Node3D, batcher: KitBatcher, district: District) -> void:
	var safehouse := district.safehouse
	var kind := String(safehouse.data.resource_path.get_file().get_basename())
	var archetype := "safehouse_%s" % kind
	if not kit()["archetypes"].has(archetype):
		archetype = "safehouse_greybox"
	var key := "safehouse:%s" % district.district_id
	var variant_seed := (hash(key) & 0x3fffffff) | 1
	var choice := pick(archetype, 1000.0, 1000.0, variant_seed >> 3)
	var building := (_scene(choice["path"])).instantiate() as Node3D
	if "dress_seed" in building:
		building.dress_seed = 0
	var mirrored := KitVariant.apply(building, variant_seed, true)
	var info := _building_info(building, mirrored)
	var solid: Rect2 = info["solid"]
	var local := Vector3(-solid.get_center().x, ROOT_Y, safehouse.data.footprint.y * 0.5 - solid.end.y)
	var xform := district.transform * safehouse.transform * Transform3D(Basis.IDENTITY, local)
	safehouse.use_kit_shell(float(info["height"]))
	_finish(holder, batcher, building, xform, info, choice["entry"], variant_seed, choice["entry"].get("dress_tier", "auto"), mirrored, key)


static func _finish(holder: Node3D, batcher: KitBatcher, building: Node3D, xform: Transform3D, info: Dictionary, entry: Dictionary, variant_seed: int, tier: String, mirrored: bool, key: String) -> void:
	if batcher == null:
		building.transform = xform
		if "dress_seed" in building:
			building.dress_mirrored = mirrored
			building.dress_tier = tier
			building.dress_seed = variant_seed
			holder.add_child(building)
		else:
			holder.add_child(building)
			KitDressing.apply(building, variant_seed, tier, mirrored)
		return
	KitDressing.apply(building, variant_seed, tier, mirrored)
	var live := _take_live(building)
	batcher.add_building(building, xform, info, entry["id"])
	if not live.is_empty():
		var shop := Node3D.new()
		shop.name = "Kit_%s" % key.validate_node_name().replace(".", "_")
		shop.transform = xform
		for node: Node3D in live:
			shop.add_child(node)
		holder.add_child(shop)
		batcher.tune_live(shop)
	building.free()


static func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]


## Shrinks the paved/grass Lot part to [param limit] (kit lot-space m) and drops yard parts that
## overhang it.
static func _crop(building: Node3D, limit: Vector2) -> void:
	var bounds := Rect2(-limit.x * 0.5 - OVERHANG, -limit.y - OVERHANG, limit.x + OVERHANG * 2.0, limit.y + OVERHANG * 2.0)
	for part in building.get_children():
		if not part is Node3D:
			continue
		var aabb := _part_aabb(part)
		if aabb.size == Vector3.ZERO:
			continue
		var flat := Rect2(aabb.position.x, aabb.position.z, aabb.size.x, aabb.size.z)
		if bounds.encloses(flat):
			continue
		if part.name == &"Lot":
			var sx := minf(1.0, limit.x / maxf(flat.size.x, 0.01))
			var sz := minf(1.0, limit.y / maxf(flat.size.y, 0.01))
			(part as Node3D).scale = Vector3(sx, 1.0, sz) * (part as Node3D).scale
		elif YARD_PARTS.has(part.name):
			building.remove_child(part)
			part.free()


static func _part_aabb(part: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for node in part.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var box := (part.transform * _relative(mi, part)) * mi.mesh.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


static func _relative(node: Node3D, ancestor: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != ancestor and n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## Front door (kit lot space), building body rect (lot-space XZ) and roof height.
static func _building_info(building: Node3D, mirrored: bool) -> Dictionary:
	var solid := Rect2()
	var solids: PackedVector4Array = building.get_meta(&"dress_solids", PackedVector4Array())
	for i in solids.size():
		var v := solids[i]
		var r := Rect2(v.x, v.y, v.z - v.x, v.w - v.y).abs()
		if mirrored:
			r.position.x = -r.end.x
		solid = r if i == 0 else solid.merge(r)
	var height := 4.0
	var body := building.get_node_or_null(^"House")
	if body == null:
		body = building.get_node_or_null(^"Building")
	if body is Node3D:
		var aabb := _part_aabb(body)
		height = aabb.end.y
		if not solid.has_area():
			solid = Rect2(aabb.position.x, aabb.position.z, aabb.size.x, aabb.size.z)
	if not solid.has_area():
		solid = Rect2(-5.0, -14.0, 10.0, 8.0)
	var door := Vector3(solid.get_center().x, 0.0, solid.end.y)
	var entrance := building.get_node_or_null(^"Entrance") as Node3D
	if entrance != null:
		door = entrance.position
	else:
		var openings: PackedFloat32Array = building.get_meta(&"dress_openings", PackedFloat32Array())
		var best := -INF
		for i in range(0, openings.size() - 7, 8):
			var kind := int(openings[i + 7])
			if (kind == 1 or kind == 2) and openings[i + 4] > 0.5 and openings[i + 2] > best:
				best = openings[i + 2]
				door = Vector3(-openings[i] if mirrored else openings[i], 0.0, openings[i + 2])
	return {"solid": solid, "height": height, "door": door}


## Detaches the nodes that stay live after harvesting (signs, entrance, counter, lights).
static func _take_live(building: Node3D) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for child in building.get_children():
		if LIVE_TYPES.has(child.get_class()):
			building.remove_child(child)
			child.owner = null
			for sub in child.find_children("*", "", true, false):
				sub.owner = null
			out.append(child)
	return out


## Census lot rect -> grass (houses) or paving (businesses) under the kit lot, merged per 200 m cell.
static func _add_yard(yards: Dictionary, rect: Rect2, paved: bool) -> void:
	var r := Rect2(CityGenerator.px_to_world(rect.position).x, CityGenerator.px_to_world(rect.position).z, rect.size.x * CityGenerator.METERS_PER_PX, rect.size.y * CityGenerator.METERS_PER_PX)
	var cell := Vector3i(floori(r.get_center().x / 200.0), floori(r.get_center().y / 200.0), 1 if paved else 0)
	if not yards.has(cell):
		yards[cell] = []
	(yards[cell] as Array).append(r)


static func _build_yards(holder: Node3D, yards: Dictionary, batch: bool) -> void:
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color(0.33, 0.45, 0.24)
	grass.roughness = 0.95
	var paving := StandardMaterial3D.new()
	paving.albedo_color = Color(0.52, 0.51, 0.49)
	paving.roughness = 0.9
	for cell: Vector3i in yards:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_normal(Vector3.UP)
		for r: Rect2 in yards[cell]:
			var a := Vector3(r.position.x, YARD_Y, r.position.y)
			var b := Vector3(r.end.x, YARD_Y, r.position.y)
			var c := Vector3(r.end.x, YARD_Y, r.end.y)
			var d := Vector3(r.position.x, YARD_Y, r.end.y)
			for v in [a, b, c, a, c, d]:
				st.set_uv(Vector2(v.x, v.z) * 0.25)
				st.add_vertex(v)
		var mi := MeshInstance3D.new()
		mi.name = "Yards_%d_%d_%d" % [cell.x, cell.y, cell.z]
		mi.mesh = st.commit()
		mi.material_override = paving if cell.z == 1 else grass
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if batch:
			mi.visibility_range_end = KitBatcher.SHELL_RANGE
		holder.add_child(mi)
