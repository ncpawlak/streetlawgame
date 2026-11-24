class_name GuardBehavior
extends JobBehavior
## Stands watch at a site: reduces the chance of risks there (raids, robberies) and trains muscle.

## Mitigation per skill point; a skill-10 guard gives 1.0.
@export var mitigation_per_skill := 0.1
## Seconds of guard duty per completed cycle (xp grant).
@export var cycle_seconds := 60.0


func tick(ctx: JobContext, seconds: float) -> void:
	ctx.assignment.progress += seconds / maxf(cycle_seconds, 0.01)
	while ctx.assignment.progress >= 1.0 - EPSILON:
		ctx.assignment.progress = maxf(0.0, ctx.assignment.progress - 1.0)
		ctx.complete_cycle()
	ctx.set_status(JobAssignment.Status.ACTIVE)


func risk_mitigation(ctx: JobContext) -> float:
	return ctx.skill() * mitigation_per_skill


func describe(_ctx: JobContext) -> String:
	return "Guarding"
