class_name ActionContext
extends RefCounted
## Everything a Condition, Cost or Effect needs to evaluate or act: who is acting, on what, where,
## plus a free-form [member vars] bag. Non-interaction systems (production, districts) build one too
## and put their own keys (site_id, district_id...) in [member vars].

## The acting node; normally the Player.
var actor: Node
## The Interactable being used, or null outside the interaction system.
var interactable: Interactable
## The node the action is about (the Interactable's target, a vehicle, an NPC...).
var target: Node
## The Location the action belongs to (a Location node), or null.
var location: Node3D
## The occupant (shopkeeper, contact...) involved, or null.
var occupant: Node
## The action being performed, if any.
var action: InteractionAction
## Per-interactable persistent memory, e.g. {action_id: {"last": play_time, "count": n}}.
var memory: Dictionary = {}
## Free-form values shared by every step of one action; also feeds [method format].
var vars: Dictionary = {}
var rng: RandomNumberGenerator


func _init(acting: Node = null, about: Node = null) -> void:
	actor = acting
	target = about
	rng = RandomNumberGenerator.new()
	rng.randomize()


## Replaces {key} placeholders with [member vars] values and a few built-ins
## ({cash}, {respect}, {target}, {location}).
func format(text: String) -> String:
	if text.find("{") == -1:
		return text
	var values := {
		"cash": GameState.cash,
		"respect": GameState.respect,
		"target": _label_of(target),
		"location": _label_of(location),
	}
	values.merge(vars, true)
	return text.format(values)


func get_var(key: Variant, default: Variant = null) -> Variant:
	return vars.get(key, default)


func set_var(key: Variant, value: Variant) -> void:
	vars[key] = value


## The memory entry for an action id, created on first use.
func action_memory(action_id: StringName) -> Dictionary:
	if not memory.has(action_id):
		memory[action_id] = {"last": -INF, "count": 0}
	return memory[action_id]


## The node a strategy should act on for a given selector: &"target", &"actor", &"location",
## &"occupant" or &"interactable".
func resolve(selector: StringName) -> Object:
	match selector:
		&"actor":
			return actor
		&"location":
			return location
		&"occupant":
			return occupant
		&"interactable":
			return interactable
		_:
			return target


## Calls [param method] on the node picked by [param selector]. [param args] are passed after the
## optional actor/context prefix. Returns null when the target or method is missing.
func invoke(selector: StringName, method: StringName, args: Array = [], pass_actor := false, pass_context := false) -> Variant:
	var object := resolve(selector)
	if object == null or method == &"" or not object.has_method(method):
		return null
	var call_args: Array = []
	if pass_actor:
		call_args.append(actor)
	if pass_context:
		call_args.append(self)
	call_args.append_array(args)
	return object.callv(method, call_args)


static func _label_of(node: Node) -> String:
	if node == null:
		return ""
	if node.has_method("label"):
		return node.call("label")
	return String(node.name)
