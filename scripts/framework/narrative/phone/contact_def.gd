class_name ContactDef
extends ContentDef
## A phone contact (data/contacts/<id>.tres), e.g. "Mister Lou". Listed in the phone's contacts
## while [member conditions] pass; calling them plays [member call_dialogue_id] (or "No answer").

const TYPE := &"contacts"

## Caller-ID / subtitle colour.
@export var color := Color(0.55, 0.85, 1.0)
## Outgoing call conversation; empty = they don't pick up.
@export var call_dialogue_id: StringName
## Shown in the contacts list only while met (e.g. FlagCondition "met_lou").
@export var conditions: Array[Condition] = []


func is_listed(ctx: ActionContext) -> bool:
	return Condition.all_met(conditions, ctx)


func validate() -> PackedStringArray:
	var issues := super()
	if call_dialogue_id != &"" and ContentDB.find_def(DialogueDef.TYPE, call_dialogue_id) == null:
		issues.append("unknown call dialogue '%s'" % call_dialogue_id)
	return issues
