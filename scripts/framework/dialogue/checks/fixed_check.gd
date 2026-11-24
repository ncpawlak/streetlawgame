class_name FixedCheck
extends SkillCheck
## Constant odds (simple content, tests). min/max clamps still apply; set them to 0/1 for certainty.

@export_range(0.0, 1.0) var odds := 0.5


func _chance(_ctx: ActionContext) -> float:
	return odds