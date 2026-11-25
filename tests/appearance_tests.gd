class_name AppearanceTests
extends RefCounted
## Tests for player appearance: clothing / hair catalogs, Appearance save + similarity, the rig
## (part swaps, tints, attachments), buying clothes and haircuts, disguise / recognition, faction
## colour reactions, the conditions / effects, GangMember attitude, the panel and stations.
## Hooked from run_tests.gd; restores everything it touches.

const BARBER_SITE := &"tamarack_barbershop"

var _runner: Node


func _init(runner: Node) -> void:
	_runner = runner


func _check(condition: bool, description: String) -> void:
	_runner.call("_check", condition, "appearance: " + description)


func run(main: Node, player: Player) -> void:
	var saved_look := PlayerAppearance.to_dict()
	var saved_cash := GameState.cash
	var saved_position := player.global_transform
	_test_content()
	_test_look_model()
	PlayerAppearance.reset()
	_test_rig(player)
	_test_buying()
	_test_recognition()
	_test_reactions()
	_test_conditions_and_effects()
	_test_save_load()
	await _test_gang_members(main, player)
	await _test_panel(main, player)
	PlayerAppearance.from_dict(saved_look)
	GameState.cash = saved_cash
	player.global_transform = saved_position


func _test_content() -> void:
	var issues := PackedStringArray()
	for type: StringName in [ClothingItemDef.TYPE, HairItemDef.TYPE, FactionStyleDef.TYPE]:
		for resource in ContentDB.all(type):
			for issue in resource.call("validate"):
				issues.append("%s: %s" % [resource.get("id"), issue])
	_check(issues.is_empty(), "catalogs validate %s" % issues)
	for slot in Appearance.SLOTS:
		_check(not Appearance.catalog(slot).is_empty(), "%s catalog has items" % slot)
	var default := Appearance.default_look()
	_check(default.slots.keys().all(func(slot: StringName) -> bool: return default.item_def(slot) != null), "default look items exist")
	for faction: StringName in [&"angeles", &"hellraisers"]:
		_check(GameState.GANGS.has(faction) and FactionStyleDef.find(faction) != null, "%s is a gang with a style" % faction)
	_check((Businesses.type_of(BARBER_SITE) as BusinessTypeDef).appearance_service == &"barber", "barbershop runs the barber service")
	var store := ContentDB.find_def(BusinessTypeDef.TYPE, &"clothing_store") as BusinessTypeDef
	_check(store != null and store.appearance_service == &"clothing", "clothing store business type exists")


func _test_look_model() -> void:
	var look := Appearance.default_look()
	var copy := Appearance.from_dict(look.to_dict())
	_check(copy.signature() == look.signature() and look.similarity(copy) == 1.0, "look round-trips through to_dict")
	var recolored := look.copy()
	recolored.set_slot(&"top", &"hoodie", 3)
	var partial := look.similarity(recolored)
	_check(partial < 1.0 and partial > 0.85, "a recoloured top only partly changes the look (%.2f)" % partial)
	var changed := look.copy()
	changed.set_slot(&"top", &"tee", 1)
	changed.set_slot(&"hat", &"cap", 0)
	changed.set_slot(&"hair", &"buzz_cut")
	changed.set_slot(&"hair_color", &"hair_dye", 4)
	_check(look.similarity(changed) < 0.6, "new top + hat + hair breaks similarity (%.2f)" % look.similarity(changed))
	var yellow := Appearance.from_dict({"slots": {"top": {"item": "hoodie", "color": 3}, "bottom": {"item": "jeans", "color": 2}}})
	var weights := yellow.color_weights()
	_check(is_equal_approx(float(weights.get(&"yellow", 0.0)), 3.0 / 8.5) and yellow.affinity([&"yellow", &"white"]) > 0.55,
		"colour weights follow the visible outfit")


