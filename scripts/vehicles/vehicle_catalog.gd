class_name VehicleCatalog
extends RefCounted
## Read-only access to the vehicle registry (data/vehicles/vehicles.json, written by
## tools/vehicles/build_vehicles.py). Traffic, carjacking and population code can pick models by
## class, zone, income tier or stealability and spawn them with seeded paint.

const PATH := "res://data/vehicles/vehicles.json"

static var _data: Dictionary = {}
static var _by_id: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var text := FileAccess.get_file_as_string(PATH)
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			_data = parsed
			for entry: Dictionary in _data.get("vehicles", []):
				_by_id[StringName(entry["id"])] = entry
		else:
			push_error("VehicleCatalog: cannot read %s" % PATH)
	return _data


static func entries() -> Array:
	return data().get("vehicles", [])


static func ids() -> Array[StringName]:
	data()
	var result: Array[StringName] = []
	result.assign(_by_id.keys())
	return result


static func find(id: StringName) -> Dictionary:
	data()
	return _by_id.get(id, {})


static func classes() -> Dictionary:
	return data().get("classes", {})


## Entries matching every given filter (empty filter = any).
static func query(vehicle_class := "", zone := "", income_tier := "", stealable_only := false) -> Array:
	var result := []
	for entry: Dictionary in entries():
		if vehicle_class != "" and entry["class"] != vehicle_class:
			continue
		if zone != "" and not (entry["spawn_zones"] as Array).has(zone):
			continue
		if income_tier != "" and entry["income_tier"] != income_tier:
			continue
		if stealable_only and not entry["stealable"]:
			continue
		result.append(entry)
	return result


## [primary, trim] colours for a seed; the same seed always gives the same paint job.
static func paint_colors(id: StringName, seed_value: int) -> Array[Color]:
	var result: Array[Color] = []
	var entry := find(id)
	if entry.is_empty():
		return result
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(id, ":", seed_value))
	var palette: Array = entry["palette"]
	var trims: Array = entry["trim_palette"]
	var primary := Color(palette[rng.randi_range(0, palette.size() - 1)])
	primary = primary.lightened(rng.randf_range(-0.06, 0.08)) if rng.randf() < 0.5 else primary.darkened(rng.randf_range(0.0, 0.1))
	result.append(primary)
	result.append(Color(trims[rng.randi_range(0, trims.size() - 1)]))
	return result


## Instantiates a vehicle scene (not yet in the tree). [param seed_value] -1 keeps authored paint.
static func instantiate(id: StringName, seed_value := -1) -> Node3D:
	var entry := find(id)
	if entry.is_empty():
		push_error("VehicleCatalog: unknown vehicle %s" % id)
		return null
	var scene := load(entry["scene"]) as PackedScene
	var node := scene.instantiate() as Node3D
	if node is Vehicle:
		(node as Vehicle).paint_seed = seed_value
	return node
