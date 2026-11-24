class_name JobData
extends ContentDef
## A kind of work at a site: cook, dealer, guard, front manager... Rules live in the pluggable
## `behavior`; everything else is tuning and gating.

## Crew skill this job uses and trains, e.g. &"cooking", &"dealing", &"muscle".
@export var skill: StringName
@export var requires_crew := true
@export var behavior: JobBehavior
## Extra gates evaluated with the job's context (vars: model, site_id, district_id, crew_id).
@export var conditions: Array[Condition] = []
## Risks that only exist while this job runs (e.g. dealer robbed).
@export var risks: Array[RiskData] = []
## Heat added to the site each time the behaviour completes a cycle.
@export var heat_per_cycle := 0.0
@export var xp_per_cycle := 1


func validate() -> PackedStringArray:
	var issues := super.validate()
	if behavior == null:
		issues.append("%s: no behavior" % id)
	return issues
