class_name Explosion
extends Node3D
## Area damage with distance falloff, a push for rigid bodies (vehicles), and a short fireball.
## Used by grenades, rockets, C4, molotovs and exploding vehicles.

## Bodies at the edge of the blast still take this fraction of the damage.
const MIN_FALLOFF := 0.15
const WORLD_LAYER := 1
const DAMAGEABLE_LAYERS := 2 | 4 | 8
## Push (per unit of falloff) given to characters and bodies thrown by the blast (ragdolls).
const BODY_PUSH := 700.0
const VISUAL_LIFETIME := 0.6

var radius := 4.0


## Damages everything with take_damage(amount, source) within [param blast_radius] that isn't behind
## a wall, and pushes rigid bodies away. Returns how many things were damaged.
static func detonate(context: Node3D, at: Vector3, blast_radius: float, damage: float, impulse: float, source: Node) -> int:
	var space := context.get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = blast_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, at)
	query.collision_mask = DAMAGEABLE_LAYERS | Ragdoll.LAYER
	var damaged := 0
	var seen := {}
	for result in space.intersect_shape(query, 64):
		var body := result.get("collider") as Node3D
		if body != null and body.is_in_group("ragdoll_parts"):
			body = body.get_parent() as Node3D
		if body == null or seen.has(body):
			continue
		seen[body] = true
		if body is Ragdoll:
			var part_at: Vector3 = (result.get("collider") as Node3D).global_position
			var part_distance := at.distance_to(part_at)
			if part_distance <= blast_radius and not _is_shielded(space, at, part_at):
				var away := (part_at - at).normalized() if part_distance > 0.01 else Vector3.UP
				(body as Ragdoll).push((away + Vector3.UP * 0.6).normalized() * BODY_PUSH * clampf(1.0 - part_distance / blast_radius, MIN_FALLOFF, 1.0), at)
			continue
		var center := _body_center(body)
		var distance := at.distance_to(center)
		if distance > blast_radius or _is_shielded(space, at, center):
			continue
		var falloff := clampf(1.0 - distance / blast_radius, MIN_FALLOFF, 1.0)
		if body is RigidBody3D and impulse > 0.0:
			var rigid := body as RigidBody3D
			var push := (center - at).normalized() if distance > 0.01 else Vector3.UP
			rigid.apply_central_impulse((push + Vector3.UP * 0.6).normalized() * impulse * falloff)
			rigid.apply_torque_impulse(push.cross(Vector3.UP) * -impulse * falloff * 0.5)
		if body.has_method("take_damage"):
			if body.has_method("register_hit"):
				var away := (center - at).normalized() if distance > 0.01 else Vector3.UP
				body.register_hit(at, (away + Vector3.UP * 0.6).normalized() * BODY_PUSH * falloff, at, false)
			body.take_damage(damage * falloff, source)
			damaged += 1
	_spawn_visual(context, at, blast_radius)
	EventBus.explosion.emit(at, blast_radius)
	return damaged


static func _body_center(body: Node3D) -> Vector3:
	return body.global_position + Vector3(0.0, 0.9, 0.0)


## True when static world geometry (buildings) sits between the blast and the target.
static func _is_shielded(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.2, to, WORLD_LAYER)
	var hit := space.intersect_ray(query)
	return not hit.is_empty() and from.distance_to(hit["position"]) < from.distance_to(to) - 0.5


static func _spawn_visual(context: Node, at: Vector3, blast_radius: float) -> void:
	var scene := context.get_tree().current_scene
	if scene == null:
		return
	var visual := Explosion.new()
	visual.radius = blast_radius
	visual.position = at
	scene.add_child(visual)


func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.6, 0.15, 0.9)
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.material = material
	var fireball := MeshInstance3D.new()
	fireball.mesh = sphere
	fireball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fireball.scale = Vector3.ONE * 0.3
	add_child(fireball)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 6.0
	light.omni_range = radius * 3.0
	add_child(light)

	var tween := create_tween().set_parallel()
	tween.tween_property(fireball, "scale", Vector3.ONE * radius * 0.8, VISUAL_LIFETIME * 0.4).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color", Color(0.25, 0.22, 0.2, 0.0), VISUAL_LIFETIME)
	tween.tween_property(light, "light_energy", 0.0, VISUAL_LIFETIME)
	tween.chain().tween_callback(queue_free)
