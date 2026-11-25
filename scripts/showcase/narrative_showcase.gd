extends Node3D
## Narrative showcase (placeholder content): a hospital-bed wake-up cutscene, a talk-to-NPC with
## choices, an ambient barker and a delayed incoming phone call. Everything is built from the
## sample_* defs in data/ (regenerate with tools/build_narrative_samples.tscn).
##   Play:        godot --path . res://scenes/showcase/narrative_showcase.tscn
##   Screenshots: godot --path . res://scenes/showcase/narrative_showcase.tscn -- --capture <dir>
## Keys: E talk, hold Space skip, Y/N answer/decline, P contacts, C replay the cutscene, K ring now.

const CALL_DELAY := 6.0

var player: Player
var nurse: Node3D
var witness: Node3D
var thug: Node3D
var witness_talk: TalkTarget
var thug_barker: Barker
var dialogue_view: DialogueView
var _status: Label
var _call_handle := 0


func _ready() -> void:
	_build_world()
	player = preload("res://scenes/player/player.tscn").instantiate()
	player.position = Vector3(0.0, 0.1, 3.0)
	add_child(player)
	nurse = _npc("Nurse", &"civilian", 2, Vector3(-6.0, 0.0, 1.0))
	witness = _npc("Witness", &"civilian", 1, Vector3(3.0, 0.0, -1.0))
	thug = _npc("Thug", &"gang", 0, Vector3(6.0, 0.0, 4.0))
	thug.rotation.y = PI * 0.75

	witness_talk = TalkTarget.new()
	witness_talk.name = "Talk"
	witness_talk.display_name = "Witness"
	witness_talk.dialogue_id = &"sample_witness"
	witness.add_child(witness_talk)
	thug_barker = Barker.new()
	thug_barker.name = "Barker"
	thug_barker.lines = PackedStringArray(["Angeles block, homie. Keep walking.", "You lost?", "Heard you got shot. Shame they missed."])
	thug_barker.cooldown = 6.0
	thug.add_child(thug_barker)

	_build_ui()
	Narrative.director.finished.connect(_on_cutscene_finished)
	var args := OS.get_cmdline_user_args()
	var capture := args.find("--capture")
	if capture >= 0:
		_capture.call_deferred(args[capture + 1] if args.size() > capture + 1 else "user://")
	else:
		play_intro.call_deferred()


func _process(_delta: float) -> void:
	var phone := Narrative.phone
	var lines: PackedStringArray = []
	lines.append("Cutscene: %s" % (String(Narrative.director.current_id()) if Narrative.is_cutscene_playing() else "-"))
	lines.append("Phone: %s  pending %s  missed %s" % [PhoneService.State.keys()[phone.state], phone.pending_calls(), phone.missed_calls()])
	lines.append("Leads: %d   car lead: %s   woke up: %s" % [int(GameState.get_flag(&"sample_leads", 0)), GameState.get_flag(&"sample_car_lead", false), GameState.get_flag(&"sample_woke_up", false)])
	lines.append("E talk  ·  hold Space skip  ·  Y/N answer/decline  ·  P contacts  ·  C replay cutscene  ·  K ring now")
	_status.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).physical_keycode:
		KEY_C:
			play_intro()
		KEY_K:
			Narrative.phone.cancel(_call_handle)
			_call_handle = Narrative.phone.schedule_call(&"sample_lou_job", 0.0)


func play_intro() -> bool:
	return Narrative.play_cutscene(&"sample_wake_up", self, {&"Nurse": nurse})


func _on_cutscene_finished(cutscene_id: StringName, _skipped: bool) -> void:
	if cutscene_id == &"sample_wake_up" and Narrative.phone.pending_calls().is_empty() and not Narrative.phone.has_missed_from(&"sample_lou"):
		_call_handle = Narrative.phone.schedule_call(&"sample_lou_job", CALL_DELAY)


# --- Automated tour for screenshots ------------------------------------------------------------

func _capture(out_dir: String) -> void:
	get_window().size = Vector2i(1600, 900)
	DirAccess.make_dir_recursive_absolute(out_dir)
	await _seconds(0.5)
	play_intro()
	await _seconds(2.4)
	_shot(out_dir, "01_cutscene_wake_up")
	await _until(func() -> bool: return Narrative.ui.subtitle_text().contains("shoulder"), 15.0)
	await _seconds(0.5)
	_shot(out_dir, "02_cutscene_dialogue")
	await _until(func() -> bool: return not Narrative.ui.choice_labels().is_empty(), 15.0)
	await _seconds(0.3)
	_shot(out_dir, "03_cutscene_choice")
	Input.action_press(&"skip_cutscene")
	await _seconds(0.6)
	_shot(out_dir, "04_hold_to_skip")
	await _until(func() -> bool: return not Narrative.is_cutscene_playing(), 5.0)
	Input.action_release(&"skip_cutscene")
	await _seconds(0.5)
	_shot(out_dir, "05_skip_end_state")

	Narrative.phone.cancel(_call_handle)
	player.global_position = witness.global_position + Vector3(0.0, 0.1, 1.6)
	await _seconds(0.3)
	witness_talk.talk()
	await _seconds(0.8)
	_shot(out_dir, "06_talk_to_npc")
	dialogue_view.pick(0)
	await _seconds(0.8)
	_shot(out_dir, "07_talk_next_line")
	dialogue_view.runner.end()
	await _seconds(0.6)

	player.global_position = thug.global_position + Vector3(-2.0, 0.1, -2.0)
	thug_barker.trigger()
	await _seconds(0.4)
	_shot(out_dir, "08_bark")

	Narrative.phone.schedule_call(&"sample_lou_job", 0.0)
	await _until(Narrative.phone.is_ringing, 5.0)
	await _seconds(0.4)
	_shot(out_dir, "09_phone_ringing")
	Narrative.phone.answer()
	await _seconds(1.2)
	_shot(out_dir, "10_phone_call")
	Narrative.phone.hang_up()
	Narrative.phone.schedule_call(&"sample_lou_job", 0.0)
	await _until(Narrative.phone.is_ringing, 5.0)
	Narrative.phone.decline()
	await _seconds(0.3)
	Narrative.ui.phone_view.open_contacts()
	await _seconds(0.4)
	_shot(out_dir, "11_contacts_missed_call")
	get_tree().quit()


