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

Standalone test scenes, one per gameplay type. They boot straight into the scenario and aren't part of the city map.

### Stick-up

```sh
godot --path . res://drivers/stick_up/stick_up_driver.tscn
```

A small street with a shop, three neighbouring businesses, bystanders, a getaway car and a stash.

1. Walk into the shop and draw a gun (1-9 or the mouse wheel). Everyone gets wary and the police countdown starts.
2. Aim (hold RMB) at the clerk to hold them up. The clerk empties the register into your bag while you keep them covered. If you lower your aim, the clerk stops, and an armed clerk will go for their gun.
3. You can kill the clerk or anyone else and empty the register yourself (hold E on it). Customers run, and bystanders and the neighbouring shops phone the cops. A finished call brings the police at once.
4. Leave, lose the cops if needed, then hold E at the stash to cash in the bag.

Pick the shop with the debug panel or F1 (corner store) / F2 (liquor store, armed clerk). F3 restarts. Esc frees the mouse for the panel. Shop tuning lives in `drivers/stick_up/shops/*.tres`.

## Tests

```sh
godot --headless --path . res://tests/test_runner.tscn
```
