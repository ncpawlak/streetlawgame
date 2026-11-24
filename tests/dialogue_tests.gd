class_name DialogueTests
extends RefCounted
## Tests for the dialogue framework (runner flow, checks, costs, content, Talk action + view).
## Hooked from FrameworkTests.

var _framework: FrameworkTests
var _player: Player


func _init(framework: FrameworkTests) -> void:
	_framework = framework


func run(main: Node, player: Player) -> void:
	_player = player
	_test_content()
	_test_runner_flow()
	_test_skill_checks()
	await _framework.with_sandbox(main, _test_recruit_once)
	await _test_talk_and_view(main)


func _check(condition: bool, description: String) -> void:
	_framework.check(condition, description)


static func _fixed(odds: float) -> FixedCheck:
	var check := FixedCheck.new()
	check.odds = odds
	check.min_chance = 0.0
	check.max_chance = 1.0
	return check


static func _choice(text: String, next: StringName, configure: Callable = Callable()) -> DialogueChoice:
	var choice := DialogueChoice.new()
	choice.text = text
	choice.next = next
	if configure.is_valid():
		configure.call(choice)
	return choice


static func _make_node(id: StringName, outcome: StringName, choices: Array[DialogueChoice]) -> DialogueNode:
	var node := DialogueNode.new()
	node.id = id
	node.outcome = outcome
	node.choices = choices
	return node


func _test_content() -> void:
	var dialogues := ContentDB.all(DialogueDef.TYPE)
	_check(dialogues.size() >= 4, "dialogues are loaded from data/dialogues")
	var clean := true
	for def: DialogueDef in dialogues:
		clean = clean and def.validate().is_empty()
	_check(clean, "shipped dialogues validate")
	var clerk := ContentDB.get_def(OccupantDef.TYPE, &"clerk") as OccupantDef
	_check(clerk.dialogue_id == &"clerk" and Location.talk_action_for(clerk) != null, "occupants with a dialogue get the Talk action")
	var broken := DialogueDef.new()
	broken.id = &"broken"
	broken.nodes = [_make_node(&"start", &"", [_choice("go", &"nowhere")])] as Array[DialogueNode]
	_check(not broken.validate().is_empty(), "validate() flags links to missing nodes")


func _test_runner_flow() -> void:
	var cash_before := GameState.cash
	var reward := CashEffect.new()
	reward.amount = 50
	var penalty := RespectEffect.new()
	penalty.amount = -1
	var pricey := CashCost.new()
	pricey.amount = 1000000
	var hidden_gate := FlagCondition.new()
	hidden_gate.flag = &"test_dialogue_never_set"
	hidden_gate.hide_when_unmet = true
	var def := DialogueDef.new()
	def.id = &"test_dialogue"
	def.nodes = [
		_make_node(&"start", &"", [
			_choice("win", &"won", func(c: DialogueChoice) -> void:
				c.check = _fixed(1.0)
				c.effects = [reward] as Array[Effect]),
			_choice("lose", &"won", func(c: DialogueChoice) -> void:
				c.check = _fixed(0.0)
				c.fail_effects = [penalty] as Array[Effect]
				c.fail_next = &"lost"),
			_choice("expensive", &"won", func(c: DialogueChoice) -> void: c.costs = [pricey] as Array[Cost]),
			_choice("secret", &"won", func(c: DialogueChoice) -> void: c.conditions = [hidden_gate] as Array[Condition]),
		]),
		_make_node(&"won", &"won", [] as Array[DialogueChoice]),
		_make_node(&"lost", &"lost", [] as Array[DialogueChoice]),
	] as Array[DialogueNode]
	_check(def.validate().is_empty(), "a well-formed dialogue validates")

	var runner := DialogueRunner.new()
	var results: Array[StringName] = []
	runner.ended.connect(func(_id: StringName, outcome: StringName) -> void: results.append(outcome))
	_check(runner.start(def, ActionContext.new(_player)) and runner.current().id == &"start", "the runner starts at the start node")
	var shown := runner.choices()
	_check(shown.size() == 3, "choices with unmet hiding conditions are hidden")
	_check(runner.choice_state(shown[2]) != "" and not runner.choose(2) and runner.current().id == &"start", "unaffordable choices report why and can't be picked")
	_check(shown[0].make_label(runner.ctx).ends_with("(100%)") and shown[2].make_label(runner.ctx).contains("$"), "labels show odds and costs")
	_check(runner.choose(0) and runner.current().id == &"won" and GameState.cash == cash_before + 50, "a passed check applies effects and follows next")
	runner.end()
	_check(not runner.is_active() and results.size() == 1 and results[0] == &"won", "ending reports the outcome")

	var respect_before := GameState.respect
	runner.start(def, ActionContext.new(_player))
	_check(not runner.choose(1) and runner.current().id == &"lost" and GameState.respect == respect_before - 1, "a failed check applies fail_effects and follows fail_next")
	runner.end()
	GameState.cash = cash_before
	GameState.respect = respect_before
	EventBus.cash_changed.emit(GameState.cash)


