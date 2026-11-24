class_name Interactor
extends Area3D
## Lives on an actor (the Player). Finds Interactables in range, keeps the best one focused, and runs
## actions: instant ones immediately, channelled ones after the actor holds still for their duration.
## UI (InteractionPrompt / InteractionMenu) observes it through its signals.

signal focus_changed(interactable: Interactable)
## Emitted when the focused interactable offers more than one action and the player pressed interact.
signal menu_requested(interactable: Interactable, actions: Array[InteractionAction])
signal channel_started(action: InteractionAction, interactable: Interactable)
signal channel_finished(action: InteractionAction, completed: bool)

## Seconds between focus re-evaluations.
@export var refresh_interval := 0.1
## How much facing an interactable (camera forward) counts against distance when picking focus.
@export var facing_weight := 1.5
@export var reach_radius := 0.5

var actor: Node3D
var focused: Interactable
var channel_action: InteractionAction
var channel_target: Interactable
var channel_ctx: ActionContext
var channel_elapsed := 0.0

var _refresh_left := 0.0
var _last_health := -1.0


func _ready() -> void:
	actor = get_parent() as Node3D
	collision_layer = 0
	collision_mask = Interactable.LAYER
	monitoring = true
	monitorable = false
	position = Vector3(0.0, 1.0, 0.0)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = reach_radius
	shape.shape = sphere
	add_child(shape)
	if actor != null and "health" in actor:
		_last_health = float(actor.get("health"))
	EventBus.player_health_changed.connect(_on_health_changed)


func _physics_process(delta: float) -> void:
	if is_channelling():
		_update_channel(delta)
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = refresh_interval
		refresh()


func is_channelling() -> bool:
	return channel_action != null


## Channel progress from 0 to 1.
func channel_fraction() -> float:
	if channel_action == null or channel_action.duration <= 0.0:
		return 0.0
	return clampf(channel_elapsed / channel_action.duration, 0.0, 1.0)


func can_interact() -> bool:
	if actor == null or not actor.is_inside_tree() or not actor.visible:
		return false
	return not actor.has_method("is_on_foot") or actor.call("is_on_foot")


## Re-evaluates which interactable has focus.
func refresh() -> void:
	var best: Interactable = null
	if can_interact():
		var best_score := INF
		for area in get_overlapping_areas():
			var candidate := area as Interactable
			if candidate == null or not candidate.enabled or candidate.visible_actions(actor).is_empty():
				continue
			var score := _score(candidate)
			if score < best_score:
				best_score = score
				best = candidate
	_set_focus(best)


## The focused interactable's actions for this actor.
func focused_actions() -> Array[InteractionAction]:
	if focused == null or not is_instance_valid(focused):
		return []
	return focused.visible_actions(actor)


## Handles an interact press. Returns true when it was consumed.
func try_interact() -> bool:
	if is_channelling():
		return true
	refresh()
	var listed := focused_actions()
	if listed.is_empty():
		return false
	if listed.size() > 1 and menu_requested.get_connections().size() > 0:
		menu_requested.emit(focused, listed)
		return true
	for action in listed:
		if action.is_available(focused.make_context(actor, action)):
			start(action)
			return true
	start(listed[0])
	return true


## Starts [param action] on [param interactable] (default: the focused one). Unavailable actions
## show their reason and return false.
func start(action: InteractionAction, interactable: Interactable = null) -> bool:
	var on := interactable if interactable != null else focused
	if on == null or action == null or is_channelling():
		return false
	var ctx := on.make_context(actor, action)
	if not action.is_available(ctx):
		var reason := action.unavailable_reason(ctx)
		if reason != "":
			EventBus.notify.emit(reason)
		return false
	if action.duration <= 0.0:
		return on.run(action, ctx)
	channel_action = action
	channel_target = on
	channel_ctx = ctx
	channel_elapsed = 0.0
	channel_started.emit(action, on)
	return true


func cancel_channel(reason: String = "Interrupted") -> void:
	if not is_channelling():
		return
	var action := channel_action
	_clear_channel()
	if reason != "":
		EventBus.notify.emit(reason)
	channel_finished.emit(action, false)


func _update_channel(delta: float) -> void:
	if not is_instance_valid(channel_target) or not can_interact():
		cancel_channel()
		return
	if channel_action.cancel_on_leave and not get_overlapping_areas().has(channel_target):
		cancel_channel()
		return
	channel_elapsed += delta
	if channel_elapsed < channel_action.duration:
		return
	var action := channel_action
	var on := channel_target
	var ctx := channel_ctx
	_clear_channel()
	var completed := on.run(action, ctx)
	if not completed:
		var reason := action.unavailable_reason(ctx)
		if reason != "":
			EventBus.notify.emit(reason)
	channel_finished.emit(action, completed)


func _clear_channel() -> void:
	channel_action = null
	channel_target = null
	channel_ctx = null
	channel_elapsed = 0.0


func _score(candidate: Interactable) -> float:
	var to_target := candidate.global_position - global_position
	var score := to_target.length()
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera != null and to_target.length_squared() > 0.0001:
		var forward := -camera.global_basis.z
		score -= forward.normalized().dot(to_target.normalized()) * facing_weight
	return score - candidate.focus_priority * 10.0


func _set_focus(interactable: Interactable) -> void:
	if interactable == focused and (focused == null or is_instance_valid(focused)):
		return
	if focused != null and is_instance_valid(focused):
		focused.focus_changed.emit(false)
	focused = interactable
	if focused != null:
		focused.focus_changed.emit(true)
	focus_changed.emit(focused)


func _on_health_changed(current: float, _maximum: float) -> void:
	if _last_health >= 0.0 and current < _last_health and is_channelling() and channel_action.cancel_on_damage:
		cancel_channel("Interrupted - you're under fire")
	_last_health = current
