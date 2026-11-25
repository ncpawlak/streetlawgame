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

## Vehicle showcase

```sh
godot --path . res://scenes/vehicles/vehicle_showcase.tscn
```

A lot with 34 vehicles across 12 classes, all fictional. Each vehicle sits on a labelled pad whose kiosk shows its name, class, top speed, handling, seats, mass and spawn zones. Walk up and press E to enter a vehicle. Drive it with WASD and use Space for the handbrake. There's a test loop with a ramp around the lot. F5 respawns every vehicle with fresh paint, and Esc releases the mouse.

| Class | Vehicles |
|---|---|
| Beater & Compact | Rustbucket, Pipsqueak, Hopper |
| Sedan | Meridian, Regent, Tradewind |
| Lowrider & Donk | Boulevard, Swamp King, Bubble |
| Muscle | Thunderhorse, Vandal, Marauder |
| Sports & Exotic | Kestrel GT, Vortex, Cabana |
| SUV & Pickup | Everglade, Palmetto, Workhorse, Mudcat |
| Van | Tradesman, Strongbox (armoured cash van) |
| Police | Palm County Cruiser, Interceptor, Bulwark SWAT |
| Emergency | Medic Unit, Engine 9 |
| Service & Commercial | Sunshine Cab, Metro Transit, Haulmaster, Hook & Haul, Compactor |
| Motorcycle & Scooter | Razorback, Zippy |
| Boat | Gladesrunner (airboat on a trailer, display only) |

- **Generated scenes.** The scenes in `scenes/vehicles/<class>/`, the showcase scene and the registry are built from `tools/vehicles/specs.py`. To regenerate them, run `python tools/vehicles/build_vehicles.py`, then rerun `godot --headless --path . --import`. Don't hand-edit the generated files.
- **Registry.** `data/vehicles/vehicles.json` holds an entry per vehicle with:
  - mass, top speed, acceleration, handling and health
  - seats and class
  - spawn zones and income tier
  - whether the vehicle is stealable (Strongbox and Bulwark aren't)
  - a `ride` block for the driver: pose (`seat`, `straddle` or `none`), entry (`door`, `bus` or `straddle`), door side, hip position, lean, grip and foot spread
- **Getting in and out.** Pressing E starts an animated boarding using the animated character model (`CharacterVisual` plus `CharacterPoseModifier` IK):
  - Cars: the player walks to the `DoorStand` marker (going round the nose or tail if needed), reaches for the handle, swings `Doors/Driver` open, sits down and shuts the door.
  - Buses: the player boards through the front door via `Ride/Step`.
  - Bikes and scooters: the player straddles the seat.
  - While driving, the hips sit on `Seats/Driver`, the feet on `Ride/Pedals` and the hands on `Ride/Steer` (the wheel or the bars). The held gun is holstered until you aim for a drive-by.
  - Pressing E again reverses the sequence. `Vehicle.exit()` still bails out instantly.
- **Livery and glass.** Stripes and other painted-on livery are clipped at the glass. The generator raises an error if any decal overlaps a window, and a test checks every scene.
- **Bullet holes.** Hitscan hits on a vehicle call `Vehicle.on_bullet_hit`, which adds `BulletHoles` (`scripts/vehicles/bullet_holes.gd`) decals: dark holes in the bodywork and crack stars on the glass. Each vehicle keeps a capped number of marks, and they move with the body.
- **`VehicleCatalog`** (`scripts/vehicles/vehicle_catalog.gd`) reads the registry for traffic, carjacking and population. It provides `entries()`, `find(id)`, `query(class, zone, tier, stealable_only)`, `paint_colors(id, seed)` and `instantiate(id, seed)`. Exports must include `*.json` in the export filter, because the registry is read with `FileAccess`.
- **Paint.** The `paint_seed` value gives each vehicle a repeatable paint and trim colour.
- **`vehicle.gd`.** The controller drives both these authored scenes and the code-built city cars, which work as before.
  - The authored scenes set a speed cap, steering that tightens at speed, and an upright assist to stop arcade rollovers.
  - The motorcycles run on hidden training wheels for now, with no lean controller yet.
- **Screenshots.** To capture them, run `godot --path . --resolution 1600x900 res://tools/capture_vehicles.tscn -- <out_dir> [ids]`. Add `--boarding` to capture enter, seated, exit and bullet-hole shots instead.

## Tests

```sh
godot --headless --path . res://tests/test_runner.tscn
```
