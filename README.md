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

### Stick-up

```sh
godot --path . res://drivers/stick_up/stick_up_driver.tscn
```

A small street with a shop, three neighbouring businesses, bystanders, a getaway car and a stash.

1. Walk into the shop and draw a gun (1-9 or the mouse wheel). Everyone gets wary and the police countdown starts.
2. Aim (hold RMB) at the clerk to hold them up. The clerk empties the register into your bag while you keep them covered. If you lower your aim, the clerk stops, and an armed clerk will go for their gun.
3. You can kill the clerk or anyone else and empty the register yourself (hold E on it). Customers run, and bystanders and the neighbouring shops phone the cops. A finished call brings the police at once.
4. Leave, lose the cops if needed, then hold E at the stash to cash in the bag.

Extras:

- **Shelves:** each stand has a stock meter. Hold E on a stand to drain the meter and fill your bag with product, one unit at a time, until the stand is empty or the bag is full (8 slots). Letting go stops it. Product sells at the stash on top of the cash.
- **Bodies:** hold E on any dead NPC to take their cash. This is the default for every NPC (see `scripts/gameplay/hit_common/README.md`).
- **Panic button:** some clerks have a hidden button under the counter (50% at the corner store, 75% at the liquor store). Once held up, if you leave them uncovered for about 2 s they press it. That trips a silent alarm: no warning or sound, and the police arrive about 12 s later, well before the visible countdown runs out. The red bulb behind the counter lights up when it's pressed. Only a lookout tells you about it.
- **Masks and heat:** X toggles the mask. Drawing in the shop unmasked shows the clerk your face, which adds personal heat. Every stick-up adds heat to the strip, and that heat carries over to the next run: a shorter countdown, more cops and lower payouts for goods. Leaving in the white swap car (west, down the road) with the mask off sheds heat fastest. F7 adds area heat; Shift+F7 clears it.
- **Crew:** F4 lookout (across the road; buys countdown time and warns you about the panic button and calls), F5 driver (waits in the getaway car; you lose the cops faster in it), F6 muscle (follows you and keeps the clerk and customers from phoning or pressing the button). Each member takes a 10% cut.

Pick the shop with the debug panel or F1 (corner store) / F2 (liquor store, armed clerk). F3 restarts. Esc frees the mouse for the panel. Shop tuning lives in `drivers/stick_up/shops/*.tres`.

## Tests

```sh
godot --headless --path . res://tests/test_runner.tscn
```
