class_name FleeingDriver
extends Node3D
## The jacked car's owner: bails out, runs away from the car and disappears (to call the cops).

@export var run_speed := 6.0
@export var lifetime := 6.0

var direction := Vector3.RIGHT


static func spawn(parent: Node, at: Vector3, away: Vector3) -> FleeingDriver:
	var runner := FleeingDriver.new()
	runner.direction = Vector3(away.x, 0.0, away.z).normalized()
	parent.add_child(runner)
	runner.global_position = Vector3(at.x, at.y - 0.4, at.z)
	return runner


func _ready() -> void:
	add_to_group("fleeing_drivers")
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.85, 0.6, 0.4)
	capsule.material = material
	var body := MeshInstance3D.new()
	body.mesh = capsule
	body.position.y = 0.85
	add_child(body)
	if direction.length_squared() > 0.0:
		look_at(global_position + direction, Vector3.UP)


func _process(delta: float) -> void:
	global_position += direction * run_speed * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
