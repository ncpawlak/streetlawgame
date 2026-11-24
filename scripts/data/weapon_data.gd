class_name WeaponData
extends Resource
## Stats for a weapon. Weapons are .tres files in res://data/weapons/<id>.tres.

enum Kind { HITSCAN, PROJECTILE }
## What a projectile does when it touches something.
enum Impact { EXPLODE, BOUNCE, STICK }

@export var id: StringName = &"pistol"
@export var display_name := "Pistol"
@export var kind := Kind.HITSCAN
## Damage per pellet, or blast damage at the center for explosives.
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

@export_group("Projectile")
## Thrown by hand (grenades, molotovs, C4): lobbed in an arc, and the HUD shows a count, not a magazine.
@export var thrown := false
@export var impact := Impact.EXPLODE
@export var projectile_speed := 18.0
## Multiplier on gravity while in flight (0 flies straight, like a rocket).
@export var projectile_gravity := 1.0
## Seconds until it explodes by itself. 0 means no fuse.
@export var fuse_time := 0.0
## Waits for the detonate key (C4).
@export var remote_detonated := false
@export var blast_radius := 0.0
## Push applied to rigid bodies (vehicles) at the center of the blast.
@export var blast_impulse := 0.0
## Fire left behind after exploding (molotovs). 0 means no fire.
@export var fire_duration := 0.0
@export var fire_radius := 3.0
@export var fire_dps := 15.0


func is_projectile() -> bool:
	return kind == Kind.PROJECTILE


func uses_ammo() -> bool:
	return magazine_size > 0


func is_melee() -> bool:
	return max_range <= 3.0
