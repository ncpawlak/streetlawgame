extends Node
## Screenshot tool for the companion showcase. Run windowed:
##   godot --path . res://tools/capture_companions.tscn -- <output_dir>
## Saves Pedro leading the player to his car and riding shotgun, the crew fight and the crew seated
## in the player's car, then for every vehicle class a passenger mid-boarding and the full row seated.

const SHOWCASE := preload("res://scenes/companions/companion_showcase.tscn")

var _cam: Camera3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else "user://companion_shots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var show: Node3D = SHOWCASE.instantiate()
	show.set("capture_mouse", false)
	show.set("auto_start_lead", false)
	add_child(show)
	var player := show.get_node("Player") as Player
	(show.get_node("HUD") as CanvasLayer).visible = false
	_cam = Camera3D.new()
	_cam.fov = 55.0
	add_child(_cam)
	await _frames(90)
	_cam.make_current()

	# Pedro leads, the player tags along a few metres behind.
	var pedro: Ally = show.pedro
	var car: Vehicle = show.pedro_car
	show.start_lead()
	for i in 600:
		if pedro.current_vehicle == car or pedro.is_busy():
			break
		var back := Ally._flat(player.global_position - pedro.global_position)
		if back.length() > 5.0:
			player.global_position = pedro.global_position + back.normalized() * 4.0 + Vector3.UP * 0.1
		if i == 90:
			_cam.look_at_from_position(pedro.global_position + Vector3(-6.0, 3.0, -6.0), pedro.global_position + Vector3(0.0, 1.0, 4.0))
			await _shot(out_dir.path_join("lead_follow_me.png"))
		await _frames(1)
	await _frames(20)
	_look_at_seat(car, 1, 4.5, 2.0)
	await _shot(out_dir.path_join("lead_pedro_boarding.png"))
	for i in 600:
		if pedro.current_vehicle == car and not pedro.is_busy():
			break
		await _frames(1)
	car.enter(player)
	await _frames(45)
	_look_at_seat(car, 0, 5.0, 2.2)
	await _shot(out_dir.path_join("lead_player_getting_in.png"))
	for i in 300:
		if player.current_vehicle == car and not player.is_busy():
			break
		await _frames(1)
	await _frames(20)
	_look_at_seat(car, 1, 4.0, 1.6)
	await _shot(out_dir.path_join("lead_driving_with_pedro.png"))

	# Crew fight, then everyone piles into the car.
	show.start_fight()
	show._go_to_station(show.FIGHT_ORIGIN + Vector3(0.0, 0.0, -4.0))
	await _frames(150)
	_cam.look_at_from_position(show.FIGHT_ORIGIN + Vector3(10.0, 6.0, -10.0), show.FIGHT_ORIGIN + Vector3(0.0, 0.5, 14.0))
	await _shot(out_dir.path_join("crew_fight.png"))
	for rival: GangMember in show.rivals:
		if is_instance_valid(rival) and rival.is_alive():
			rival.take_damage(9999.0, player)
	await _frames(60)
	var ride: Vehicle = show.fight_car
	player.global_position = ride.global_position + ride.global_basis.x * 3.0 + Vector3.UP * 0.2
	await _frames(5)
	ride.enter(player)
	await _frames(70)
	_cam.look_at_from_position(ride.global_position + ride.global_basis * Vector3(-7.0, 3.5, 5.0), ride.global_position + Vector3.UP)
	await _shot(out_dir.path_join("crew_auto_boarding.png"))
	for i in 900:
		if Party.members.all(func(a: Ally) -> bool: return a.current_vehicle == ride and not a.is_busy()):
			break
		await _frames(1)
	await _frames(20)
	_cam.look_at_from_position(ride.global_position + ride.global_basis * Vector3(-4.5, 2.6, 3.0), ride.global_position + Vector3.UP * 0.9)
	await _shot(out_dir.path_join("crew_seated.png"))
	ride.exit_seat(player)

	# Every class: one passenger climbs out and back in (mid-boarding shot), then the seated row.
	var row_vehicles: Array[Vehicle] = []
	for node in show.get_children():
		if node is Vehicle and node != car and node != ride:
			row_vehicles.append(node)
	player.global_position = show.ROW_ORIGIN + Vector3(-25.0, 0.2, -10.0)
	for vehicle in row_vehicles:
		var rider := vehicle.occupant(1) as Ally
		if rider == null:
			continue
		vehicle.exit_seat(rider)
		await _frames(10)
		rider.enter_vehicle(vehicle, 1)
		for i in 240:
			if rider.is_busy():
				break
			await _frames(1)
		await _frames(30)
		var id := String(vehicle.get("model_id") if vehicle.get("model_id") != null else vehicle.get_meta("model_id", vehicle.name))
		_look_at_seat(vehicle, 1, 4.5, 2.0)
		await _shot(out_dir.path_join("boarding_%s.png" % id.to_lower()))
		for i in 300:
			if rider.current_vehicle == vehicle and not rider.is_busy():
				break
			await _frames(1)
		await _frames(15)
		_look_at_seat(vehicle, 1, 5.5, 2.6)
		await _shot(out_dir.path_join("seated_%s.png" % id.to_lower()))
	var first := row_vehicles[0].global_position
	var last := row_vehicles[-1].global_position
	_cam.look_at_from_position(first.lerp(last, 0.5) + Vector3(-45.0, 30.0, 0.0), first.lerp(last, 0.5))
	await _shot(out_dir.path_join("row_overview.png"))
	get_tree().quit()


## Camera outside [param seat]'s door, looking at the seat.
func _look_at_seat(vehicle: Vehicle, seat: int, distance: float, height: float) -> void:
	var info := vehicle.seat_info(seat)
	var hip: Vector3 = vehicle.global_transform * (info.get("hip", Vector3.ZERO) as Vector3)
	var stand: Vector3 = vehicle.global_transform * (info.get("stand", Vector3.ZERO) as Vector3)
	var out := Ally._flat(stand - vehicle.global_position).normalized()
	if out == Vector3.ZERO:
		out = vehicle.global_basis.x
	var ahead := vehicle.global_basis.z * 0.35 * distance
	_cam.look_at_from_position(hip + out * distance + ahead + Vector3.UP * height, hip)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _shot(path: String) -> void:
	_cam.make_current()
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
