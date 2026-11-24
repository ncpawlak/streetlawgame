class_name JobBehavior
extends Resource
## Strategy that decides what a job does each simulation step. Subclass to add new kinds of work
## (laundering, fencing, smuggling...) without touching OperationsModel. Behaviours only change
## state through the JobContext helpers, which keeps them deterministic and testable.

## Small tolerance so fractional progress gives identical results for any tick size.
const EPSILON := 0.000001


## "" when the assignment can run, otherwise the reason it's blocked.
func validate(_ctx: JobContext) -> String:
	return ""


func tick(_ctx: JobContext, _seconds: float) -> void:
	pass


## One-line status for the management UI.
func describe(_ctx: JobContext) -> String:
	return ""


## How much this assignment reduces risks at its site (0 = none, 1 = one full guard).
func risk_mitigation(_ctx: JobContext) -> float:
	return 0.0


## Parameters the UI should ask for when assigning: {param_key: [[value, label], ...]}.
func param_options(_model: OperationsModel, _site_id: StringName) -> Dictionary:
	return {}
