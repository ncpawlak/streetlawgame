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
| Map | Tab / M |
| Release / capture mouse | Esc / click |

## Prototype gameplay

You start in **The Bottoms**. Every other district belongs to a rival gang. To take a district, kill all of its defenders, then stay inside it **on foot** until the capture bar fills. Owned turf pays income every 30 seconds.

There are 9 buyable businesses. Tamarack Row sites are in The Bottoms. Northgrove (Rail Yards) and Mangona (Old Harbor) sites are in rival turf, so take those districts first. Walk to a business door and press E to buy it, or to shop there. Owned businesses pay income, add clout to their district and sell to you at half price.

You start with fists and a pistol. There's a stash of guns (SMG, shotgun, rifle) next to your car, with a row of explosives (grenades, molotovs, C4, RPG) beside it, and rivals drop their weapons when they die. Weapons use magazines and reserve ammo.

Vehicles take damage from bullets, explosions and crashes: they smoke, then catch fire, then explode. Rivals will shoot at your car while you're driving.

## Gameplay drivers

Drivers are standalone test scenes for a single gameplay type. They aren't part of the city.

### House robbery

```sh
godot --path . res://drivers/house_robbery/house_robbery_driver.tscn
```

A street with a house you can burgle, its neighbours, a stakeout bench across the road, a getaway car and a lock-up garage (the stash) at the west end of the street.

- **Tiers:**
  - Low income: no security.
  - Medium income: one camera and an alarm on the front door.
  - High income: 9 cameras, and most doors and windows are alarmed. The master bedroom's side window is the blind spot.
- **Stakeout:** hold E on the bench to see who's home, plus the cameras, alarmed entries and neighbour timer.
- **Getting in:**
  - Doors: pick the lock (quiet) or kick it in (loud).
  - Windows: pry them (quiet) or smash them (loud), then climb through.
- **Calling the police:**
  - Breaking in while nobody's home starts the neighbours' countdown (60 / 45 / 35 s by tier).
  - An alarmed door or window calls the police straight away. So does being seen by a camera after the break-in.
  - Gunshots, including killing the owners, start the countdown.
  - Owners who are home and spot you phone the police. If you point a gun at them, they cower.
- **Looting:** hold E on loose items and cash, and search furniture (drawers, safes and so on). Loot placement is random. The bag holds 8 slots.
- **Escaping:** leave, lose any cops, then hold E at the stash to cash in. The stash won't take the bag while you're wanted.

Debug keys:

| Key | Does |
| --- | --- |
| F1 / F2 / F3 | Low / medium / high-income house |
| F4 | Toggle owners home |
| F5 | Re-roll loot |
| F6 | Reset |
| F7 | Toggle roof |

`-- --screenshots=<dir>` saves the tier layouts, the stakeout view and the looting HUD to `<dir>`, then quits.

The shared pieces of the hit aftermath are in `scripts/gameplay/hit_common/` (see its README): the bag, loot, police countdown, cops and stash. The house-specific code is in `scripts/gameplay/house_robbery/`.

## Tests

```sh
godot --headless --path . res://tests/test_runner.tscn
```
