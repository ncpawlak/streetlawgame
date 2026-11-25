class_name CarCrew
extends RefCounted
## Puts animated people in the driver's seat of carjack cars (victims, cops) and tints the cabin glass
## so you can see who is inside. Purely visual; collision stays the car's.

## Adds a [CharacterVisual] of [param kind] in the driver's seat, facing forward.
static func seat_driver(car: Vehicle, kind: StringName, tint: Variant = null, bandana: Variant = null) -> CharacterVisual:
	var visual := CharacterVisual.create(kind, randi())
	visual.name = "Driver"
	visual.position = Vehicle.DRIVER_SEAT
	visual.rotation.y = PI
	visual.set_seated(1.0)
	if tint != null:
		visual.set_tint(tint)
	visual.set_bandana(bandana)
	car.add_child(visual)
	return visual


## Darkens the car's cabin glass a little (every car's cabin is see-through; see [Vehicle]).
static func tint_glass(car: Vehicle) -> void:
	if car._body_materials.size() < 2:
		return
	var glass := car._body_materials[1]
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color.a = 0.45
