class_name MissionJournal
extends RefCounted
## The Leads journal: things the player has heard about (who to see, where to look). Each lead is a
## plain Dictionary so it saves as-is:
## {id, title, note, mission_id, state (&"open" | &"done"), has_marker, marker (Vector3),
##  marker_unlocked, added_at}.
## A lead's map marker only shows once it's unlocked, so a rumour can name a place before the
## player knows where it is.

signal lead_changed(lead_id: StringName)

const OPEN := &"open"
const DONE := &"done"

var _leads: Dictionary = {}
var _order: Array[StringName] = []


## Adds (or updates) a lead. [param marker] is a Vector3 or null for no map marker.
func add_lead(lead_id: StringName, title: String, note := "", marker: Variant = null, marker_unlocked := true, mission_id: StringName = &"") -> Dictionary:
	var lead: Dictionary = _leads.get(lead_id, {})
	var is_new := lead.is_empty()
	lead["id"] = lead_id
	lead["title"] = title
	if note != "" or is_new:
		lead["note"] = note
	lead["mission_id"] = mission_id
	lead["state"] = lead.get("state", OPEN)
	if marker is Vector3:
		lead["has_marker"] = true
		lead["marker"] = marker
		lead["marker_unlocked"] = marker_unlocked
	elif is_new:
		lead["has_marker"] = false
		lead["marker"] = Vector3.ZERO
		lead["marker_unlocked"] = false
	lead["added_at"] = lead.get("added_at", GameState.play_time)
	_leads[lead_id] = lead
	if is_new:
		_order.append(lead_id)
		EventBus.notify.emit("New lead: %s" % title)
	lead_changed.emit(lead_id)
	return lead


func has_lead(lead_id: StringName) -> bool:
	return _leads.has(lead_id)


func get_lead(lead_id: StringName) -> Dictionary:
	return _leads.get(lead_id, {})


## Leads in the order they were added, optionally filtered by state.
func leads(state: StringName = &"") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for lead_id in _order:
		var lead: Dictionary = _leads[lead_id]
		if state == &"" or lead["state"] == state:
			out.append(lead)
	return out


func set_note(lead_id: StringName, note: String) -> void:
	if _leads.has(lead_id):
		_leads[lead_id]["note"] = note
		lead_changed.emit(lead_id)


func set_marker(lead_id: StringName, at: Vector3, unlocked := true) -> void:
	if not _leads.has(lead_id):
		return
	_leads[lead_id]["has_marker"] = true
	_leads[lead_id]["marker"] = at
	_leads[lead_id]["marker_unlocked"] = unlocked
	lead_changed.emit(lead_id)


func unlock_marker(lead_id: StringName) -> void:
	_set_marker_unlocked(lead_id, true)


func lock_marker(lead_id: StringName) -> void:
	_set_marker_unlocked(lead_id, false)


func is_marker_visible(lead_id: StringName) -> bool:
	var lead := get_lead(lead_id)
	return not lead.is_empty() and lead["has_marker"] and lead["marker_unlocked"] and lead["state"] == OPEN


func complete(lead_id: StringName) -> void:
	if _leads.has(lead_id) and _leads[lead_id]["state"] != DONE:
		_leads[lead_id]["state"] = DONE
		lead_changed.emit(lead_id)


func remove(lead_id: StringName) -> void:
	if _leads.erase(lead_id):
		_order.erase(lead_id)
		lead_changed.emit(lead_id)


func clear() -> void:
	_leads.clear()
	_order.clear()


func to_dict() -> Dictionary:
	var out: Array = []
	for lead_id in _order:
		out.append(_leads[lead_id].duplicate())
	return {"leads": out}


func from_dict(data: Dictionary) -> void:
	clear()
	for lead: Dictionary in data.get("leads", []):
		var lead_id := StringName(lead.get("id", ""))
		if lead_id == &"":
			continue
		var copy := lead.duplicate()
		copy["id"] = lead_id
		copy["state"] = StringName(copy.get("state", OPEN))
		copy["mission_id"] = StringName(copy.get("mission_id", ""))
		_leads[lead_id] = copy
		_order.append(lead_id)


func _set_marker_unlocked(lead_id: StringName, unlocked: bool) -> void:
	if _leads.has(lead_id) and _leads[lead_id]["marker_unlocked"] != unlocked:
		_leads[lead_id]["marker_unlocked"] = unlocked
		lead_changed.emit(lead_id)
