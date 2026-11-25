class_name PhoneService
extends Node
## The player's phone (Narrative.phone). Scheduled calls ring once the player is free (no cutscene
## or conversation), can be answered ([phone_answer] Y) or declined ([phone_decline] N), and time
## out as missed. Answered calls play their dialogue over gameplay with subtitles while the player
## keeps control. Missed / declined calls can be returned from the contacts list ([phone] P).

signal state_changed(state: State)
signal ringing(call: PhoneCallDef)
signal call_started(call_id: StringName, contact_id: StringName)
## [param outcome]: &"declined", &"missed", &"hung_up", or the dialogue outcome (&"finished" if none).
signal call_ended(call_id: StringName, contact_id: StringName, outcome: StringName)
signal missed_changed

enum State { IDLE, RINGING, IN_CALL }

var state := State.IDLE
## The ringing / active call (null for an outgoing call to a contact with no PhoneCallDef).
var current_call: PhoneCallDef
var current_contact: ContactDef
var playback: DialoguePlayback
## Seconds left before the ringing call is missed.
var ring_left := 0.0
## Play the generated ring tone.
var ring_sound := true

var _queue: Array[Dictionary] = []
var _next_handle := 1
## Call ids that can be returned, oldest first.
var _missed: Array[StringName] = []
var _ring_player: AudioStreamPlayer
var _call_ctx: ActionContext


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_ring_player = AudioStreamPlayer.new()
	_ring_player.name = "Ring"
	_ring_player.stream = _make_ring_tone()
	_ring_player.volume_db = -8.0
	add_child(_ring_player)


func _process(delta: float) -> void:
	for entry in _queue:
		entry["left"] -= delta
	if state == State.IDLE and not _queue.is_empty() and _can_ring():
		for i in _queue.size():
			if _queue[i]["left"] <= 0.0:
				var entry: Dictionary = _queue[i]
				_queue.remove_at(i)
				_ring(entry["call"])
				break
	match state:
		State.RINGING:
			ring_left -= delta
			if ring_left <= 0.0:
				_miss()
		State.IN_CALL:
			if playback != null:
				playback.tick(delta)


func _unhandled_input(event: InputEvent) -> void:
	if state == State.RINGING:
		if event.is_action_pressed(&"phone_answer"):
			answer()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed(&"phone_decline"):
			decline()
			get_viewport().set_input_as_handled()
	elif state == State.IN_CALL and event.is_action_pressed(&"phone_decline"):
		hang_up()
		get_viewport().set_input_as_handled()


# --- Scheduling --------------------------------------------------------------------------------

## Queues [param call] (PhoneCallDef or id) to ring after [param delay] seconds (and once the
## player is free). Returns a handle for [method cancel], or 0 if the call is unknown.
func schedule_call(call: Variant, delay := 0.0) -> int:
	var def := _resolve_call(call)
	if def == null:
		push_warning("PhoneService: unknown call %s" % [call])
		return 0
	var handle := _next_handle
	_next_handle += 1
	_queue.append({"handle": handle, "call": def, "left": maxf(delay, 0.0)})
	return handle


func cancel(handle: int) -> bool:
	for i in _queue.size():
		if _queue[i]["handle"] == handle:
			_queue.remove_at(i)
			return true
	return false


## Call ids still waiting to ring.
func pending_calls() -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry in _queue:
		ids.append((entry["call"] as PhoneCallDef).id)
	return ids


func is_ringing() -> bool:
	return state == State.RINGING


func in_call() -> bool:
	return state == State.IN_CALL


# --- Incoming ----------------------------------------------------------------------------------

func answer() -> bool:
	if state != State.RINGING:
		return false
	_ring_player.stop()
	var call := current_call
	_call_ctx = _make_ctx(call, current_contact)
	Effect.apply_all(call.on_answer, _call_ctx)
	return _start_conversation(call.resolve_dialogue(), call.choice_timeout, call.default_choice)


func decline() -> bool:
	if state != State.RINGING:
		return false
	var call := current_call
	_ring_player.stop()
	_add_missed(call)
	Effect.apply_all(call.on_decline, _make_ctx(call, current_contact))
	_finish(&"declined")
	return true


