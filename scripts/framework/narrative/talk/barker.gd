class_name Barker
extends Node3D
## Ambient one-liners: drop under an NPC and it barks a random line over its head when the player
## comes within [member radius] (edge-triggered, with a cooldown). Call [method trigger] from script
## for scripted barks (e.g. Pedro: "Follow me!").

signal barked(text: String)

@export_multiline var lines: PackedStringArray = []
@export var radius := 6.0
@export var cooldown := 10.0
@export_range(0.0, 1.0) var chance := 1.0
## Gate (e.g. only while a flag is set).
@export var conditions: Array[Condition] = []
## Also show barks in the subtitle bar.
@export var subtitle := false
## Speaker node; empty = parent.
@export var speaker_path: NodePath
## Bark automatically on proximity (off = only via trigger()).
@export var auto := true

var _cooldown_left := 0.0
var _poll := 0.0
var _inside := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func _process(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if not auto:
		return
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = 0.25
	var player := GameState.player as Node3D
	var inside := player != null and is_instance_valid(player) and player.global_position.distance_to(global_position) <= radius
	if inside and not _inside and _cooldown_left <= 0.0 and not Narrative.is_busy() and _rng.randf() <= chance:
		trigger()
	_inside = inside


func speaker() -> Node3D:
	var node := get_node_or_null(speaker_path) if not speaker_path.is_empty() else get_parent()
	return node as Node3D


## Barks [param text] (or a random line). Respects [member conditions]; returns false when suppressed.
func trigger(text := "") -> bool:
	if not Condition.all_met(conditions, ActionContext.new(GameState.player, speaker())):
		return false
	if text == "":
		if lines.is_empty():
			return false
		text = lines[_rng.randi_range(0, lines.size() - 1)]
	if not Narrative.bark(speaker(), text, {"subtitle": subtitle, "force": true}):
		return false
	_cooldown_left = cooldown
	barked.emit(text)
	return true
