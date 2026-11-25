class_name HitIdentity
extends Node
## Who the police think did it. Lives on the actor as a child named "HitIdentity"
## ([method HitIdentity.of]), like [CarryBag].
##
## - Wear a mask ([method set_masked]) during a hit and witnesses/cameras don't get your face: no
##   personal heat. Get seen unmasked and [method witness] adds personal heat to the [HeatMap].
## - The car you were seen in (or arrived in) is remembered as [member seen_vehicle].
## - Afterwards, mask OFF and in a DIFFERENT car than the one seen at the hit, the heat drops much
##   faster: [method decay_multiplier] (personal heat) and [method escape_multiplier] (losing the
##   cops in a [PoliceResponse]). Staying in the seen car or keeping the mask on in public is slow.

signal mask_changed(masked: bool)
signal identified

const NODE_NAME := &"HitIdentity"
## Disguised (masked at the hit, mask off now) AND in a different car.
const CLEAN_SWAP := 4.0
## Only one of the two.
const HALF_SWAP := 1.75
## Still in the car they saw, or walking around in a mask.
const MARKED := 0.6

var masked := false
## A hit is in progress (between [method begin_hit] and [method end_hit]).
var on_hit := false
## Someone saw your face during this hit.
var face_seen := false
## The vehicle the police associate with this hit.
var seen_vehicle: Node3D
## The last vehicle the actor drove (what they probably arrived in).
var last_vehicle: Node3D
## Personal heat added this hit, per evidence source (so erasing footage can take it back).
var evidence: Dictionary = {}
## Where the mask sits on actors without a [CharacterVisual] (actor-local). Animated actors wear it on
## the head bone instead, like the gang bandana.
var mask_offset := Vector3(0.0, 1.55, -0.15)

var _mask_mesh: MeshInstance3D
var _mask_visual: CharacterVisual


static func of(actor: Node, create := true) -> HitIdentity:
	if actor == null:
		return null
	var identity := actor.get_node_or_null(NodePath(NODE_NAME)) as HitIdentity
	if identity == null and create:
		identity = HitIdentity.new()
		identity.name = NODE_NAME
		actor.add_child(identity)
	return identity


func _physics_process(_delta: float) -> void:
	var vehicle := _current_vehicle()
	if vehicle != null:
		last_vehicle = vehicle


func set_masked(value: bool) -> void:
	if masked == value:
		return
	masked = value
	_update_mask_visual()
	EventBus.notify.emit("Mask on" if masked else "Mask off")
	mask_changed.emit(masked)


func toggle_mask() -> void:
	set_masked(not masked)


## Starts tracking a new hit.
func begin_hit() -> void:
	on_hit = true
	face_seen = false
	seen_vehicle = null
	evidence.clear()


func end_hit() -> void:
	on_hit = false


## The actor was seen during the hit by [param source] (&"camera", &"witness", &"police"...).
## Unmasked, that's personal heat in [param heat]. The car they're in (or came in) gets noted.
## Returns true if their face was seen.
func witness(heat: HeatMap, source: StringName, amount := HeatMap.FACE_HEAT) -> bool:
	note_vehicle()
	if masked:
		return false
	if not evidence.has(source):
		evidence[source] = amount
		if heat != null:
			heat.add_personal_heat(amount)
		if not face_seen:
			EventBus.notify.emit("They got a look at your face")
			identified.emit()
	face_seen = true
	return true


## Notes the car the actor is in (or last drove) as the one seen at the hit, without adding heat.
func note_vehicle() -> void:
	var vehicle := _current_vehicle()
	if vehicle != null:
		seen_vehicle = vehicle
	elif seen_vehicle == null and last_vehicle != null and is_instance_valid(last_vehicle):
		seen_vehicle = last_vehicle


## Destroys one kind of evidence (e.g. &"camera" when the recorder is unplugged), taking back the
## personal heat it added. Returns the heat removed.
func erase_evidence(heat: HeatMap, source: StringName) -> float:
	if not evidence.has(source):
		return 0.0
	var amount := float(evidence[source])
	evidence.erase(source)
	if heat != null:
		heat.add_personal_heat(-amount)
	face_seen = not evidence.is_empty()
	return amount


## True when the actor no longer looks like the person at the hit: they weren't seen unmasked there
## and aren't wearing the mask now.
func is_disguised() -> bool:
	return not face_seen and not masked


## True when they're not in the vehicle the police are looking for.
func swapped_vehicle() -> bool:
	var vehicle := _current_vehicle()
	return vehicle != null and vehicle != seen_vehicle


## Personal heat decay multiplier.
func decay_multiplier() -> float:
	var disguised := is_disguised()
	var swapped := swapped_vehicle()
	if disguised and swapped:
		return CLEAN_SWAP
	if disguised or swapped:
		return HALF_SWAP if not _in_seen_vehicle() else MARKED
	if masked or _in_seen_vehicle():
		return MARKED
	return 1.0


## How fast cops lose track of the actor (multiplies [member PoliceResponse.unseen_time] gain).
func escape_multiplier() -> float:
	return decay_multiplier()


func status_text() -> String:
	var text := "MASK ON" if masked else "mask off"
	if seen_vehicle != null or face_seen:
		var rate := decay_multiplier()
		if rate >= CLEAN_SWAP:
			text += "  |  clean swap: heat dropping fast"
		elif rate < 1.0:
			text += "  |  %s" % ("they know this car" if _in_seen_vehicle() else "the mask draws attention")
		if face_seen:
			text += "  |  FACE SEEN"
	return text


func _update_mask_visual() -> void:
	var actor := get_parent() as Node3D
	if actor == null:
		return
	if _mask_mesh == null:
		_mask_visual = actor.get("visual") as CharacterVisual if "visual" in actor else null
		var mesh := BoxMesh.new()
		# A balaclava wrapping the head (slightly bigger than the bandana so it covers it).
		mesh.size = Vector3(0.26, 0.27, 0.29) if _mask_visual != null else Vector3(0.62, 0.42, 0.14)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.05, 0.05, 0.06)
		mesh.material = material
		_mask_mesh = MeshInstance3D.new()
		_mask_mesh.name = "Mask"
		_mask_mesh.mesh = mesh
		if _mask_visual != null:
			_mask_mesh.top_level = true
			_mask_visual.skeleton.skeleton_updated.connect(_place_mask)
		else:
			_mask_mesh.position = mask_offset
		actor.add_child.call_deferred(_mask_mesh)
	_mask_mesh.visible = masked


## Keeps the balaclava on the animated head (runs once the pose is final, like the bandana).
func _place_mask() -> void:
	if _mask_mesh == null or not _mask_mesh.visible or not is_instance_valid(_mask_visual) or not _mask_visual.is_inside_tree():
		return
	var skeleton := _mask_visual.skeleton
	var head := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Head"))
	var basis := head.basis.orthonormalized()
	_mask_mesh.global_transform = Transform3D(basis, head.origin + basis.y * 0.12 * CharacterVisual._shared_scale())


func _current_vehicle() -> Node3D:
	var actor := get_parent()
	if actor != null and "current_vehicle" in actor:
		return actor.get("current_vehicle") as Node3D
	return null


func _in_seen_vehicle() -> bool:
	var vehicle := _current_vehicle()
	return vehicle != null and vehicle == seen_vehicle
