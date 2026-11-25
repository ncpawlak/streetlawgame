class_name BulletHoles
extends RefCounted
## Bullet holes in vehicles. Hitscan calls [method add] (through Vehicle.on_bullet_hit) for every
## bullet that strikes one. The shot is traced against the visible body meshes, because the
## collision boxes only approximate them. The hole then sticks to the panel it hit: a punched
## hole ringed with bare metal on bodywork, or a spider-web crack on glass. Holes ride their
## panel, so they move with opening doors and turning wheels. The oldest are recycled past
## [constant MAX_PER_BODY].
## This works like the blood FX wound marks (scripts/combat/blood_fx.gd on the blood-fx branch):
## procedural textures on small quads parented to whatever was hit, so nothing projects onto the
## road or onto a car parked alongside.

const MAX_PER_BODY := 40
const HOLE_SIZE := 0.075
const CRACK_SIZE := 0.36
## How far the quad floats off the panel (m), to avoid z-fighting.
const LIFT := 0.004
## How far before / after the collision hit to look for the visible surface (m).
const SEARCH_BEFORE := 0.4
const SEARCH_AFTER := 1.6
const META_LIST := &"bullet_holes"
const META_HOLE := &"bullet_hole"
## Material resource_name the vehicle generator gives windows (tools/vehicles/builder.py).
const GLASS_MATERIAL := "glass"

static var _quads := {}


## Adds a hole where a bullet travelling along [param direction] struck [param body] near
## [param point] (the hit on its collision shape, with that shape's [param normal]). Returns the
## hole, or null when the shot only clipped the collision box and missed the visible bodywork.
static func add(body: Node3D, point: Vector3, direction: Vector3, normal: Vector3) -> MeshInstance3D:
	if body == null or not is_instance_valid(body) or not body.is_inside_tree():
		return null
	var shot := direction.normalized() if direction.length_squared() > 0.0001 else -normal.normalized()
	if shot.length_squared() < 0.0001:
		return null
	var surface := trace(body, point - shot * SEARCH_BEFORE, point + shot * SEARCH_AFTER)
	if surface.is_empty():
		return null
	var face: Vector3 = surface["normal"]
	if face.length_squared() < 0.0001:
		face = -shot
	face = face.normalized()
	if face.dot(shot) > 0.0:
		face = -face
	var glass: bool = surface["glass"]
	var hole := MeshInstance3D.new()
	hole.name = "GlassCrack" if glass else "BulletHole"
	hole.mesh = _quad(glass)
	hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hole.set_meta(META_HOLE, true)
	(surface["mesh"] as Node3D).add_child(hole)
	hole.global_transform = Transform3D(_facing(face, randf() * TAU), surface["position"] + face * LIFT)
	var own: Array = holes_on(body)
	own.append(hole)
	while own.size() > MAX_PER_BODY:
		var oldest: Node = own.pop_front()
		oldest.queue_free()
	body.set_meta(META_LIST, own)
	return hole


## Holes on [param body], oldest first.
static func holes_on(body: Node) -> Array:
	return (body.get_meta(META_LIST, []) as Array).filter(
		func(node: Variant) -> bool: return node != null and is_instance_valid(node) and not (node as Node).is_queued_for_deletion())


static func clear(body: Node) -> void:
	for hole: Node in holes_on(body):
		hole.queue_free()
	body.set_meta(META_LIST, [])


## Nearest visible mesh of [param body] crossed by the segment [param from] to [param to], as
## {mesh, position, normal, glass} in world space, or {} if the segment misses them all.
static func trace(body: Node3D, from: Vector3, to: Vector3) -> Dictionary:
	var best := {}
	var best_distance := INF
	var stack: Array[Node] = [body]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.has_meta(META_HOLE):
			continue
		stack.append_array(node.get_children())
		var instance := node as MeshInstance3D
		if instance == null or instance.mesh == null or not instance.is_visible_in_tree():
			continue
		var to_local := instance.global_transform.affine_inverse()
		var a := to_local * from
		var b := to_local * to
		if not instance.mesh.get_aabb().grow(0.01).intersects_segment(a, b):
			continue
		var hit := _triangle_mesh(instance.mesh).intersect_segment(a, b)
		if hit.is_empty():
			continue
		var position: Vector3 = instance.global_transform * (hit["position"] as Vector3)
		var distance := from.distance_squared_to(position)
		if distance < best_distance:
			best_distance = distance
			var local_normal: Vector3 = hit.get("normal", Vector3.ZERO)
			best = {
				"mesh": instance,
				"position": position,
				"normal": (instance.global_basis.inverse().transposed() * local_normal).normalized(),
				"glass": is_glass(instance),
			}
	return best


static func is_glass(instance: MeshInstance3D) -> bool:
	var material := instance.material_override
	if material == null:
		material = instance.get_active_material(0)
	return material != null and material.resource_name == GLASS_MATERIAL


