extends Node
## Narrative presentation hub (autoload "Narrative"): input lock and HUD hiding shared by cutscenes,
## conversations and scripted scenes; talk-to-NPC camera framing; ambient barks; subtitles; voice
## playback; story events. Owns the [CutsceneDirector] ([member director]), the [PhoneService]
## ([member phone]) and the overlay UI ([member ui]). See README "Cutscenes, dialogue & phone".

signal input_lock_changed(locked: bool)
signal hud_visibility_changed(visible: bool)
signal story_event(event: StringName, payload: Dictionary)

const BARK_DURATION := 3.0
## A speaker can't be re-barked sooner than this unless forced.
const BARK_COOLDOWN := 0.75

var director: CutsceneDirector
var phone: PhoneService
var ui: NarrativeUI
## Registered by the HUD's DialogueView.
var dialogue_view: DialogueView

var _input_locks := {}
var _hud_hides := {}
var _talk_camera: Camera3D
var _talk_previous_camera: Camera3D
var _talk_tween: Tween
var _talk: Dictionary = {}
var _voice: AudioStreamPlayer
## speaker instance id -> {"label": Label3D, "node": Node3D, "left": float, "age": float}
var _barks := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ui = NarrativeUI.new()
	ui.name = "UI"
	add_child(ui)
	director = CutsceneDirector.new()
	director.name = "Director"
	add_child(director)
	phone = PhoneService.new()
	phone.name = "Phone"
	add_child(phone)
	ui.phone_view.service = phone
	_voice = AudioStreamPlayer.new()
	_voice.name = "Voice"
	add_child(_voice)
	_talk_camera = Camera3D.new()
	_talk_camera.name = "TalkCamera"
	_talk_camera.cull_mask &= ~GameState.MAP_LAYER
	add_child(_talk_camera)


func _input(event: InputEvent) -> void:
	if not is_input_locked() or get_tree().paused:
		return
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion \
			or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_update_barks(delta)


# --- Input lock / HUD -------------------------------------------------------------------------

## Blocks player control (movement, camera, weapons, interaction, driving) until every reason is
## unlocked. Reasons let a cutscene and a conversation overlap safely.
func lock_input(reason: StringName) -> void:
	var was := is_input_locked()
	_input_locks[reason] = true
	if not was:
		input_lock_changed.emit(true)


func unlock_input(reason: StringName) -> void:
	if not _input_locks.erase(reason):
		return
	if not is_input_locked():
		input_lock_changed.emit(false)


func is_input_locked() -> bool:
	return not _input_locks.is_empty()


func hide_hud(reason: StringName) -> void:
	var was := is_hud_visible()
	_hud_hides[reason] = true
	if was:
		hud_visibility_changed.emit(false)


func show_hud(reason: StringName) -> void:
	if not _hud_hides.erase(reason):
		return
	if is_hud_visible():
		hud_visibility_changed.emit(true)


func is_hud_visible() -> bool:
	return _hud_hides.is_empty()


func is_cutscene_playing() -> bool:
	return director.is_playing()


## True while anything owns the player's attention (cutscene, conversation, phone call).
func is_busy() -> bool:
	return is_cutscene_playing() or is_talking() or phone.in_call() or (dialogue_view != null and dialogue_view.is_open())


# --- Cutscenes ---------------------------------------------------------------------------------

## Plays a CutsceneDef (or its id). See CutsceneDirector.play().
func play_cutscene(cutscene: Variant, stage: Node = null, bindings: Dictionary = {}, ctx: ActionContext = null) -> bool:
	var def: CutsceneDef = cutscene if cutscene is CutsceneDef else ContentDB.find_def(CutsceneDef.TYPE, StringName(str(cutscene))) as CutsceneDef
	if def == null:
		push_warning("Narrative: unknown cutscene %s" % [cutscene])
		return false
	return director.play(def, stage, bindings, ctx)


# --- Story events, voice, subtitles ------------------------------------------------------------

## Fires a named story event (e.g. &"lead_added" with {"id": &"shooter_car"}). Missions, objectives
## and quest logs listen on EventBus.story_event.
func emit_event(event: StringName, payload: Dictionary = {}) -> void:
	story_event.emit(event, payload)
	EventBus.story_event.emit(event, payload)


func play_voice(stream: AudioStream) -> void:
	if stream == null:
		return
	_voice.stream = stream
	_voice.play()


## Shows a subtitle line; [param duration] 0 = from the word count.
func subtitle(speaker: String, text: String, duration := 0.0, color := NarrativeUI.SPEAKER_COLOR) -> void:
	ui.show_line(speaker, text, duration if duration > 0.0 else DialogueNode.auto_duration(text), color)


# --- Talk to NPC -------------------------------------------------------------------------------

