extends RefCounted
## CharacterVisual tests: person scale, aim/fire animation layer and the NPC death animation.

var _runner: Node


func _init(runner: Node) -> void:
	_runner = runner


func run(main: Node, player: Player) -> void:
	player.respawn()
	await _frames(10)
	_test_scale(player)
	await _test_aim(player)
	await _test_gang_member(main, player)


func _test_scale(player: Player) -> void:
	var visual := player.visual
	var capsule := player.get_node("Collision").shape as CapsuleShape3D
	_check(is_equal_approx(capsule.radius, 0.4) and is_equal_approx(capsule.height, 1.8), "player keeps its 0.4 x 1.8 m collision capsule")
	var head := visual.head_height()
	_check(head > 1.4 and head < 1.65, "player model is person-scale (head bone at %.2f m)" % head)
	_check(visual.animation_tree.get_animation_list().size() >= 20, "shared Quaternius clip library is loaded")


func _test_aim(player: Player) -> void:
	var visual := player.visual
	visual.set_weapon(GameState.weapon_data(&"pistol"))
	var rest := _hand_forward(visual)
	Input.action_press(&"aim")
	await _frames(30)
	var aimed := _hand_forward(visual)
	_check(aimed > rest + 0.2, "aiming raises the gun hand forward (%.2f -> %.2f m)" % [rest, aimed])
	var weapon := visual.get_node("Weapon") as Node3D
	_check(weapon.visible and weapon.global_position.distance_to(visual.hand_position()) < 0.4, "the held weapon follows the right hand")
	visual.fire()
	await _frames(5)
	_check(visual.animation_tree.get(&"parameters/shoot/active"), "firing plays the shoot one-shot")
	Input.action_release(&"aim")


func _test_gang_member(main: Node, player: Player) -> void:
	var member := GangMember.new()
	member.gang_id = &"vipers"
	member.weapon_id = &"smg"
	member.aggro_range = 0.0
	member.alerted_range = 0.0
	member.position = player.global_position + Vector3(0.0, 0.0, 30.0)
	main.add_child(member)
	await _frames(10)
	var bandana := member.visual.get_node("Bandana") as Node3D
	_check(member.visual.archetype == &"gang" and bandana.visible, "gang members wear an animated model with gang bandana")
	member.take_damage(1000.0, player)
	await _frames(90)
	var head := member.visual.head_height()
	_check(member.visual.is_dead() and head < 0.8, "a killed gang member plays the death animation (head at %.2f m)" % head)
	member.queue_free()


## How far the right hand is in front of the character (m).
func _hand_forward(visual: CharacterVisual) -> float:
	return (visual.hand_position() - visual.global_position).dot(-visual.global_basis.z)


func _frames(count: int) -> void:
	for i in count:
		await _runner.get_tree().physics_frame


func _check(condition: bool, description: String) -> void:
	_runner.call(&"_check", condition, description)
