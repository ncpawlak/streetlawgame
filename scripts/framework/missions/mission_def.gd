class_name MissionDef
extends ContentDef
## A mission: an ordered list of [MissionStep]s plus side/bonus objectives, fail rules, rewards and
## unlocks. Lives in data/missions/<id>.tres (or ContentDB.register for code-built missions).
## Started by [MissionStartMarker], StartMissionEffect or Missions.start_mission().

const TYPE := &"missions"

## Who gives it, for the journal ("Pedro").
@export var giver := ""
## Must be unlocked (Missions.unlock_mission, another mission's unlock_missions) before it can start.
@export var requires_unlock := false
@export var repeatable := false
@export var start_conditions: Array[Condition] = []
@export var steps: Array[MissionStep] = []
## Run in parallel with the main steps. Achieved ones grant their bonus_rewards on completion;
## missed ones never fail the mission.
@export var side_objectives: Array[MissionStep] = []
## Mission-wide fail rules (any step).
@export var fail_conditions: Array[MissionFail] = []
## Dying fails the mission (adds a PlayerDiedFail).
@export var fail_on_death := true
@export var cash_reward := 0
@export var respect_reward := 0
## Extra completion effects (leads, flags, unlock grants...).
@export var rewards: Array[Effect] = []
## PlayerSafehouseDef ids unlocked on completion.
@export var unlock_safehouses: Array[StringName] = []
## MissionDef ids unlocked on completion.
@export var unlock_missions: Array[StringName] = []
## Optional default start position (map marker when no MissionStartMarker is placed).
@export var start_position := Vector3.ZERO
@export var has_start_position := false


func reward_text() -> String:
	var parts: PackedStringArray = []
	if cash_reward != 0:
		parts.append("$%d" % cash_reward)
	if respect_reward != 0:
		parts.append("%+d respect" % respect_reward)
	for effect in rewards:
		if effect != null:
			var text := effect.describe()
			if text != "":
				parts.append(text)
	for safehouse_id in unlock_safehouses:
		var def := ContentDB.find_def(PlayerSafehouseDef.TYPE, safehouse_id)
		parts.append("Safehouse: %s" % (def.label() if def != null else String(safehouse_id)))
	return ", ".join(parts)


func validate() -> PackedStringArray:
	var problems := super.validate()
	if steps.is_empty():
		problems.append("mission %s has no steps" % id)
	var seen := {}
	for step in steps + side_objectives:
		if step == null:
			problems.append("mission %s has an empty step" % id)
			continue
		if step.id != &"" and seen.has(step.id):
			problems.append("mission %s repeats step id %s" % [id, step.id])
		seen[step.id] = true
		problems.append_array(step.validate())
	return problems
