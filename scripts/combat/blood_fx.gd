class_name BloodFx
extends Node3D
## Gunshot blood. Hitscan calls [method on_hit] for every bullet that hits a character, which:
## - sprays a burst of blood out of the impact point along the shot,
## - throws droplets that land as splat decals on the ground (or on a wall in the way),
## - leaves a wound mark on the body at the impact point, riding the nearest bone of an animated
##   model (CharacterVisual) or the body itself for plain capsule characters,
## - and, once the character is down, grows a pool under the body.
## One BloodFx node per scene (see [method of]) owns the pools of nodes and recycles the oldest
## splats, sprays, pools and wounds once the caps below are reached.

const NODE_NAME := &"BloodFx"
const MAX_SPRAYS := 16
const MAX_SPLATS := 120
const MAX_POOLS := 12
const MAX_WOUNDS := 64
const MAX_WOUNDS_PER_BODY := 8
const DROPLETS_PER_HIT := 4
## Furthest a droplet is thrown along the shot (m).
const DROPLET_RANGE := 2.4
const WOUND_SIZE := 0.2
## Wound splotch on animated models: width (m) and how far it sits off the skin.
const SPLOTCH_SIZE := 0.18
const SPLOTCH_LIFT := 0.012
const POOL_START_SIZE := 0.35
const POOL_SIZE := 1.9
const POOL_GROW_TIME := 7.0
## Ground and walls (the "world" physics layer).
const WORLD_MASK := 1
const BLOOD_COLOR := Color(0.36, 0.01, 0.015)
const TEXTURE_VARIANTS := 4

static var _textures: Array[Texture2D] = []
static var _wound_texture: Texture2D
static var _droplet_mesh: Mesh
static var _splotch: Mesh

var _sprays: Array[GPUParticles3D] = []
var _next_spray := 0
var _splats: Array[Decal] = []
var _pools: Array[Decal] = []
var _wounds: Array[Node3D] = []


## The scene's BloodFx, created on first use.
static func of(context: Node) -> BloodFx:
	var tree := context.get_tree()
	var scene: Node = tree.current_scene if tree.current_scene != null else tree.root
	var existing := scene.get_node_or_null(NodePath(NODE_NAME)) as BloodFx
	if existing != null:
		return existing
	var fx := BloodFx.new()
	fx.name = NODE_NAME
	scene.add_child(fx)
	return fx


## Characters bleed: CharacterBody3Ds (player, NPCs, cops), unless they define bleeds() -> false.
## Anything else can opt in with a bleeds() method.
static func bleeds(body: Object) -> bool:
	if body == null or not is_instance_valid(body) or not body is Node3D:
		return false
	if body.has_method(&"bleeds"):
		return body.call(&"bleeds")
	return body is CharacterBody3D


## Entry point for weapons: blood for a bullet that hit [param body] at [param point], travelling
## along [param direction], on a surface facing [param normal]. Does nothing for bodies that don't bleed.
static func on_hit(body: Node3D, point: Vector3, direction: Vector3, normal: Vector3) -> void:
	if bleeds(body) and body.is_inside_tree():
		of(body).spawn_hit(body, point, direction, normal)


func spawn_hit(body: Node3D, point: Vector3, direction: Vector3, normal: Vector3) -> void:
	var shot := direction.normalized() if direction.length_squared() > 0.0001 else -normal
	_spray(point, shot)
	add_wound(body, point, normal if normal.length_squared() > 0.0001 else -shot, shot)
	_throw_droplets(point, shot, body)
	if _is_down(body):
		start_pool(body)


