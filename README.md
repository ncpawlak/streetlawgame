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

Drivers are standalone scenes that boot straight into one gameplay loop, outside the city map.

### Drive-by

```sh
godot --path . res://drivers/driveby/driveby_driver.tscn
godot --path . res://drivers/driveby/driveby_driver.tscn -- --crew=6 --no-cars --no-gunner --gunner-skill=8
```

You start in a car a few blocks from a Red Vipers corner crew, with an SMG and a crew member riding shotgun who shoots at nearby rivals on his own. Roll up and shoot from the car (LMB). Once the crew gets hit, the survivors pile into their parked cars and chase you, shooting from the windows. If nobody makes it to a car, backup rolls out instead. Stay out of their sight for 5 seconds (break line of sight behind buildings, or get more than 60 m away) to finish. You need at least one kill, and dying fails the run.

| Debug key | Effect |
| --- | --- |
| F1 / F2 | Crew size -/+ (1-8, default 4) |
| F3 | Rivals have cars on/off |
| F4 | Passenger gunner on/off |
| F5 | Restart |
| F6 / F7 | Gunner shooting skill -/+ (1-10, default 5; applies live) |

The gunner is a crew member (`CrewMemberData`) with a `shooting` skill. Higher skill means tighter spread, faster reactions (1.2 s down to 0.15 s before opening fire), shorter, disciplined bursts instead of long sprays, and more range (22 m up to 34 m). Each rival the gunner drops earns them shooting xp, so they level up through the normal crew skill system.

Code lives in `drivers/driveby/` and `scripts/gameplay/driveby/`. Tests are in `tests/driveby_tests.gd`.

## Tests

```sh
godot --headless --path . res://tests/test_runner.tscn
```