func _test_rig(player: Player) -> void:
	var visual := player.visual
	var rig := AppearanceRig.for_visual(visual)
	_check(rig.part_source(&"Body") == &"hoodie" and visual.appearance().get_item(&"top") == &"hoodie", "player wears the default look")
	var look := Appearance.default_look()
	look.set_slot(&"top", &"punk_jacket", 1)
	look.set_slot(&"hat", &"cap", 2)
	look.set_slot(&"hair", &"mohawk")
	look.set_slot(&"facial_hair", &"goatee")
	PlayerAppearance.set_look(look)
	_check(rig.part_source(&"Body") == &"punk" and rig.part_source(&"Head") == &"punk", "tops and hairstyles swap part meshes")
	var body := rig.active_part(&"Body")
	var tinted := false
	for i in body.mesh.get_surface_count():
		var material := body.get_surface_override_material(i) as BaseMaterial3D
		if material != null and body.mesh.surface_get_material(i).resource_name == "Pink":
			tinted = material.albedo_color.is_equal_approx(Color(0.98, 0.84, 0.2))
	_check(tinted, "variant colour tints the clothing material")
	_check(body.skeleton == NodePath("..") and body.get_parent() == visual.skeleton, "swapped parts are skinned to the rig")
	_check(rig.attachment_nodes().size() == 3, "hat + goatee attachments are built (%d)" % rig.attachment_nodes().size())
	var head := rig.skeleton_pose(visual.skeleton.find_bone("Head")).origin
	var cap := rig.attachment_nodes()[0].global_position
	_check(cap.distance_to(head) < 0.45 and cap.y > head.y, "the cap sits on the head")
	look.clear_slot(&"hat")
	look.clear_slot(&"facial_hair")
	look.set_slot(&"top", &"hoodie", 0)
	look.set_slot(&"hair", &"short_crop")
	PlayerAppearance.set_look(look)
	_check(rig.part_source(&"Body") == &"hoodie" and rig.attachment_nodes().is_empty() and rig.active_part(&"Body").visible,
		"changing back restores the model's own parts")
	PlayerAppearance.reset()


func _test_buying() -> void:
	PlayerAppearance.reset()
	_check(PlayerAppearance.owns(&"hoodie", 0) and not PlayerAppearance.owns(&"hoodie", 3), "starts owning only the starting clothes")
	_check(PlayerAppearance.equip(&"top", &"tee", 0) != "", "can't wear clothes you don't own")
	var tee := Appearance.find_item(&"top", &"tee")
	GameState.cash = 1000
	_check(PlayerAppearance.buy(&"top", &"tee", 1) == "" and GameState.cash == 1000 - tee.base_price, "buying charges the price")
	_check(PlayerAppearance.look().is_wearing(&"tee", 1) and PlayerAppearance.owns(&"tee", 1), "bought clothes are owned and worn")
	_check(PlayerAppearance.equip(&"top", &"hoodie", 0) == "" and PlayerAppearance.buy(&"top", &"tee", 1) == ""
		and GameState.cash == 1000 - tee.base_price, "owned clothes aren't charged again")
	GameState.cash = 1
	_check(PlayerAppearance.buy(&"top", &"suit_jacket", 0) != "" and not PlayerAppearance.owns(&"suit_jacket", 0), "can't buy without cash")
	_check(PlayerAppearance.unequip(&"top") != "" and PlayerAppearance.unequip(&"hat") == "", "only hats / accessories come off")
	var tier := Businesses.tier_of(BARBER_SITE)
	var expected := roundi(tee.base_price * (1.0 + PlayerAppearance.TIER_MARKUP * (tier - 1)))
	_check(PlayerAppearance.price_of(tee, BARBER_SITE) == expected, "prices scale with the site's area tier")
	Businesses.acquire(BARBER_SITE)
	_check(PlayerAppearance.price_of(tee, BARBER_SITE) == roundi(expected * Businesses.OWNER_DISCOUNT), "owned sites charge half")
	Businesses.lose_site(BARBER_SITE)
	GameState.cash = 1000
	var cut := Appearance.find_item(&"hair", &"buzz_cut")
	_check(PlayerAppearance.get_haircut(&"hair", &"buzz_cut") == "" and GameState.cash == 1000 - cut.base_price
		and PlayerAppearance.look().get_item(&"hair") == &"buzz_cut", "a haircut is paid for and applied")
	_check(PlayerAppearance.get_haircut(&"hair", &"buzz_cut") == "" and GameState.cash == 1000 - cut.base_price, "the same cut again is free")
	_check(PlayerAppearance.get_haircut(&"hair", &"short_crop") == "" and GameState.cash == 1000 - cut.base_price - 20,
		"going back to the old style is paid for (hair isn't owned)")
	_check(PlayerAppearance.get_haircut(&"facial_hair", &"beard") == "" and PlayerAppearance.get_haircut(&"facial_hair", &"") == ""
		and PlayerAppearance.look().get_item(&"facial_hair") == &"", "facial hair can be shaved off")
	PlayerAppearance.reset()


