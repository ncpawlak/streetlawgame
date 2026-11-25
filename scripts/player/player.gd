class_name Player
extends CharacterBody3D
## Third-person on-foot controller: movement (walk, jog, sprint with stamina, crouch, climbing),
## the over-the-shoulder camera, shooting feel, melee, health and getting in and out of vehicles.

## Emitted whenever stamina changes (the HUD shows a bar while it isn't full).
signal stamina_changed(current: float, maximum: float)
## Emitted when damage lands, with the world position it came from (damage direction arcs).
signal damaged_from(origin: Vector3)

## Crouching cuts how far away witnesses, cops and dogs notice you.
const CROUCH_DETECTION := 0.55
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.2
## Obstacle heights (m) you vault or step onto, and the highest ledge you can pull up onto.
const VAULT_MIN := 0.35
const VAULT_MAX := 1.35
const LEDGE_MAX := 2.7
const MELEE_COOLDOWN := 0.6
const MELEE_REACH := 0.9
const MELEE_RADIUS := 0.7
## Melee hits land this long into the swing.
const MELEE_DELAY := 0.2
## Seconds without aiming or shooting before the gun goes back in its holster.
const HOLSTER_DELAY := 2.5
## Seconds the gun stays raised (body facing the crosshair) after the last shot.
const RAISED_LINGER := 1.5
## Off the floor this long (or rising) counts as airborne for the jump pose; skips stair-step blips.
const AIRBORNE_DELAY := 0.12
const CORPSE_LIFETIME := 30.0

@export var walk_speed := 5.0
@export var sprint_speed := 9.0
@export var crouch_speed := 2.2
## Slow walk (hold Alt).
@export var slow_walk_speed := 1.8
## Top speed while aiming (strafing).
@export var aim_speed := 4.0
@export var acceleration := 10.0
@export var jump_velocity := 5.5
@export var mouse_sensitivity := 0.003
@export var max_health := 100.0
@export var vehicle_enter_range := 3.5
## Fraction of cash lost when killed.
@export_range(0.0, 1.0) var death_cash_penalty := 0.1
## Range of the camera ray used to find what the crosshair is on.
@export var aim_ray_length := 200.0

@export_group("Stamina")
@export var max_stamina := 100.0
## Stamina used per second of sprinting.
@export var stamina_drain := 18.0
@export var stamina_regen := 22.0
## Seconds after sprinting before stamina comes back.
@export var stamina_regen_delay := 1.0
## After running dry you can't sprint again until stamina is back above this.
@export var stamina_recover_threshold := 30.0

@export_group("Camera")
@export var camera_height := 1.5
@export var camera_crouch_height := 1.05
@export var camera_distance := 3.0
@export var camera_side := 0.5
@export var camera_fov := 70.0
@export var aim_distance := 1.4
@export var aim_side := 0.65
@export var aim_fov := 48.0
## Look sensitivity multiplier while aiming.
@export var aim_sensitivity := 0.55
@export var sprint_fov_boost := 8.0
@export var sprint_distance_boost := 0.6

var health := 0.0
var current_vehicle: Vehicle
var spawn_point := Vector3.ZERO
var weapons: WeaponInventory
## Finds and runs Interactables (E); vehicles are entered through it too.
var interactor: Interactor
var stamina := 0.0
## Upgrade hook: multiplies how fast sprinting uses stamina (perks / stats lower it).
var stamina_drain_scale := 1.0
## 1 for the right shoulder, -1 for the left.
var shoulder := 1.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _shake := 0.0
var _crouching := false
var _sprinting := false
var _exhausted := false
var _stamina_wait := 0.0
var _aim_blend := 0.0
var _sprint_blend := 0.0
var _side_blend := 1.0
var _camera_kick := 0.0
var _bloom := 0.0
var _since_combat := 0.0
var _since_shot := INF
var _air_time := 0.0
var _melee_cooldown := 0.0
var _melee_count := 0
## Last hit reported through register_hit (where it came from, push, where it landed, frame).
var _last_hit := {}
## Vehicle whose seat the body sits in while driving.
var _riding: Vehicle
## Scripted moves (climbing, car doors): see [method play_moves].
var _moves: Array = []
var _move_index := 0
var _move_time := 0.0
var _move_from := Vector3.ZERO
var _move_from_yaw := 0.0
var _moves_done := Callable()
var _capsule: CapsuleShape3D

