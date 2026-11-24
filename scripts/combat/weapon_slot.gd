class_name WeaponSlot
extends RefCounted
## Runtime state of a carried weapon: its data plus loaded and reserve ammo.

var data: WeaponData
var magazine := 0
var reserve := 0


func _init(weapon: WeaponData, reserve_ammo: int = 0) -> void:
	data = weapon
	magazine = weapon.magazine_size
	reserve = clampi(reserve_ammo, 0, weapon.max_reserve)


func is_empty() -> bool:
	return data.uses_ammo() and magazine <= 0


func can_reload() -> bool:
	return data.uses_ammo() and magazine < data.magazine_size and reserve > 0


func has_any_ammo() -> bool:
	return not data.uses_ammo() or magazine + reserve > 0


func ammo_text() -> String:
	return "%d / %d" % [magazine, reserve] if data.uses_ammo() else "-"