func _test_recognition() -> void:
	PlayerAppearance.reset()
	_check(PlayerAppearance.recognised_by(&"angeles") and not PlayerAppearance.is_disguised_from(&"angeles"),
		"the Angeles recognise the starting look")
	_check(not PlayerAppearance.has_known_look(&"hellraisers") and PlayerAppearance.is_disguised_from(&"hellraisers")
		and not PlayerAppearance.is_disguised_from(&"hellraisers", true), "factions that never saw you have nothing to recognise")
	_grant_and_wear(&"top", &"hoodie", 6)
	_check(PlayerAppearance.recognised_by(&"angeles"), "a different hoodie colour isn't a disguise")
	_disguise()
	_check(not PlayerAppearance.recognised_by(&"angeles") and PlayerAppearance.is_disguised_from(&"angeles", true),
		"new outfit + hair breaks recognition (%.2f)" % PlayerAppearance.recognition(&"angeles"))
	PlayerAppearance.remember_look(&"angeles")
	_check(PlayerAppearance.recognised_by(&"angeles"), "once seen, the new look is known too")
	PlayerAppearance.forget_look(&"angeles")
	_check(not PlayerAppearance.has_known_look(&"angeles"), "forget_look clears the record")
	PlayerAppearance.reset()


func _test_reactions() -> void:
	PlayerAppearance.reset()
	_check(PlayerAppearance.reaction_of(&"angeles") == &"hostile", "recognised by the Angeles = hostile")
	_check(PlayerAppearance.reaction_of(&"vipers") == &"hostile", "classic rival gangs stay hostile")
	_check(PlayerAppearance.reaction_of(&"hellraisers") == &"suspicious", "Hellraisers are wary of strangers")
	_disguise()
	_check(PlayerAppearance.reaction_of(&"angeles") == &"neutral", "a disguised stranger is left alone")
	_grant_and_wear(&"top", &"varsity_jacket", 1)
	_grant_and_wear(&"bottom", &"jeans", 2)
	_grant_and_wear(&"hat", &"cap", 2)
	_check(PlayerAppearance.faction_affinity(&"angeles") >= 0.5 and PlayerAppearance.reaction_of(&"angeles") == &"friendly",
		"wearing yellow + white reads as Angeles (%.2f)" % PlayerAppearance.faction_affinity(&"angeles"))
	_check(PlayerAppearance.reaction_of(&"hellraisers") == &"hostile", "the Angeles' rivals hate their colours")
	_grant_and_wear(&"top", &"punk_jacket", 4)
	_grant_and_wear(&"bottom", &"punk_pants", 0)
	_grant_and_wear(&"hat", &"head_bandana", 3)
	_check(PlayerAppearance.reaction_of(&"angeles") == &"hostile" and PlayerAppearance.reaction_of(&"hellraisers") == &"neutral",
		"black + orange provokes the Angeles and calms the Hellraisers")
	PlayerAppearance.reset()