@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _spring_arm: SpringArm3D = $CameraPivot/SpringArm
@onready var _camera: Camera3D = $CameraPivot/SpringArm/Camera
@onready var _collision: CollisionShape3D = $Collision
## Animated body (see CharacterVisual); driven from movement, aim and fire.
@onready var visual: CharacterVisual = $Visual


func _ready() -> void:
	add_to_group("player")
	# Each player resizes its own capsule when crouching.
	_capsule = (_collision.shape as CapsuleShape3D).duplicate()
	_collision.shape = _capsule
	weapons = WeaponInventory.new()
	weapons.name = "Weapons"
	add_child(weapons)
	weapons.current_index = weapons.slots.size() - 1
	weapons.changed.connect(_on_weapons_changed)
	_on_weapons_changed()
	interactor = Interactor.new()
	interactor.name = "Interactor"
	add_child(interactor)
	health = max_health
	stamina = max_stamina
	spawn_point = global_position
	_camera_pivot.top_level = true
	_spring_arm.add_excluded_object(get_rid())
	_spring_arm.spring_length = camera_distance
	_spring_arm.position.x = camera_side
	_camera.fov = camera_fov
	_camera.cull_mask &= ~GameState.MAP_LAYER
	_camera.make_current()
	GameState.player = self
	EventBus.explosion.connect(_on_explosion)


## How much a crouching [param target] shrinks detection ranges (1 for anyone else).
static func detection_scale(target: Node) -> float:
	return CROUCH_DETECTION if target is Player and (target as Player).is_crouching() else 1.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and is_on_foot() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		var sensitivity := mouse_sensitivity * lerpf(1.0, aim_sensitivity, _aim_blend)
		_camera_pivot.rotate_y(-motion.relative.x * sensitivity)
		_spring_arm.rotation.x = clampf(_spring_arm.rotation.x - motion.relative.y * sensitivity, deg_to_rad(-65.0), deg_to_rad(35.0))
	elif event.is_action_pressed("swap_shoulder"):
		shoulder = -shoulder
		visual.set_shoulder(shoulder)
	elif is_busy() or not is_on_foot():
		return
	elif event.is_action_pressed("interact"):
		if interactor.try_interact() or _try_enter_vehicle():
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("reload"):
		weapons.reload()
	elif event.is_action_pressed("crouch"):
		set_crouching(not _crouching)
	elif event.is_action_pressed("melee"):
		melee()
	elif event.is_action_pressed("detonate"):
		if weapons.detonate_charges() == 0 and weapons.find(&"c4") != null:
			EventBus.notify.emit("No C4 placed")
	elif event.is_action_pressed("next_weapon"):
		weapons.cycle(1)
	elif event.is_action_pressed("prev_weapon"):
		weapons.cycle(-1)
	else:
		for i in InputSetup.WEAPON_HOTKEYS:
			if event.is_action_pressed("weapon_%d" % (i + 1)):
				weapons.select(i)


func _process(delta: float) -> void:
	if _riding != null:
		if is_instance_valid(_riding):
			global_transform = _riding.global_transform * Transform3D(Basis(Vector3.UP, PI), Vehicle.DRIVER_SEAT)
		else:
			_riding = null
	_update_camera(delta)
	_update_shake(delta)


func _update_camera(delta: float) -> void:
	var armed := weapons.current() != null and not weapons.current().data.is_melee()
	_aim_blend = move_toward(_aim_blend, 1.0 if is_aiming() and armed else 0.0, delta * 6.0)
	_sprint_blend = move_toward(_sprint_blend, 1.0 if _sprinting else 0.0, delta * 3.0)
	_side_blend = move_toward(_side_blend, shoulder, delta * 6.0)
	var height := lerpf(camera_height, camera_crouch_height, visual.crouch_amount())
	_camera_pivot.global_position = global_position + Vector3(0.0, height, 0.0)
	_spring_arm.spring_length = lerpf(camera_distance + sprint_distance_boost * _sprint_blend, aim_distance, _aim_blend)
	_spring_arm.position.x = _side_blend * lerpf(camera_side, aim_side, _aim_blend)
	_camera.fov = lerpf(camera_fov + sprint_fov_boost * _sprint_blend, aim_fov, _aim_blend)
	_camera_kick *= exp(-delta * 10.0)
	_camera.rotation.x = _camera_kick


