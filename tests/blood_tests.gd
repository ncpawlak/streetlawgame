extends RefCounted
## BloodFx tests: gun hits leave a wound mark at the impact point that follows the body, droplets
## splat on the ground, the dead get a growing pool, non-characters don't bleed, and the caps hold.

var _runner: Node
var _shooter: Node3D


func _init(runner: Node) -> void:
	_runner = runner


func run(main: Node, player: Player) -> void:
	player.respawn()
	await _frames(5)
	var origin := player.global_position + Vector3(0.0, 0.0, 30.0)
	_shooter = Node3D.new()
	_shooter.name = "BloodTestShooter"
	main.add_child(_shooter)
	var fx := BloodFx.of(main)
	fx.clear()
	await _frames(2)
	await _test_animated_hit(main, fx, origin)
	await _test_capsule_hit(main, fx, origin + Vector3(4.0, 0.0, 0.0))
	await _test_no_blood_for_props(main, fx, origin + Vector3(-4.0, 0.0, 0.0))
	await _test_caps(main, fx, origin + Vector3(8.0, 0.0, 0.0))
	await _test_every_model(main, origin + Vector3(0.0, 0.0, 12.0))
	fx.clear()
	_shooter.queue_free()


func _test_animated_hit(main: Node, fx: BloodFx, at: Vector3) -> void:
	var member := GangMember.new()
	member.gang_id = &"vipers"
	member.weapon_id = &"pistol"
	member.aggro_range = 0.0
	member.alerted_range = 0.0
	member.wander_radius = 0.0
	member.drop_chance = 0.0
	member.max_health = 1000.0
	member.position = at
	main.add_child(member)
	await _frames(20)

	var splats_before := fx.splat_count()
	var muzzle := member.global_position + Vector3(0.1, 1.3, 3.0)
	var expected := _ray_point(member, muzzle, Vector3.FORWARD)
	Hitscan.fire(_shooter, muzzle, Vector3.FORWARD, _gun(), [])
	var wounds := BloodFx.wounds_on(member)
	_check(wounds.size() == 1, "a gunshot leaves a wound mark on the NPC")
	if wounds.is_empty():
		member.queue_free()
		return
	var wound := wounds[0] as Node3D
	var anchor := wound.get_parent()
	_check(anchor is BoneAttachment3D and anchor.get_parent() == member.visual.skeleton, "the wound rides a bone of the animated model (%s)" % anchor.name)
	_check_on_skin(wound, member.visual.skeleton, expected, "the gang member")
	_check(fx.spray_count() >= 1, "the hit sprays blood")
	_check(fx.splat_count() > splats_before, "blood droplets land on the ground (%d splats)" % (fx.splat_count() - splats_before))
	var ground_y := _ray_point(member, member.global_position + Vector3.UP, Vector3.DOWN).y
	var on_ground := fx.splats().filter(func(s: Decal) -> bool: return absf(s.global_position.y - ground_y) < 0.1)
	_check(not on_ground.is_empty(), "splats sit on the ground surface")

	var before := wound.global_position
	member.global_position += Vector3(3.0, 0.0, 0.0)
	await _frames(5)
	var moved := wound.global_position - before
	_check(absf(moved.x - 3.0) < 0.5 and absf(moved.z) < 0.5, "the wound follows the body as it moves (moved %.2f, %.2f m)" % [moved.x, moved.z])

	var pools_before := fx.pool_count()
	member.health = 1.0
	Hitscan.fire(_shooter, member.global_position + Vector3(0.0, 1.0, 3.0), Vector3.FORWARD, _gun(), [])
	_check(not member.is_alive() and fx.pool_count() == pools_before + 1, "a killed character gets a blood pool")
	var pool := member.get_meta(&"blood_pool") as Decal
	var start := pool.size.x
	await _frames(90)
	_check(pool.size.x > start + 0.1, "the pool grows under the body (%.2f -> %.2f m)" % [start, pool.size.x])
	member.queue_free()


