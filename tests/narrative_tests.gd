class_name NarrativeTests
extends RefCounted
## Tests for cutscenes, dialogue upgrades (branching, speakers, playback, talk-to-NPC, barks), story
## events and the phone. Hooked from FrameworkTests; every test leaves Narrative reset.

const FLAGS: Array[StringName] = [&"narr_test_count", &"narr_test_flag", &"sample_leads", &"sample_car_lead", &"sample_lou_job"]

var _framework: FrameworkTests
var _main: Node
var _player: Player
var _events: Array[StringName] = []


func _init(framework: FrameworkTests) -> void:
	_framework = framework


func run(main: Node, player: Player) -> void:
	_main = main
	_player = player
	var on_event := func(event: StringName, _payload: Dictionary) -> void: _events.append(event)
	EventBus.story_event.connect(on_event)
	Narrative.reset()
	_test_content()
	_test_branching_and_effects()
	_test_playback()
	await _framework.with_sandbox(main, _test_cutscene_plays)
	await _framework.with_sandbox(main, _test_cutscene_skip)
	await _framework.with_sandbox(main, _test_input_lock)
	await _framework.with_sandbox(main, _test_talk_to_npc)
	await _framework.with_sandbox(main, _test_barks)
	await _test_phone()
	EventBus.story_event.disconnect(on_event)
	Narrative.reset()
	for flag in FLAGS:
		GameState.flags.erase(flag)


func _check(condition: bool, description: String) -> void:
	_framework.check(condition, description)


func _frames(count: int) -> void:
	await _framework.frames(count)


func _clear_flags() -> void:
	for flag in FLAGS:
		GameState.flags.erase(flag)


static func _line(id: StringName, speaker: StringName, text: String, next: StringName = &"") -> DialogueNode:
	var node := DialogueNode.new()
	node.id = id
	node.speaker = speaker
	node.text = text
	node.next = next
	return node


func _marker(marker_name: String, offset: Vector3, yaw := 0.0) -> Marker3D:
	var marker := Marker3D.new()
	marker.name = marker_name
	_framework.sandbox().add_child(marker)
	marker.global_position = FrameworkTests.SANDBOX + offset
	marker.global_rotation.y = yaw
	return marker


static func _flat_distance(a: Node3D, b: Node3D) -> float:
	return Vector2(a.global_position.x - b.global_position.x, a.global_position.z - b.global_position.z).length()


func _npc(npc_name: String, offset: Vector3) -> Node3D:
	var npc := Node3D.new()
	npc.name = npc_name
	_framework.sandbox().add_child(npc)
	npc.global_position = FrameworkTests.SANDBOX + offset
	var visual := CharacterVisual.create(&"civilian", 1)
	visual.name = "Visual"
	npc.add_child(visual)
	return npc


# --- Content -----------------------------------------------------------------------------------

func _test_content() -> void:
	var cutscene := ContentDB.find_def(CutsceneDef.TYPE, &"sample_wake_up") as CutsceneDef
	_check(cutscene != null and cutscene.steps.size() > 5 and cutscene.validate().is_empty(), "the sample cutscene loads from data/cutscenes and validates")
	var call := ContentDB.find_def(PhoneCallDef.TYPE, &"sample_lou_job") as PhoneCallDef
	_check(call != null and call.validate().is_empty() and call.caller_name() == "Mister Lou" and call.resolve_dialogue() != null, "phone calls resolve their contact and dialogue")
	_check(Narrative.phone.contacts().any(func(c: ContactDef) -> bool: return c.id == &"sample_lou"), "contacts are listed for the phone")
	var bad := CutsceneDef.new()
	bad.id = &"narr_test_bad"
	var move := ActorMoveStep.new()
	bad.steps = [move] as Array[CutsceneStep]
	_check(not bad.validate().is_empty(), "cutscene validate() flags incomplete steps")


# --- Dialogue ----------------------------------------------------------------------------------

