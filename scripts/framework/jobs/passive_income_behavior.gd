class_name PassiveIncomeBehavior
extends JobBehavior
## Pays a flat income over time (fronts, legit businesses). Usually on a job with requires_crew = false.

@export var income_per_minute := 60


func tick(ctx: JobContext, seconds: float) -> void:
	ctx.assignment.progress += seconds * income_per_minute / 60.0
	var whole := floori(ctx.assignment.progress + EPSILON)
	if whole > 0:
		ctx.assignment.progress = maxf(0.0, ctx.assignment.progress - whole)
		ctx.pay(whole)
	ctx.set_status(JobAssignment.Status.ACTIVE)


func describe(_ctx: JobContext) -> String:
	return "$%d/min" % income_per_minute
