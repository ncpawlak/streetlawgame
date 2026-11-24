class_name LocationPlacer
extends RefCounted
## Deterministically assigns LocationDefs to building lots and spawns them through Locations.
## Order: unique defs, then each def's min_count, then weighted fill up to [member density] of lots.
## Respects district_ids, max_per_district and max_count. Same seed + lots + defs = same layout.

## Kinds the placer leaves to their owning system (#24 places safehouses itself).
var skip_kinds: Array[StringName] = [&"safehouse"]
## Fraction of lots that receive a location (uniques and min_count are placed regardless).
var density := 0.2
var placement_seed := 0

var _rng := RandomNumberGenerator.new()
var _counts := {}
var _district_counts := {}


## Spawns [method plan] through Locations under [param parent]. Returns the spawned locations.
func place(lots: Array[Dictionary], parent: Node, defs: Array = []) -> Array[Location]:
	var placed: Array[Location] = []
	for entry in plan(lots, defs):
		placed.append(Locations.spawn(entry["def"], entry["transform"], parent, entry["instance_id"]))
	return placed


## Pure layout: [{def, transform, instance_id, district_id}] for [param lots] (as recorded by
## CityGenerator.building_lots). [param defs] defaults to every LocationDef in ContentDB.
func plan(lots: Array[Dictionary], defs: Array = []) -> Array[Dictionary]:
	_rng.seed = placement_seed
	_counts.clear()
	_district_counts.clear()
	var candidates: Array[LocationDef] = []
	for def: LocationDef in (defs if not defs.is_empty() else ContentDB.all(LocationDef.TYPE)):
		if def.auto_place and not skip_kinds.has(def.kind) and def.spawn_weight >= 0.0:
			candidates.append(def)
	var free: Array[Dictionary] = []
	for lot in lots:
		var entry := lot.duplicate()
		entry["district_id"] = Locations.resolve_district(door_transform(lot).origin)
		free.append(entry)
	_shuffle(free)

	var result: Array[Dictionary] = []
	for def in candidates:
		var wanted := 1 if def.unique else def.min_count
		for i in wanted:
			_try_place(def, free, result)
	var target := int(float(lots.size()) * density)
	var fillers := candidates.filter(func(def: LocationDef) -> bool: return not def.unique and def.spawn_weight > 0.0)
	var guard := lots.size() * 4
	while result.size() < target and not free.is_empty() and not fillers.is_empty() and guard > 0:
		guard -= 1
		var def: LocationDef = _pick(fillers)
		if not _try_place(def, free, result):
			fillers.erase(def)
	return result

## Door transform for a lot: on the face pointing away from the block centre (toward the road),
## +Z facing the street.
static func door_transform(lot: Dictionary) -> Transform3D:
	var center: Vector3 = lot["center"]
	var footprint: Vector2 = lot["footprint"]
	var block_center: Vector3 = lot.get("block_center", center)
	var away := center - block_center
	var outward := Vector3.BACK
	if absf(away.x) > 0.5 or absf(away.z) > 0.5:
		outward = Vector3(signf(away.x), 0.0, 0.0) if absf(away.x) >= absf(away.z) else Vector3(0.0, 0.0, signf(away.z))
	var half := footprint.x * 0.5 if outward.x != 0.0 else footprint.y * 0.5
	var origin := Vector3(center.x, 0.0, center.z) + outward * (half + 0.15)
	return Transform3D(Basis.looking_at(-outward), origin)


func _try_place(def: LocationDef, free: Array[Dictionary], result: Array[Dictionary]) -> bool:
	if def.unique and _counts.get(def.id, 0) > 0:
		return false
	if def.max_count >= 0 and _counts.get(def.id, 0) >= def.max_count:
		return false
	for i in free.size():
		var lot := free[i]
		var district: StringName = lot["district_id"]
		if not def.district_ids.is_empty() and not def.district_ids.has(district):
			continue
		var key := "%s@%s" % [def.id, district]
		if def.max_per_district >= 0 and _district_counts.get(key, 0) >= def.max_per_district:
			continue
		free.remove_at(i)
		_counts[def.id] = _counts.get(def.id, 0) + 1
		_district_counts[key] = _district_counts.get(key, 0) + 1
		var instance_id := def.id if def.unique else StringName("%s_%d" % [def.id, _counts[def.id]])
		result.append({"def": def, "transform": door_transform(lot), "instance_id": instance_id, "district_id": district})
		return true
	return false


func _pick(defs: Array) -> LocationDef:
	var total := 0.0
	for def: LocationDef in defs:
		total += def.spawn_weight
	var roll := _rng.randf() * total
	for def: LocationDef in defs:
		roll -= def.spawn_weight
		if roll <= 0.0:
			return def
	return defs.back()


func _shuffle(items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var swap: Variant = items[i]
		items[i] = items[j]
		items[j] = swap