## Shakes whichever camera is active (on foot or driving): explosions, hard hits.
func _update_shake(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	_shake = move_toward(_shake, 0.0, delta * 1.5)
	camera.h_offset = randf_range(-_shake, _shake) * 0.3
	camera.v_offset = randf_range(-_shake, _shake) * 0.3


## Adds camera shake (0..1, decays over about a second).
func add_shake(amount: float) -> void:
	_shake = clampf(maxf(_shake, amount), 0.0, 1.0)


func _on_explosion(at: Vector3, radius: float) -> void:
	var distance := get_focus_position().distance_to(at)
	add_shake(clampf(1.0 - distance / (radius * 5.0), 0.0, 1.0))


func _physics_process(delta: float) -> void:
	if not _moves.is_empty():
		_air_time = 0.0
		visual.set_airborne(false)
		_step_moves(delta)
		return
	_melee_cooldown = maxf(0.0, _melee_cooldown - delta)
	_since_shot += delta
	if not is_on_floor():
		velocity.y -= _gravity * delta
	if Input.is_action_just_pressed("jump") and _jump_or_climb():
		return

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := Basis(Vector3.UP, _camera_pivot.rotation.y) * Vector3(input.x, 0.0, input.y)
	var moving := direction.length_squared() > 0.01
	var aiming := is_aiming()
	if Input.is_action_pressed("sprint") and moving and not Input.is_action_pressed("aim") and not Input.is_action_pressed("shoot"):
		_since_shot = INF
	var raised := is_weapon_raised()
	_update_sprint(moving and Input.is_action_pressed("sprint") and not raised, delta)
	var speed := walk_speed
	if _crouching:
		speed = crouch_speed
	elif _sprinting:
		speed = sprint_speed
	elif Input.is_action_pressed("walk"):
		speed = slow_walk_speed
	if raised:
		speed = minf(speed, aim_speed)
	var blend := clampf(acceleration * delta, 0.0, 1.0)
	velocity.x = lerpf(velocity.x, direction.x * speed, blend)
	velocity.z = lerpf(velocity.z, direction.z * speed, blend)

	# With the gun up the body keeps facing the crosshair and the legs strafe / backpedal under it.
	if raised:
		rotation.y = lerp_angle(rotation.y, _camera_pivot.rotation.y, clampf(20.0 * delta, 0.0, 1.0))
	elif moving:
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), clampf(10.0 * delta, 0.0, 1.0))

	_update_weapon_state(aiming, raised, delta)
	if wants_to_fire():
		shoot()

	move_and_slide()
	_air_time = 0.0 if is_on_floor() else _air_time + delta
	visual.set_airborne(is_airborne(), velocity.y)
	visual.set_aiming(raised)
	visual.set_aim_pitch(asin(clampf(-_camera.global_basis.z.y, -1.0, 1.0)))
	visual.update_motion(velocity, delta)
	if global_position.y < -50.0:
		respawn()


## Right mouse held: the over-the-shoulder zoom (tighter spread). Firing alone doesn't zoom.
func is_aiming() -> bool:
	return is_on_foot() and not is_busy() and Input.is_action_pressed("aim")


## Gun up and pointed at the crosshair: aiming, holding fire, or shortly after a shot. The body
## faces the camera so you can move one way and shoot another.
func is_weapon_raised() -> bool:
	if not is_on_foot() or is_busy():
		return false
	var slot := weapons.current()
	if slot == null or slot.data.is_melee():
		return false
	return Input.is_action_pressed("aim") or Input.is_action_pressed("shoot") or _since_shot < RAISED_LINGER


## Off the ground from a jump or a fall (not just stepping off a kerb).
func is_airborne() -> bool:
	return is_on_foot() and not is_busy() and not is_on_floor() and (_air_time > AIRBORNE_DELAY or velocity.y > 1.0)


func is_crouching() -> bool:
	return _crouching


func is_sprinting() -> bool:
	return _sprinting


## Climbing or getting in / out of a car: input is ignored until the move finishes.
func is_busy() -> bool:
	return not _moves.is_empty()


## Crouches or stands up. Standing up fails under low cover. Returns whether the change happened.
func set_crouching(crouching: bool) -> bool:
	if crouching == _crouching:
		return true
	if not crouching and not _can_stand():
		return false
	_crouching = crouching
	_capsule.height = CROUCH_HEIGHT if crouching else STAND_HEIGHT
	_collision.position.y = _capsule.height * 0.5
	visual.set_crouching(crouching)
	return true


