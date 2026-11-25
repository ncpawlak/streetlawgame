extends Node
## Screenshot tool for the house kit. Run windowed:
##   godot --path . res://tools/capture_houses.tscn -- <output_dir> [house ids...]
## Saves street overviews (houses and the business block) plus a close-up of each listed house /
## business (e.g. 1F_02, B_01, S_03) with the player standing in front for scale. Shop ids also
## get an "inside" shot looking from the doorway toward the ShopCounter.

const SHOWCASE := preload("res://scenes/houses/house_showcase.tscn")


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else "user://house_shots"
	var ids := args.slice(1) if args.size() > 1 else PackedStringArray(["1F_02", "1F_04", "1F_07", "2F_03", "2F_05", "2F_07", "B_01", "B_03", "B_04", "B_05", "S_01", "S_03", "S_05", "S_07"])
	DirAccess.make_dir_recursive_absolute(out_dir)
	var street: Node3D = SHOWCASE.instantiate()
	street.set("spawn_cars", true)
	add_child(street)
	var player := street.get_node("Player") as Node3D
	player.set_physics_process(false)
	var cam := Camera3D.new()
	cam.fov = 60.0
	add_child(cam)
	for i in 10:
		await get_tree().process_frame
	cam.make_current()
	var houses := street.get_node("Houses")
	var first: Node3D = houses.get_child(0)
	var row_center := Vector3(0, 0, first.global_position.z)
	cam.look_at_from_position(row_center + Vector3(-60, 28, 40), row_center + Vector3(-15, 0, -10))
	await _shot(out_dir.path_join("street_north.png"))
	cam.look_at_from_position(Vector3(40, 28, -40), Vector3(10, 0, 15))
	await _shot(out_dir.path_join("street_south.png"))
	cam.look_at_from_position(Vector3(-150, 60, 0), Vector3(-40, 0, 0))
	await _shot(out_dir.path_join("street_long.png"))
	var businesses := street.get_node("Businesses")
	var bx := 0.0
	for n: Node3D in businesses.get_children():
		bx += n.global_position.x / businesses.get_child_count()
	cam.look_at_from_position(Vector3(bx - 70, 40, 55), Vector3(bx - 10, 0, 0))
	await _shot(out_dir.path_join("street_businesses.png"))
	cam.look_at_from_position(Vector3(bx + 70, 40, -55), Vector3(bx + 10, 0, 0))
	await _shot(out_dir.path_join("street_businesses_back.png"))
	var buildings := street.get_node_or_null("Buildings")
	if buildings:
		await _row_shots(cam, buildings.get_children(), 5, out_dir, "street2")
	var variants := street.get_node_or_null("Variants")
	if variants:
		await _row_shots(cam, variants.get_children(), 4, out_dir, "variants")
	var gallery := street.get_node_or_null("FloridaGallery") as Node3D
	if gallery:
		var gx0 := INF
		var gx1 := -INF
		for n in gallery.get_children():
			if n is KitProp and (n as KitProp).mount == "ground":
				gx0 = minf(gx0, (n as Node3D).global_position.x)
				gx1 = maxf(gx1, (n as Node3D).global_position.x)
		var steps := maxi(1, ceili((gx1 - gx0) / 40.0))
		for i in steps + 1:
			var x := lerpf(gx0, gx1, float(i) / steps)
			cam.look_at_from_position(Vector3(x - 6, 14, 20), Vector3(x + 4, 0, -10))
			await _shot(out_dir.path_join("gallery_north_%d.png" % i))
			cam.look_at_from_position(Vector3(x + 6, 14, -20), Vector3(x - 4, 0, 10))
			await _shot(out_dir.path_join("gallery_south_%d.png" % i))
	var furniture := street.get_node_or_null("StreetFurniture/bus_shelter") as Node3D
	if furniture:
		var p := furniture.global_position
		player.global_position = p + Vector3(3, 0.0, -1)
		cam.look_at_from_position(p + Vector3(-22, 7, 9), p + Vector3(6, 3, -2))
		await _shot(out_dir.path_join("street_power_lines.png"))
	for id in ids:
		var house: Node3D = null
		for group: Node in [houses, businesses, buildings]:
			if group and not house:
				house = group.get_node_or_null(NodePath(id)) as Node3D
		if house == null:
			continue
		var lot: Vector2 = house.get("lot_size")
		var b := house.global_transform.basis
		var o := house.global_position
		player.global_position = o + b * Vector3(-1.5, 0.06, 1.2)
		player.global_rotation = Vector3(0, house.global_rotation.y + PI, 0)
		var target := o + b * Vector3(0, 3.0, -lot.y * 0.45)
		var dist := clampf(lot.x * 0.55, 11.0, 22.0)
		var height := 4.5 + dist * 0.15 + maxf(0.0, lot.x - 40.0) * 0.4
		if dist > 13.0:
			# Past the 13 m street the camera sits over the opposite lot; rise above its roofs.
			height = maxf(height, 15.0)
		cam.look_at_from_position(o + b * Vector3(minf(lot.x * 0.35, 12.0), height, dist), target)
		await _shot(out_dir.path_join("%s_%s.png" % ["house" if house.get("bedrooms") != null else "business", id]))
		var entrance := house.get_node_or_null("Entrance") as Node3D
		var counter := house.get_node_or_null("ShopCounter") as Node3D
		if entrance and counter:
			player.global_position = counter.global_position + Vector3(0, -0.94, 0)
			var eye := entrance.global_position - entrance.global_transform.basis.z * 1.6 + Vector3(0, 1.6, 0)
			cam.look_at_from_position(eye, counter.global_position + Vector3(0, 0.2, 0))
			await _shot(out_dir.path_join("inside_%s.png" % id))
	get_tree().quit()


## Shoots a row of placed buildings in chunks of `per_shot`, from the street side of each chunk.
func _row_shots(cam: Camera3D, nodes: Array[Node], per_shot: int, out_dir: String, prefix: String) -> void:
	var sides := {}
	for n: Node3D in nodes:
		var key := "n" if n.global_transform.basis.z.z < 0.0 else "s"
		if not sides.has(key):
			sides[key] = []
		sides[key].append(n)
	for key: String in sides:
		var row: Array = sides[key]
		row.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.global_position.x < b.global_position.x)
		var shot := 0
		for i in range(0, row.size(), per_shot):
			var chunk := row.slice(i, i + per_shot)
			var lo: Vector3 = chunk[0].global_position
			var hi: Vector3 = chunk[-1].global_position
			var front: Vector3 = chunk[0].global_transform.basis.z
			var center := (lo + hi) * 0.5 - front * 12.0
			var span := maxf(40.0, absf(hi.x - lo.x) + 30.0)
			# Stay over the street: the far side of the road can hold tall, deep buildings.
			cam.look_at_from_position(center + front * 26.0 + Vector3(-span * 0.1, span * 0.5, 0), center)
			shot += 1
			await _shot(out_dir.path_join("%s_%s%d.png" % [prefix, key, shot]))


func _shot(path: String) -> void:
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
