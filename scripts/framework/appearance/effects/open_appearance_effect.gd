class_name OpenAppearanceEffect
extends Effect
## Opens the appearance panel: &"wardrobe" (owned clothes, free), &"clothing" (clothing store) or
## &"barber". site_id empty = the business site the action is about (if any), for pricing.

@export var mode: StringName = &"wardrobe"
@export var site_id: StringName


func _describe(_ctx: ActionContext) -> String:
	return AppearancePanel.MODE_TITLES.get(mode, "Change look")


func _apply(ctx: ActionContext) -> void:
	var site := site_id if site_id != &"" else BusinessSiteDef.site_id_from(ctx)
	var anchor: Node3D = null
	if ctx.interactable is AppearanceStation:
		anchor = (ctx.interactable as AppearanceStation).anchor()
	PlayerAppearance.open_panel(mode, site, ctx.actor, anchor)