func _can_stand() -> bool:
	var probe := CapsuleShape3D.new()
	probe.radius = _capsule.radius - 0.02
	probe.height = STAND_HEIGHT - 0.1
	return _is_free(global_position + Vector3.UP * (STAND_HEIGHT * 0.5 + 0.06), probe)


func _is_free(center: Vector3, shape: Shape3D, mask := 1 | 8) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, center)
	query.collision_mask = mask
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


## Sprinting drains stamina; running dry drops you to a jog until it recovers past the threshold.
func _update_sprint(wants_sprint: bool, delta: float) -> void:
	if wants_sprint and _crouching:
		set_crouching(false)
	_sprinting = wants_sprint and not _exhausted and not _crouching
	var before := stamina
	if _sprinting:
		stamina = maxf(0.0, stamina - stamina_drain * stamina_drain_scale * delta)
		_stamina_wait = stamina_regen_delay
		if stamina <= 0.0:
			_exhausted = true
			_sprinting = false
		if weapons.is_reloading:
			weapons.cancel_reload()
	else:
		_stamina_wait = maxf(0.0, _stamina_wait - delta)
		if _stamina_wait <= 0.0:
			stamina = minf(max_stamina, stamina + stamina_regen * delta)
	if _exhausted and stamina >= stamina_recover_threshold:
		_exhausted = false
	if stamina != before:
		stamina_changed.emit(stamina, max_stamina)
	visual.set_sprinting(_sprinting)
	visual.set_winded(clampf((0.4 - stamina / max_stamina) / 0.4, 0.0, 1.0))


## Spread, holstering and the reload pose.
func _update_weapon_state(aiming: bool, raised: bool, delta: float) -> void:
	var slot := weapons.current()
	var data := slot.data if slot else null
	var recovery := (data.max_bloom * 2.5 + 2.0) if data else 4.0
	_bloom = move_toward(_bloom, 0.0, delta * recovery)
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	var spread := _bloom + flat_speed / sprint_speed * 3.0 + (0.0 if aiming else 1.5)
	if _crouching:
		spread *= 0.6
	weapons.extra_spread = spread
	if raised or weapons.is_reloading:
		_since_combat = 0.0
	else:
		_since_combat += delta
	visual.set_holstered(_since_combat > HOLSTER_DELAY and not raised)
	if weapons.is_reloading and data != null:
		visual.set_reload(data.reload_style, weapons.reload_progress())
	else:
		visual.set_reload(WeaponData.ReloadStyle.NONE, -1.0)


## Degrees of cone the next shot can stray (weapon spread plus movement, bloom and stance).
func current_spread() -> float:
	var slot := weapons.current()
	return (slot.data.spread_degrees if slot else 0.0) + weapons.extra_spread


func shoot() -> bool:
	var exclude: Array[RID] = [get_rid()]
	var muzzle := global_position + Vector3(0.0, 1.4 - 0.45 * visual.crouch_amount(), 0.0)
	var aim_point := Hitscan.camera_aim_point(_camera, aim_ray_length, exclude)
	var fired := weapons.try_fire(self, muzzle, aim_point - muzzle, exclude)
	if fired:
		_since_combat = 0.0
		var data_fired := weapons.current().data
		if not data_fired.is_melee():
			_since_shot = 0.0
		visual.set_holstered(false)
		visual.fire()
		var data := weapons.current().data
		if not data.is_melee():
			_bloom = minf(_bloom + data.bloom_per_shot, data.max_bloom)
			_recoil(data.recoil_degrees)
	return fired


## Kicks the camera up: part of it stays (you have to pull back down), the rest springs back.
func _recoil(degrees: float) -> void:
	var kick := deg_to_rad(degrees)
	_spring_arm.rotation.x = clampf(_spring_arm.rotation.x + kick * 0.35, deg_to_rad(-65.0), deg_to_rad(35.0))
	_camera_kick += kick * 0.65
	_camera_pivot.rotate_y(randf_range(-1.0, 1.0) * kick * 0.15)
	add_shake(minf(degrees * 0.03, 0.15))


## Point under the crosshair of whichever camera is active (used for drive-bys too).
func aim_point_from(camera: Camera3D, exclude: Array[RID]) -> Vector3:
	return Hitscan.camera_aim_point(camera, aim_ray_length, exclude)


## Automatic weapons fire while held; others once per click.
func wants_to_fire() -> bool:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or weapons.current() == null or is_busy():
		return false
	if weapons.current().data.automatic:
		return Input.is_action_pressed("shoot")
	return Input.is_action_just_pressed("shoot")