static func _triangle_mesh(mesh: Mesh) -> TriangleMesh:
	var cached: TriangleMesh = mesh.get_meta(&"bullet_hole_triangles") if mesh.has_meta(&"bullet_hole_triangles") else null
	if cached == null:
		cached = mesh.generate_triangle_mesh()
		mesh.set_meta(&"bullet_hole_triangles", cached)
	return cached


## Quad basis: +Z (the quad's face) along [param normal], spun by [param spin] around it.
static func _facing(normal: Vector3, spin: float) -> Basis:
	var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	var x := up.cross(normal).normalized()
	return Basis(x, normal.cross(x), normal).rotated(normal, spin)


static func _quad(glass: bool) -> QuadMesh:
	if _quads.has(glass):
		return _quads[glass]
	var material := StandardMaterial3D.new()
	material.albedo_texture = _crack_texture() if glass else _hole_texture()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if glass:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.roughness = 0.15
		material.metallic_specular = 0.8
	else:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.35
		material.roughness = 0.55
		material.metallic = 0.6
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * (CRACK_SIZE if glass else HOLE_SIZE)
	quad.material = material
	_quads[glass] = quad
	return quad


## Punched hole: a black core, a jagged ring of bare metal, then a scorched paint halo.
static func _hole_texture() -> Texture2D:
	const SIZE := 64
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var bumps: Array[float] = []
	for i in 12:
		bumps.append(rng.randf_range(0.85, 1.15))
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var p := Vector2((x + 0.5) / SIZE - 0.5, (y + 0.5) / SIZE - 0.5)
			var angle := fposmod(p.angle(), TAU) / TAU * bumps.size()
			var i := int(angle)
			var jag := lerpf(bumps[i % bumps.size()], bumps[(i + 1) % bumps.size()], angle - i)
			var r := p.length() / jag
			var pixel := Color(0, 0, 0, 0)
			if r < 0.15:
				pixel = Color(0.02, 0.02, 0.02, 1.0)
			elif r < 0.25:
				var shine := 0.55 + 0.3 * (1.0 - absf(r - 0.2) / 0.05)
				pixel = Color(shine, shine, shine * 1.02, 1.0)
			elif r < 0.42:
				var t := (r - 0.25) / 0.17
				pixel = Color(0.08, 0.07, 0.06, lerpf(0.85, 0.0, t))
			image.set_pixel(x, y, pixel)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## Spider-web crack: a hole, radial cracks with a kink or two, and two broken rings between them.
static func _crack_texture() -> Texture2D:
	const SIZE := 128
	var rng := RandomNumberGenerator.new()
	rng.seed = 9001
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 0))
	var centre := Vector2(SIZE, SIZE) * 0.5
	var spokes: Array[float] = []
	var count := 11
	for i in count:
		var angle := (i + rng.randf_range(-0.3, 0.3)) * TAU / count
		spokes.append(angle)
		var from := centre
		var length := rng.randf_range(0.36, 0.49) * SIZE
		var segments := 4
		for s in segments:
			var bend := angle + rng.randf_range(-0.18, 0.18)
			var to := centre + Vector2.from_angle(bend) * length * (s + 1) / segments
			_line(image, from, to, lerpf(0.95, 0.35, float(s) / segments))
			from = to
	for ring in [0.16, 0.3]:
		for i in count:
			if rng.randf() < 0.3:
				continue
			var a0: float = spokes[i]
			var a1: float = spokes[(i + 1) % count] + (TAU if i == count - 1 else 0.0)
			var r0: float = ring * SIZE * rng.randf_range(0.9, 1.1)
			var r1: float = ring * SIZE * rng.randf_range(0.9, 1.1)
			_line(image, centre + Vector2.from_angle(a0) * r0, centre + Vector2.from_angle(a1) * r1, 0.7 - ring)
	for y in SIZE:
		for x in SIZE:
			var r := Vector2(x + 0.5, y + 0.5).distance_to(centre) / SIZE
			if r < 0.035:
				image.set_pixel(x, y, Color(0.02, 0.02, 0.02, 1.0))
			elif r < 0.07:
				image.set_pixel(x, y, Color(0.95, 0.97, 1.0, 0.9))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


static func _line(image: Image, from: Vector2, to: Vector2, alpha: float) -> void:
	var steps := int(ceilf(from.distance_to(to))) + 1
	for i in steps + 1:
		var p := from.lerp(to, float(i) / steps)
		for o: Vector2i in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN]:
			var px := Vector2i(p) + o
			if px.x < 0 or px.y < 0 or px.x >= image.get_width() or px.y >= image.get_height():
				continue
			var a := alpha if o == Vector2i.ZERO else alpha * 0.5
			if image.get_pixel(px.x, px.y).a < a:
				image.set_pixel(px.x, px.y, Color(0.92, 0.95, 1.0, a))
