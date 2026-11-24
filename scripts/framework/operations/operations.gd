extends Node
## Operations autoload: drives the OperationsModel on a timer and connects it to the game.
## Applies cash to GameState, forwards model events to EventBus, shows notifications, reveals plug
## markers, and opens the management panels (from door actions or the operations_menu key).

const MENU_ACTION := "operations_menu"

## Simulation step. Off-screen operations cost nothing between ticks.
@export var tick_seconds := 2.0
## Street sales are summed into one notification this often.
@export var report_seconds := 30.0

var model: OperationsModel
var panel: OperationsPanel

var _tick_timer: Timer
var _report_timer: Timer
var _sales_units := 0
var _sales_revenue := 0


func _ready() -> void:
	model = OperationsModel.new()
	model.rng.randomize()
	model.districts = WorldDistrictProvider.new()
	model.crew_source = func() -> Array: return GameState.crew
	model.spend_cash = func(amount: int) -> bool: return GameState.spend_cash(amount)
	_seed_starter_crew()
	model.setup()
	model.drain_events()
	_tick_timer = _make_timer(tick_seconds, func() -> void: simulate(tick_seconds))
	_report_timer = _make_timer(report_seconds, _report)
	_register_input()
	if EventBus.has_signal("district_owner_changed"):
		EventBus.connect("district_owner_changed", func(_district_id: StringName, _gang_id: StringName, _previous: StringName, _reason: StringName) -> void: refresh())
	if EventBus.has_signal("territory_captured"):
		EventBus.connect("territory_captured", func(_territory: Node, _gang_id: StringName) -> void: refresh())
	_sync_markers.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(MENU_ACTION) and GameState.player != null and (panel == null or not panel.is_open):
		open_overview()
		get_viewport().set_input_as_handled()


## Advances the simulation (also used for offline catch-up after loading).
func simulate(seconds: float) -> void:
	apply_events(model.step(seconds))


## Re-evaluates statuses without advancing time (district changed hands, etc.).
func refresh() -> void:
	apply_events(model.step(0.0))


## Forwards model events to the game. Call after changing the model outside step().
func apply_events(events: Array[Dictionary] = []) -> void:
	events.append_array(model.drain_events())
	for event in events:
		_apply(event)
	if panel != null and panel.is_open and not events.is_empty():
		panel.rebuild()


func open_overview() -> void:
	_panel().open_overview()


func open_site_panel(site_id: StringName) -> void:
	_panel().open_site(site_id)


func open_plug_panel(plug_id: StringName) -> void:
	_panel().open_plug(plug_id)
	apply_events()


func to_dict() -> Dictionary:
	return {"model": model.to_dict()}


func from_dict(data: Dictionary) -> void:
	model.from_dict(data.get("model", {}))
	_sync_markers()


func _apply(event: Dictionary) -> void:
	EventBus.operations_event.emit(event)
	match event.type:
		&"income":
			GameState.add_cash(event.amount)
		&"stash_changed":
			EventBus.stash_changed.emit(event.site_id, event.item_id, event.count)
		&"site_acquired":
			EventBus.site_acquired.emit(event.site_id)
			EventBus.notify.emit("%s is yours" % _site_name(event.site_id))
		&"job_assigned":
			EventBus.job_assigned.emit(event.assignment_id, event.crew_id, event.site_id, event.job_id)
		&"job_unassigned":
			EventBus.job_unassigned.emit(event.assignment_id, event.crew_id, event.site_id, event.job_id)
		&"job_status_changed":
			EventBus.job_status_changed.emit(event.assignment_id, event.site_id, event.status, event.reason)
			if event.status != JobAssignment.Status.ACTIVE and not str(event.reason).is_empty():
				EventBus.notify.emit("%s: %s" % [_site_name(event.site_id), event.reason])
		&"production_completed":
			EventBus.production_completed.emit(event.site_id, event.recipe_id, event.outputs)
		&"sale_completed":
			EventBus.sale_completed.emit(event.district_id, event.item_id, event.units, event.revenue)
			_sales_units += event.units
			_sales_revenue += event.revenue
		&"unlock_granted":
			EventBus.unlock_granted.emit(event.unlock_id)
		&"plug_revealed":
			EventBus.plug_revealed.emit(event.plug_id, event.location_id)
			EventBus.notify.emit("New contact: %s" % model.plug(event.plug_id).display_name)
			_sync_markers()
		&"plug_established":
			EventBus.plug_established.emit(event.plug_id)
			EventBus.notify.emit("You're in business with %s" % model.plug(event.plug_id).display_name)
		&"plug_relationship_changed":
			EventBus.plug_relationship_changed.emit(event.plug_id, event.relationship)
		&"operation_risk":
			EventBus.operation_risk.emit(event.risk_id, event.site_id, event.crew_id, event.text)
			if not str(event.text).is_empty():
				EventBus.notify.emit(event.text)
		&"crew_arrested":
			EventBus.notify.emit("%s got locked up" % _crew_name(event.crew_id))
		&"crew_released":
			EventBus.notify.emit("%s is back on the street" % _crew_name(event.crew_id))
		&"crew_levelled":
			EventBus.notify.emit("%s got better at %s" % [_crew_name(event.crew_id), event.skill])


func _report() -> void:
	if _sales_units > 0:
		EventBus.notify.emit("Street sales: +$%d (%d sold)" % [_sales_revenue, _sales_units])
	_sales_units = 0
	_sales_revenue = 0
	_sync_markers()


## Shows map markers on the meeting spots of revealed plugs (Location from the Locations autoload).
func _sync_markers() -> void:
	var locations := get_node_or_null("/root/Locations")
	if locations == null or not locations.has_method("get_location"):
		return
	for plug_id in model.plug_ids():
		var location: Node = locations.call("get_location", model.plug(plug_id).location_id)
		if location != null and location.has_method("set_marker_visible"):
			location.call("set_marker_visible", model.is_plug_revealed(plug_id))


## Adds the starter crew (data/crew entries with starter = true) to the player's gang once.
func _seed_starter_crew() -> void:
	for res in ContentDB.all(&"crew"):
		var member := res as CrewMemberData
		if member == null or not member.starter or model.crew(member.id) != null:
			continue
		GameState.crew.append(member.duplicate(true) as CrewMemberData)


func _panel() -> OperationsPanel:
	if panel == null:
		panel = OperationsPanel.new()
		panel.model = model
		panel.changed.connect(apply_events)
		add_child(panel)
	return panel


func _make_timer(wait: float, callback: Callable) -> Timer:
	var timer := Timer.new()
	timer.wait_time = wait
	timer.autostart = true
	timer.timeout.connect(callback)
	add_child(timer)
	return timer


func _register_input() -> void:
	if InputMap.has_action(MENU_ACTION):
		return
	InputMap.add_action(MENU_ACTION)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_O
	InputMap.action_add_event(MENU_ACTION, key)


func _site_name(site_id: StringName) -> String:
	var site_data := model.site(site_id)
	return site_data.display_name if site_data != null else String(site_id)


func _crew_name(crew_id: StringName) -> String:
	var member := model.crew(crew_id)
	return member.display_name if member != null else "A crew member"
