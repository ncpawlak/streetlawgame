class_name RiskData
extends ContentDef
## Something bad that can happen to a running operation (raid, robbery, burned plug). Rolled each
## simulation step; effects are shared Effect resources run with the operation's JobContext.

@export var chance_per_minute := 0.02
## Extra chance per minute per point of site heat.
@export var heat_multiplier := 0.001
## How strongly guards reduce the chance (1.0 = a skill-10 guard cancels it).
@export var guard_mitigation := 0.5
@export var effects: Array[Effect] = []
## Shown when it fires; formatted with ctx.vars ({site_name}, {district_name}, {crew_name}...).
@export var notify_text := ""


func chance(heat: float, mitigation: float, seconds: float) -> float:
	var per_minute := chance_per_minute + heat * heat_multiplier
	var guarded := clampf(1.0 - mitigation * guard_mitigation, 0.0, 1.0)
	return clampf(per_minute * seconds / 60.0 * guarded, 0.0, 1.0)