## Wound mark at [param point] that follows the body (or the nearest bone of its animated model).
## On an animated model the point is the hit on the (wider) collision capsule, so the bullet's line
## [param direction] is traced on into the posed skin and a splotch mesh is laid just outside it.
func add_wound(body: Node3D, point: Vector3, normal: Vector3, direction := Vector3.ZERO) -> Node3D:
	var wound: Node3D
	var skeleton := _skeleton_of(body)
	var skin := {}
	if skeleton != null:
		skin = skin_hit(skeleton, point, direction if direction.length_squared() > 0.0001 else -normal)
	if not skin.is_empty():
		var skin_normal: Vector3 = skin["normal"]
		var splotch := MeshInstance3D.new()
		splotch.mesh = _splotch_mesh()
		splotch.layers = skin["layers"]
		splotch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wound = splotch
		_wound_anchor(body, skin["position"]).add_child(wound)
		var basis := Basis.looking_at(-skin_normal, Vector3.UP if absf(skin_normal.y) < 0.9 else Vector3.FORWARD)
		# Thin limbs get a smaller splotch so it doesn't overhang their edges.
		var thickness: float = (skin["position"] as Vector3).distance_to(_nearest_bone(skeleton, skin["position"])[1])
		var size := clampf(thickness * 2.2, SPLOTCH_SIZE * 0.4, SPLOTCH_SIZE)
		basis = basis.rotated(skin_normal, randf() * TAU).scaled_local(Vector3(size, size, 1.0))
		wound.global_transform = Transform3D(basis, skin["position"] + skin_normal * SPLOTCH_LIFT)
	else:
		wound = _make_decal(_wound_tex(), Vector3(WOUND_SIZE, 0.3, WOUND_SIZE), BLOOD_COLOR.darkened(0.15))
		_wound_anchor(body, point).add_child(wound)
		wound.global_transform = Transform3D(_basis_facing(normal), point)
	wound.name = "BloodWound"
	wound.set_meta(&"blood_body", body)

	var own: Array = body.get_meta(&"blood_wounds", [])
	own = own.filter(_valid)
	own.append(wound)
	while own.size() > MAX_WOUNDS_PER_BODY:
		_free_wound(own.pop_front())
	body.set_meta(&"blood_wounds", own)
	_wounds = _wounds.filter(_valid)
	_wounds.append(wound)
	while _wounds.size() > MAX_WOUNDS:
		_free_wound(_wounds.pop_front())
	return wound


## Starts a growing pool under a downed body (once per body).
func start_pool(body: Node3D) -> Decal:
	var existing: Variant = body.get_meta(&"blood_pool") if body.has_meta(&"blood_pool") else null
	if existing != null and is_instance_valid(existing):
		return existing
	var pool: Decal
	_pools = _pools.filter(_valid)
	if _pools.size() >= MAX_POOLS:
		pool = _pools.pop_front()
		var old_body: Variant = pool.get_meta(&"blood_body") if pool.has_meta(&"blood_body") else null
		if old_body != null and is_instance_valid(old_body):
			(old_body as Node).remove_meta(&"blood_pool")
	else:
		pool = _make_decal(_splat_tex(), Vector3.ONE, BLOOD_COLOR.darkened(0.2))
		pool.name = "BloodPool"
		pool.sorting_offset = -1.0
		add_child(pool)
	pool.texture_albedo = _splat_tex()
	pool.set_meta(&"blood_body", body)
	pool.set_meta(&"blood_age", 0.0)
	pool.size = Vector3(POOL_START_SIZE, 0.6, POOL_START_SIZE)
	pool.rotation = Vector3(0.0, randf() * TAU, 0.0)
	_place_pool(pool, body)
	body.set_meta(&"blood_pool", pool)
	_pools.append(pool)
	return pool


func splat_count() -> int:
	return _splats.size()


func pool_count() -> int:
	_pools = _pools.filter(_valid)
	return _pools.size()


func wound_count() -> int:
	_wounds = _wounds.filter(_valid)
	return _wounds.size()


func spray_count() -> int:
	return _sprays.size()


func splats() -> Array[Decal]:
	return _splats


func pools() -> Array[Decal]:
	return _pools


## Wounds on [param body] (oldest first).
static func wounds_on(body: Node) -> Array:
	return (body.get_meta(&"blood_wounds", []) as Array).filter(_valid)


## Removes all blood: splats, pools, wounds and sprays in flight.
func clear() -> void:
	for node in _splats + _pools:
		node.queue_free()
	for wound in _wounds.filter(_valid):
		_free_wound(wound)
	for spray in _sprays:
		spray.emitting = false
	_splats.clear()
	_pools.clear()
	_wounds.clear()