## Melee with whatever is equipped: punches (every third swing, or any swing while sprinting, is a
## kick), a pistol-whip, or a rifle-butt. Hitting an unaware gang member from behind is a silent
## takedown. Returns whether a swing started.
func melee() -> bool:
	if _melee_cooldown > 0.0 or not is_on_foot() or is_busy():
		return false
	var slot := weapons.current()
	var data := slot.data if slot else null
	var kind := &"punch_r"
	var damage := 15.0
	if data == null or data.is_melee():
		_melee_count += 1
		damage = data.damage if data else damage
		if _sprinting or _melee_count % 3 == 0:
			kind = &"kick"
			damage *= 1.5
		else:
			kind = &"punch_l" if _melee_count % 2 == 1 else &"punch_r"
	else:
		kind = &"butt" if data.carry == WeaponData.Carry.BACK else &"whip"
		damage = data.melee_damage
		_since_combat = 0.0
		visual.set_holstered(false)
	weapons.cancel_reload()
	_melee_cooldown = MELEE_COOLDOWN
	visual.melee(kind)
	get_tree().create_timer(MELEE_DELAY, false).timeout.connect(_melee_strike.bind(damage))
	return true


func _melee_strike(damage: float) -> void:
	if not is_inside_tree() or health <= 0.0:
		return
	var forward := -global_basis.z
	var center := global_position + forward * MELEE_REACH + Vector3.UP * (1.0 - 0.4 * visual.crouch_amount())
	var sphere := SphereShape3D.new()
	sphere.radius = MELEE_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, center)
	query.collision_mask = 4 | 8 | Ragdoll.LAYER
	query.exclude = [get_rid()]
	var seen := {}
	var hit_any := false
	var killed := false
	for result in get_world_3d().direct_space_state.intersect_shape(query, 16):
		var body := result.get("collider") as Node3D
		if body == null or seen.has(body):
			continue
		seen[body] = true
		var push := (forward + Vector3.UP * 0.3).normalized() * damage * 2.0
		if Ragdoll.push_part(body, push, center):
			continue
		if not body.has_method("take_damage"):
			continue
		var amount := damage
		if _is_takedown(body):
			amount = 1000.0
			EventBus.notify.emit("Silent takedown")
		if body.has_method("register_hit"):
			body.register_hit(global_position, push, center, false)
		var was_alive := Hitscan.is_alive(body)
		body.take_damage(amount, self)
		hit_any = true
		killed = killed or (was_alive and not Hitscan.is_alive(body))
	if hit_any:
		weapons.hit_confirmed.emit()
		add_shake(0.08)
	if killed:
		weapons.kill_confirmed.emit()


## A gang member who hasn't noticed you, hit from behind.
func _is_takedown(body: Node3D) -> bool:
	var member := body as GangMember
	if member == null or not member.is_alive() or member.is_alerted():
		return false
	var from_me := member.global_position - global_position
	return from_me.dot(-member.global_basis.z) > 0.0


## Space: vault, step up or pull up onto a ledge in front; otherwise an ordinary jump. In the air it
## grabs a ledge within reach. Returns true when a climb started.
func _jump_or_climb() -> bool:
	var climb := find_climb()
	if not climb.is_empty():
		_start_climb(climb)
		return true
	if is_on_floor():
		if _crouching:
			set_crouching(false)
		else:
			velocity.y = jump_velocity
	return false


