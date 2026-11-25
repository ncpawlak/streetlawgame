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
	for id in ids:
		var house := houses.get_node_or_null(NodePath(id)) as Node3D
		if house == null:
			house = businesses.get_node_or_null(NodePath(id)) as Node3D
		if house == null:
			continue
		var lot: Vector2 = house.get("lot_size")
		var b := house.global_transform.basis
		var o := house.global_position
		player.global_position = o + b * Vector3(-1.5, 0.06, 1.2)
		player.global_rotation = Vector3(0, house.global_rotation.y + PI, 0)
		var target := o + b * Vector3(0, 3.0, -lot.y * 0.45)
		var dist := maxf(11.0, lot.x * 0.55)
		cam.look_at_from_position(o + b * Vector3(lot.x * 0.35, 4.5 + dist * 0.15, dist), target)
		await _shot(out_dir.path_join("%s_%s.png" % ["house" if house.get("bedrooms") != null else "business", id]))
		var entrance := house.get_node_or_null("Entrance") as Node3D
		var counter := house.get_node_or_null("ShopCounter") as Node3D
		if entrance and counter:
			player.global_position = counter.global_position + Vector3(0, -0.94, 0)
			var eye := entrance.global_position - entrance.global_transform.basis.z * 1.6 + Vector3(0, 1.6, 0)
			cam.look_at_from_position(eye, counter.global_position + Vector3(0, 0.2, 0))
			await _shot(out_dir.path_join("inside_%s.png" % id))
	get_tree().quit()


func _shot(path: String) -> void:
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