func _test_conditions_and_effects() -> void:
	PlayerAppearance.reset()
	var ctx := ActionContext.new(GameState.player)
	var disguised := DisguisedCondition.new()
	disguised.faction = &"angeles"
	_check(not disguised.is_met(ctx) and disguised.reason(ctx) != "", "is_disguised_from(angeles) fails in the starting look")
	var not_hostile := FactionReactionCondition.new()
	not_hostile.faction = &"angeles"
	var wearing := WearingCondition.new()
	wearing.color_tag = &"yellow"
	wearing.min_share = 0.12
	_check(not not_hostile.is_met(ctx) and not wearing.is_met(ctx), "reaction / wearing conditions start unmet")
	_disguise()
	_grant_and_wear(&"top", &"varsity_jacket", 1)
	_check(disguised.is_met(ctx) and not_hostile.is_met(ctx) and wearing.is_met(ctx), "conditions pass once disguised in yellow")
	var remember := RememberLookEffect.new()
	remember.faction = &"angeles"
	remember.apply(ctx)
	_check(not disguised.is_met(ctx), "RememberLookEffect burns the disguise")
	remember.forget = true
	remember.apply(ctx)
	_check(not PlayerAppearance.has_known_look(&"angeles"), "RememberLookEffect can forget")
	PlayerAppearance.reset()


func _test_save_load() -> void:
	PlayerAppearance.reset()
	_disguise()
	PlayerAppearance.remember_look(&"hellraisers")
	var data := PlayerAppearance.to_dict()
	var signature := PlayerAppearance.signature()
	PlayerAppearance.reset()
	PlayerAppearance.from_dict(JSON.parse_string(JSON.stringify(data)))
	_check(PlayerAppearance.signature() == signature and PlayerAppearance.owns(&"tee", 5)
		and PlayerAppearance.recognised_by(&"hellraisers") and not PlayerAppearance.recognised_by(&"angeles"),
		"look, wardrobe and faction memories survive save/load (as JSON)")
	PlayerAppearance.reset()


func _test_gang_members(main: Node, player: Player) -> void:
	PlayerAppearance.reset()
	var spot := player.global_position + Vector3(0.0, 0.0, 30.0)
	player.global_position = spot
	var angel := _spawn_member(main, &"angeles", spot + Vector3(6.0, 0.5, 0.0))
	var biker := _spawn_member(main, &"hellraisers", spot + Vector3(-6.0, 0.5, 0.0))
	var viper := _spawn_member(main, &"vipers", spot + Vector3(0.0, 0.5, 30.0))
	await _runner.call("_physics_frames", 5)
	_check(angel.visual.appearance().get_item(&"top") == &"varsity_jacket" and angel.visual.appearance().get_color(&"top") == 1,
		"Angeles wear their yellow uniform")
	_check(viper.visual.appearance() == null, "gangs without a uniform keep the tinted model")
	_check(angel.attitude == &"hostile" and angel.is_hostile(), "an Angeles member is hostile to the recognised player")
	_check(biker.attitude == &"suspicious", "a Hellraiser is suspicious of a stranger")
	_disguise()
	angel.refresh_attitude()
	_check(angel.attitude == &"neutral" and not angel.is_hostile(), "the disguise calms the Angeles member")
	var style := FactionStyleDef.find(&"hellraisers")
	var saved_time := style.suspicion_time
	style.suspicion_time = 0.2
	await _runner.call("_physics_frames", 40)
	style.suspicion_time = saved_time
	_check(biker.is_hostile() and PlayerAppearance.recognised_by(&"hellraisers"),
		"a suspicious stare turns hostile and the Hellraisers remember the look")
	angel.provoke()
	_check(angel.is_hostile(), "being shot at makes even a neutral member hostile")
	for member in [angel, biker, viper]:
		member.queue_free()
	player.health = player.max_health
	PlayerAppearance.reset()


