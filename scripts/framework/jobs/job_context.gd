class_name JobContext
extends ActionContext
## The shared ActionContext, specialised for the operations simulation. Passed to job behaviours,
## conditions and risk effects. `vars` always holds "model", plus "site_id", "district_id",
## "site_name", "crew_id", "crew_name" when known, so generic Conditions/Effects can read them.

var model: OperationsModel
var site: SiteData
var state: SiteState
var assignment: JobAssignment
var job: JobData
var crew: CrewMemberData


func stash() -> Inventory:
	return state.stash if state != null else null


func param(key: String, default: Variant = null) -> Variant:
	return assignment.param(key, default) if assignment != null else default


func take(item_id: StringName, amount: int) -> bool:
	return stash() != null and stash().remove(item_id, amount)


func give(item_id: StringName, amount: int) -> int:
	return stash().add(item_id, amount) if stash() != null else 0


## Pays (or with a negative amount, takes) player cash. Applied by the Operations autoload.
func pay(amount: int) -> void:
	model.add_income(amount, site.id if site != null else &"")


func add_heat(amount: float) -> void:
	if state != null:
		state.heat = maxf(0.0, state.heat + amount)


func skill() -> int:
	if crew == null or job == null:
		return 1
	return crew.skill_for(job.skill)


func set_status(status: JobAssignment.Status, reason: String = "") -> void:
	if assignment != null:
		model.set_status(assignment, status, reason)


## Completes one work cycle: job heat and crew xp.
func complete_cycle() -> void:
	if job == null:
		return
	add_heat(job.heat_per_cycle)
	if crew != null and crew.add_xp(job.skill, job.xp_per_cycle):
		model.emit_event(&"crew_levelled", {"crew_id": crew.id, "skill": job.skill, "level": crew.skill_for(job.skill)})
