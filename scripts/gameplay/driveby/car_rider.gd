class_name CarRider
extends Node3D
## An animated [CharacterVisual] riding in a car and leaning out of a side window to shoot, drive-by
## style. Child of the [Vehicle]; purely visual (no collision). The node is the pivot on the window
## sill: legs hang down inside the car body, torso, head and gun lean out over the door.
## Car body is y 0.4-1.4 and the cabin 1.4-2.0 (see docs/design/SCALE.md); the car faces +Z.

const SILL_HEIGHT := 1.35
const SILL_INSET := 0.8
## Hip height of the 1.8 m model above its feet.
const HIP_HEIGHT := 0.9
const LEAN := 0.35

var visual: CharacterVisual
## +1 leans out of the car's +X side, -1 out of the -X side.
var side := 1.0


static func create(archetype: StringName, seed_value: int, color: Color, rider_side: float, seat_z: float, weapon_id: StringName, tint_darken := 0.3) -> CarRider:
	var rider := CarRider.new()
	rider.name = "Rider"
	rider.side = signf(rider_side) if rider_side != 0.0 else 1.0
	rider.position = Vector3(rider.side * SILL_INSET, SILL_HEIGHT, seat_z)
	rider.rotation.z = -rider.side * LEAN
	rider.visual = CharacterVisual.create(archetype, seed_value)
	rider.visual.position = Vector3(0.0, -HIP_HEIGHT, 0.0)
	rider.visual.set_tint(color.darkened(tint_darken))
	rider.visual.set_bandana(color)
	rider.visual.set_weapon(GameState.weapon_data(weapon_id))
	rider.add_child(rider.visual)
	rider.idle()
	return rider


## Turns to face and points the gun at a world position.
func aim_at(point: Vector3) -> void:
	if visual.is_dead():
		return
	var local := global_transform.basis.inverse() * (point - visual.global_position)
	visual.rotation.y = atan2(-local.x, -local.z)
	visual.set_aiming(true)
	visual.set_aim_pitch(atan2(local.y, Vector2(local.x, local.z).length()))


## Gun lowered, looking the way the car is going.
func idle() -> void:
	if visual.is_dead():
		return
	visual.set_aiming(false)
	visual.set_aim_pitch(0.0)
	visual.rotation.y = PI


func fire() -> void:
	visual.fire()


func hit() -> void:
	visual.hit()


func die() -> void:
	visual.die()