func _test_skill_checks() -> void:
	var ctx := ActionContext.new(_player)
	var intimidate := IntimidateCheck.new()
	var previous := _player.weapons.current_index
	_player.weapons.select(0)
	var unarmed := _player.weapons.current().data.id == &"fists"
	_check(not unarmed or intimidate.chance(ctx) == 0.0, "intimidation needs a drawn weapon")
	var armed_index := -1
	for i in _player.weapons.slots.size():
		if _player.weapons.slots[i].data.id != &"fists":
			armed_index = i
			break
	if armed_index >= 0:
		_player.weapons.select(armed_index)
		_check(intimidate.chance(ctx) > 0.0, "a drawn weapon makes intimidation possible")
	_player.weapons.select(previous)
	var persuade := PersuadeCheck.new()
	var respect_before := GameState.respect
	GameState.respect = 0
	var low := persuade.chance(ctx)
	GameState.respect = 50
	_check(persuade.chance(ctx) > low, "respect improves persuasion")
	GameState.respect = respect_before
	var rolls := 0
	var check := _fixed(1.0)
	for i in 5:
		rolls += 1 if check.roll(ctx) else 0
	_check(rolls == 5 and ctx.vars.get("check_passed") == true, "roll() records its result in ctx.vars")


func _test_recruit_once() -> void:
	var def := ContentDB.get_def(LocationDef.TYPE, &"bar") as LocationDef
	var at := Transform3D(Basis.IDENTITY, FrameworkTests.SANDBOX + Vector3(0.0, 0.0, -6.0))
	var bar := Locations.spawn(def, at, _framework.sandbox(), &"test_bar")
	var occupant := Occupant.create(ContentDB.get_def(OccupantDef.TYPE, &"barfly") as OccupantDef, bar, false)
	var ctx := ActionContext.new(_player, bar)
	ctx.location = bar
	ctx.occupant = occupant
	var cash_before := GameState.cash
	var crew_before := GameState.crew.size()
	GameState.cash = cash_before + 1000
	var runner := DialogueRunner.new()
	runner.start(ContentDB.get_def(DialogueDef.TYPE, &"barfly") as DialogueDef, ctx)
	var pay_index := -1
	var shown := runner.choices()
	for i in shown.size():
		if not shown[i].costs.is_empty():
			pay_index = i
	_check(pay_index >= 0 and runner.choose(pay_index) and runner.outcome == &"recruited", "paying the barfly recruits them")
	_check(GameState.crew.size() == crew_before + 1 and GameState.cash == cash_before + 800, "recruiting adds crew and takes the cost")
	runner.end()
	runner.start(ContentDB.get_def(DialogueDef.TYPE, &"barfly") as DialogueDef, ctx)
	_check(runner.choices().size() == 1, "recruit choices are hidden once this location's barfly has joined")
	runner.end()
	var mood := bar.state.disposition(&"barfly")
	DispositionEffect.new().apply(ctx)
	var shift := DispositionEffect.new()
	shift.fear = 2.0
	shift.apply(ctx)
	_check(float(mood["fear"]) == 1.0, "disposition is stored per location and clamped")
	occupant.free()
	GameState.crew.resize(crew_before)
	GameState.cash = cash_before
	EventBus.cash_changed.emit(GameState.cash)
	Locations.forget(&"test_bar")


func _test_talk_and_view(main: Node) -> void:
	var view: DialogueView = main.get_node("HUD").dialogue_view
	var informant := Locations.get_location(&"informant_flat")
	var talk := informant.door.find_action(&"talk_informant")
	_check(talk != null, "door-only occupants with a dialogue offer Talk on the door")
	if talk == null:
		return
	var informant_state := informant.state.to_dict()
	var cash_before := GameState.cash
	GameState.cash = cash_before + 1000
	var started: Array[StringName] = []
	var on_started := func(id: StringName, _target: Node) -> void: started.append(id)
	EventBus.dialogue_started.connect(on_started)
	_check(informant.door.perform(&"talk_informant", _player), "the Talk action runs")
	await _framework.frames(2)
	_check(view.is_open() and view.visible and main.get_tree().paused, "the dialogue view opens and pauses the game")
	_check(started.size() == 1 and started[0] == &"informant" and view.runner.text().contains("Informant"), "the occupant's dialogue starts with {occupant} filled in")
	_check(view.pick(0) and GameState.has_flag(&"intel:rival_fronts") and GameState.cash == cash_before + 750, "paying the informant gives intel")
	_check(view.is_open() and view.runner.choices().is_empty(), "the reply node has no choices")
	view.pick(0)
	_check(not view.is_open() and not view.visible and not main.get_tree().paused, "leaving closes the view and unpauses")
	EventBus.dialogue_started.disconnect(on_started)
	for location in Locations.query(&"front"):
		location.set_marker_visible(false)
	GameState.flags.erase(&"intel:rival_fronts")
	informant.state.from_dict(informant_state)
	GameState.cash = cash_before
	EventBus.cash_changed.emit(GameState.cash)