## Starts a face-to-face conversation with [param npc] (talk-to-NPC flow): turns both to face each
## other, frames the camera on whoever speaks (shot / reverse shot) and opens the DialogueView.
## [param options]: "frame_camera" (true), "face" (true), "pause" (true), "speakers" ({id: Node}),
## "ctx" (ActionContext to reuse), "actor" (defaults to the player).
func talk(npc: Node3D, dialogue: DialogueDef, options: Dictionary = {}) -> bool:
	if npc == null or dialogue == null or dialogue_view == null or dialogue_view.is_open() or is_cutscene_playing():
		return false
	var actor: Node3D = options.get("actor", GameState.player)
	var ctx: ActionContext = options.get("ctx", null)
	if ctx == null:
		ctx = ActionContext.new(actor, npc)
		ctx.occupant = npc
	var speakers: Dictionary = ctx.vars.get("speakers", {}).duplicate()
	speakers.merge(options.get("speakers", {}), true)
	if not speakers.has(&"npc"):
		speakers[&"npc"] = npc
	if actor != null and not speakers.has(&"player"):
		speakers[&"player"] = actor
	ctx.vars["speakers"] = speakers
	if options.has("pause"):
		ctx.vars["dialogue_pause"] = options["pause"]
	if options.get("face", true) and actor != null:
		face_toward(npc, actor.global_position)
		face_toward(actor, npc.global_position)
	_talk = {"npc": npc, "actor": actor, "frame": options.get("frame_camera", true)}
	dialogue_view.runner.node_entered.connect(_on_talk_node)
	dialogue_view.runner.ended.connect(_on_talk_ended)
	if not dialogue_view.open(dialogue, ctx) or not dialogue_view.is_open():
		_end_talk()
		return false
	_on_talk_node(dialogue_view.runner.current())
	return true


func is_talking() -> bool:
	return not _talk.is_empty()


## Over-the-shoulder shot of [param subject] seen past [param viewer]; blends from the active camera.
func frame(subject: Node3D, viewer: Node3D, blend := 0.45) -> void:
	if subject == null or not is_instance_valid(subject):
		return
	var target := over_shoulder(subject, viewer)
	var current := get_viewport().get_camera_3d()
	if current != _talk_camera:
		_talk_previous_camera = current
		if current != null:
			_talk_camera.global_transform = current.global_transform
			_talk_camera.fov = current.fov
		_talk_camera.make_current()
	if _talk_tween != null:
		_talk_tween.kill()
	if blend <= 0.0:
		_talk_camera.global_transform = target
		return
	_talk_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_talk_tween.tween_property(_talk_camera, "global_transform", target, blend)


func is_framing() -> bool:
	return _talk_camera.current


## Returns to the camera that was active before [method frame].
func release_frame() -> void:
	if _talk_tween != null:
		_talk_tween.kill()
		_talk_tween = null
	if not _talk_camera.current:
		return
	if _talk_previous_camera != null and is_instance_valid(_talk_previous_camera) and _talk_previous_camera.is_inside_tree():
		_talk_previous_camera.make_current()
	else:
		_talk_camera.clear_current(true)
	_talk_previous_camera = null


func _on_talk_node(node: DialogueNode) -> void:
	if node == null or _talk.is_empty() or not _talk.get("frame", false):
		return
	var speaker := dialogue_view.runner.speaker_node() as Node3D
	if speaker == null:
		speaker = _talk["npc"]
	var other: Node3D = _talk["actor"] if speaker != _talk["actor"] else _talk["npc"]
	frame(speaker, other)


func _on_talk_ended(_id: StringName, _outcome: StringName) -> void:
	_end_talk()


func _end_talk() -> void:
	if dialogue_view != null:
		if dialogue_view.runner.node_entered.is_connected(_on_talk_node):
			dialogue_view.runner.node_entered.disconnect(_on_talk_node)
		if dialogue_view.runner.ended.is_connected(_on_talk_ended):
			dialogue_view.runner.ended.disconnect(_on_talk_ended)
	if _talk.get("frame", false):
		release_frame()
	_talk = {}


# --- Barks -------------------------------------------------------------------------------------