func _test_branching_and_effects() -> void:
	_clear_flags()
	_events.clear()
	var gated := _line(&"gated", &"npc", "You found a lead.")
	var at_least := FlagAtLeastCondition.new()
	at_least.flag = &"narr_test_count"
	at_least.amount = 1
	gated.conditions = [at_least] as Array[Condition]
	gated.else_next = &"fallback"
	gated.outcome = &"knew"
	var intro := _line(&"start", &"cop", "Officer Diaz. Who shot you?", &"gated")
	intro.speaker_name = "Officer Diaz"
	var fallback := _line(&"fallback", &"player", "No idea.")
	fallback.outcome = &"blank"
	var def := DialogueDef.new()
	def.id = &"narr_test_branch"
	def.nodes = [intro, gated, fallback] as Array[DialogueNode]
	_check(def.validate().is_empty(), "next / else_next links validate")

	var runner := DialogueRunner.new()
	var outcomes: Array[StringName] = []
	runner.ended.connect(func(_id: StringName, outcome: StringName) -> void: outcomes.append(outcome))
	runner.start(def, ActionContext.new(_player))
	_check(runner.speaker_name() == "Officer Diaz" and runner.can_continue(), "nodes show an authored speaker name and continue via next")
	runner.advance()
	_check(runner.current() == fallback and runner.speaker_name() == "You", "a gated node redirects to else_next when its condition fails")
	runner.advance()
	_check(outcomes == ([&"blank"] as Array[StringName]), "the conversation ends with the reached outcome")

	var count := AddFlagEffect.new()
	count.flag = &"narr_test_count"
	var event := StoryEventEffect.new()
	event.event = &"narr_test_lead"
	Effect.apply_all([count, event] as Array[Effect], ActionContext.new(_player))
	_check(int(GameState.get_flag(&"narr_test_count", 0)) == 1 and _events.has(&"narr_test_lead"), "effects add to counters and emit story events")
	runner.start(def, ActionContext.new(_player))
	runner.advance()
	_check(runner.current() == gated, "the gated node opens once its condition is met")
	runner.end()
	_clear_flags()


func _test_playback() -> void:
	var question := _line(&"start", &"npc", "In or out?")
	question.duration = 0.1
	var yes := DialogueChoice.new()
	yes.text = "In."
	yes.next = &"in"
	var no := DialogueChoice.new()
	no.text = "Out."
	no.next = &"out"
	question.choices = [yes, no] as Array[DialogueChoice]
	var in_node := _line(&"in", &"npc", "Good.")
	in_node.outcome = &"in"
	in_node.duration = 0.1
	var out_node := _line(&"out", &"npc", "Shame.")
	out_node.outcome = &"out"
	var def := DialogueDef.new()
	def.id = &"narr_test_playback"
	def.nodes = [question, in_node, out_node] as Array[DialogueNode]

	var playback := DialoguePlayback.new()
	playback.choice_timeout = 0.5
	playback.default_choice = 1
	var lines: Array[String] = []
	var outcomes: Array[StringName] = []
	playback.line_shown.connect(func(_speaker: String, text: String, _duration: float, _node: DialogueNode) -> void: lines.append(text))
	playback.finished.connect(func(outcome: StringName) -> void: outcomes.append(outcome))
	playback.start(def, ActionContext.new(_player))
	playback.tick(0.2)
	_check(playback.waiting_for_choice() and playback.choice_labels().size() == 2, "timed playback offers choices after the line")
	playback.tick(0.6)
	playback.tick(5.0)
	_check(outcomes == ([&"out"] as Array[StringName]) and lines.has("Shame."), "an unanswered choice times out to the default")

	outcomes.clear()
	playback.default_choice = 0
	playback.start(def, ActionContext.new(_player))
	playback.fast_forward()
	_check(outcomes == ([&"in"] as Array[StringName]), "fast-forward resolves a conversation with default choices")


# --- Cutscenes ---------------------------------------------------------------------------------

