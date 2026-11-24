class_name IntelEffect
extends Effect
## Grants a piece of intel: sets flag "intel:<intel_id>" and emits EventBus.intel_gained.
## Optionally reveals the map markers of locations of [member reveal_kind] (e.g. rival fronts).

@export var intel_id := &""
@export var message := ""
@export var reveal_kind := &""


func _apply(ctx: ActionContext) -> void:
	GameState.set_flag(StringName("intel:%s" % intel_id), true)
	if reveal_kind != &"":
		for location in Locations.query(reveal_kind):
			location.set_marker_visible(true)
	EventBus.intel_gained.emit(intel_id, ctx.format(message))
	if message != "":
		EventBus.notify.emit(ctx.format(message))


func _describe(_ctx: ActionContext) -> String:
	return "Intel: %s" % intel_id