func _process(delta: float) -> void:
	for pool in _pools:
		if not is_instance_valid(pool):
			continue
		var age: float = pool.get_meta(&"blood_age", POOL_GROW_TIME)
		if age >= POOL_GROW_TIME:
			continue
		age += delta
		pool.set_meta(&"blood_age", age)
		var grown := lerpf(POOL_START_SIZE, POOL_SIZE, ease(clampf(age / POOL_GROW_TIME, 0.0, 1.0), 0.4))
		pool.size = Vector3(grown, 0.6, grown)
		var body: Variant = pool.get_meta(&"blood_body") if pool.has_meta(&"blood_body") else null
		if body != null and is_instance_valid(body):
			_place_pool(pool, body)


# --- spray ----------------------------------------------------------------------------------------

func _spray(point: Vector3, shot: Vector3) -> void:
	var spray: GPUParticles3D
	if _sprays.size() < MAX_SPRAYS:
		spray = _make_spray()
		_sprays.append(spray)
	else:
		spray = _sprays[_next_spray]
		_next_spray = (_next_spray + 1) % MAX_SPRAYS
	spray.global_transform = Transform3D(_basis_facing(-shot), point)
	spray.restart()
	spray.emitting = true


func _make_spray() -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	# Particles leave along local -Y, which _basis_facing(-shot) points down the shot.
	process.direction = Vector3(0.0, -1.0, 0.0)
	process.spread = 22.0
	process.initial_velocity_min = 2.5
	process.initial_velocity_max = 6.5
	process.gravity = Vector3(0.0, -9.8, 0.0)
	process.damping_min = 0.5
	process.damping_max = 2.0
	process.scale_min = 0.5
	process.scale_max = 1.4
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.03
	var spray := GPUParticles3D.new()
	spray.name = "BloodSpray"
	spray.amount = 28
	spray.lifetime = 0.75
	spray.one_shot = true
	spray.explosiveness = 0.92
	spray.randomness = 0.4
	spray.local_coords = false
	spray.emitting = false
	spray.process_material = process
	spray.draw_pass_1 = _droplet()
	spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spray.visibility_aabb = AABB(Vector3(-3.0, -3.0, -3.0), Vector3(6.0, 6.0, 6.0))
	add_child(spray)
	return spray


static func _droplet() -> Mesh:
	if _droplet_mesh == null:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(0.55, 0.02, 0.03)
		var drop := SphereMesh.new()
		drop.radius = 0.022
		drop.height = 0.044
		drop.radial_segments = 6
		drop.rings = 3
		drop.material = material
		_droplet_mesh = drop
	return _droplet_mesh


# --- ground splats --------------------------------------------------------------------------------

func _throw_droplets(point: Vector3, shot: Vector3, body: Node3D) -> void:
	var space := get_world_3d().direct_space_state
	var flat := Vector3(shot.x, 0.0, shot.z)
	flat = flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	var exclude: Array[RID] = []
	if body is CollisionObject3D:
		exclude.append((body as CollisionObject3D).get_rid())
	for i in DROPLETS_PER_HIT:
		# The first droplet drips at the feet; the rest are thrown along the shot.
		var reach := randf_range(0.0, 0.35) if i == 0 else randf_range(0.4, DROPLET_RANGE)
		var heading := flat.rotated(Vector3.UP, randf_range(-0.45, 0.45))
		var target := point + heading * reach
		var size := randf_range(0.35, 0.75) if i == 0 else randf_range(0.18, 0.55)
		var wall := _ray(space, point, target, exclude)
		if not wall.is_empty() and (wall["normal"] as Vector3).y < 0.7:
			_add_splat(wall["position"], wall["normal"], size * 0.8, 0.0)
			continue
		var ground := _ray(space, target + Vector3.UP * 0.2, target + Vector3.DOWN * 6.0, exclude)
		if ground.is_empty():
			continue
		var drop := maxf(0.0, point.y - (ground["position"] as Vector3).y)
		_add_splat(ground["position"], ground["normal"], size, sqrt(2.0 * drop / 9.8))


