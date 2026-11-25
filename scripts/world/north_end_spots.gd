class_name NorthEndSpots
extends RefCounted
## Where the North End roster (docs/design/NORTH_END_HITS.md) sits on the greybox, in wireframe px
## (docs/map/north_end_wireframe_source.svg; as-built: north_end_wireframe.svg). main.gd puts each spot on the nearest lot:
## - kind &"site": a business site (#36) by [code]id[/code].
## - kind &"location": a LocationDef [code]id[/code] spawned as [code]instance[/code], optionally renamed.
## - kind &"marker": no system yet; a labelled post and map marker so the spot can be found.
## [code]face[/code] (px) turns the door toward that point instead of the nearest road.
## [code]style[/code] colours markers: home, shop, bank, raid, event, trap, corner, plug.

const SPOTS := [
	# --- Tamarack Row -------------------------------------------------------------------------
	{"roster": "1", "name": "Tamarind Ave house", "kind": &"location", "id": &"house", "instance": &"house_tamarind_1", "px": Vector2(440, 803)},
	{"roster": "1", "name": "Tamarind Ave house", "kind": &"location", "id": &"house", "instance": &"house_tamarind_2", "px": Vector2(488, 803)},
	{"roster": "1", "name": "Tamarind Ave house", "kind": &"location", "id": &"house", "instance": &"house_tamarind_3", "px": Vector2(440, 863)},
	{"roster": "1", "name": "Tamarind Ave house", "kind": &"location", "id": &"house", "instance": &"house_tamarind_4", "px": Vector2(488, 863)},
	{"roster": "1", "name": "Tamarind Ave house", "kind": &"location", "id": &"house", "instance": &"house_tamarind_5", "px": Vector2(440, 923)},
	{"roster": "1", "name": "Tamarind Ave house", "kind": &"location", "id": &"house", "instance": &"house_tamarind_6", "px": Vector2(488, 975)},
	{"roster": "2", "name": "Track-side duplex", "kind": &"location", "id": &"house", "instance": &"house_trackside_1", "px": Vector2(540, 863)},
	{"roster": "2", "name": "Track-side duplex", "kind": &"location", "id": &"house", "instance": &"house_trackside_2", "px": Vector2(540, 923)},
	{"roster": "3", "name": "Tamarack Bodega", "kind": &"site", "id": &"tamarack_corner_store", "px": Vector2(488, 1045)},
	{"roster": "4", "name": "Row Liquors", "kind": &"site", "id": &"tamarack_liquor_store", "px": Vector2(440, 1085)},
	{"roster": "5", "name": "Fresh Cutz Barbershop", "kind": &"site", "id": &"tamarack_barbershop", "px": Vector2(470, 955)},
	{"roster": "6", "name": "Gas-N-Go", "kind": &"location", "id": &"corner_store", "instance": &"corner_store_gas_n_go", "px": Vector2(343, 1086)},
	{"roster": "7", "name": "Viper corner deal (Tamarind & 15th)", "kind": &"marker", "style": &"event", "px": Vector2(505, 943)},
	{"roster": "8", "name": "The Spot (Viper trap)", "kind": &"location", "id": &"bottoms_trap_house", "instance": &"bottoms_trap_house", "px": Vector2(541, 1027)},
	{"roster": "C1", "name": "Dealer corner", "kind": &"marker", "style": &"corner", "px": Vector2(505, 912)},
	{"roster": "C2", "name": "Dealer corner", "kind": &"marker", "style": &"corner", "px": Vector2(462, 812)},
	{"roster": "C3", "name": "Dealer corner", "kind": &"marker", "style": &"corner", "px": Vector2(360, 1110)},
	{"roster": "24", "name": "Hot car", "kind": &"marker", "style": &"event", "px": Vector2(300, 1034)},
	# --- Northgrove ---------------------------------------------------------------------------
	{"roster": "9", "name": "Bungalow row", "kind": &"location", "id": &"house", "instance": &"house_bungalow_1", "px": Vector2(768, 625)},
	{"roster": "9", "name": "Bungalow row", "kind": &"location", "id": &"house", "instance": &"house_bungalow_2", "px": Vector2(822, 625)},
	{"roster": "9", "name": "Bungalow row", "kind": &"location", "id": &"house", "instance": &"house_bungalow_3", "px": Vector2(876, 625)},
	{"roster": "9", "name": "Bungalow row", "kind": &"location", "id": &"house", "instance": &"house_bungalow_4", "px": Vector2(768, 685)},
	{"roster": "9", "name": "Bungalow row", "kind": &"location", "id": &"house", "instance": &"house_bungalow_5", "px": Vector2(876, 685)},
	{"roster": "10", "name": "Grove Apartments (4 units)", "kind": &"marker", "style": &"home", "px": Vector2(875, 425)},
	{"roster": "11", "name": "Northgrove Pawn", "kind": &"site", "id": &"northgrove_pawn_shop", "px": Vector2(768, 508)},
	{"roster": "12", "name": "Grove Pharmacy", "kind": &"site", "id": &"northgrove_pharmacy", "px": Vector2(640, 548)},
	{"roster": "13", "name": "Ink Lab Tattoo", "kind": &"site", "id": &"northgrove_tattoo_parlor", "px": Vector2(822, 548)},
	{"roster": "14", "name": "Wired Electronics", "kind": &"location", "id": &"corner_store", "instance": &"corner_store_wired", "px": Vector2(878, 505)},
	{"roster": "15", "name": "Northgrove Savings (teller hold-up)", "kind": &"marker", "style": &"bank", "px": Vector2(689, 482)},
	{"roster": "16", "name": "Viper Stash House", "kind": &"location", "id": &"rival_front", "instance": &"rival_front_stash_house", "px": Vector2(590, 478)},
	{"roster": "T2", "name": "Grove Stash House", "kind": &"location", "id": &"riverside_lab", "instance": &"riverside_lab", "px": Vector2(590, 505)},
	{"roster": "", "name": "The Gallery (bar)", "kind": &"location", "id": &"bar", "instance": &"bar_grove_rd", "px": Vector2(700, 548)},
	{"roster": "", "name": "Informant's Flat", "kind": &"location", "id": &"informant_flat", "instance": &"informant_flat", "px": Vector2(822, 685)},
	{"roster": "P2", "name": "Pills plug (hospital orderly)", "kind": &"marker", "style": &"plug", "px": Vector2(652, 429)},
	{"roster": "C4", "name": "Dealer corner", "kind": &"marker", "style": &"corner", "px": Vector2(795, 450)},
	{"roster": "C5", "name": "Dealer corner", "kind": &"marker", "style": &"corner", "px": Vector2(850, 590)},
	{"roster": "C6", "name": "Dealer corner", "kind": &"marker", "style": &"corner", "px": Vector2(740, 650)},
	{"roster": "24", "name": "Hot car", "kind": &"marker", "style": &"event", "px": Vector2(900, 460)},
	# --- Mangona ------------------------------------------------------------------------------
	{"roster": "17", "name": "Lakeside trailer", "kind": &"location", "id": &"house", "instance": &"house_trailer_1", "px": Vector2(311, 677)},
	{"roster": "17", "name": "Lakeside trailer", "kind": &"location", "id": &"house", "instance": &"house_trailer_2", "px": Vector2(345, 677)},
	{"roster": "17", "name": "Lakeside trailer", "kind": &"location", "id": &"house", "instance": &"house_trailer_3", "px": Vector2(379, 677)},
	{"roster": "17", "name": "Lakeside trailer", "kind": &"location", "id": &"house", "instance": &"house_trailer_4", "px": Vector2(413, 677)},
	{"roster": "18", "name": "Mangona Guns & Ammo", "kind": &"site", "id": &"mangona_gun_store", "px": Vector2(380, 248)},
	{"roster": "19", "name": "Mangona Hardware", "kind": &"site", "id": &"mangona_hardware_store", "px": Vector2(469.5, 228)},
	{"roster": "20", "name": "Lakeside Chop Shop", "kind": &"site", "id": &"mangona_chop_shop", "px": Vector2(538, 386), "face": Vector2(500, 380)},
	{"roster": "21", "name": "Lake Mangona junkyard", "kind": &"marker", "style": &"home", "px": Vector2(538, 565)},
	{"roster": "22", "name": "Viper Garage", "kind": &"location", "id": &"rival_front", "instance": &"rival_front_viper_garage", "px": Vector2(538, 300)},
	{"roster": "23", "name": "Viper cash van route (I-59)", "kind": &"marker", "style": &"event", "px": Vector2(209, 433)},
	{"roster": "24", "name": "Hot car", "kind": &"marker", "style": &"event", "px": Vector2(262, 380)},
	{"roster": "25", "name": "Plug rip-off (boat ramp)", "kind": &"marker", "style": &"event", "px": Vector2(318, 525)},
	{"roster": "P1", "name": "Smokey's Boat Ramp", "kind": &"location", "id": &"weed_plug_meet", "instance": &"weed_plug_meet", "px": Vector2(306, 488), "free": true, "face": Vector2(290, 488)},
	{"roster": "", "name": "Coke plug meet", "kind": &"location", "id": &"coke_plug_meet", "instance": &"coke_plug_meet", "px": Vector2(533, 688)},
	{"roster": "T3", "name": "Lakeside trailer ($2k, buy later)", "kind": &"marker", "style": &"trap", "px": Vector2(447, 677)},
	{"roster": "C7", "name": "Dealer corner", "kind": &"marker", "style": &"corner", "px": Vector2(262, 670)},
	{"roster": "C8", "name": "Dealer corner", "kind": &"marker", "style": &"corner", "px": Vector2(515, 228)},
]

const MARKER_COLORS := {
	&"home": Color(0.2, 0.45, 0.85), &"shop": Color(0.95, 0.55, 0.1), &"bank": Color(0.95, 0.8, 0.15),
	&"raid": Color(0.85, 0.15, 0.15), &"event": Color(0.55, 0.25, 0.85), &"trap": Color(0.1, 0.1, 0.1),
	&"corner": Color(0.95, 0.85, 0.2), &"plug": Color(0.1, 0.65, 0.65),
}
