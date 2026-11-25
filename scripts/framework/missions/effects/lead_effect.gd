class_name LeadEffect
extends Effect
## Edits the Leads journal: add a lead, mark it done, or lock/unlock its map marker. The marker is
## placed at [member marker_target] (zone/tag id, resolved via Missions.locate) or [member marker_position].

enum Op { ADD, COMPLETE, UNLOCK_MARKER, LOCK_MARKER, REMOVE }

@export var op := Op.ADD
@export var lead_id: StringName
@export var title := ""
@export_multiline var note := ""
@export var mission_id: StringName
@export var has_marker := false
@export var marker_target: StringName
@export var marker_position := Vector3.ZERO
@export var marker_unlocked := true


func _apply(ctx: ActionContext) -> void:
	match op:
		Op.ADD:
			var marker: Variant = null
			if has_marker:
				marker = marker_position
				if marker_target != &"":
					var at: Variant = Missions.locate(marker_target)
					if at is Vector3:
						marker = at
			var text := ctx.format(note) if ctx != null else note
			Missions.add_lead(lead_id, title, text, marker, marker_unlocked, mission_id)
		Op.COMPLETE:
			Missions.journal.complete(lead_id)
		Op.UNLOCK_MARKER:
			Missions.journal.unlock_marker(lead_id)
		Op.LOCK_MARKER:
			Missions.journal.lock_marker(lead_id)
		Op.REMOVE:
			Missions.journal.remove(lead_id)


func _describe(_ctx: ActionContext) -> String:
	return "New lead: %s" % title if op == Op.ADD else "Lead %s" % lead_id
