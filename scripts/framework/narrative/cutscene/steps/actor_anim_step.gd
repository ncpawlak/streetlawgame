class_name ActorAnimStep
extends CutsceneStep
## Plays a full-body clip on an actor's CharacterVisual (CharacterVisual.clip_names(), e.g. &"Wave",
## &"Interact", &"Idle_Gun_Pointing"), stops it, and/or raises the phone to the ear.

enum Phone { KEEP, ON, OFF }

@export var actor: StringName = &"player"
## Empty = no clip change (unless [member stop]).
@export var clip: StringName
@export var blend := 0.25
## Return to normal locomotion instead of playing a clip.
@export var stop := false
## Wait for the clip to play through before the next step.
@export var wait_for_clip := false
## Keep the clip after the scene ends (otherwise clips stop when actors are released).
@export var hold_after := false
@export var phone := Phone.KEEP


func begin(director: CutsceneDirector, state: Dictionary) -> void:
	var node := director.resolve(actor)
	var visual := Narrative.visual_of(node)
	if visual == null:
		push_warning("ActorAnimStep: '%s' has no CharacterVisual" % actor)
		return
	director.claim(node)
	if stop:
		visual.stop_clip(blend)
	elif clip != &"" and not visual.play_clip(clip, blend):
		push_warning("ActorAnimStep: unknown clip '%s'" % clip)
	if phone != Phone.KEEP:
		visual.set_phone(phone == Phone.ON)
	director.keep_clip(node, hold_after)
	state["t"] = 0.0
	state["length"] = CharacterVisual.clip_length(clip) if wait_for_clip and not stop else 0.0


func tick(_director: CutsceneDirector, state: Dictionary, delta: float) -> bool:
	if not state.has("t"):
		return true
	state["t"] += delta
	return state["t"] >= state["length"]


func skip(director: CutsceneDirector, state: Dictionary) -> void:
	if state.is_empty():
		begin(director, state)


func validate() -> PackedStringArray:
	var issues := PackedStringArray()
	if actor == &"":
		issues.append("needs an actor")
	if clip != &"" and not CharacterVisual.clip_names().has(String(clip)):
		issues.append("unknown clip '%s'" % clip)
	return issues