func _test_capsule_hit(main: Node, fx: BloodFx, at: Vector3) -> void:
	var body := _capsule(main, at)
	await _frames(3)
	var muzzle := at + Vector3(0.0, 1.2, 3.0)
	var expected := _ray_point(body, muzzle, Vector3.FORWARD)
	Hitscan.fire(_shooter, muzzle, Vector3.FORWARD, _gun(), [])
	var wounds := BloodFx.wounds_on(body)
	_check(wounds.size() == 1 and (wounds[0] as Node).get_parent() == body, "a capsule character gets a wound parented to its body")
	if not wounds.is_empty():
		_check((wounds[0] as Node3D).global_position.distance_to(expected) < 0.05, "the capsule wound sits at the impact point")
	body.queue_free()


func _test_no_blood_for_props(main: Node, fx: BloodFx, at: Vector3) -> void:
	var prop := StaticBody3D.new()
	prop.set_script(preload("res://tests/blood_tests_target.gd"))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE
	shape.shape = box
	prop.add_child(shape)
	prop.position = at + Vector3(0.0, 1.0, 0.0)
	main.add_child(prop)
	await _frames(3)
	var splats := fx.splat_count()
	var wounds := fx.wound_count()
	Hitscan.fire(_shooter, at + Vector3(0.0, 1.0, 3.0), Vector3.FORWARD, _gun(), [])
	_check(prop.get(&"damage_taken") > 0.0 and fx.splat_count() == splats and fx.wound_count() == wounds, "damageable props don't bleed")
	var fists := GameState.weapon_data(&"fists")
	var body := _capsule(main, at + Vector3(0.0, 0.0, -3.0))
	await _frames(3)
	Hitscan.fire(_shooter, body.global_position + Vector3(0.0, 1.2, 1.0), Vector3.FORWARD, fists, [])
	_check(BloodFx.wounds_on(body).is_empty(), "melee hits don't bleed")
	prop.queue_free()
	body.queue_free()


func _test_caps(main: Node, fx: BloodFx, at: Vector3) -> void:
	var body := _capsule(main, at)
	await _frames(3)
	for i in 300:
		fx.spawn_hit(body, body.global_position + Vector3(randf_range(-0.2, 0.2), randf_range(0.5, 1.6), 0.4), Vector3.FORWARD, Vector3.BACK)
	_check(fx.splat_count() == BloodFx.MAX_SPLATS, "ground splats are capped at %d and recycled (%d)" % [BloodFx.MAX_SPLATS, fx.splat_count()])
	_check(fx.spray_count() == BloodFx.MAX_SPRAYS, "sprays are pooled at %d" % BloodFx.MAX_SPRAYS)
	await _frames(1)
	_check(BloodFx.wounds_on(body).size() == BloodFx.MAX_WOUNDS_PER_BODY, "wound marks per body are capped at %d" % BloodFx.MAX_WOUNDS_PER_BODY)
	var bodies: Array[Node3D] = []
	for i in BloodFx.MAX_WOUNDS / BloodFx.MAX_WOUNDS_PER_BODY + 3:
		var other := _capsule(main, at + Vector3(2.0 + i, 0.0, 0.0))
		bodies.append(other)
		for j in BloodFx.MAX_WOUNDS_PER_BODY:
			fx.add_wound(other, other.global_position + Vector3.UP, Vector3.BACK)
	for i in BloodFx.MAX_POOLS + 5:
		fx.start_pool(bodies[i % bodies.size()] if i < bodies.size() else _capsule(main, at + Vector3(0.0, 0.0, 2.0 + i)))
	await _frames(1)
	_check(fx.wound_count() <= BloodFx.MAX_WOUNDS, "wound marks are capped at %d overall (%d)" % [BloodFx.MAX_WOUNDS, fx.wound_count()])
	_check(fx.pool_count() == BloodFx.MAX_POOLS, "pools are capped at %d and recycled" % BloodFx.MAX_POOLS)
	_check(fx.get_child_count() <= BloodFx.MAX_SPLATS + BloodFx.MAX_POOLS + BloodFx.MAX_SPRAYS, "BloodFx holds no more nodes than its caps")
	body.queue_free()
	for other in bodies:
		other.queue_free()