func _add_splat(at: Vector3, normal: Vector3, size: float, delay: float) -> Decal:
	var splat: Decal
	if _splats.size() >= MAX_SPLATS:
		splat = _splats.pop_front()
	else:
		splat = _make_decal(null, Vector3.ONE, BLOOD_COLOR)
		splat.name = "BloodSplat"
		add_child(splat)
	splat.texture_albedo = _splat_tex()
	splat.size = Vector3(size, 0.35, size)
	splat.global_transform = Transform3D(_basis_facing(normal).rotated(normal, randf() * TAU), at)
	var color := BLOOD_COLOR.lerp(Color(0.5, 0.02, 0.02), randf() * 0.4)
	splat.modulate = Color(color, 0.0)
	var fade := splat.create_tween()
	fade.tween_interval(delay)
	fade.tween_property(splat, ^"modulate:a", 1.0, 0.08)
	_splats.append(splat)
	return splat


func _place_pool(pool: Decal, body: Node3D) -> void:
	var center := _torso_position(body)
	var ground := _ray(get_world_3d().direct_space_state, center + Vector3.UP * 0.5, center + Vector3.DOWN * 4.0, [])
	pool.global_position = ground["position"] if not ground.is_empty() else Vector3(center.x, body.global_position.y, center.z)


# --- wounds ---------------------------------------------------------------------------------------

## Parent for a wound at [param point]: a BoneAttachment3D on the bone of the body's animated model
## nearest the point, else the body's own wound_anchor(point) if it has one, else the body itself.
func _wound_anchor(body: Node3D, point: Vector3) -> Node3D:
	var skeleton := _skeleton_of(body)
	if skeleton == null:
		return body.call(&"wound_anchor", point) if body.has_method(&"wound_anchor") else body
	var best: int = _nearest_bone(skeleton, point)[0]
	if best < 0:
		return body
	var bone_name := skeleton.get_bone_name(best)
	var anchor_name := "BloodBone_%s" % bone_name.validate_node_name()
	var attachment := skeleton.get_node_or_null(anchor_name) as BoneAttachment3D
	if attachment == null:
		attachment = BoneAttachment3D.new()
		attachment.name = anchor_name
		skeleton.add_child(attachment)
		attachment.bone_name = bone_name
	attachment.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(best)
	return attachment


## [bone, closest world point] of the bone (as a segment to each child bone) nearest [param point].
## Root bones are skipped: their segment runs from the feet up between the legs.
static func _nearest_bone(skeleton: Skeleton3D, point: Vector3) -> Array:
	var best := -1
	var best_point := point
	var best_distance := INF
	for bone in skeleton.get_bone_count():
		if skeleton.get_bone_parent(bone) < 0:
			continue
		var start := skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
		var ends: Array[Vector3] = [start]
		for child in skeleton.get_bone_children(bone):
			ends.append(skeleton.global_transform * skeleton.get_bone_global_pose(child).origin)
		for end in ends:
			var closest := Geometry3D.get_closest_point_to_segment(point, start, end)
			var distance := closest.distance_squared_to(point)
			if distance < best_distance:
				best = bone
				best_point = closest
				best_distance = distance
	return [best, best_point]


## Where a bullet through [param point] along [param direction] meets the posed skin of the
## skeleton's skinned meshes: {position, normal, layers, mesh}, or {} if there's no skin there.
## The point is usually on the collision capsule, which is wider than the model, so a line that
## grazes past the model is retried straight at the nearest bone.
static func skin_hit(skeleton: Skeleton3D, point: Vector3, direction: Vector3) -> Dictionary:
	if direction.length_squared() < 0.0001:
		return {}
	var dir := direction.normalized()
	var hit := SkinRaycast.intersect(skeleton, point - dir * 0.6, point + dir * 1.2)
	if hit.is_empty():
		var bone: Vector3 = _nearest_bone(skeleton, point)[1]
		var toward := bone - point
		if toward.length_squared() > 0.0001:
			toward = toward.normalized()
			hit = SkinRaycast.intersect(skeleton, point - toward * 0.3, bone + toward * 0.05)
	if not hit.is_empty():
		hit["layers"] = (hit["mesh"] as MeshInstance3D).layers
	return hit

