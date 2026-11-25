class_name CutsceneDirector
extends Node
## Plays CutsceneDefs (owned by the Narrative autoload; use Narrative.play_cutscene). Runs the step
## list, claims actors (AI/physics paused, restored afterwards), owns the cutscene camera, locks
## input / hides the HUD, and handles hold-to-skip. Skipping applies every remaining step's end
## state, so the world always ends up exactly as if the scene had been watched.

signal started(cutscene_id: StringName)
signal finished(cutscene_id: StringName, skipped: bool)
signal skipped(cutscene_id: StringName)
## EventStep fired.
signal event(event: StringName, payload: Dictionary)
## LineStep / DialogueStep line shown.
signal line(speaker: String, text: String, duration: float)

const MAX_INSTANT_STEPS := 64
const LOCK_REASON := &"cutscene"

var def: CutsceneDef
var stage: Node
var bindings: Dictionary = {}
var ctx: ActionContext
var camera: Camera3D
## Kept aimed at by the camera every frame (set by CameraStep.look_at).
var look_node: Node3D
var look_offset := Vector3.ZERO
## Seconds the skip action has been held.
var skip_progress := 0.0
## Instance ids of claimed actors that a step is currently moving (not held in idle).
var moving: Dictionary = {}

var _playing := false
var _index := 0
var _current: CutsceneStep
var _state: Dictionary = {}
var _background: Array = []
var _claimed: Dictionary = {}
var _previous_camera: Camera3D
var _was_skipped := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	camera = Camera3D.new()
	camera.name = "CutsceneCamera"
	camera.cull_mask &= ~GameState.MAP_LAYER
	add_child(camera)


## Starts [param cutscene]. [param stage] scopes name lookups (e.g. the hospital room node);
## [param bindings] maps step names to nodes ({&"doctor": $Doctor}). Returns false if one is
## already playing.
func play(cutscene: CutsceneDef, scene_stage: Node = null, scene_bindings: Dictionary = {}, context: ActionContext = null) -> bool:
	if cutscene == null or _playing:
		return false
	def = cutscene
	stage = scene_stage
	bindings = scene_bindings
	ctx = context if context != null else ActionContext.new(GameState.player, null)
	_playing = true
	_was_skipped = false
	_index = 0
	_current = null
	_state = {}
	_background = []
	_claimed = {}
	moving = {}
	look_node = null
	skip_progress = 0.0
	if def.lock_input:
		Narrative.lock_input(LOCK_REASON)
	if def.hide_hud:
		Narrative.hide_hud(LOCK_REASON)
	if def.letterbox:
		Narrative.ui.set_letterbox(1.0, 0.4)
	Narrative.ui.set_skip_progress(0.0, def.skippable)
	started.emit(def.id)
	EventBus.cutscene_started.emit(def.id)
	_advance()
	return true


func is_playing() -> bool:
	return _playing


func current_id() -> StringName:
	return def.id if _playing else &""


func _process(delta: float) -> void:
	if not _playing:
		return
	_update_skip(delta)
	if not _playing:
		return
	for i in range(_background.size() - 1, -1, -1):
		var entry: Array = _background[i]
		if (entry[0] as CutsceneStep).tick(self, entry[1], delta):
			_background.remove_at(i)
		if not _playing:
			return
	if _current != null and _current.tick(self, _state, delta):
		_current = null
	if not _playing:
		return
	_advance()
	_hold_actors(delta)
	_aim_camera()


## Skips to the end: every running and remaining step applies its end state.
func skip() -> void:
	if not _playing:
		return
	_was_skipped = true
	for entry: Array in _background:
		(entry[0] as CutsceneStep).skip(self, entry[1])
	_background = []
	if _current != null:
		_current.skip(self, _state)
		_current = null
	while _index < def.steps.size():
		var step := def.steps[_index]
		_index += 1
		if step != null:
			step.skip(self, {})
	_aim_camera()
	skipped.emit(def.id)
	_finish()


## Aborts without applying end states or on_finish (e.g. the player died, tests).
func stop() -> void:
	if not _playing:
		return
	_background = []
	_current = null
	_finish(false)


# --- Step helpers ------------------------------------------------------------------------------

## Finds a node by name: bindings, &"player", the stage subtree, then the current scene.
func resolve(node_name: StringName) -> Node:
	if node_name == &"":
		return null
	if bindings.has(node_name):
		return bindings[node_name]
	if bindings.has(String(node_name)):
		return bindings[String(node_name)]
	if node_name == &"player" and GameState.player != null:
		return GameState.player
	for root: Node in [stage, get_tree().current_scene]:
		if root != null and is_instance_valid(root):
			if root.name == node_name:
				return root
			var found := root.find_child(String(node_name), true, false)
			if found != null:
				return found
	return null


func resolve_3d(node_name: StringName) -> Node3D:
	return resolve(node_name) as Node3D


## Makes the cutscene camera current (copying the gameplay camera the first time).
func take_camera() -> Camera3D:
	if not camera.current:
		var active := get_viewport().get_camera_3d()
		if active != camera:
			_previous_camera = active
			if active != null:
				camera.global_transform = active.global_transform
				camera.fov = active.fov
		camera.make_current()
	return camera


