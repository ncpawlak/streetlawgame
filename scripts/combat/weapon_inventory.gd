class_name WeaponInventory
extends Node
## Weapons a character carries: selection, fire cadence, ammo and reloading.
## Used by the player and by NPCs.

signal changed
## Emitted when a shot damages something.
signal hit_confirmed

@export var starting_weapon_ids: Array[StringName] = [&"fists", &"pistol"]
## Spare magazines given with each starting weapon.
@export var starting_magazines := 3
## Delay after switching weapons before you can fire.
@export var swap_time := 0.2
## Multiplier on outgoing damage (NPCs hit softer than the player).
@export var damage_scale := 1.0
## Extra spread in degrees on top of the weapon's own.
@export var extra_spread := 0.0
## Reloads never consume reserve ammo (NPCs).
@export var infinite_reserve := false

var slots: Array[WeaponSlot] = []
var current_index := 0
var is_reloading := false
## C4 charges placed and waiting for the detonate key.
var placed_charges: Array = []

var _cooldown := 0.0
var _reload_left := 0.0


func _ready() -> void:
	for id in starting_weapon_ids:
		var weapon := GameState.weapon_data(id)
		if weapon != null:
			add_weapon(weapon, weapon.magazine_size * starting_magazines)


func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if is_reloading:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()


func current() -> WeaponSlot:
	return slots[current_index] if current_index < slots.size() else null


func find(id: StringName) -> WeaponSlot:
	for slot in slots:
		if slot.data.id == id:
			return slot
	return null


## Adds a weapon, or just its ammo if already carried.
func add_weapon(weapon: WeaponData, reserve_ammo: int) -> WeaponSlot:
	var slot := find(weapon.id)
	if slot != null:
		slot.reserve = mini(slot.reserve + reserve_ammo, weapon.max_reserve)
	else:
		slot = WeaponSlot.new(weapon, reserve_ammo)
		slots.append(slot)
	changed.emit()
	return slot


func select(index: int) -> void:
	if index < 0 or index >= slots.size() or index == current_index:
		return
	is_reloading = false
	current_index = index
	_cooldown = swap_time
	changed.emit()


func cycle(step: int) -> void:
	if not slots.is_empty():
		select(posmod(current_index + step, slots.size()))


func can_reload() -> bool:
	var slot := current()
	if slot == null or is_reloading or not slot.data.uses_ammo():
		return false
	return slot.magazine < slot.data.magazine_size and (infinite_reserve or slot.reserve > 0)


func reload() -> bool:
	if not can_reload():
		return false
	is_reloading = true
	_reload_left = current().data.reload_time
	changed.emit()
	return true


## 0..1 progress of the active reload.
func reload_progress() -> float:
	var slot := current()
	if not is_reloading or slot == null or slot.data.reload_time <= 0.0:
		return 0.0
	return clampf(1.0 - _reload_left / slot.data.reload_time, 0.0, 1.0)


## Fires the current weapon if it's ready. Starts a reload when the magazine runs dry.
func try_fire(shooter: Node3D, muzzle: Vector3, direction: Vector3, exclude: Array[RID] = []) -> bool:
	var slot := current()
	if slot == null or is_reloading or _cooldown > 0.0:
		return false
	if slot.is_empty():
		reload()
		return false
	_cooldown = slot.data.fire_interval
	if slot.data.uses_ammo():
		slot.magazine -= 1
	if slot.data.is_projectile():
		var projectile := Projectile.launch(shooter, slot.data, muzzle, direction, exclude)
		if slot.data.remote_detonated:
			placed_charges.append(projectile)
	elif Hitscan.fire(shooter, muzzle, direction, slot.data, exclude, damage_scale, extra_spread) > 0:
		hit_confirmed.emit()
	if slot.is_empty():
		reload()
	changed.emit()
	return true


## Sets off every C4 charge this inventory has placed. Returns how many went off.
func detonate_charges() -> int:
	var count := 0
	for charge in placed_charges:
		if is_instance_valid(charge):
			(charge as Projectile).detonate()
			count += 1
	placed_charges.clear()
	if count > 0:
		changed.emit()
	return count


func _finish_reload() -> void:
	is_reloading = false
	var slot := current()
	if slot != null:
		var needed := slot.data.magazine_size - slot.magazine
		var moved := needed if infinite_reserve else mini(needed, slot.reserve)
		slot.magazine += moved
		if not infinite_reserve:
			slot.reserve -= moved
	changed.emit()