## Ends the active conversation early.
func hang_up() -> bool:
	if state != State.IN_CALL:
		return false
	_finish(&"hung_up")
	return true


# --- Missed calls / contacts -------------------------------------------------------------------

func missed_calls() -> Array[StringName]:
	return _missed.duplicate()


func has_missed_from(contact_id: StringName) -> bool:
	for call_id in _missed:
		var call := ContentDB.find_def(PhoneCallDef.TYPE, call_id) as PhoneCallDef
		if call != null and call.contact_id == contact_id:
			return true
	return false


## Returns a missed call (by call id or contact id): plays its conversation immediately.
func call_back(id: StringName) -> bool:
	if state != State.IDLE:
		return false
	for call_id in _missed:
		var call := ContentDB.find_def(PhoneCallDef.TYPE, call_id) as PhoneCallDef
		if call != null and (call.id == id or call.contact_id == id):
			_missed.erase(call_id)
			missed_changed.emit()
			current_call = call
			current_contact = call.contact()
			_call_ctx = _make_ctx(call, current_contact)
			Effect.apply_all(call.on_answer, _call_ctx)
			return _start_conversation(call.resolve_dialogue(), call.choice_timeout, call.default_choice)
	return false


## Outgoing call: returns a missed call from them, else plays the contact's call dialogue, else
## "No answer". Returns true when a conversation started.
func call_contact(contact_id: StringName) -> bool:
	if state != State.IDLE:
		return false
	if has_missed_from(contact_id):
		return call_back(contact_id)
	var contact := ContentDB.find_def(ContactDef.TYPE, contact_id) as ContactDef
	if contact == null:
		return false
	var dialogue := ContentDB.find_def(DialogueDef.TYPE, contact.call_dialogue_id) as DialogueDef if contact.call_dialogue_id != &"" else null
	if dialogue == null:
		EventBus.notify.emit("%s: No answer" % contact.label())
		return false
	current_call = null
	current_contact = contact
	_call_ctx = _make_ctx(null, contact)
	return _start_conversation(dialogue, 0.0, 0)


## Contacts the player can call (ContactDef.conditions met), sorted by name.
func contacts() -> Array[ContactDef]:
	var ctx := ActionContext.new(GameState.player, null)
	var result: Array[ContactDef] = []
	for def in ContentDB.all(ContactDef.TYPE):
		var contact := def as ContactDef
		if contact != null and contact.is_listed(ctx):
			result.append(contact)
	result.sort_custom(func(a: ContactDef, b: ContactDef) -> bool: return a.label() < b.label())
	return result


func caller_name() -> String:
	if current_call != null:
		return current_call.caller_name()
	return current_contact.label() if current_contact != null else ""


func caller_color() -> Color:
	return current_contact.color if current_contact != null else NarrativeUI.SPEAKER_COLOR


# --- Persistence -------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var queued: Array = []
	for entry in _queue:
		queued.append({"id": String((entry["call"] as PhoneCallDef).id), "left": entry["left"]})
	if state == State.RINGING and current_call != null:
		queued.push_front({"id": String(current_call.id), "left": 0.0})
	var missed: Array = []
	for call_id in _missed:
		missed.append(String(call_id))
	return {"queued": queued, "missed": missed}


func from_dict(data: Dictionary) -> void:
	reset()
	for entry: Dictionary in data.get("queued", []):
		schedule_call(StringName(entry.get("id", "")), float(entry.get("left", 0.0)))
	for call_id: String in data.get("missed", []):
		_missed.append(StringName(call_id))
	missed_changed.emit()


func reset() -> void:
	_ring_player.stop()
	if playback != null:
		var old := playback
		playback = null
		old.stop()
	_set_phone_pose(false)
	_queue.clear()
	_missed.clear()
	current_call = null
	current_contact = null
	_call_ctx = null
	if state != State.IDLE:
		state = State.IDLE
		state_changed.emit(state)
	missed_changed.emit()


# --- Internals ---------------------------------------------------------------------------------

func _resolve_call(call: Variant) -> PhoneCallDef:
	if call is PhoneCallDef:
		return call
	return ContentDB.find_def(PhoneCallDef.TYPE, StringName(str(call))) as PhoneCallDef if call != null else null


