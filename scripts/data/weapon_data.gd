class_name WeaponData
extends Resource
## Stats for a hitscan weapon. Weapons are .tres files in res://data/weapons/<id>.tres.

@export var id: StringName = &"pistol"
@export var display_name := "Pistol"
## Damage per projectile.
@export var damage := 25.0
@export var max_range := 80.0
@export var fire_interval := 0.25
@export var spread_degrees := 1.0
## Projectiles per shot (shotguns fire several pellets).
@export var pellets := 1
## Hold the trigger to keep firing.
@export var automatic := false
## Rounds per magazine. 0 means the weapon needs no ammo (melee).
@export var magazine_size := 12
@export var max_reserve := 120
@export var reload_time := 1.2
@export var price := 0
@export var show_tracer := true
@export var tracer_color := Color(1.0, 0.85, 0.4)


func uses_ammo() -> bool:
	return magazine_size > 0


func is_melee() -> bool:
	return max_range <= 3.0