## Ambient one-liner over [param speaker]'s head. [param options]: "duration", "color",
## "subtitle" (also show it in the subtitle bar), "name" (subtitle speaker name), "force"
## (ignore the per-speaker cooldown). Returns false when suppressed.
func bark(speaker: Node3D, text: String, options: Dictionary = {}) -> bool:
	if speaker == null or not is_instance_valid(speaker) or not speaker.is_inside_tree() or text == "":
		return false
	var key := speaker.get_instance_id()
	var existing: Dictionary = _barks.get(key, {})
	if not existing.is_empty() and not options.get("force", false) and existing["age"] < BARK_COOLDOWN:
		return false
	var label: Label3D = existing.get("label", null)
	if label == null or not is_instance_valid(label):
		label = Label3D.new()
		label.name = "Bark"
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.pixel_size = 0.0035
		label.font_size = 44
		label.outline_size = 12
		label.width = 520.0
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.top_level = true
		speaker.add_child(label)
	label.text = text
	label.modulate = options.get("color", Color.WHITE)
	var duration: float = options.get("duration", maxf(BARK_DURATION, DialogueNode.auto_duration(text)))
	_barks[key] = {"label": label, "node": speaker, "left": duration, "age": 0.0}
	_place_bark(_barks[key])
	if options.get("subtitle", false):
		subtitle(options.get("name", ActionContext._label_of(speaker)), text, duration)
	EventBus.bark.emit(speaker, text)
	return true


## The text currently barked by [param speaker], or "".
func bark_text(speaker: Node3D) -> String:
	var entry: Dictionary = _barks.get(speaker.get_instance_id(), {}) if speaker != null else {}
	return entry["label"].text if not entry.is_empty() and is_instance_valid(entry["label"]) else ""


func _update_barks(delta: float) -> void:
	if get_tree().paused:
		return
	for key in _barks.keys():
		var entry: Dictionary = _barks[key]
		entry["left"] -= delta
		entry["age"] += delta
		var valid: bool = is_instance_valid(entry["node"]) and is_instance_valid(entry["label"])
		if not valid or entry["left"] <= 0.0:
			if is_instance_valid(entry["label"]):
				entry["label"].queue_free()
			_barks.erase(key)
			continue
		entry["label"].modulate.a = clampf(entry["left"] / 0.4, 0.0, 1.0)
		_place_bark(entry)


func _place_bark(entry: Dictionary) -> void:
	entry["label"].global_position = focus_point(entry["node"]) + Vector3.UP * 0.45


# --- Helpers -----------------------------------------------------------------------------------

## The CharacterVisual of an actor (the node itself, a "visual" property, or a direct child).
static func visual_of(node: Node) -> CharacterVisual:
	if node == null or not is_instance_valid(node):
		return null
	if node is CharacterVisual:
		return node
	var visual: Variant = node.get("visual")
	if visual is CharacterVisual:
		return visual
	for child in node.get_children():
		if child is CharacterVisual:
			return child
	return null


## Head position for characters, the origin for anything else.
static func focus_point(node: Node3D) -> Vector3:
	if node == null or not is_instance_valid(node):
		return Vector3.ZERO
	var visual := visual_of(node)
	if visual != null and visual.skeleton != null and visual.is_inside_tree():
		return visual.global_position + Vector3.UP * visual.head_height()
	return node.global_position


## Camera transform looking at [param subject]'s face from just behind [param viewer]'s shoulder
## (or from in front of the subject when there is no viewer).
static func over_shoulder(subject: Node3D, viewer: Node3D) -> Transform3D:
	var look := focus_point(subject)
	var from := focus_point(viewer) if viewer != null and is_instance_valid(viewer) else look - subject.global_basis.z * 2.0
	var axis := look - from
	axis.y = 0.0
	if axis.length() < 0.05:
		axis = -subject.global_basis.z
	axis = axis.normalized()
	var right := axis.cross(Vector3.UP).normalized()
	var distance := clampf(Vector2(from.x, from.z).distance_to(Vector2(look.x, look.z)), 1.0, 4.0)
	var spot := look - axis * (distance + 0.9) + right * 0.55 + Vector3.UP * 0.12
	return Transform3D(Basis.IDENTITY, spot).looking_at(look, Vector3.UP)


## Turns a node (yaw only) to face [param point].
static func face_toward(node: Node3D, point: Vector3) -> void:
	if node == null:
		return
	var flat := point - node.global_position
	flat.y = 0.0
	if flat.length() > 0.01:
		node.global_rotation.y = atan2(-flat.x, -flat.z)


## Clears every lock, bark, call and cutscene (tests, loading a save).
func reset() -> void:
	if director.is_playing():
		director.stop()
	phone.reset()
	if dialogue_view != null and is_instance_valid(dialogue_view):
		dialogue_view.close()
	_end_talk()
	release_frame()
	for key in _barks.keys():
		if is_instance_valid(_barks[key]["label"]):
			_barks[key]["label"].queue_free()
	_barks.clear()
	ui.reset()
	var was_locked := is_input_locked()
	var was_hidden := not is_hud_visible()
	_input_locks.clear()
	_hud_hides.clear()
	if was_locked:
		input_lock_changed.emit(false)
	if was_hidden:
		hud_visibility_changed.emit(true)
