extends Node
## Renders reference screenshots of the appearance system: a looks line-up (calibrates hats /
## facial hair / accessories), before / after disguise, the clothing store UI and the barber chair.
## Usage: godot --path . res://tools/capture_appearance.tscn -- <output_dir>

var _out := "user://"
var _cam: Camera3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	_go.call_deferred()


func _go() -> void:
	get_window().size = Vector2i(1280, 720)
	var show: Node3D = load("res://scenes/showcase/appearance_showcase.tscn").instantiate()
	add_child(show)
	var player: Player = show.get("player")
	await _wait(1.0)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	show.add_child(_cam)

	await _lineup(show)

	player.global_position = Vector3(0.0, 0.0, 4.0)
	player.rotation.y = 0.0
	await _wait(0.4)
	_frame(player.global_position, 2.6)
	await _shot("look_before.png")

	show.get("store_station").perform(AppearanceStation.ACTION, player)
	var panel := PlayerAppearance.panel()
	panel.select(&"varsity_jacket", 1)
	await _wait(0.6)
	await _shot("store_ui.png")
	panel.confirm()
	panel.close()

	show.get("barber_station").perform(AppearanceStation.ACTION, player)
	panel.select(&"buzz_cut")
	panel.confirm()
	panel.select_slot(&"hair_color")
	panel.select(&"hair_dye", 4)
	panel.confirm()
	panel.select_slot(&"hair")
	panel.select(&"mohawk")
	await _wait(0.6)
	await _shot("barber_chair.png")
	panel.close()

	PlayerAppearance.grant(&"tee", 5)
	PlayerAppearance.equip(&"top", &"tee", 5)
	PlayerAppearance.grant(&"beanie", 1)
	PlayerAppearance.equip(&"hat", &"beanie", 1)
	player.global_position = Vector3(0.0, 0.0, 34.0)
	player.rotation.y = 0.0
	await _wait(1.5)
	_cam.make_current()
	_cam.look_at_from_position(Vector3(3.0, 2.6, 30.5), Vector3(0.0, 1.0, 38.0))
	await _wait(0.3)
	await _shot("look_after_disguised.png")
	_frame(player.global_position, 2.6)
	await _shot("look_after_closeup.png")
	get_tree().quit()


## Six looks side by side, front and back, to check the attachments sit right.
func _lineup(show: Node3D) -> void:
	var looks: Array[Dictionary] = [
		{},
		{"top": ["varsity_jacket", 1], "hat": ["cap", 1], "hair": ["buzz_cut", 0], "accessory": ["chain", 0]},
		{"top": ["punk_jacket", 4], "bottom": ["punk_pants", 0], "shoes": ["boots", 0], "hat": ["head_bandana", 3], "facial_hair": ["beard", 0]},
		{"top": ["suit_jacket", 0], "bottom": ["slacks", 0], "shoes": ["dress_shoes", 0], "hair": ["slick_back", 0], "accessory": ["sunglasses", 0], "facial_hair": ["moustache", 0]},
		{"top": ["tank_top", 2], "bottom": ["shorts", 1], "shoes": ["sandals", 0], "hat": ["backwards_cap", 0], "hair": ["mohawk", 0], "facial_hair": ["goatee", 0]},
		{"top": ["tee", 5], "hat": ["beanie", 1], "hair": ["curls", 0], "hair_color": ["hair_dye", 3]},
	]
	var stage := Node3D.new()
	stage.position = Vector3(0.0, 0.0, -30.0)
	show.add_child(stage)
	for i in looks.size():
		var look := Appearance.default_look()
		for slot: String in looks[i]:
			look.set_slot(StringName(slot), StringName(looks[i][slot][0]), looks[i][slot][1])
		var visual := CharacterVisual.create(&"player", 0)
		visual.position = Vector3(i * 1.3 - 3.25, 0.0, 0.0)
		stage.add_child(visual)
		visual.apply_appearance(look)
	_cam.make_current()
	_cam.look_at_from_position(stage.position + Vector3(0.0, 1.5, -8.5), stage.position + Vector3(0.0, 1.0, 0.0))
	await _wait(0.5)
	await _shot("looks_lineup.png")
	_cam.look_at_from_position(stage.position + Vector3(0.0, 1.65, -3.0), stage.position + Vector3(0.0, 1.5, 0.0))
	await _wait(0.2)
	await _shot("looks_heads.png")
	_cam.look_at_from_position(stage.position + Vector3(0.0, 1.5, 8.5), stage.position + Vector3(0.0, 1.0, 0.0))
	await _wait(0.2)
	await _shot("looks_lineup_back.png")
	stage.queue_free()


## Close-up of a character facing -Z.
func _frame(at: Vector3, distance: float) -> void:
	_cam.make_current()
	_cam.look_at_from_position(at + Vector3(0.6, 1.5, -distance), at + Vector3(0.0, 1.05, 0.0))


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _out.path_join(file)
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