func _shot(out_dir: String, shot_name: String) -> void:
	var path := out_dir.path_join(shot_name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("captured ", path)


func _seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _until(predicate: Callable, timeout: float) -> void:
	var left := timeout
	while not predicate.call() and left > 0.0:
		await get_tree().process_frame
		left -= get_process_delta_time()


# --- Set dressing ------------------------------------------------------------------------------

func _npc(npc_name: String, kind: StringName, variant: int, at: Vector3) -> Node3D:
	var npc := Node3D.new()
	npc.name = npc_name
	npc.position = at
	add_child(npc)
	var visual := CharacterVisual.create(kind, variant)
	visual.name = "Visual"
	npc.add_child(visual)
	return npc


func _build_world() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.16, 0.18, 0.22)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.75, 0.78, 0.85)
	environment.environment.ambient_light_energy = 0.6
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	_box(self, "Floor", Vector3(40.0, 0.2, 40.0), Vector3(0.0, -0.1, 0.0), Color(0.55, 0.57, 0.6), true)
	# Ward corner: bed, curtain, markers for the wake-up cutscene.
	_box(self, "BedFrame", Vector3(1.1, 0.5, 2.2), Vector3(-4.0, 0.25, -3.0), Color(0.85, 0.87, 0.9), true)
	_box(self, "Pillow", Vector3(0.7, 0.12, 0.4), Vector3(-4.0, 0.56, -3.85), Color.WHITE, false)
	_box(self, "Curtain", Vector3(0.05, 2.2, 3.0), Vector3(-5.4, 1.1, -3.0), Color(0.45, 0.65, 0.7), true)
	_box(self, "WardWall", Vector3(6.0, 3.0, 0.2), Vector3(-4.0, 1.5, -4.6), Color(0.7, 0.8, 0.78), true)
	# Bed marker sits at the foot of the mattress; the lying pose's head points toward the pillow.
	_marker("Bed", Vector3(-4.0, 0.0, -2.1), 0.0)
	_marker("BedSide", Vector3(-2.9, 0.05, -2.6), -90.0)
	_marker("NurseStart", Vector3(-1.0, 0.0, 2.0), 0.0)
	_marker("NurseMark", Vector3(-3.0, 0.0, -1.6), 0.0)
	_camera_marker("CamClose", Vector3(-3.0, 1.9, -1.3), Vector3(-4.0, 0.7, -3.4))
	_camera_marker("CamWide", Vector3(0.5, 2.6, 2.0), Vector3(-3.5, 0.8, -2.5))


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ShowcaseUI"
	add_child(layer)
	dialogue_view = DialogueView.new()
	layer.add_child(dialogue_view)
	_status = Label.new()
	_status.position = Vector2(16.0, 12.0)
	_status.add_theme_font_size_override(&"font_size", 15)
	_status.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_status.add_theme_constant_override(&"outline_size", 4)
	layer.add_child(_status)
	# The status overlay is "HUD": cutscenes hide it like the game HUD.
	Narrative.hud_visibility_changed.connect(func(shown: bool) -> void: _status.visible = shown)


func _marker(marker_name: String, at: Vector3, yaw_degrees: float) -> Marker3D:
	var marker := Marker3D.new()
	marker.name = marker_name
	marker.position = at
	marker.rotation_degrees.y = yaw_degrees
	add_child(marker)
	return marker


func _camera_marker(marker_name: String, at: Vector3, look: Vector3) -> Marker3D:
	var marker := _marker(marker_name, at, 0.0)
	marker.look_at_from_position(at, look)
	return marker


func _box(parent: Node, box_name: String, size: Vector3, at: Vector3, color: Color, solid: bool) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = box_name
	var box := BoxMesh.new()
	box.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	box.material = material
	mesh.mesh = box
	mesh.position = at
	parent.add_child(mesh)
	if solid:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		(shape.shape as BoxShape3D).size = size
		body.add_child(shape)
		mesh.add_child(body)
