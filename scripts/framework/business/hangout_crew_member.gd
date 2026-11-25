class_name HangoutCrewMember
extends Node3D
## Ambient player-gang crew idling in front of an owned business (animated CharacterVisual in the
## gang's colours that ambles around its spot). Purely decorative for now: it doesn't fight and isn't in "gang_members".

const GROUP := &"hangout_crew"

@export var wander_radius := 2.0
@export var move_speed := 0.8

var _anchor := Vector3.ZERO
var _target := Vector3.ZERO
var _wait := 0.0
var _rng := RandomNumberGenerator.new()
var _visual: CharacterVisual


static func create(color: Color, at: Vector3, rng_seed: int) -> HangoutCrewMember:
	var member := HangoutCrewMember.new()
	member.position = at
	member._rng.seed = rng_seed
	member._visual = CharacterVisual.create(&"crew", rng_seed & 0xFFFF)
	member._visual.set_tint(color.darkened(0.2))
	member._visual.set_bandana(color)
	member.add_child(member._visual)
	return member


func _ready() -> void:
	add_to_group(GROUP)
	_anchor = position
	_target = position
	_wait = _rng.randf_range(0.0, 3.0)


func _process(delta: float) -> void:
	if _wait > 0.0:
		_wait -= delta
		_visual.update_motion(Vector3.ZERO, delta)
		return
	var to_target := _target - position
	if to_target.length() < 0.05:
		var angle := _rng.randf() * TAU
		_target = _anchor + Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf_range(0.0, wander_radius)
		_wait = _rng.randf_range(2.0, 6.0)
		return
	var step := to_target.normalized() * minf(move_speed * delta, to_target.length())
	position += step
	rotation.y = atan2(-step.x, -step.z)
	_visual.update_motion(step / maxf(delta, 0.0001), delta)
