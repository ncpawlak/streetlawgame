class_name BarkEffect
extends Effect
## Barks a line over a node picked by [member on] (&"target", &"occupant", &"actor"...).

@export_multiline var text := ""
@export var on: StringName = &"target"
@export var subtitle := false


func _apply(ctx: ActionContext) -> void:
	var node := ctx.resolve(on) as Node3D
	if node != null:
		Narrative.bark(node, ctx.format(text), {"subtitle": subtitle, "force": true})