func _can_ring() -> bool:
	return not Narrative.is_cutscene_playing() and not Narrative.is_talking() \
			and not (Narrative.dialogue_view != null and Narrative.dialogue_view.is_open())


func _ring(call: PhoneCallDef) -> void:
	current_call = call
	current_contact = call.contact()
	ring_left = call.ring_time
	state = State.RINGING
	if ring_sound and _ring_player.is_inside_tree():
		_ring_player.play()
	state_changed.emit(state)
	ringing.emit(call)
	EventBus.phone_ringing.emit(call.id, call.contact_id)


func _miss() -> void:
	var call := current_call
	_ring_player.stop()
	_add_missed(call)
	Effect.apply_all(call.on_missed, _make_ctx(call, current_contact))
	EventBus.phone_call_missed.emit(call.id, call.contact_id)
	EventBus.notify.emit("Missed call: %s" % call.caller_name())
	_finish(&"missed")


func _add_missed(call: PhoneCallDef) -> void:
	if call.callback_allowed and not _missed.has(call.id):
		_missed.append(call.id)
		missed_changed.emit()


func _start_conversation(dialogue: DialogueDef, timeout: float, default_choice: int) -> bool:
	if dialogue == null:
		_finish(&"finished")
		return false
	state = State.IN_CALL
	state_changed.emit(state)
	var call_id := current_call.id if current_call != null else &""
	var contact_id := current_contact.id if current_contact != null else &""
	call_started.emit(call_id, contact_id)
	EventBus.phone_call_started.emit(call_id, contact_id)
	_set_phone_pose(true)
	playback = DialoguePlayback.new()
	playback.choice_timeout = timeout
	playback.default_choice = default_choice
	playback.finished.connect(_on_playback_finished)
	Narrative.ui.bind_playback(playback)
	if not playback.start(dialogue, _call_ctx):
		_finish(&"finished")
		return false
	return true


func _on_playback_finished(outcome: StringName) -> void:
	if state == State.IN_CALL:
		_finish(outcome if outcome != &"" else &"finished")


func _finish(outcome: StringName) -> void:
	var call := current_call
	var contact := current_contact
	var was_in_call := state == State.IN_CALL
	if playback != null:
		var old := playback
		playback = null
		old.stop()
	if was_in_call:
		_set_phone_pose(false)
		if call != null:
			Effect.apply_all(call.on_finished, _call_ctx if _call_ctx != null else _make_ctx(call, contact))
	current_call = null
	current_contact = null
	_call_ctx = null
	state = State.IDLE
	state_changed.emit(state)
	var call_id := call.id if call != null else &""
	var contact_id := contact.id if contact != null else &""
	call_ended.emit(call_id, contact_id, outcome)
	EventBus.phone_call_ended.emit(call_id, contact_id, outcome)


func _make_ctx(call: PhoneCallDef, contact: ContactDef) -> ActionContext:
	var ctx := ActionContext.new(GameState.player, null)
	var caller := contact.label() if contact != null else (call.caller_name() if call != null else "")
	ctx.vars["speakers"] = {&"npc": caller, &"caller": caller}
	if GameState.player != null:
		ctx.vars["speakers"][&"player"] = GameState.player
	ctx.vars["caller"] = caller
	if call != null:
		ctx.vars["call_id"] = call.id
	return ctx


func _set_phone_pose(on: bool) -> void:
	var visual := Narrative.visual_of(GameState.player)
	if visual != null:
		visual.set_phone(on)


## Two-tone trill, looping: 0.8 s ring, 1.2 s silence.
static func _make_ring_tone() -> AudioStreamWAV:
	var rate := 22050
	var data := PackedByteArray()
	var total := rate * 2
	data.resize(total * 2)
	for i in total:
		var t := float(i) / rate
		var sample := 0.0
		if t < 0.8:
			var tone := 880.0 if int(t * 20.0) % 2 == 0 else 1320.0
			sample = sin(TAU * tone * t) * 0.35 * minf(1.0, (0.8 - t) * 20.0)
		data.encode_s16(i * 2, int(sample * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = total
	return wav
