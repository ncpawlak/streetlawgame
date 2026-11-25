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
| Move / sprint (uses stamina) / walk | WASD / Shift / Alt |
| Jump, vault, climb a ledge | Space |
| Crouch (toggle) | C / Ctrl |
| Look | Mouse |
| Shoot from the hip / zoom over the shoulder (LMB still fires) | LMB / RMB |
| Swap shoulder | Z / MMB |
| Melee (takedown from behind) | V |
| Weapon wheel (pauses the game) | Hold Q, move the mouse, release |
| Switch weapon | Mouse wheel / 1-9 |
| Throw grenade / molotov / C4, fire RPG | LMB with it equipped |
| Detonate placed C4 | G |
| Reload | R |
| Enter (from any door), steal or exit a vehicle | E |
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

## Gameplay drivers

Drivers are minimal test scenes for working out one gameplay system before it's integrated into the main game. They aren't part of the city, and they aren't meant to be played on their own.

### Movement and animation

```sh
godot --path . res://drivers/movement/movement_driver.tscn
```

A flat test ground for the shared on-foot controller (`scripts/player/player.gd`), `CharacterVisual`, camera, combat feedback and vehicle doors. Everything here is built into the shared scripts, so the main game gets it too. The ground has a 1.0 m vault wall, a step box, 2.0 m and 2.6 m ledges, a crouch-only overhang, three passive dummies, and three cars: upright, on its side and on its roof. F5 resets the ground.

- **On foot:** arm swing at walk, run and sprint. With a gun up (LMB, RMB, or just after a shot) the body keeps facing the crosshair and the legs strafe or backpedal, so you can move one way and shoot another. Jumping tucks the legs and throws the arms out with no stride in the air, then dips on landing. Sprinting drains the stamina bar under health; when it's empty you're winded until it recovers. Health doesn't regenerate. Crouching lowers your capsule and detection range.
- **Camera:** the camera sits close over the shoulder. LMB fires from the hip without zooming (wider spread). RMB zooms in for tighter aim and LMB fires while zoomed. Z or MMB swaps shoulders, and firing kicks and shakes the camera. Sprinting pulls it back and widens the FOV.
- **Weapons:** holstered pistols sit on the hip and long guns are slung across the back. Reloads are animated per weapon type, and sprinting cancels them.
- **Combat:** the reticle shows hit and kill markers, and arcs point towards whoever just shot you. Headshots do extra damage. Characters flinch away from hits and ragdoll when they die. V attacks in melee, and from behind it's a takedown.
- **Vehicles:** E walks you to the nearest of the four doors. You open it, get in, slide across to the driver's seat and shut it. E again gets you out of the driver's door. In a car on its side you climb out of the top door, and in an upside-down car you crawl out of the side.

### Carjack / hot car

```sh
godot --path . res://drivers/carjack/carjack_driver.tscn
```

Jack a car through a minigame, lose its tracker, and deliver it to the chop shop. Press F2 in-game, or pass `-- --minigame=lock_pick|hotwire|struggle|auto`, to switch the minigame. See [drivers/carjack/README.md](drivers/carjack/README.md).

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
- **Dogs (medium / high):** a dog in the yard growls, then barks if it sees you, which starts the neighbours' countdown early. Feed it a treat (hold E) to make it a friend, or shoot it (loud: counts as a gunshot).
- **Safes:** the closet / study safe is locked. Hold E to crack it: press E or Space each time the pin is in the green, several times in a row. A miss, or letting the pin hit the far wall, resets the streak.
- **Disabling cameras:**
  - Cut the power at the breaker box on the side wall. Cameras and lights go dark for 60 s; door alarms stay on battery.
  - Spray-paint a camera's lens (one can per camera, quiet).
  - Shoot a camera (loud).
  - Unplug the CCTV recorder (DVR) inside. Every camera stops recording, footage of your face is wiped (that personal heat comes off), and the area cools a little.
- **Masks and heat:** X toggles the mask. Cameras, witnesses and cops that see you unmasked add personal heat. Each hit adds heat to the street, which carries over: more cops, a shorter countdown, and lower payouts for goods. Heat cools over time, and much faster if you leave in a different car (the blue swap car down the street) with the mask off.
- **Crew:** a lookout stands on the corner (35% longer countdown, and a warning when the police are called or arrive). A driver waits in the getaway car with the engine running (cops lose you faster while you're in it). Muscle follows you and keeps owners on the floor so they can't phone. Each member takes 10% of the payout.

Debug keys:

| Key | Does |
| --- | --- |
| F1 / F2 / F3 | Low / medium / high-income house |
| F4 | Toggle owners home |
| F5 / Shift+F5 | Re-roll loot / refill tools (2 dog treats, 2 spray cans) |
| F6 | Reset (the street's heat carries over) |
| F7 / Shift+F7 | Toggle roof / cut the power |
| F8 / Shift+F8 | Toggle dogs / toggle locked safes |
| F9 / F10 / F11 | Toggle lookout / driver / muscle |
| F12 / Shift+F12 | +25 street heat / clear all heat |
| X | Mask on / off |

`-- --screenshots=<dir>` saves the tier layouts, the stakeout view, the looting HUD, the safe minigame, the security extras (dog, breaker, recorder, crew) and the crew / mask view to `<dir>`, then quits.

The shared pieces of the hit aftermath are in `scripts/gameplay/hit_common/` (see its README): the bag, loot, police countdown, cops, stash, heat map, masks, crew and the timing minigame. The house-specific code is in `scripts/gameplay/house_robbery/`.

## Tests

```sh
godot --headless --path . res://tests/test_runner.tscn
```