## Looks for something climbable straight ahead. Returns {} or {kind (&"vault" / &"step" / &"ledge"),
## edge (top of the near face), into (horizontal direction into it), land (where the feet end up)}.
func find_climb() -> Dictionary:
	var space := get_world_3d().direct_space_state
	var forward := -global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var base := global_position
	var wall := {}
	for height in [0.5, 1.0, 1.6, 2.2]:
		var from: Vector3 = base + Vector3.UP * height
		var query := PhysicsRayQueryParameters3D.create(from, from + forward * 1.0, 1 | 8)
		query.exclude = [get_rid()]
		var hit := space.intersect_ray(query)
		if not hit.is_empty() and absf((hit["normal"] as Vector3).y) < 0.5:
			wall = hit
			break
	if wall.is_empty():
		return {}
	var into := -(wall["normal"] as Vector3)
	into.y = 0.0
	into = into.normalized()
	var face: Vector3 = wall["position"]
	var top := _floor_below(space, face + into * 0.2, base.y + LEDGE_MAX + 0.4, base.y + 0.1)
	if top.is_empty():
		return {}
	var top_y: float = (top["position"] as Vector3).y
	var height := top_y - base.y
	if height < VAULT_MIN or height > LEDGE_MAX:
		return {}
	var edge := Vector3(face.x, top_y, face.z)
	var probe := CapsuleShape3D.new()
	probe.radius = 0.3
	probe.height = 1.0
	if height <= VAULT_MAX:
		var beyond := _floor_below(space, face + into * 1.2, top_y + 0.5, base.y - 2.0)
		var beyond_y: float = (beyond["position"] as Vector3).y if not beyond.is_empty() else base.y - 2.0
		if beyond_y < top_y - 0.4:
			var land := Vector3(face.x, beyond_y, face.z) + into * 1.2
			if beyond.is_empty():
				land.y = base.y
			if _is_free(land + Vector3.UP * 0.75, probe, 1 | 8 | 4):
				return {kind = &"vault", edge = edge, into = into, land = land}
	var stand_at := face + into * 0.5
	var stand := _floor_below(space, stand_at, top_y + 0.3, top_y - 0.3)
	if stand.is_empty():
		return {}
	var land_top: Vector3 = stand["position"]
	if not _is_free(land_top + Vector3.UP * 0.75, probe, 1 | 8 | 4):
		return {}
	return {kind = &"step" if height <= VAULT_MAX else &"ledge", edge = edge, into = into, land = land_top}


func _floor_below(space: PhysicsDirectSpaceState3D, at: Vector3, from_y: float, to_y: float) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(Vector3(at.x, from_y, at.z), Vector3(at.x, to_y, at.z), 1 | 8)
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty() or (hit["normal"] as Vector3).y < 0.7:
		return {}
	return hit


func _start_climb(climb: Dictionary) -> void:
	var edge: Vector3 = climb["edge"]
	var into: Vector3 = climb["into"]
	var land: Vector3 = climb["land"]
	var side := into.cross(Vector3.UP).normalized() * 0.22
	var hands := {&"L": edge - side + Vector3.UP * 0.03, &"R": edge + side + Vector3.UP * 0.03}
	var back := edge - into * 0.3
	weapons.cancel_reload()
	var steps: Array = []
	match climb["kind"]:
		&"vault":
			steps = [
				{to = Vector3(back.x, maxf(global_position.y, edge.y - 0.7), back.z), time = 0.16, face = into, crouch = true, reach = hands},
				{to = edge + into * 0.25 + Vector3.UP * 0.12, time = 0.22, face = into, crouch = true, reach = hands},
				{to = land, time = 0.24, face = into, crouch = false},
			]
		&"step":
			steps = [
				{to = Vector3(back.x, maxf(global_position.y, edge.y - 0.55), back.z), time = 0.18, face = into, crouch = true, reach = hands},
				{to = land, time = 0.3, face = into, crouch = true, reach = hands},
				{to = land, time = 0.15, face = into, crouch = false},
			]
		_:
			steps = [
				{to = Vector3(back.x, edge.y - 1.45, back.z), time = 0.25, face = into, reach = hands},
				{to = Vector3(back.x, edge.y - 1.45, back.z), time = 0.12, face = into, reach = hands},
				{to = edge - into * 0.1 + Vector3.DOWN * 0.3, time = 0.45, face = into, crouch = true, reach = hands},
				{to = land, time = 0.3, face = into, crouch = true},
				{to = land, time = 0.15, face = into, crouch = false},
			]
	play_moves(steps)


## Steers the body through scripted [param steps] with collision off (climbing, car doors), then
## calls [param finished]. Step keys: [code]to[/code] (feet position), [code]time[/code],
## [code]frame[/code] (a Node3D that [code]to[/code], [code]face[/code] and [code]reach[/code] are
## local to), [code]face[/code] (direction to turn to), [code]keep_y[/code], [code]walk[/code] (play
## locomotion for the movement), [code]arc[/code] (hop height), [code]seated[/code] /
## [code]crawl[/code] (0..1 pose targets), [code]crouch[/code], [code]reach[/code] ({&"L": point,
## &"R": point} for the hands) and [code]start[/code] (Callable run when the step begins).
func play_moves(steps: Array, finished := Callable()) -> void:
	if steps.is_empty():
		if finished.is_valid():
			finished.call()
		return
	_moves = steps
	_moves_done = finished
	_move_index = -1
	_sprinting = false
	visual.set_sprinting(false)
	visual.set_aiming(false)
	velocity = Vector3.ZERO
	_sync_collision.call_deferred()
	_next_move()


