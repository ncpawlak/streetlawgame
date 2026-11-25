extends Node3D
## Entry scene: lighting/environment, mouse capture, and placing the player in the generated city.

@onready var _city: CityGenerator = $City
@onready var _player: Player = $Player

## Lots left after the roster (NorthEndSpots) for the filler placer; tests replay the plan.
var placer_lots: Array[Dictionary] = []
var placer_density := 0.05


func _ready() -> void:
	_build_environment()
	_player.global_position = _city.player_spawn
	_player.spawn_point = _city.player_spawn
	_spawn_starter_stash()
	_place_locations()
	_tag_hot_cars()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	EventBus.notify.emit.call_deferred("Welcome to Tamarack Row. The Red Vipers run the North End. Take the boarded duplex [E] and start taking it back.")
	EventBus.notify.emit.call_deferred("There's a weapon stash by your ride. Hold [Q] for the weapon wheel.")


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


## Guns and explosives near spawn so the arsenal can be tried right away (until the gun store, #12).
func _spawn_starter_stash() -> void:
	var ground := _city.player_spawn - Vector3(0.0, 1.0, 0.0)
	var stash := {
		&"smg": Vector3(-4.0, 0.0, -3.0), &"shotgun": Vector3(-4.0, 0.0, 0.0), &"rifle": Vector3(-4.0, 0.0, 3.0),
		&"grenade": Vector3(-7.0, 0.0, -4.5), &"molotov": Vector3(-7.0, 0.0, -1.5), &"c4": Vector3(-7.0, 0.0, 1.5), &"rpg": Vector3(-7.0, 0.0, 4.5),
	}
	for id: StringName in stash:
		var weapon := GameState.weapon_data(id)
		add_child(WeaponPickup.create(weapon, weapon.magazine_size * (5 if weapon.thrown else 3), ground + stash[id]))


## The North End roster (NorthEndSpots) on its wireframe lots: business sites, robbable houses and
## shops, fronts, the trap house and plugs; roster items without a system yet get a labelled marker.
## Remaining lots get a sprinkle of extra houses. Content: data/locations/, data/business_sites/.
func _place_locations() -> void:
	var parent := Node3D.new()
	parent.name = "Locations"
	add_child(parent)
	var markers := Node3D.new()
	markers.name = "RosterMarkers"
	add_child(markers)
	var used := {}
	for spot: Dictionary in NorthEndSpots.SPOTS:
		var px: Vector2 = spot["px"]
		var lot := {} if spot.get("free", false) else _city.lot_near(px, 40.0, used, CityGenerator.district_for_px(px))
		if not lot.is_empty():
			used[lot["index"]] = true
		var at := _spot_transform(spot, lot)
		match spot["kind"]:
			&"site":
				Businesses.spawn_site(spot["id"], at, parent)
			&"location":
				var def := ContentDB.get_def(LocationDef.TYPE, spot["id"]) as LocationDef
				if def == null:
					push_warning("North End: missing LocationDef %s" % spot["id"])
					continue
				if not def.unique and def.display_name != spot["name"]:
					def = def.duplicate() as LocationDef
					def.display_name = spot["name"]
				Locations.spawn(def, at, parent, spot["instance"])
			&"marker":
				_add_roster_marker(spot, at.origin, markers)
	placer_lots.clear()
	for lot in _city.building_lots:
		if not used.has(lot["index"]):
			placer_lots.append(lot)
	var placer := LocationPlacer.new()
	placer.placement_seed = _city.city_seed
	placer.density = placer_density
	placer.place(placer_lots, parent, placer_defs())
	Businesses.place_sites(placer_lots, parent)


## Defs used for the filler sprinkle on lots the roster leaves free.
func placer_defs() -> Array:
	return [ContentDB.get_def(LocationDef.TYPE, &"house")]