func _test_cutscene_plays() -> void:
	_events.clear()
	var hud: CanvasLayer = _main.get_node("HUD")
	var mark := _marker("NarrTestMark", Vector3(3.0, 0.1, 0.0), PI * 0.5)
	var cam := _marker("NarrTestCam", Vector3(0.0, 2.0, 5.0))
	var def := CutsceneDef.new()
	def.id = &"narr_test_scene"
	var place := ActorPlaceStep.new()
	place.marker = &"NarrTestMark"
	var shot := CameraStep.new()
	shot.marker = &"NarrTestCam"
	shot.look_at = &"player"
	var line := LineStep.new()
	line.speaker_name = "Nurse"
	line.text = "Easy. You're at Grove General."
	line.duration = 0.3
	var fade := FadeStep.new()
	fade.to = 1.0
	fade.duration = 0.2
	var together := ParallelStep.new()
	together.steps = [line, fade] as Array[CutsceneStep]
	var event := EventStep.new()
	event.event = &"narr_test_woke"
	def.steps = [place, shot, together, event] as Array[CutsceneStep]
	var log: Array[String] = []
	var started := func(id: StringName) -> void: log.append("started %s" % id)
	var finished := func(id: StringName, skipped: bool) -> void: log.append("finished %s %s" % [id, skipped])
	Narrative.director.started.connect(started)
	Narrative.director.finished.connect(finished)
	var previous_camera := _main.get_viewport().get_camera_3d()

	_check(Narrative.play_cutscene(def, _framework.sandbox()), "a cutscene starts")
	await _frames(3)
	_check(log == ["started narr_test_scene"] and Narrative.is_input_locked() and not hud.visible, "cutscenes lock input and hide the HUD")
	_check(_flat_distance(_player, mark) < 0.05 and Narrative.director.camera.current, "steps place actors and take the camera")
	_check(Narrative.ui.letterbox_amount > 0.0 and Narrative.ui.subtitle_text().contains("Grove General"), "letterbox bars and subtitles show")
	_check(not Narrative.play_cutscene(def), "only one cutscene plays at a time")
	await _frames(45)
	_check(log.has("finished narr_test_scene false") and _events.has(&"narr_test_woke"), "the cutscene runs to the end and fires its event")
	_check(not Narrative.is_input_locked() and hud.visible and _main.get_viewport().get_camera_3d() == previous_camera, "input, HUD and camera are restored")
	Narrative.director.started.disconnect(started)
	Narrative.director.finished.disconnect(finished)
	Narrative.reset()
	mark.queue_free()
	cam.queue_free()


func _test_cutscene_skip() -> void:
	_clear_flags()
	_events.clear()
	var end_mark := _marker("NarrTestEnd", Vector3(-3.0, 0.1, 2.0))
	var def := CutsceneDef.new()
	def.id = &"narr_test_skip"
	def.skip_hold = 0.2
	var wait := WaitStep.new()
	wait.seconds = 60.0
	var place := ActorPlaceStep.new()
	place.marker = &"NarrTestEnd"
	var event := EventStep.new()
	event.event = &"narr_test_skipped_event"
	var flag := SetFlagEffect.new()
	flag.flag = &"narr_test_flag"
	event.effects = [flag] as Array[Effect]
	def.steps = [wait, place, event] as Array[CutsceneStep]
	var skipped: Array[StringName] = []
	var on_skip := func(id: StringName) -> void: skipped.append(id)
	Narrative.director.skipped.connect(on_skip)

	Narrative.play_cutscene(def, _framework.sandbox())
	await _frames(5)
	_check(Narrative.is_cutscene_playing(), "a long cutscene keeps playing")
	Input.action_press(&"skip_cutscene")
	await _frames(30)
	Input.action_release(&"skip_cutscene")
	_check(skipped == ([&"narr_test_skip"] as Array[StringName]) and not Narrative.is_cutscene_playing(), "holding skip ends the cutscene")
	_check(_flat_distance(_player, end_mark) < 0.05, "skipping applies the end state of the remaining steps")
	_check(_events.has(&"narr_test_skipped_event") and GameState.has_flag(&"narr_test_flag"), "skipped steps still fire their events and effects")
	_check(not Narrative.is_input_locked() and Narrative.is_hud_visible(), "skipping releases input and the HUD")

	def.skippable = false
	Narrative.play_cutscene(def, _framework.sandbox())
	Input.action_press(&"skip_cutscene")
	await _frames(30)
	Input.action_release(&"skip_cutscene")
	_check(Narrative.is_cutscene_playing(), "unskippable cutscenes ignore the skip button")
	Narrative.reset()
	Narrative.director.skipped.disconnect(on_skip)
	end_mark.queue_free()
	_clear_flags()