func _next_move() -> void:
	_move_index += 1
	if _move_index >= _moves.size():
		_end_moves()
		return
	var step: Dictionary = _moves[_move_index]
	_move_time = 0.0
	_move_from = global_position
	_move_from_yaw = rotation.y
	if step.has("seated"):
		visual.set_seated(step["seated"])
	if step.has("crawl"):
		visual.set_crawl(step["crawl"])
	if step.has("crouch"):
		visual.set_crouching(step["crouch"] or _crouching)
	for side in [&"L", &"R"]:
		visual.set_reach(side, Vector3.ZERO, 0.0)
	if step.has("start"):
		(step["start"] as Callable).call()


func _step_moves(delta: float) -> void:
	var step: Dictionary = _moves[_move_index]
	var frame: Node3D = step.get("frame")
	if frame != null and not is_instance_valid(frame):
		_end_moves()
		return
	var to_world := frame.global_transform if frame != null else Transform3D.IDENTITY
	var duration: float = maxf(step.get("time", 0.3), 0.001)
	_move_time += delta
	var t := clampf(_move_time / duration, 0.0, 1.0)
	var eased := t if step.get("walk", false) else smoothstep(0.0, 1.0, t)
	var target: Vector3 = to_world * (step.get("to", to_world.affine_inverse() * _move_from) as Vector3)
	if step.get("keep_y", false):
		target.y = _move_from.y
	var previous := global_position
	global_position = _move_from.lerp(target, eased) + Vector3.UP * (float(step.get("arc", 0.0)) * sin(t * PI))
	if step.has("face"):
		var face: Vector3 = to_world.basis * (step["face"] as Vector3)
		if Vector2(face.x, face.z).length_squared() > 0.0001:
			rotation.y = lerp_angle(_move_from_yaw, atan2(-face.x, -face.z), smoothstep(0.0, 1.0, minf(t * 2.0, 1.0)))
	var reach: Dictionary = step.get("reach", {})
	for side: StringName in reach:
		visual.set_reach(side, to_world * (reach[side] as Vector3), smoothstep(0.0, 0.4, t))
	var moved := (global_position - previous) / delta
	visual.update_motion(Vector3(moved.x, 0.0, moved.z) if step.get("walk", false) else Vector3.ZERO, delta)
	if t >= 1.0:
		_next_move()


func _end_moves() -> void:
	var finished := _moves_done
	_moves = []
	_moves_done = Callable()
	for side in [&"L", &"R"]:
		visual.set_reach(side, Vector3.ZERO, 0.0)
	visual.set_crouching(_crouching)
	visual.set_crawl(0.0)
	if _riding == null:
		visual.set_seated(0.0)
	velocity = Vector3.ZERO
	_sync_collision.call_deferred()
	if finished.is_valid():
		finished.call()


## Stops any scripted move without running its finish callback (death, respawn).
func cancel_moves() -> void:
	_moves_done = Callable()
	if not _moves.is_empty():
		_end_moves()


func _sync_collision() -> void:
	if _wants_collision_off():
		_collision.disabled = true
		return
	if not _collision.disabled:
		return
	# Jolt sweeps a teleported kinematic body to its new transform over the next physics step; with the
	# shape live it would plough through (and launch) the car we just left, so enable it a step later.
	await get_tree().physics_frame
	if is_inside_tree():
		_collision.disabled = _wants_collision_off()


func _wants_collision_off() -> bool:
	return _riding != null or current_vehicle != null or not _moves.is_empty()


func is_on_foot() -> bool:
	return current_vehicle == null


## Position the world should treat as "where the player is" (the vehicle when driving).
func get_focus_position() -> Vector3:
	return current_vehicle.global_position if current_vehicle else global_position


func nearest_free_vehicle() -> Vehicle:
	var best: Vehicle = null
	var best_distance := vehicle_enter_range
	for node in get_tree().get_nodes_in_group("vehicles"):
		var vehicle := node as Vehicle
		var distance := global_position.distance_to(vehicle.global_position)
		if vehicle.can_enter() and distance < best_distance:
			best = vehicle
			best_distance = distance
	return best


