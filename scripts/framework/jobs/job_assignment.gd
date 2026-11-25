class_name JobAssignment
extends RefCounted
## Runtime record of one job running at a site (optionally staffed by a crew member).

enum Status { ACTIVE, STARVED, BLOCKED, FULL }

var id := 0
## Empty for jobs that don't need crew (passive business income).
var crew_id: StringName
var site_id: StringName
var job_id: StringName
## Job-specific choices, e.g. {"recipe_id": &"grow_weed"} or {"district_id": &"tamarack_row"}.
var params := {}
## Fractional cycles accumulated by the behaviour.
var progress := 0.0
var status := Status.ACTIVE
var status_reason := ""


func param(key: String, default: Variant = null) -> Variant:
	return params.get(key, default)


func to_dict() -> Dictionary:
	var stored := {}
	for key: String in params:
		stored[key] = str(params[key]) if params[key] is StringName else params[key]
	return {
		"id": id, "crew_id": String(crew_id), "site_id": String(site_id), "job_id": String(job_id),
		"params": stored, "progress": progress, "status": status, "status_reason": status_reason,
	}


static func from_dict(data: Dictionary) -> JobAssignment:
	var assignment := JobAssignment.new()
	assignment.id = int(data.get("id", 0))
	assignment.crew_id = StringName(str(data.get("crew_id", "")))
	assignment.site_id = StringName(str(data.get("site_id", "")))
	assignment.job_id = StringName(str(data.get("job_id", "")))
	var stored: Dictionary = data.get("params", {})
	for key: String in stored:
		assignment.params[key] = StringName(stored[key]) if stored[key] is String else stored[key]
	assignment.progress = float(data.get("progress", 0.0))
	assignment.status = int(data.get("status", Status.ACTIVE)) as Status
	assignment.status_reason = str(data.get("status_reason", ""))
	return assignment
