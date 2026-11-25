extends Node3D
## Minimal damageable body for blood_tests.gd.

var damage_taken := 0.0


func take_damage(amount: float, _source: Node = null) -> void:
	damage_taken += amount