## Called by Vehicle when entering/exiting. While driving the body sits in the driver's seat.
func set_on_foot(on_foot: bool, vehicle: Vehicle = null) -> void:
	current_vehicle = null if on_foot else vehicle
	_riding = null if on_foot else vehicle
	visible = true
	set_physics_process(on_foot)
	velocity = Vector3.ZERO
	if not on_foot:
		_crouching = false
		_capsule.height = STAND_HEIGHT
		_collision.position.y = STAND_HEIGHT * 0.5
		visual.set_crouching(false)
		visual.set_sprinting(false)
		visual.set_aiming(false)
		visual.set_airborne(false)
		visual.set_seated(1.0)
		visual.update_motion(Vector3.ZERO)
		_sprinting = false
	else:
		var yaw := global_rotation.y
		rotation = Vector3(0.0, yaw, 0.0)
		visual.set_seated(0.0)
		_camera_pivot.rotation.y = yaw
		_camera.make_current()
	_sync_collision.call_deferred()


## Records where the next take_damage comes from (bullets, blasts, cars) so hit reactions, the
## damage-direction HUD and a death ragdoll can follow it.
func register_hit(origin: Vector3, impulse: Vector3, at: Vector3 = Vector3.INF, _headshot := false) -> void:
	_last_hit = {origin = origin, impulse = impulse, at = at, frame = Engine.get_physics_frames()}


func take_damage(amount: float, source: Node = null) -> void:
	if health <= 0.0 or amount <= 0.0:
		return
	var hit := _recent_hit()
	var origin: Vector3 = hit.get("origin", source.global_position if source is Node3D else global_position)
	var impulse: Vector3 = hit.get("impulse", Vector3.ZERO)
	if impulse == Vector3.ZERO and origin.distance_squared_to(global_position) > 0.01:
		impulse = (global_position - origin).normalized() * amount
	_set_health(health - amount)
	damaged_from.emit(origin)
	add_shake(clampf(amount / max_health * 1.5, 0.05, 0.5))
	if health <= 0.0:
		_die(impulse, hit.get("at", Vector3.INF))
	else:
		visual.hit(impulse)


func _recent_hit() -> Dictionary:
	if _last_hit.is_empty() or Engine.get_physics_frames() - int(_last_hit["frame"]) > 1:
		return {}
	return _last_hit


func respawn() -> void:
	cancel_moves()
	if current_vehicle:
		current_vehicle.exit()
	set_crouching(false)
	global_position = spawn_point
	velocity = Vector3.ZERO
	_set_health(max_health)
	stamina = max_stamina
	_exhausted = false
	stamina_changed.emit(stamina, max_stamina)


## Health only comes back through pickups, items and services; it never regenerates on its own.
func heal(amount: float) -> void:
	if health > 0.0:
		_set_health(health + amount)


func _try_enter_vehicle() -> bool:
	var vehicle := nearest_free_vehicle()
	if vehicle == null:
		return false
	vehicle.begin_enter(self)
	return true


func _die(impulse := Vector3.ZERO, at := Vector3.INF) -> void:
	_spawn_corpse(impulse, at)
	var loss := int(GameState.cash * death_cash_penalty)
	GameState.add_cash(-loss)
	EventBus.notify.emit("WASTED - hospital bill: $%d" % loss)
	EventBus.player_died.emit()
	respawn()


## Leaves a ragdoll copy of the body where you died (you respawn straight away).
func _spawn_corpse(impulse: Vector3, at: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null or not is_on_foot():
		return
	var corpse := CharacterVisual.create(visual.archetype, visual.variant)
	corpse.name = "PlayerCorpse"
	scene.add_child(corpse)
	corpse.global_transform = visual.global_transform
	corpse.set_crouching(_crouching)
	var carried := []
	for slot in weapons.slots:
		carried.append(slot.data)
	corpse.set_carried(carried)
	var moving := velocity
	# One frame of animation first so the ragdoll starts from a real pose, not the rest pose.
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(corpse):
		corpse.die(impulse, at, moving)
		get_tree().create_timer(CORPSE_LIFETIME, false).timeout.connect(corpse.queue_free)


func _on_weapons_changed() -> void:
	visual.set_weapon(weapons.current().data if weapons.current() else null)
	var carried := []
	for slot in weapons.slots:
		carried.append(slot.data)
	visual.set_carried(carried)


func _set_health(value: float) -> void:
	health = clampf(value, 0.0, max_health)
	EventBus.player_health_changed.emit(health, max_health)
