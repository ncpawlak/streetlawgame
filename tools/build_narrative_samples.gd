extends Node
## Regenerates the placeholder narrative content (sample_* cutscene, dialogues, contact, phone call)
## used by scenes/showcase/narrative_showcase.tscn and tests/narrative_tests.gd.
##   godot --headless --path . res://tools/build_narrative_samples.tscn
## The .tres files are plain resources: tweak them in the inspector afterwards, this is just a seed.


func _ready() -> void:
	_save(_witness(), "res://data/dialogues/sample_witness.tres")
	_save(_wake_talk(), "res://data/dialogues/sample_wake_up_talk.tres")
	_save(_lou_call(), "res://data/dialogues/sample_lou_call.tres")
	_save(_lou_chat(), "res://data/dialogues/sample_lou_chat.tres")
	_save(_contact(), "res://data/contacts/sample_lou.tres")
	_save(_phone_call(), "res://data/phone_calls/sample_lou_job.tres")
	_save(_wake_up(), "res://data/cutscenes/sample_wake_up.tres")
	get_tree().quit()


func _save(resource: Resource, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var error := ResourceSaver.save(resource, path)
	print("%s %s" % ["saved" if error == OK else "FAILED (%d)" % error, path])


# --- dialogue helpers -------------------------------------------------------------------------

func _node(id: StringName, speaker: StringName, speaker_name: String, text: String, next: StringName = &"") -> DialogueNode:
	var node := DialogueNode.new()
	node.id = id
	node.speaker = speaker
	node.speaker_name = speaker_name
	node.text = text
	node.next = next
	return node


func _choice(text: String, next: StringName, effects: Array[Effect] = []) -> DialogueChoice:
	var choice := DialogueChoice.new()
	choice.text = text
	choice.next = next
	choice.effects = effects
	return choice


func _dialogue(id: StringName, name: String, nodes: Array[DialogueNode]) -> DialogueDef:
	var def := DialogueDef.new()
	def.id = id
	def.display_name = name
	def.nodes = nodes
	return def


func _event(event: StringName, payload: Dictionary = {}) -> StoryEventEffect:
	var effect := StoryEventEffect.new()
	effect.event = event
	effect.payload = payload
	return effect


func _add_flag(flag: StringName, amount := 1) -> AddFlagEffect:
	var effect := AddFlagEffect.new()
	effect.flag = flag
	effect.amount = amount
	return effect


func _set_flag(flag: StringName, value: Variant = true) -> SetFlagEffect:
	var effect := SetFlagEffect.new()
	effect.flag = flag
	effect.value = value
	return effect


# --- dialogues --------------------------------------------------------------------------------

## Talk-to-NPC sample: choices, a skill check, story events/flags, a conditional node with else_next.
func _witness() -> DialogueDef:
	var start := _node(&"start", &"npc", "Witness", "You're the one they shot outside Grove General? I saw the whole thing.")
	var car := _choice("What kind of car was it?", &"car", [_event(&"lead_added", {"id": &"sample_car"}), _add_flag(&"sample_leads")] as Array[Effect])
	car.hide_when_unavailable = true
	var not_twice := FlagCondition.new()
	not_twice.flag = &"sample_car_lead"
	not_twice.value = false
	car.conditions = [not_twice] as Array[Condition]
	var persuade := _choice("[Persuade] You saw the shooter too, didn't you?", &"shooter")
	persuade.check = PersuadeCheck.new()
	persuade.fail_next = &"clam_up"
	start.choices = [car, persuade, _choice("Forget it.", &"bye")] as Array[DialogueChoice]

	var car_node := _node(&"car", &"npc", "Witness", "Green lowrider, gold rims. Took off toward the docks.", &"car_ack")
	car_node.on_enter = [_set_flag(&"sample_car_lead")] as Array[Effect]
	var car_ack := _node(&"car_ack", &"player", "", "Green lowrider. Got it.", &"start")

	# Only says more once the player has at least one lead; otherwise falls through to else_next.
	var shooter := _node(&"shooter", &"npc", "Witness", "Same crew as that lowrider. Neck tattoo, a crown. That's all I got.")
	var has_lead := FlagAtLeastCondition.new()
	has_lead.flag = &"sample_leads"
	has_lead.amount = 1
	shooter.conditions = [has_lead] as Array[Condition]
	shooter.else_next = &"shooter_blank"
	shooter.on_enter = [_event(&"lead_added", {"id": &"sample_tattoo"}), _add_flag(&"sample_leads")] as Array[Effect]
	shooter.outcome = &"told"
	var blank := _node(&"shooter_blank", &"npc", "Witness", "Didn't get a look at his face. Ask me about the car.", &"start")
	var clam := _node(&"clam_up", &"npc", "Witness", "I didn't see nothing. Leave me alone.")
	clam.outcome = &"refused"
	var bye := _node(&"bye", &"npc", "Witness", "Watch your back out there.")
	bye.outcome = &"left"
	return _dialogue(&"sample_witness", "Witness (sample)", [start, car_node, car_ack, shooter, blank, clam, bye] as Array[DialogueNode])


## Timed lines played inside the wake-up cutscene (DialogueStep); `speaker` keys bind to actors.
func _wake_talk() -> DialogueDef:
	var a := _node(&"start", &"nurse", "Nurse", "Easy, easy. You took two in the shoulder. You're lucky.", &"b")
	var b := _node(&"b", &"player", "", "Lucky... Who did this?", &"c")
	var c := _node(&"c", &"nurse", "Nurse", "There's an officer outside asking the same thing.")
	c.choices = [_choice("Send him in.", &"in"), _choice("I don't talk to cops.", &"out")] as Array[DialogueChoice]
	var go_in := _node(&"in", &"nurse", "Nurse", "I'll get him.")
	go_in.outcome = &"cooperate"
	var go_out := _node(&"out", &"nurse", "Nurse", "Suit yourself. He's not leaving.")
	go_out.outcome = &"refuse"
	return _dialogue(&"sample_wake_up_talk", "Wake-up talk (sample)", [a, b, c, go_in, go_out] as Array[DialogueNode])


## Phone-call conversation: plays over gameplay, the choice times out to default_choice.
func _lou_call() -> DialogueDef:
	var a := _node(&"start", &"caller", "Mister Lou", "Heard you got shot. Heard you got up, too. I like that.", &"b")
	var b := _node(&"b", &"caller", "Mister Lou", "I got a list of cars that need new owners. You want work?")
	var accept := _choice("I'm in.", &"yes", [_event(&"job_offered", {"job": &"sample_car_list"}), _set_flag(&"sample_lou_job")] as Array[Effect])
	b.choices = [accept, _choice("Not now, Lou.", &"no")] as Array[DialogueChoice]
	var yes := _node(&"yes", &"caller", "Mister Lou", "Good. I'll text you the list.")
	yes.outcome = &"accepted"
	var no := _node(&"no", &"caller", "Mister Lou", "Your loss. You know my number.")
	no.outcome = &"declined"
	return _dialogue(&"sample_lou_call", "Lou: car list (sample)", [a, b, yes, no] as Array[DialogueNode])


## What Lou says when the player rings him from the contacts list.
func _lou_chat() -> DialogueDef:
	var a := _node(&"start", &"caller", "Mister Lou", "You got my list. Quit calling and go to work.")
	return _dialogue(&"sample_lou_chat", "Lou: small talk (sample)", [a] as Array[DialogueNode])


func _contact() -> ContactDef:
	var def := ContactDef.new()
	def.id = &"sample_lou"
	def.display_name = "Mister Lou"
	def.color = Color(0.95, 0.75, 0.3)
	def.call_dialogue_id = &"sample_lou_chat"
	return def


func _phone_call() -> PhoneCallDef:
	var def := PhoneCallDef.new()
	def.id = &"sample_lou_job"
	def.display_name = "Lou's offer"
	def.contact_id = &"sample_lou"
	def.dialogue_id = &"sample_lou_call"
	def.ring_time = 10.0
	def.choice_timeout = 8.0
	def.on_missed = [_event(&"call_missed", {"from": &"sample_lou"})] as Array[Effect]
	return def


# --- cutscene ---------------------------------------------------------------------------------

## Hospital wake-up. Stage markers: Bed, BedSide, CamClose, CamWide, NurseStart, NurseMark; actor Nurse.
func _wake_up() -> CutsceneDef:
	var def := CutsceneDef.new()
	def.id = &"sample_wake_up"
	def.display_name = "Wake up (sample)"
	var steps: Array[CutsceneStep] = []

	var black := FadeStep.new()
	black.duration = 0.0
	steps.append(black)
	var bars := LetterboxStep.new()
	bars.duration = 0.0
	steps.append(bars)

	var in_bed := ActorPlaceStep.new()
	in_bed.marker = &"Bed"
	in_bed.pose_visual = true
	in_bed.visual_rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	in_bed.visual_offset = Vector3(0.0, 0.55, 0.0)
	steps.append(in_bed)
	var nurse_off := ActorPlaceStep.new()
	nurse_off.actor = &"Nurse"
	nurse_off.marker = &"NurseStart"
	steps.append(nurse_off)

	var close := CameraStep.new()
	close.marker = &"CamClose"
	close.look_at = &"player"
	steps.append(close)

	var open_eyes := ParallelStep.new()
	var fade_in := FadeStep.new()
	fade_in.to = 0.0
	fade_in.duration = 2.0
	var groggy := LineStep.new()
	groggy.speaker = &"player"
	groggy.text = "...where... am I?"
	groggy.duration = 2.5
	open_eyes.steps = [fade_in, groggy] as Array[CutsceneStep]
	steps.append(open_eyes)

	var walk_in := ParallelStep.new()
	var walk := ActorMoveStep.new()
	walk.actor = &"Nurse"
	walk.marker = &"NurseMark"
	var dolly := CameraStep.new()
	dolly.mode = CameraStep.Mode.DOLLY
	dolly.from_marker = &"CamClose"
	dolly.marker = &"CamWide"
	dolly.look_at = &"Nurse"
	dolly.duration = 2.5
	walk_in.steps = [walk, dolly] as Array[CutsceneStep]
	steps.append(walk_in)

	var face := ActorFaceStep.new()
	face.actor = &"Nurse"
	face.toward = &"player"
	steps.append(face)

	var orbit := CameraStep.new()
	orbit.mode = CameraStep.Mode.ORBIT
	orbit.look_at = &"player"
	orbit.orbit_radius = 3.2
	orbit.orbit_height = 2.2
	orbit.orbit_from_degrees = 200.0
	orbit.orbit_to_degrees = 250.0
	orbit.duration = 3.0
	steps.append(orbit)

	var talk := ParallelStep.new()
	var lines := DialogueStep.new()
	lines.dialogue_id = &"sample_wake_up_talk"
	lines.speakers = {&"nurse": &"Nurse", &"player": &"player"}
	lines.choice_timeout = 6.0
	var gesture := ActorAnimStep.new()
	gesture.actor = &"Nurse"
	gesture.clip = &"Interact"
	gesture.wait = false
	talk.steps = [lines, gesture] as Array[CutsceneStep]
	steps.append(talk)

	var beat := EventStep.new()
	beat.event = &"woke_up"
	beat.effects = [_set_flag(&"sample_woke_up")] as Array[Effect]
	steps.append(beat)

	var out := FadeStep.new()
	out.duration = 0.8
	steps.append(out)
	# End state (also applied when skipped): standing beside the bed, ready to play.
	var stand := ActorPlaceStep.new()
	stand.marker = &"BedSide"
	steps.append(stand)
	def.steps = steps
	return def