## Every character model, hit in the chest and the thigh: the wound is a visible splotch lying on
## its skin (the bullet stops on the wider collision capsule, which the old decals missed).
func _test_every_model(main: Node, at: Vector3) -> void:
	var models := {}
	for archetype: StringName in CharacterVisual.ARCHETYPES:
		var list: Array = CharacterVisual.ARCHETYPES[archetype]
		for i in list.size():
			if not models.has(list[i]):
				models[list[i]] = [archetype, i]
	var spot := at
	for model: StringName in models:
		var body := _capsule(main, spot)
		var visual := CharacterVisual.create(models[model][0], models[model][1])
		body.add_child(visual)
		body.set(&"visual", visual)
		spot += Vector3(2.5, 0.0, 0.0)
		await _frames(10)
		for height in [1.3, 0.7]:
			var muzzle := body.global_position + Vector3(0.08, height, 3.0)
			var expected := _ray_point(body, muzzle, Vector3.FORWARD)
			var count := BloodFx.wounds_on(body).size()
			Hitscan.fire(_shooter, muzzle, Vector3.FORWARD, _gun(), [])
			var wounds := BloodFx.wounds_on(body)
			_check(wounds.size() == count + 1, "%s: a %.1f m high hit leaves a wound" % [model, height])
			if wounds.size() > count:
				_check_on_skin(wounds[-1], visual.skeleton, expected, "%s at %.1f m" % [model, height])
		body.queue_free()


## The wound is a visible mesh on the model's layers, lying just outside its posed skin (nothing
## of the model between it and the shooter, skin right behind it) and behind the capsule impact point.
func _check_on_skin(wound: Node3D, skeleton: Skeleton3D, capsule_point: Vector3, label: String) -> void:
	var mesh := wound as MeshInstance3D
	var skin := BloodFx.skin_hit(skeleton, capsule_point, Vector3.FORWARD)
	if mesh == null or skin.is_empty():
		_check(false, "%s: the wound is a splotch mesh on the skin (mesh %s, skin hit %s)" % [label, mesh != null, not skin.is_empty()])
		return
	var skin_mesh := skin["mesh"] as MeshInstance3D
	_check(mesh.is_visible_in_tree() and mesh.layers & skin_mesh.layers != 0 and mesh.mesh != null, "%s: the wound is a visible mesh on the model's layers" % label)
	var normal := mesh.global_basis.z.normalized()
	var in_front := SkinRaycast.intersect(skeleton, wound.global_position + Vector3.BACK * 0.5, wound.global_position + Vector3.BACK * 0.001)
	var behind := SkinRaycast.intersect(skeleton, wound.global_position, wound.global_position - normal * 0.05)
	_check(in_front.is_empty() and not behind.is_empty(), "%s: the wound lies just outside the skin (skin %.3f m behind)" % [label, wound.global_position.distance_to(behind.get("position", Vector3.ZERO))])
	_check(capsule_point.z - wound.global_position.z > 0.03, "%s: the wound sits in from the capsule surface (%.2f m)" % [label, capsule_point.z - wound.global_position.z])


func _capsule(main: Node, at: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.collision_layer = 4
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = 0.9
	body.add_child(shape)
	body.set_script(preload("res://tests/blood_tests_target.gd"))
	body.position = at
	main.add_child(body)
	return body


## A no-spread, no-tracer copy of the pistol.
func _gun() -> WeaponData:
	var gun := GameState.weapon_data(&"pistol").duplicate() as WeaponData
	gun.spread_degrees = 0.0
	gun.show_tracer = false
	return gun


func _ray_point(context: Node3D, from: Vector3, direction: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * 10.0)
	var hit := context.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("position", from)


func _frames(count: int) -> void:
	for i in count:
		await _runner.get_tree().physics_frame


func _check(condition: bool, description: String) -> void:
	_runner.call(&"_check", condition, description)