func _test_input_lock() -> void:
	await _frames(10)
	Narrative.lock_input(&"narr_test")
	var before := _player.global_position
	Input.action_press(&"move_forward")
	await _frames(30)
	Input.action_release(&"move_forward")
	var moved := Vector2(_player.global_position.x - before.x, _player.global_position.z - before.z).length()
	_check(moved < 0.1, "the player can't move while input is locked (moved %.2f m)" % moved)
	Narrative.unlock_input(&"narr_test")
	Input.action_press(&"move_forward")
	await _frames(30)
	Input.action_release(&"move_forward")
	moved = Vector2(_player.global_position.x - before.x, _player.global_position.z - before.z).length()
	_check(moved > 0.5, "unlocking gives control back (moved %.2f m)" % moved)
	_player.velocity = Vector3.ZERO


# --- Talk / barks ------------------------------------------------------------------------------

func _test_talk_to_npc() -> void:
	_clear_flags()
	_events.clear()
	var witness := _npc("NarrTestWitness", Vector3(0.0, 0.0, -1.6))
	var target := TalkTarget.new()
	target.display_name = "Witness"
	target.dialogue_id = &"sample_witness"
	witness.add_child(target)
	await _frames(3)
	var view := Narrative.dialogue_view
	_check(target.interactable != null and target.label().contains("Witness"), "TalkTarget adds a Talk interaction")
	_check(target.talk() and view.is_open() and Narrative.is_talking(), "talking opens the dialogue view")
	await _frames(3)
	_check(Narrative.is_framing() and view.runner.speaker_name().contains("Witness"), "the camera frames the speaker, who is named")
	_check(not Narrative.phone._can_ring(), "calls wait while a conversation is open")
	view.pick(0)
	_check(int(GameState.get_flag(&"sample_leads", 0)) == 1 and _events.has(&"lead_added") and GameState.has_flag(&"sample_car_lead"), "choices can add leads and set story flags")
	view.pick(0)
	_check(view.runner.speaker_name() == "You", "player lines show the player as speaker")
	view.pick(0)
	var labels: Array[String] = []
	for choice in view.runner.choices():
		labels.append(choice.text)
	_check(not labels.any(func(text: String) -> bool: return text.contains("car")), "a choice hidden by a flag condition disappears once asked")
	view.close()
	await _frames(3)
	_check(not Narrative.is_talking() and not Narrative.is_framing() and not _main.get_tree().paused, "closing the conversation restores the camera and world")
	witness.queue_free()
	_clear_flags()


func _test_barks() -> void:
	var thug := _npc("NarrTestThug", Vector3(4.0, 0.0, 0.0))
	await _frames(2)
	_check(Narrative.bark(thug, "Angeles block."), "NPCs can bark one-liners")
	_check(Narrative.bark_text(thug) == "Angeles block.", "the bark shows over the speaker")
	_check(not Narrative.bark(thug, "Again?"), "barks have a per-speaker cooldown")
	_check(Narrative.bark(thug, "Follow me!", {"force": true}) and Narrative.bark_text(thug) == "Follow me!", "forced barks interrupt")
	var barker := Barker.new()
	barker.lines = PackedStringArray(["You lost?"])
	barker.radius = 8.0
	var heard: Array[String] = []
	barker.barked.connect(func(text: String) -> void: heard.append(text))
	var other := _npc("NarrTestBarker", Vector3(-4.0, 0.0, 0.0))
	other.add_child(barker)
	await _frames(30)
	_check(heard == (["You lost?"] as Array[String]) and Narrative.bark_text(other) == "You lost?", "a Barker speaks when the player comes near")
	await _frames(30)
	_check(heard.size() == 1, "a Barker waits for its cooldown")
	Narrative.reset()
	_check(Narrative.bark_text(other) == "", "reset clears barks")
	thug.queue_free()
	other.queue_free()


