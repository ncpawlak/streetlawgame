# Street Law

A 3rd-person open-world gang warfare game in the spirit of *Saints Row 1 & 2* and classic 3D *GTA*. Take your crew from the gutter to running the city: take over territories, rob houses, businesses and banks, do drive-bys, run trap houses and drug operations, buy businesses, and stock up on guns and explosives.

- 📜 [Game design document](docs/GDD.md)
- 🏗️ [Architecture](docs/ARCHITECTURE.md)

## Requirements

- [Godot 4.7](https://godotengine.org/download) (standard build; GDScript only). On Windows: `winget install GodotEngine.GodotEngine`

## Running

Open `project.godot` in Godot and press **F5**, or from a terminal:

```sh
godot --path .
```

## Controls

| Action | Key |
| --- | --- |
| Move / sprint / jump | WASD / Shift / Space |
| Look | Mouse |
| Shoot / aim | LMB / RMB |
| Weapon wheel (pauses the game) | Hold Q, move the mouse, release |
| Switch weapon | Mouse wheel / 1-9 |
| Throw grenade / molotov / C4, fire RPG | LMB with it equipped |
| Detonate placed C4 | G |
| Reload | R |
| Enter, steal or exit a vehicle | E |
| Handbrake | Space (in vehicle) |
| Drive-by (uses your equipped gun) | LMB (in vehicle) |
| Pause map | M (M / Esc closes) |
| Release / capture mouse | Esc / click |

**Pause map (M):** the game pauses while it's open. Pan with a mouse drag or WASD/arrows, and zoom with the wheel or Q/E, from the whole North End down to a few blocks. Click a marker for its info card. Right-click sets a waypoint, or right-click the pin to clear it. A GPS line to the waypoint follows the streets on the minimap. Space recentres on you and Backspace clears the waypoint. The legend toggles each category: objectives and the current mission, hit spots, your businesses and trap houses, businesses for sale, rival fronts, plugs and corners, safehouses, gun and explosive shops, world events (hot cars) and turf colours. Roster spots without a system yet show as *coming soon*.

## Prototype gameplay

The world is a greybox of the **North End** (Zone 1, see `docs/map/north_end_wireframe.svg`): Tamarack Row, Northgrove and Mangona, all run by the Red Vipers. You start outside the boarded duplex in Tamarack Row. To take a district, kill its safehouse guards and patrols, then hold [E] Take over at the safehouse door. Owned turf pays income every 30 seconds. Roster spots from `docs/design/NORTH_END_HITS.md` that have no system yet show as labelled "coming soon" posts.

There are 9 buyable businesses, three per North End district, all in Viper turf at start, so take a district before buying there. Walk to a business door and press E to buy it, or to shop there. Owned businesses pay income, add clout to their district and sell to you at half price.

You start with fists and a pistol. There's a stash of guns (SMG, shotgun, rifle) next to your car, with a row of explosives (grenades, molotovs, C4, RPG) beside it, and rivals drop their weapons when they die. Weapons use magazines and reserve ammo.

Vehicles take damage from bullets, explosions and crashes: they smoke, then catch fire, then explode. Rivals will shoot at your car while you're driving.

## House exteriors & stand-in businesses

The kit replaces the North End's placeholder buildings. Every building is one plain CSG `.tscn` that includes its own lot: yard, driveway or parking, fences and trees. Buildings are sized to `docs/design/SCALE.md` (doors are at least 1.2 × 2.4 m, storeys 3 m, shop ground floors 3.5 m or more), and every shell has static collision.

| What | Where |
| --- | --- |
| 15 one-floor houses, 1 bed/1 bath up to 4 bed/2 bath | `scenes/houses/one_floor/house_1f_01..15.tscn` |
| 10 two-floor houses | `scenes/houses/two_floor/house_2f_01..10.tscn` |
| 5 closed businesses: strip mall, vacant storefront, mixed-use, industrial shed, warehouse | `scenes/businesses/closed/business_b_01..05.tscn` |
| 8 enterable shops: clothing, gun, chop shop, tattoo, barber, liquor, corner store, pawn | `scenes/businesses/shops/shop_s_01..08.tscn` |
| Shared window, door and garage door parts | `scenes/houses/parts/` |
| Materials and textures | `assets/materials/houses/` |
| Showcase street | `scenes/houses/house_showcase.tscn` |

- **Houses can't be entered.** Their doors and windows are shallow recesses in the wall.
- **Closed businesses are also solid.**
- **Shops have a real doorway** into an empty interior. Each shop has:
  - a `shop_type` export that matches `data/business_types/` where one exists
  - an `Entrance` Marker3D just outside the door
  - a `ShopCounter` Interactable inside

  No buy actions are wired up yet.

**Lot convention.** The root's origin is the centre of the front property line, with the street toward +Z and the lot running from z = -depth to z = 0. The root scripts are `HouseExterior` and `BusinessExterior`. They expose:
- `lot_size`
- `lot_type`
- `footprint`
- bed/bath (houses) or `archetype`/`shop_type` (businesses)

**Showcase.** Open and run `scenes/houses/house_showcase.tscn` (F6). Layout:
- One-floor houses, then the closed businesses, on the north side.
- Two-floor houses, then the shops, on the south side.
- Every lot has a label with its ID, its type and its lot type.

Esc releases the mouse and a click recaptures it.

**Editing.** Open any scene in the editor and move or resize the CSG nodes. In the generated scenes:
- Subtraction nodes cut windows and doors out of earlier siblings.
- `Lot` holds the ground and paving.
- `House` or `Building` is the solid shell.

The scenes are generated by `python tools/houses/build_houses.py`. The specs are in `tools/houses/specs_one.py`, `specs_two.py` and `specs_biz.py`. Re-running the generator overwrites the scenes, so once you've hand-edited a scene, regenerate only the other ones with `--only`, e.g. `--only 1F-03 S-02`.

**Screenshots:**

```sh
godot --path . res://tools/capture_houses.tscn -- <out_dir> [ids like 1F_02 B_04 S_03]
```

## Tests

```sh
godot --headless --path . res://tests/test_runner.tscn
```
