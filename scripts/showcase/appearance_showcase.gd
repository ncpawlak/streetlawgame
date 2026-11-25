extends Node3D
## Player appearance showcase: a clothing store counter, a barber chair and a wardrobe next to an
## Angeles block (yellow / white) and a Hellraiser corner (black / orange). The Angeles know the
## starting look, so walk in, change top + hair (+ hat) and watch the readout and the gang flip from
## hostile to neutral, or wear their colours to be greeted as one of them.
## Run: godot --path . res://scenes/showcase/appearance_showcase.tscn

const STORE := Vector3(-10.0, 0.0, -6.0)
const BARBER := Vector3(0.0, 0.0, -6.0)
const WARDROBE := Vector3(10.0, 0.0, -6.0)
const ANGELES_BLOCK := Vector3(0.0, 0.0, 45.0)
const HELLRAISER_CORNER := Vector3(-40.0, 0.0, 30.0)

var members: Array[GangMember] = []
var store_station: AppearanceStation
var barber_station: AppearanceStation
var wardrobe: Wardrobe

var _readout: Label

@onready var player: Player = $Player


func _ready() -> void:
	PlayerAppearance.reset()
	GameState.add_cash(2500 - GameState.cash)
	_build_environment()
	_build_ground()
	_build_store()
	_build_barber()
	_build_wardrobe()
	_build_gang(&"angeles", ANGELES_BLOCK, 4)
	_build_gang(&"hellraisers", HELLRAISER_CORNER, 2)
	_build_readout()
	player.global_position = Vector3(0.0, 0.5, 4.0)
	player.spawn_point = player.global_position
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	EventBus.notify.emit.call_deferred("The Angeles (yellow/white, south) know your face. Change clothes and hair before walking up. [E] at the counter, chair or wardrobe.")


func _process(_delta: float) -> void:
	var lines := PackedStringArray(["$%d   look %s" % [GameState.cash, PlayerAppearance.signature()]])
	for faction: StringName in [&"angeles", &"hellraisers"]:
		lines.append("%s: %s   recognition %d%%   colours %d%%   disguised: %s" % [
			String(faction).capitalize(), PlayerAppearance.reaction_of(faction),
			roundi(PlayerAppearance.recognition(faction) * 100.0), roundi(PlayerAppearance.faction_affinity(faction) * 100.0),
			"yes" if PlayerAppearance.is_disguised_from(faction) else "no"])
	_readout.text = "\n".join(lines)


func _input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_ground() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(160.0, 1.0, 160.0)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	var mesh := VisualSpec.greybox(&"box", box.size, Color(0.42, 0.42, 0.4))
	mesh.position.y = -0.5
	floor_body.add_child(mesh)
	add_child(floor_body)
	var block := VisualSpec.greybox(&"box", Vector3(24.0, 0.05, 14.0), Color(0.75, 0.66, 0.3))
	block.position = ANGELES_BLOCK + Vector3(0.0, 0.03, 0.0)
	add_child(block)
	_sign("ANGELES BLOCK", ANGELES_BLOCK + Vector3(0.0, 4.0, -7.0), Color(0.98, 0.84, 0.2))
	_sign("HELLRAISERS", HELLRAISER_CORNER + Vector3(0.0, 4.0, -4.0), Color(0.95, 0.45, 0.08))


## A three-wall booth so the stations read as shops.
func _booth(at: Vector3, title: String, color: Color) -> void:
	var walls := [[Vector3(0.0, 1.5, -3.0), Vector3(7.0, 3.0, 0.3)], [Vector3(-3.5, 1.5, -0.5), Vector3(0.3, 3.0, 5.0)],
		[Vector3(3.5, 1.5, -0.5), Vector3(0.3, 3.0, 5.0)]]
	for wall: Array in walls:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = wall[1]
		shape.shape = box
		body.add_child(shape)
		body.add_child(VisualSpec.greybox(&"box", wall[1], color))
		body.position = at + (wall[0] as Vector3)
		add_child(body)
	_sign(title, at + Vector3(0.0, 3.6, -2.8), color.lightened(0.4))


