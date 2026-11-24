class_name CooldownCondition
extends Condition
## The action hasn't been performed on this interactable within [member seconds] of play time, and
## (optionally) fewer than [member max_uses] times. Reads ctx.memory[action id].

@export var seconds := 0.0
## 0 = unlimited.
@export var max_uses := 0


func _evaluate(ctx: ActionContext) -> bool:
	var entry := _entry(ctx)
	if max_uses > 0 and int(entry.get("count", 0)) >= max_uses:
		return false
	return GameState.play_time - float(entry.get("last", -INF)) >= seconds


func _reason(ctx: ActionContext) -> String:
	var entry := _entry(ctx)
	if max_uses > 0 and int(entry.get("count", 0)) >= max_uses:
		return "Already done"
	var left := seconds - (GameState.play_time - float(entry.get("last", -INF)))
	return "Wait %ds" % ceili(left)


func _entry(ctx: ActionContext) -> Dictionary:
	if ctx.action == null:
		return {}
	return ctx.memory.get(ctx.action.id, {})
