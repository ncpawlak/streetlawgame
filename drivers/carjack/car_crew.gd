class_name CarCrew
extends RefCounted
## Puts animated people in the driver's seat of carjack cars (victims, cops) and tints the cabin glass
## so you can see who is inside. Purely visual; collision stays the car's.

## Driver's seat in car space. Cars face +Z, so the driver (left-hand drive) sits on +X, the same side
## [method Vehicle.exit] and the fleeing owner leave from. The feet stand on the floor pan (the body's
## underside, 0.4 m) so they don't poke out below the car.
const DRIVER_SEAT := Vector3(0.4, 0.4, 0.2)
## There is no sitting clip yet, so a standing model stands in for a seated one, scaled to keep the head
## under the 2.0 m roof with head and shoulders showing through the cabin glass (docs/design/SCALE.md).
const SEATED_SCALE := 0.85


## Adds a [CharacterVisual] of [param kind] in the driver's seat, facing forward.
static func seat_driver(car: Vehicle, kind: StringName, tint: Variant = null, bandana: Variant = null) -> CharacterVisual:
	var visual := CharacterVisual.create(kind, randi())
	visual.name = "Driver"
	visual.position = DRIVER_SEAT
	visual.rotation.y = PI
	visual.scale = Vector3.ONE * SEATED_SCALE
	if tint != null:
		visual.set_tint(tint)
	visual.set_bandana(bandana)
	car.add_child(visual)
	return visual


## Makes the car's cabin box see-through tinted glass.
static func tint_glass(car: Vehicle) -> void:
	if car._body_materials.size() < 2:
		return
	var glass := car._body_materials[1]
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color.a = 0.45