func _build_store() -> void:
	_booth(STORE, "THREADS (clothing)", Color(0.35, 0.3, 0.5))
	var counter := VisualSpec.greybox(&"box", Vector3(2.4, 1.0, 0.6), Color(0.55, 0.4, 0.25))
	counter.position = STORE + Vector3(0.0, 0.5, -1.8)
	add_child(counter)
	store_station = AppearanceStation.new()
	store_station.mode = "clothing"
	store_station.prompt_name = "Threads"
	add_child(store_station)
	store_station.global_position = STORE + Vector3(0.0, 0.0, -0.8)
	# Faces out of the booth so the preview camera frames the player from the shop floor.
	store_station.rotation.y = PI


func _build_barber() -> void:
	_booth(BARBER, "FRESH CUTZ (barber)", Color(0.25, 0.45, 0.45))
	var chair := Node3D.new()
	chair.name = "BarberChair"
	add_child(chair)
	chair.position = BARBER + Vector3(0.0, 0.0, -1.4)
	var seat := VisualSpec.greybox(&"box", Vector3(0.8, 0.45, 0.8), Color(0.6, 0.1, 0.1))
	seat.position = Vector3(0.0, 0.22, 0.0)
	chair.add_child(seat)
	var back := VisualSpec.greybox(&"box", Vector3(0.8, 1.0, 0.15), Color(0.6, 0.1, 0.1))
	back.position = Vector3(0.0, 0.9, 0.45)
	chair.add_child(back)
	var mirror := VisualSpec.greybox(&"box", Vector3(1.6, 1.2, 0.05), Color(0.75, 0.85, 0.9))
	mirror.position = BARBER + Vector3(0.0, 1.7, -2.8)
	add_child(mirror)
	var anchor := Marker3D.new()
	anchor.name = "Anchor"
	chair.add_child(anchor)
	barber_station = AppearanceStation.new()
	barber_station.mode = "barber"
	barber_station.prompt_name = "Barber chair"
	add_child(barber_station)
	barber_station.global_position = chair.global_position + Vector3(0.0, 0.0, 1.0)
	barber_station.anchor_path = barber_station.get_path_to(anchor)


func _build_wardrobe() -> void:
	_booth(WARDROBE, "SAFEHOUSE WARDROBE", Color(0.4, 0.35, 0.28))
	var closet := VisualSpec.greybox(&"box", Vector3(1.6, 2.2, 0.6), Color(0.3, 0.22, 0.15))
	closet.position = WARDROBE + Vector3(0.0, 1.1, -2.5)
	add_child(closet)
	wardrobe = Wardrobe.new()
	add_child(wardrobe)
	wardrobe.global_position = WARDROBE + Vector3(0.0, 0.0, -1.4)
	wardrobe.rotation.y = PI


func _build_gang(gang: StringName, at: Vector3, count: int) -> void:
	for i in count:
		var member := GangMember.new()
		member.gang_id = gang
		member.wander_radius = 4.0
		member.position = at + Vector3((i - count * 0.5) * 2.5, 0.5, randf_range(-2.0, 2.0))
		add_child(member)
		members.append(member)


func _build_readout() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_readout = Label.new()
	_readout.position = Vector2(16.0, 160.0)
	_readout.add_theme_font_size_override(&"font_size", 16)
	_readout.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_readout.add_theme_constant_override(&"outline_size", 6)
	layer.add_child(_readout)
	get_tree().process_frame.connect(_sync_readout)


## Hidden while the appearance panel (which pauses the game) is up.
func _sync_readout() -> void:
	_readout.visible = not get_tree().paused


func _sign(text: String, at: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 64
	label.pixel_size = 0.01
	label.outline_size = 12
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = at
	add_child(label)


func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.35, 0.5, 0.75)
	sky_material.sky_horizon_color = Color(0.8, 0.65, 0.55)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
