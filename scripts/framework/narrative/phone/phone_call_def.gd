class_name PhoneCallDef
extends ContentDef
## A scripted incoming call (data/phone_calls/<id>.tres): who calls, the conversation played over
## gameplay when answered, and what happens on answer / decline / missed. Trigger with
## Narrative.phone.schedule_call(id, delay) or PhoneCallEffect.

const TYPE := &"phone_calls"

@export var contact_id: StringName
@export var dialogue: DialogueDef
## Used when [member dialogue] is empty.
@export var dialogue_id: StringName
## Seconds it rings before counting as missed.
@export var ring_time := 12.0
## A missed / declined call can be returned from the contacts list (plays the same conversation).
@export var callback_allowed := true
## Seconds before a timed choice auto-picks; 0 = waits for the player.
@export var choice_timeout := 0.0
@export var default_choice := 0
@export var on_answer: Array[Effect] = []
@export var on_decline: Array[Effect] = []
@export var on_missed: Array[Effect] = []
## Applied when the conversation ends (any outcome, including a call-back).
@export var on_finished: Array[Effect] = []


func contact() -> ContactDef:
	return ContentDB.find_def(ContactDef.TYPE, contact_id) as ContactDef if contact_id != &"" else null


## Caller display name.
func caller_name() -> String:
	var who := contact()
	return who.label() if who != null else String(contact_id).capitalize()


func resolve_dialogue() -> DialogueDef:
	if dialogue != null:
		return dialogue
	return ContentDB.find_def(DialogueDef.TYPE, dialogue_id) as DialogueDef if dialogue_id != &"" else null


func validate() -> PackedStringArray:
	var issues := super()
	if contact_id == &"":
		issues.append("needs a contact_id")
	elif contact() == null:
		issues.append("unknown contact '%s'" % contact_id)
	if resolve_dialogue() == null:
		issues.append("needs a dialogue")
	return issues