## Door on the lot face toward the spot (or [code]face[/code]); the spot itself when it has no lot.
func _spot_transform(spot: Dictionary, lot: Dictionary) -> Transform3D:
	var px: Vector2 = spot["px"]
	var toward: Vector2 = spot.get("face", px)
	if lot.is_empty():
		var facing := CityGenerator.px_to_world(toward) - CityGenerator.px_to_world(px)
		var outward := Vector3.BACK if facing.length() < 0.1 else facing.normalized()
		return Transform3D(Basis.looking_at(-outward), CityGenerator.px_to_world(px))
	var rect: Rect2 = lot["rect_px"]
	if not spot.has("face") and rect.has_point(px):
		return LocationPlacer.door_transform(lot)
	var away := toward - rect.get_center()
	var side := Vector3(signf(away.x), 0.0, 0.0) if absf(away.x) >= absf(away.y) else Vector3(0.0, 0.0, signf(away.y))
	if side == Vector3.ZERO:
		return LocationPlacer.door_transform(lot)
	var faced := lot.duplicate()
	faced["block_center"] = (lot["center"] as Vector3) - side
	return LocationPlacer.door_transform(faced)


## The orange hot cars (CityGenerator.HOT_CARS_PX) go in the &"hot_cars" group for the pause map.
func _tag_hot_cars() -> void:
	for hot: Array in CityGenerator.HOT_CARS_PX:
		var at := CityGenerator.px_to_world(hot[0])
		for node in _city.get_children():
			if node is Vehicle and Vector2(node.position.x - at.x, node.position.z - at.z).length() < 3.0:
				node.add_to_group(&"hot_cars")


## A tall labelled post plus a map disc for roster items that have no working system yet.
func _add_roster_marker(spot: Dictionary, at: Vector3, parent: Node3D) -> void:
	var color: Color = NorthEndSpots.MARKER_COLORS.get(spot.get("style", &"event"), Color.WHITE)
	var title := "#%s %s" % [spot["roster"], spot["name"]] if spot["roster"] != "" else String(spot["name"])
	var marker := Node3D.new()
	marker.name = "Roster_%s" % String(spot["roster"]).validate_node_name()
	marker.set_meta(&"spot", spot)
	marker.add_to_group(&"roster_markers")
	parent.add_child(marker)
	marker.position = Vector3(at.x, 0.0, at.z)
	var pole := VisualSpec.greybox(&"box", Vector3(0.3, 6.0, 0.3), color)
	pole.position = Vector3(0.0, 3.0, 0.0)
	marker.add_child(pole)
	var sign_label := Label3D.new()
	sign_label.text = "%s\n(coming soon)" % title
	sign_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign_label.font_size = 48
	sign_label.pixel_size = 0.01
	sign_label.outline_size = 10
	sign_label.modulate = color.lightened(0.4)
	sign_label.position = Vector3(0.0, 7.0, 0.0)
	marker.add_child(sign_label)
	var disc := CylinderMesh.new()
	disc.top_radius = 3.0
	disc.bottom_radius = 3.0
	disc.height = 0.5
	disc.material = VisualSpec.material(color)
	var map_disc := MeshInstance3D.new()
	map_disc.mesh = disc
	map_disc.layers = GameState.MAP_LAYER
	map_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	map_disc.position = Vector3(0.0, Location.MARKER_HEIGHT, 0.0)
	marker.add_child(map_disc)
	var map_label := Label3D.new()
	map_label.text = String(spot["roster"])
	map_label.layers = GameState.MAP_LAYER
	map_label.font_size = 96
	map_label.pixel_size = 0.05
	map_label.outline_size = 16
	map_label.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	map_label.position = Vector3(0.0, Location.MARKER_HEIGHT + 1.0, 0.0)
	marker.add_child(map_label)

func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.35, 0.5, 0.75)
	sky_material.sky_horizon_color = Color(0.8, 0.65, 0.55)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_density = 0.003
	environment.fog_light_color = Color(0.75, 0.65, 0.6)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
	add_child(sun)