static func _splotch_mesh() -> Mesh:
	if _splotch == null:
		var material := StandardMaterial3D.new()
		material.albedo_texture = _wound_tex()
		material.albedo_color = BLOOD_COLOR.lightened(0.05)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.4
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.roughness = 0.3
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		quad.material = material
		_splotch = quad
	return _splotch


static func _skeleton_of(body: Node) -> Skeleton3D:
	var visual: Variant = body.get(&"visual")
	if visual is CharacterVisual and (visual as CharacterVisual).skeleton != null:
		return (visual as CharacterVisual).skeleton
	return null


func _free_wound(wound: Variant) -> void:
	if wound != null and is_instance_valid(wound):
		(wound as Node).queue_free()


func _torso_position(body: Node3D) -> Vector3:
	var skeleton := _skeleton_of(body)
	if skeleton != null:
		var hips := skeleton.find_bone("Hips")
		if hips < 0:
			hips = skeleton.find_bone("Abdomen")
		if hips >= 0:
			return skeleton.global_transform * skeleton.get_bone_global_pose(hips).origin
	if body.has_method(&"wound_anchor"):
		return (body.call(&"wound_anchor", body.global_position) as Node3D).global_position
	return body.global_position + Vector3.UP * 0.5


static func _is_down(body: Node) -> bool:
	if body.has_method(&"is_alive"):
		return not body.call(&"is_alive")
	return false


static func _valid(node: Variant) -> bool:
	return node != null and is_instance_valid(node)


# --- helpers --------------------------------------------------------------------------------------

## Decals project along their local -Y, so +Y faces back out of the surface.
static func _basis_facing(normal: Vector3) -> Basis:
	var up := normal.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(side, up, side.cross(up)).orthonormalized()


static func _make_decal(texture: Texture2D, size: Vector3, color: Color) -> Decal:
	var decal := Decal.new()
	decal.texture_albedo = texture
	decal.size = size
	decal.modulate = color
	decal.albedo_mix = 1.0
	decal.upper_fade = 0.15
	decal.lower_fade = 0.15
	decal.normal_fade = 0.3
	return decal


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID]) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK)
	query.exclude = exclude
	return space.intersect_ray(query)


static func _splat_tex() -> Texture2D:
	if _textures.is_empty():
		for i in TEXTURE_VARIANTS:
			_textures.append(_blob_texture(1000 + i, 6, false))
	return _textures.pick_random()


static func _wound_tex() -> Texture2D:
	if _wound_texture == null:
		_wound_texture = _blob_texture(77, 3, true)
	return _wound_texture


## A white blob with ragged edges and a few satellite drops; decals tint it with their modulate.
static func _blob_texture(seed_value: int, satellites: int, dark_core: bool) -> Texture2D:
	const SIZE := 64
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var lobes: Array[Vector3] = [Vector3(0.5, 0.5, 0.3)]
	for i in 5:
		var angle := rng.randf() * TAU
		var offset := rng.randf_range(0.05, 0.14)
		lobes.append(Vector3(0.5 + cos(angle) * offset, 0.5 + sin(angle) * offset, rng.randf_range(0.12, 0.2)))
	for i in satellites:
		var angle := rng.randf() * TAU
		var offset := rng.randf_range(0.3, 0.44)
		lobes.append(Vector3(0.5 + cos(angle) * offset, 0.5 + sin(angle) * offset, rng.randf_range(0.02, 0.05)))
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var uv := Vector2((x + 0.5) / SIZE, (y + 0.5) / SIZE)
			var alpha := 0.0
			for lobe in lobes:
				var d := uv.distance_to(Vector2(lobe.x, lobe.y)) / lobe.z
				alpha = maxf(alpha, clampf((1.0 - d) * 4.0, 0.0, 1.0))
			var shade := 1.0
			if dark_core:
				shade = lerpf(0.35, 1.0, clampf(uv.distance_to(Vector2(0.5, 0.5)) / 0.18, 0.0, 1.0))
			image.set_pixel(x, y, Color(shade, shade, shade, alpha))
	return ImageTexture.create_from_image(image)