## Freezes an actor's own control (AI / player physics) for the scene. Released at the end.
func claim(actor: Node) -> void:
	if actor == null or _claimed.has(actor.get_instance_id()):
		return
	var visual := Narrative.visual_of(actor)
	_claimed[actor.get_instance_id()] = {
		"node": actor,
		"physics": actor.is_physics_processing(),
		"visual": visual,
		"visual_transform": visual.transform if visual != null and visual != actor else Transform3D.IDENTITY,
		"keep_clip": false,
	}
	actor.set_physics_process(false)
	if actor is CharacterBody3D:
		(actor as CharacterBody3D).velocity = Vector3.ZERO


func is_claimed(actor: Node) -> bool:
	return actor != null and _claimed.has(actor.get_instance_id())


## Keeps the actor's scripted clip playing after the scene (otherwise stopped on release).
func keep_clip(actor: Node, keep := true) -> void:
	if is_claimed(actor):
		_claimed[actor.get_instance_id()]["keep_clip"] = keep


## Offsets/rotates the actor's CharacterVisual relative to its rest pose (fake lying / sitting
## poses, e.g. a hospital bed). Undone when the actor is released.
func pose_visual(actor: Node, offset: Vector3, rotation_degrees: Vector3) -> void:
	claim(actor)
	var entry: Dictionary = _claimed.get(actor.get_instance_id(), {}) if actor != null else {}
	var visual: CharacterVisual = entry.get("visual", null)
	if visual == null or visual == actor:
		return
	var rest: Transform3D = entry["visual_transform"]
	var euler := Vector3(deg_to_rad(rotation_degrees.x), deg_to_rad(rotation_degrees.y), deg_to_rad(rotation_degrees.z))
	visual.transform = Transform3D(rest.basis * Basis.from_euler(euler), rest.origin + offset)


func emit_line(speaker: String, text: String, duration: float) -> void:
	line.emit(speaker, text, duration)


func emit_event(event_name: StringName, payload: Dictionary) -> void:
	event.emit(event_name, payload)
	Narrative.emit_event(event_name, payload)


# --- Internals ---------------------------------------------------------------------------------

func _advance() -> void:
	var instant := 0
	while _playing and _current == null and _index < def.steps.size() and instant < MAX_INSTANT_STEPS:
		var step := def.steps[_index]
		_index += 1
		instant += 1
		if step == null:
			continue
		var state := {}
		step.begin(self, state)
		if not _playing:
			return
		if step.tick(self, state, 0.0):
			continue
		if step.wait:
			_current = step
			_state = state
		else:
			_background.append([step, state])
	if _playing and _current == null and _index >= def.steps.size() and _background.is_empty():
		_finish()


func _update_skip(delta: float) -> void:
	if not def.skippable:
		return
	if InputMap.has_action(&"skip_cutscene") and Input.is_action_pressed(&"skip_cutscene"):
		skip_progress += delta
	else:
		skip_progress = maxf(skip_progress - delta * 2.0, 0.0)
	Narrative.ui.set_skip_progress(clampf(skip_progress / maxf(def.skip_hold, 0.01), 0.0, 1.0), true)
	if skip_progress >= def.skip_hold:
		skip()


func _hold_actors(delta: float) -> void:
	for key in _claimed:
		if moving.has(key):
			continue
		var visual: CharacterVisual = _claimed[key]["visual"]
		if visual != null and is_instance_valid(visual):
			visual.update_motion(Vector3.ZERO, delta)


func _aim_camera() -> void:
	if look_node == null or not camera.current:
		return
	if not is_instance_valid(look_node):
		look_node = null
		return
	var target := Narrative.focus_point(look_node) + look_offset
	if camera.global_position.distance_to(target) > 0.01:
		camera.look_at(target, Vector3.UP)


func _finish(apply_effects := true) -> void:
	var finished_def := def
	var was_skipped := _was_skipped
	_playing = false
	if apply_effects:
		if was_skipped:
			Effect.apply_all(finished_def.on_skip, ctx)
		Effect.apply_all(finished_def.on_finish, ctx)
	_release_actors()
	if finished_def.restore_camera:
		_restore_camera()
	if finished_def.letterbox or Narrative.ui.letterbox_amount > 0.0:
		Narrative.ui.set_letterbox(0.0, 0.0 if was_skipped else 0.4)
	if finished_def.clear_fade_on_end and Narrative.ui.fade_amount > 0.0:
		Narrative.ui.fade_to(0.0, 0.6)
	Narrative.ui.set_skip_progress(0.0, false)
	Narrative.ui.clear_line()
	Narrative.ui.bind_playback(null)
	Narrative.unlock_input(LOCK_REASON)
	Narrative.show_hud(LOCK_REASON)
	look_node = null
	moving = {}
	finished.emit(finished_def.id, was_skipped)
	EventBus.cutscene_finished.emit(finished_def.id, was_skipped)


func _release_actors() -> void:
	for key in _claimed:
		var entry: Dictionary = _claimed[key]
		var actor: Node = entry["node"]
		if not is_instance_valid(actor):
			continue
		var visual: CharacterVisual = entry["visual"]
		if visual != null and is_instance_valid(visual):
			if visual != actor:
				visual.transform = entry["visual_transform"]
			if not entry["keep_clip"]:
				visual.stop_clip()
		if actor.has_method("is_on_foot"):
			actor.set_physics_process(actor.call("is_on_foot"))
		else:
			actor.set_physics_process(entry["physics"])
	_claimed = {}


func _restore_camera() -> void:
	if not camera.current:
		return
	if _previous_camera != null and is_instance_valid(_previous_camera) and _previous_camera.is_inside_tree():
		_previous_camera.make_current()
	else:
		camera.clear_current(true)
	_previous_camera = null
