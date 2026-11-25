extends RefCounted
## House exterior kit + stand-in business tests: all scenes load, metadata is sane, shells are
## solid and fit their lots, closed stand-ins are sealed and a player-sized capsule can walk into
## every shop.

const DIRS := {1: "res://scenes/houses/one_floor", 2: "res://scenes/houses/two_floor"}
const COUNTS := {1: 15, 2: 10}
const BIZ_DIRS := {false: "res://scenes/businesses/closed", true: "res://scenes/businesses/shops"}
const BIZ_COUNTS := {false: 5, true: 9}

var _runner: Node


func _init(runner: Node) -> void:
	_runner = runner


func run() -> void:
	for floors in DIRS:
		var files := Array(DirAccess.get_files_at(DIRS[floors])).filter(func(f: String) -> bool: return f.ends_with(".tscn"))
		_check(files.size() == COUNTS[floors], "%d %d-floor house scenes exist (found %d)" % [COUNTS[floors], floors, files.size()])
		var bad: Array[String] = []
		for file: String in files:
			var house := (load(DIRS[floors].path_join(file)) as PackedScene).instantiate() as HouseExterior
			if house == null:
				bad.append("%s: not a HouseExterior" % file)
				continue
			_runner.add_child(house)
			await _runner.get_tree().process_frame
			bad.append_array(_problems(house, floors, file))
			house.queue_free()
		_check(bad.is_empty(), "%d-floor houses are valid shells on their lots %s" % [floors, bad])
	for enterable in BIZ_DIRS:
		var files := Array(DirAccess.get_files_at(BIZ_DIRS[enterable])).filter(func(f: String) -> bool: return f.ends_with(".tscn"))
		var kind := "shops" if enterable else "closed businesses"
		_check(files.size() == BIZ_COUNTS[enterable], "%d %s scenes exist (found %d)" % [BIZ_COUNTS[enterable], kind, files.size()])
		var bad: Array[String] = []
		for file: String in files:
			var biz := (load(BIZ_DIRS[enterable].path_join(file)) as PackedScene).instantiate() as BusinessExterior
			if biz == null:
				bad.append("%s: not a BusinessExterior" % file)
				continue
			_runner.add_child(biz)
			await _runner.get_tree().process_frame
			bad.append_array(_biz_problems(biz, enterable, file))
			if enterable and biz.entrance():
				bad.append_array(await _walk_in(biz, file))
			biz.queue_free()
		_check(bad.is_empty(), "%s are valid commercial shells on their lots %s" % [kind, bad])


func _problems(house: HouseExterior, floors: int, file: String) -> Array[String]:
	var out: Array[String] = []
	if house.floors != floors:
		out.append("%s: floors=%d" % [file, house.floors])
	if floors == 1 and (house.bedrooms < 1 or house.bedrooms > 4 or house.bathrooms < 1 or house.bathrooms > 2):
		out.append("%s: %d bed / %d bath exceeds 4/2" % [file, house.bedrooms, house.bathrooms])
	if house.lot_type.is_empty():
		out.append("%s: no lot type" % file)
	var shell := house.get_node_or_null("House") as CSGCombiner3D
	if shell == null or not shell.use_collision:
		out.append("%s: House combiner missing or has no collision" % file)
		return out
	var meshes := shell.get_meshes()
	if meshes.size() < 2:
		out.append("%s: House CSG built no mesh" % file)
		return out
	var aabb := (meshes[0] as Transform3D) * (meshes[1] as Mesh).get_aabb()
	var lot := house.lot_rect().grow(0.05)
	if not (lot.has_point(Vector2(aabb.position.x, aabb.position.z)) and lot.has_point(Vector2(aabb.end.x, aabb.end.z))):
		out.append("%s: house %s spills outside lot %s" % [file, aabb, lot])
	var min_h := 4.0 if floors == 1 else 6.5
	if aabb.size.y < min_h:
		out.append("%s: only %.1f m tall" % [file, aabb.size.y])
	return out


func _biz_problems(biz: BusinessExterior, enterable: bool, file: String) -> Array[String]:
	var out: Array[String] = []
	if biz.enterable != enterable or biz.lot_type.is_empty() or biz.archetype.is_empty():
		out.append("%s: bad metadata" % file)
	if enterable and (biz.shop_type.is_empty() or biz.entrance() == null or biz.counter() == null):
		out.append("%s: shop needs shop_type, Entrance and ShopCounter" % file)
	if not enterable and (biz.entrance() != null or biz.counter() != null):
		out.append("%s: closed stand-in has an entrance" % file)
	var shell := biz.get_node_or_null("Building") as CSGCombiner3D
	if shell == null or not shell.use_collision:
		out.append("%s: Building combiner missing or has no collision" % file)
		return out
	var meshes := shell.get_meshes()
	if meshes.size() < 2:
		out.append("%s: Building CSG built no mesh" % file)
		return out
	var aabb := (meshes[0] as Transform3D) * (meshes[1] as Mesh).get_aabb()
	var lot := biz.lot_rect().grow(0.05)
	if not (lot.has_point(Vector2(aabb.position.x, aabb.position.z)) and lot.has_point(Vector2(aabb.end.x, aabb.end.z))):
		out.append("%s: building %s spills outside lot %s" % [file, aabb, lot])
	if aabb.size.y < 3.9:
		out.append("%s: only %.1f m tall" % [file, aabb.size.y])
	return out


## Drives a player-sized capsule (0.4 m radius, 1.8 m) from the Entrance marker through the door.
func _walk_in(biz: BusinessExterior, file: String) -> Array[String]:
	var body := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	shape.shape = capsule
	body.add_child(shape)
	biz.add_child(body)
	var marker := biz.entrance()
	var inward := -marker.basis.z
	body.position = marker.position + Vector3(0, 1.0, 0)
	var start := body.position
	for i in 90:
		body.velocity = inward * 4.0 + Vector3(0, -4.0, 0)
		body.move_and_slide()
		await _runner.get_tree().physics_frame
	var travelled := (body.position - start).dot(inward)
	body.queue_free()
	if travelled < 3.0:
		return ["%s: capsule only got %.1f m through the doorway" % [file, travelled]]
	return []


func _check(condition: bool, description: String) -> void:
	_runner._check(condition, description)
