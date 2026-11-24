class_name HangoutCrewMember
extends Node3D
## Ambient player-gang crew idling in front of an owned business (greybox capsule that ambles
## around its spot). Purely decorative for now: it doesn't fight and isn't in "gang_members".

const GROUP := &"hangout_crew"

@export var wander_radius := 2.0
@export var move_speed := 0.8

var _anchor := Vector3.ZERO
var _target := Vector3.ZERO
var _wait := 0.0
var _rng := RandomNumberGenerator.new()


static func create(color: Color, at: Vector3, rng_seed: int) -> HangoutCrewMember:
	var member := HangoutCrewMember.new()
	member.position = at
	member._rng.seed = rng_seed
	var body := VisualSpec.greybox(&"capsule", Vector3(0.6, 1.8, 0.6), color)
	body.position = Vector3(0.0, 0.9, 0.0)
	member.add_child(body)
	return member


func _ready() -> void:
	add_to_group(GROUP)
	_anchor = position
	_target = position
	_wait = _rng.randf_range(0.0, 3.0)


func _process(delta: float) -> void:
	if _wait > 0.0:
		_wait -= delta
		return
	var to_target := _target - position
	if to_target.length() < 0.05:
		var angle := _rng.randf() * TAU
		_target = _anchor + Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf_range(0.0, wander_radius)
		_wait = _rng.randf_range(2.0, 6.0)
		return
	var step := to_target.normalized() * minf(move_speed * delta, to_target.length())
	position += step
	rotation.y = atan2(step.x, step.z)
