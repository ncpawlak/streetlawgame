class_name DialogueStep
extends CutsceneStep
## Plays a DialogueDef inside the cutscene, timed (DialoguePlayback): lines advance on their own,
## choices appear over the letterbox (1-9 / E) and auto-pick [member default_choice] after
## [member choice_timeout]. Skipping fast-forwards through default choices so the same effects and
## outcome apply. Optionally frames the camera on whoever is speaking.

@export var dialogue: DialogueDef
## Used when [member dialogue] is empty.
@export var dialogue_id: StringName
## DialogueNode.speaker id -> actor name, e.g. {&"npc": &"Nurse", &"cop": &"Officer"}.
## &"player" maps to the player automatically.
@export var speakers: Dictionary = {}
@export var default_choice := 0
## Seconds before a choice auto-picks; 0 = wait for the player.
@export var choice_timeout := 0.0
## Shot / reverse shot on the speaking actor.
@export var frame_speakers := true


func begin(director: CutsceneDirector, state: Dictionary) -> void:
	_start(director, state, true)


func tick(director: CutsceneDirector, state: Dictionary, delta: float) -> bool:
	var playback: DialoguePlayback = state.get("playback")
	if playback == null:
		return true
	playback.tick(delta)
	if frame_speakers and state.has("shot") and playback.is_playing():
		var camera := director.camera
		camera.global_transform = camera.global_transform.interpolate_with(state["shot"], clampf(delta * 5.0, 0.0, 1.0))
	return not playback.is_playing()


func skip(director: CutsceneDirector, state: Dictionary) -> void:
	if state.is_empty():
		_start(director, state, false)
	var playback: DialoguePlayback = state.get("playback")
	if playback != null:
		playback.fast_forward()


func resolve_dialogue() -> DialogueDef:
	if dialogue != null:
		return dialogue
	return ContentDB.find_def(DialogueDef.TYPE, dialogue_id) as DialogueDef if dialogue_id != &"" else null


func validate() -> PackedStringArray:
	if dialogue == null and dialogue_id == &"":
		return PackedStringArray(["needs dialogue or dialogue_id"])
	if dialogue == null and ContentDB.find_def(DialogueDef.TYPE, dialogue_id) == null:
		return PackedStringArray(["unknown dialogue '%s'" % dialogue_id])
	return PackedStringArray()


func _start(director: CutsceneDirector, state: Dictionary, show: bool) -> void:
	var def := resolve_dialogue()
	if def == null:
		push_warning("DialogueStep: no dialogue")
		return
	var ctx := ActionContext.new(director.ctx.actor, director.ctx.target)
	ctx.vars = director.ctx.vars.duplicate()
	var map := {}
	if GameState.player != null:
		map[&"player"] = GameState.player
	for key in speakers:
		var node := director.resolve(StringName(str(speakers[key])))
		map[StringName(str(key))] = node if node != null else str(speakers[key])
	ctx.vars["speakers"] = map
	if map.has(&"npc") and map[&"npc"] is Node:
		ctx.occupant = map[&"npc"]
		ctx.target = map[&"npc"]
	var playback := DialoguePlayback.new()
	playback.default_choice = default_choice
	playback.choice_timeout = choice_timeout
	state["playback"] = playback
	if show:
		Narrative.ui.bind_playback(playback)
		playback.line_shown.connect(_on_line.bind(director, state))
	playback.start(def, ctx)


func _on_line(speaker: String, text: String, duration: float, _node: DialogueNode, director: CutsceneDirector, state: Dictionary) -> void:
	director.emit_line(speaker, text, duration)
	if not frame_speakers:
		return
	var playback: DialoguePlayback = state["playback"]
	var who := playback.runner.speaker_node() as Node3D
	if who == null:
		return
	var other: Node3D = null
	for node: Variant in playback.runner.ctx.vars["speakers"].values():
		if node is Node3D and node != who:
			other = node
			break
	director.take_camera()
	director.look_node = null
	state["shot"] = Narrative.over_shoulder(who, other)
