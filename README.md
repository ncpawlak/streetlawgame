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

Gunshots draw blood (`scripts/combat/blood_fx.gd`, hooked into `Hitscan.fire`). Every bullet that hits a character (the player, NPCs or cops, capsules or animated models) sprays blood along the shot. The droplets splat on the ground and on nearby walls, and a red wound mark stays at the impact point, riding the nearest bone so it moves with the body. The dead bleed out into a pool that grows under the body. Props and melee hits don't bleed. Everything is capped and recycled: 16 sprays, 120 splats, 12 pools, 64 wound marks (8 per body).

## Gameplay drivers

Drivers are small sandbox scenes for testing one system on its own, outside the city.

### Blood

```sh
godot --path . res://drivers/blood/blood_driver.tscn
```

A concrete yard with a wall, the player (current controls: LMB hip-fire, RMB aim with zoom, 1-9 or the wheel to switch guns, R to reload) and a lineup of targets: a standing and a walking capsule, a standing civilian model, a standing cop model, a walking civilian model and a passive Viper. Shoot them to check the spurts, ground and wall splats, wound marks and pools. The top-left counters show the BloodFx caps.

| Key | Action |
| --- | --- |
| F5 | Respawn the targets and clear the blood |
| F6 | Clear the blood |
| F7 | Toggle slow motion (0.25x) |
| F8 | Kill every target (pools) |

Add `-- --screenshots=<dir>` to stage the effect, save `blood_*.png` screenshots into `<dir>` and quit.
## Tests

```sh
godot --headless --path . res://tests/test_runner.tscn
```