func _test_panel(main: Node, player: Player) -> void:
	PlayerAppearance.reset()
	GameState.cash = 1000
	var station := AppearanceStation.new()
	station.mode = "clothing"
	main.add_child(station)
	station.global_position = player.global_position + Vector3(2.0, 0.0, 0.0)
	_check(station.perform(AppearanceStation.ACTION, player), "a clothing station opens the store")
	var panel := PlayerAppearance.panel()
	_check(panel != null and panel.is_open and panel.mode == &"clothing" and main.get_tree().paused, "the store panel pauses the game")
	_check(panel.camera() != null and panel.camera().current, "the preview camera takes over")
	_check(player.global_position.distance_to(station.global_position) < 0.01, "the player steps up to the station")
	var start := panel.camera().global_position
	panel.orbit(1.0)
	_check(panel.camera().global_position.distance_to(start) > 0.5, "the preview camera orbits the player")
	panel.select(&"varsity_jacket", 1)
	_check(player.visual.appearance().is_wearing(&"varsity_jacket", 1) and not PlayerAppearance.look().is_wearing(&"varsity_jacket"),
		"selecting previews the item without buying it")
	var price := panel.selection_price()
	_check(panel.confirm() == "" and GameState.cash == 1000 - price and PlayerAppearance.look().is_wearing(&"varsity_jacket", 1),
		"confirm buys and wears it")
	panel.select_slot(&"hat")
	panel.select(&"beanie", 0)
	panel.close()
	_check(not panel.is_open and not main.get_tree().paused and not player.visual.appearance().is_wearing(&"beanie"),
		"closing drops the unbought preview and unpauses")
	station.queue_free()

	var wardrobe := Wardrobe.new()
	main.add_child(wardrobe)
	wardrobe.perform(AppearanceStation.ACTION, player)
	_check(panel.mode == &"wardrobe" and panel.selection_price() == 0, "the wardrobe opens the free owned-clothes mode")
	panel.select(&"hoodie", 0)
	_check(panel.confirm() == "" and PlayerAppearance.look().is_wearing(&"hoodie", 0), "the wardrobe changes into owned clothes")
	panel.select(&"tee", 2)
	_check(panel.confirm() != "", "the wardrobe can't conjure unowned clothes")
	panel.close()
	wardrobe.queue_free()

	var chair_spot := player.global_position
	PlayerAppearance.open_panel(&"barber", BARBER_SITE, player, null)
	_check(panel.mode == &"barber" and panel.slots() == Appearance.HAIR_SLOTS, "the barber edits hair slots")
	panel.orbit(10.0)
	panel.select(&"mohawk")
	var cut_price := panel.selection_price()
	_check(cut_price > 0 and panel.confirm() == "" and PlayerAppearance.look().get_item(&"hair") == &"mohawk",
		"the barber charges for a new hairstyle ($%d)" % cut_price)
	panel.close()
	_check(player.global_position.distance_to(chair_spot) < 0.01, "the player is back where they stood")
	PlayerAppearance.reset()


func _spawn_member(main: Node, gang: StringName, at: Vector3) -> GangMember:
	var member := GangMember.new()
	member.gang_id = gang
	member.weapon_id = &"pistol"
	main.add_child(member)
	member.global_position = at
	return member


func _grant_and_wear(slot: StringName, item_id: StringName, color: int) -> void:
	PlayerAppearance.grant(item_id, color)
	PlayerAppearance.equip(slot, item_id, color)


## The Mission 1 style disguise: a plain grey tee and beanie, buzz cut and bleached hair.
func _disguise() -> void:
	_grant_and_wear(&"top", &"tee", 5)
	_grant_and_wear(&"hat", &"beanie", 1)
	var look := PlayerAppearance.look()
	look.set_slot(&"hair", &"buzz_cut")
	look.set_slot(&"hair_color", &"hair_dye", 4)
	PlayerAppearance.set_look(look)
