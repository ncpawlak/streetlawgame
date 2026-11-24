class_name CrewMemberData
extends Resource
## A recruited gang member. Jobs (dealing, cooking, guarding...) are assigned through the
## Operations framework, which reads skills/status from here and grants xp.

## Deprecated: kept so existing data keeps loading. Live assignments live in Operations.
enum Assignment { IDLE, FOLLOW, DEALING, GUARDING }
enum Status { ACTIVE, INJURED, ARRESTED, DEAD }

## Xp needed per skill level-up.
const XP_PER_LEVEL := 10
const MAX_SKILL := 10

@export var id: StringName
@export var display_name := ""
## Fallback level for any skill not listed in `skills`.
@export_range(1, 10) var skill := 1
## Per-skill levels (1..10), e.g. {&"cooking": 4, &"dealing": 2, &"muscle": 6}.
@export var skills: Dictionary = {}
@export_range(0, 100) var loyalty := 50
@export var status := Status.ACTIVE
## Seeded into the starting crew by Operations.
@export var starter := false
@export_file var portrait_path := ""
@export var visual: VisualSpec
@export var assignment := Assignment.IDLE
@export var assigned_territory: StringName

## Accumulated xp per skill id.
var xp := {}

static var _next_id := 1


## Creates a member with a unique id. Use this instead of new() for recruits.
static func create(member_name: String, member_skills: Dictionary = {}) -> CrewMemberData:
	var member := CrewMemberData.new()
	member.id = StringName("crew_%d_%d" % [Time.get_ticks_usec(), _next_id])
	_next_id += 1
	member.display_name = member_name
	member.skills = member_skills.duplicate()
	return member


func skill_for(skill_id: StringName) -> int:
	return clampi(int(skills.get(skill_id, skill)), 1, MAX_SKILL)


func is_available() -> bool:
	return status == Status.ACTIVE


## Adds xp to a skill and levels it up every XP_PER_LEVEL. Returns true if it levelled up.
func add_xp(skill_id: StringName, amount: int) -> bool:
	if skill_id.is_empty() or amount <= 0:
		return false
	var total: int = int(xp.get(skill_id, 0)) + amount
	var levelled := false
	while total >= XP_PER_LEVEL:
		total -= XP_PER_LEVEL
		if skill_for(skill_id) < MAX_SKILL:
			skills[skill_id] = skill_for(skill_id) + 1
			levelled = true
	xp[skill_id] = total
	return levelled


func to_dict() -> Dictionary:
	var stored_skills := {}
	for key: StringName in skills:
		stored_skills[String(key)] = skills[key]
	var stored_xp := {}
	for key: StringName in xp:
		stored_xp[String(key)] = xp[key]
	return {
		"id": String(id), "display_name": display_name, "skill": skill, "skills": stored_skills,
		"xp": stored_xp, "loyalty": loyalty, "status": status, "starter": starter,
	}


static func from_dict(data: Dictionary) -> CrewMemberData:
	var member := CrewMemberData.new()
	member.id = StringName(str(data.get("id", "")))
	member.display_name = str(data.get("display_name", ""))
	member.skill = int(data.get("skill", 1))
	member.loyalty = int(data.get("loyalty", 50))
	member.status = int(data.get("status", Status.ACTIVE)) as Status
	member.starter = bool(data.get("starter", false))
	var stored_skills: Dictionary = data.get("skills", {})
	for key: String in stored_skills:
		member.skills[StringName(key)] = int(stored_skills[key])
	var stored_xp: Dictionary = data.get("xp", {})
	for key: String in stored_xp:
		member.xp[StringName(key)] = int(stored_xp[key])
	return member