# --- Phone -------------------------------------------------------------------------------------

func _test_phone() -> void:
	_clear_flags()
	_events.clear()
	var phone := Narrative.phone
	phone.ring_sound = false
	phone.reset()
	var ended: Array[StringName] = []
	var on_end := func(_call: StringName, _contact: StringName, outcome: StringName) -> void: ended.append(outcome)
	phone.call_ended.connect(on_end)

	var handle := phone.schedule_call(&"sample_lou_job", 0.3)
	_check(handle > 0 and phone.pending_calls() == ([&"sample_lou_job"] as Array[StringName]) and not phone.is_ringing(), "calls can be scheduled with a delay")
	await _frames(40)
	_check(phone.is_ringing() and phone.caller_name() == "Mister Lou" and Narrative.ui.phone_view.card_text().contains("Mister Lou"), "a scheduled call rings with the caller's name")
	_check(not Narrative.is_input_locked(), "the player keeps control while the phone rings")
	_check(phone.answer() and phone.in_call() and not Narrative.is_input_locked(), "answering plays the call over gameplay")
	_check(_player.visual.is_on_phone(), "the player holds the phone during a call")
	await _frames(3)
	_check(Narrative.ui.subtitle_speaker() == "Mister Lou" and Narrative.ui.subtitle_text() != "", "the call is subtitled")
	phone.playback.fast_forward()
	_check(ended == ([&"accepted"] as Array[StringName]) and GameState.has_flag(&"sample_lou_job") and _events.has(&"job_offered"), "the call's choices apply effects and end with an outcome")
	_check(not phone.in_call() and not _player.visual.is_on_phone(), "the phone is put away after the call")

	_events.clear()
	phone.schedule_call(&"sample_lou_job")
	await _frames(3)
	_check(phone.decline() and phone.missed_calls() == ([&"sample_lou_job"] as Array[StringName]) and phone.has_missed_from(&"sample_lou"), "declining leaves a missed call")
	_check(phone.call_back(&"sample_lou") and phone.in_call() and phone.missed_calls().is_empty(), "missed calls can be returned")
	phone.hang_up()
	_check(not phone.in_call() and ended.back() == &"hung_up", "the player can hang up")

	var quick := PhoneCallDef.new()
	quick.id = &"sample_lou_job"
	quick.contact_id = &"sample_lou"
	quick.dialogue_id = &"sample_lou_chat"
	quick.ring_time = 0.2
	var missed_event := StoryEventEffect.new()
	missed_event.event = &"narr_test_missed"
	quick.on_missed = [missed_event] as Array[Effect]
	phone.schedule_call(quick)
	await _frames(30)
	_check(not phone.is_ringing() and phone.has_missed_from(&"sample_lou") and _events.has(&"narr_test_missed"), "an unanswered call becomes a missed call and runs on_missed")
	_check(phone.call_contact(&"sample_lou") and phone.in_call(), "calling a contact with a missed call returns it")
	phone.hang_up()
	_check(phone.call_contact(&"sample_lou") and phone.in_call(), "calling a contact plays their chat dialogue")
	phone.hang_up()

	var scene := CutsceneDef.new()
	scene.id = &"narr_test_block"
	var wait := WaitStep.new()
	wait.seconds = 30.0
	scene.steps = [wait] as Array[CutsceneStep]
	Narrative.play_cutscene(scene)
	var effect := PhoneCallEffect.new()
	effect.call_id = &"sample_lou_job"
	Effect.apply_all([effect] as Array[Effect], ActionContext.new(_player))
	await _frames(10)
	_check(not phone.is_ringing() and phone.pending_calls().size() == 1, "calls wait until the cutscene ends")
	Narrative.director.stop()
	await _frames(5)
	_check(phone.is_ringing(), "the held call rings after the cutscene")
	var saved := phone.to_dict()
	phone.reset()
	phone.from_dict(saved)
	_check(phone.pending_calls() == ([&"sample_lou_job"] as Array[StringName]), "a ringing call is saved and restored as pending")
	phone.call_ended.disconnect(on_end)
	phone.reset()
	phone.ring_sound = true
	_clear_flags()
