class_name GiveWeaponEffect
extends Effect
## Gives the acting player a weapon with [member ammo] reserve rounds, or just the ammo if it's
## already carried.

@export var weapon_id: StringName
@export var ammo := 0


func _describe(_ctx: ActionContext) -> String:
	return "%s +%d" % [String(weapon_id).capitalize(), ammo]


func _apply(ctx: ActionContext) -> void:
	var player := ctx.actor as Player if ctx.actor is Player else GameState.player
	var weapon := GameState.weapon_data(weapon_id)
	if player != null and weapon != null:
		player.weapons.add_weapon(weapon, ammo)
