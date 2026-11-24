class_name ProductionBehavior
extends JobBehavior
## Runs a RecipeData (params.recipe_id) in a loop: consume inputs from the site stash, wait
## cycle_seconds (faster with skill), add outputs. STARVED without inputs, FULL without space.


func validate(ctx: JobContext) -> String:
	var recipe := ctx.model.recipe(ctx.param("recipe_id", &""))
	if recipe == null:
		return "Pick something to make"
	return ctx.model.recipe_block_reason(recipe, ctx.site)


func tick(ctx: JobContext, seconds: float) -> void:
	var recipe := ctx.model.recipe(ctx.param("recipe_id", &""))
	var speed := 1.0 + (ctx.skill() - 1) * recipe.skill_speed_bonus
	var assignment := ctx.assignment
	assignment.progress += seconds * speed / maxf(recipe.cycle_seconds, 0.01)
	while assignment.progress >= 1.0 - EPSILON:
		if not ctx.stash().has_all(recipe.inputs):
			assignment.progress = minf(assignment.progress, 1.0)
			ctx.set_status(JobAssignment.Status.STARVED, "Out of supplies")
			return
		if _net_units(recipe) > ctx.stash().free_space():
			assignment.progress = minf(assignment.progress, 1.0)
			ctx.set_status(JobAssignment.Status.FULL, "Stash is full")
			return
		for stack in recipe.inputs:
			ctx.take(stack.item_id, stack.count)
		var produced := {}
		for stack in recipe.outputs:
			produced[stack.item_id] = ctx.give(stack.item_id, stack.count)
			var item := ctx.model.item(stack.item_id)
			if item != null:
				ctx.add_heat(item.heat_per_unit * stack.count)
		assignment.progress = maxf(0.0, assignment.progress - 1.0)
		ctx.complete_cycle()
		ctx.model.emit_event(&"production_completed", {"site_id": ctx.site.id, "recipe_id": recipe.id, "outputs": produced})
	ctx.set_status(JobAssignment.Status.ACTIVE)


func describe(ctx: JobContext) -> String:
	var recipe := ctx.model.recipe(ctx.param("recipe_id", &""))
	return "Making %s (%d%%)" % [recipe.display_name, roundi(ctx.assignment.progress * 100.0)] if recipe != null else ""


func param_options(model: OperationsModel, site_id: StringName) -> Dictionary:
	var options: Array = []
	for recipe in model.available_recipes(site_id):
		options.append([recipe.id, recipe.display_name])
	return {"recipe_id": options}


func _net_units(recipe: RecipeData) -> int:
	var net := 0
	for stack in recipe.outputs:
		net += stack.count
	for stack in recipe.inputs:
		net -= stack.count
	return net
