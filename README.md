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

## Appearance, clothing and disguise

You start in a fixed look (purple hoodie, jeans, sneakers and a short crop) and can only change it at a **clothing store**, a **barber** or a **wardrobe**. Everything lives in `scripts/framework/appearance/`, and the content is data: `data/clothing/`, `data/hair/` and `data/faction_styles/`.

**Looks.** An `Appearance` resource holds eight slots: top, bottom, shoes, hat, accessory, hair, hair colour and facial hair. Each slot stores an item id and a colour variant.
- `AppearanceRig` applies a look to a `CharacterVisual`.
  - Tops, bottoms, shoes and hairstyles swap in that body part from another Quaternius model.
  - Colour variants tint the item's materials.
  - Hats, glasses, chains and facial hair are procedural attachments that follow the head and neck bones.
- `CharacterVisual.apply_appearance(look)` works on any character, so gang uniforms use it too.

**Catalogs.** Each `ClothingItemDef` and `HairItemDef` has an id, name, slot, price, colour variants and colour tags. Tags such as `yellow` or `white` are used for gang colours.

**Player state.** The `PlayerAppearance` autoload holds:
- The current look and the owned clothes (keyed by item and colour).
- Each faction's remembered look.

Saving uses `to_dict` / `from_dict`.

**Changing your look.**
- `buy`, `equip` and `get_haircut` charge through `GameState` cash.
- Prices rise 25% per area tier and are halved at sites you own.
- Hair isn't owned: a new cut costs money, but keeping your current one is free.

**Shops and stations.**
- An `AppearanceStation` opens the `AppearancePanel`. Modes:
  - `clothing`: buy and wear clothes.
  - `barber`: hairstyle, colour and facial hair, with the player in the chair.
  - `wardrobe`: change into clothes you already own, for free.
- The panel has:
  - Slot tabs and an item list with colour swatches.
  - A live preview on the player, with an orbit camera (Q/E).
  - A per-faction readout: "would / won't recognise you".
- `Wardrobe` is a ready-made station for safehouses.
- Business types with `appearance_service = clothing` or `barber` add the store action to their door. Both are set up: `clothing_store` and `barbershop`.

**Disguise and gang colours.**
- Each gang's `FactionStyleDef` lists its colours, its rivals, its attitudes and an optional uniform.
- A faction recognises you when your look matches the one it remembers at 60% or more.
  - The top, hair, hair colour and hat count most.
  - The same item in a different colour only counts partly.
- `reaction_of(faction)` resolves to hostile, suspicious, neutral or friendly, in this order:
  1. If they recognise you, their "recognised" attitude applies.
  2. Wearing their rivals' colours makes them hostile.
  3. Wearing their own colours applies their "own colours" attitude.
  4. Otherwise their default attitude applies.
- `GangMember` reads this every half second:
  - Neutral and friendly members leave you alone unless shot at.
  - Suspicious members walk up and stare, then turn hostile.
  - A gang memorises your look when it fights you.
- **Angeles** (yellow and white) know the starting look, so change your top and hair before walking up to their block. Wearing their colours makes them friendly.
- **Hellraisers** (black and orange, Angeles rivals) are suspicious of strangers.
- The Red Vipers, Kings and Syndicate stay hostile.

**For missions.**
- Conditions: `DisguisedCondition` (`is_disguised_from`), `FactionReactionCondition`, `WearingCondition` (an item or a share of a colour).
- Effects: `RememberLookEffect`, `OpenAppearanceEffect`.
- Signals on `EventBus`: `appearance_changed`, `appearance_purchase`, `faction_attitude_changed`.

**Showcase:** `godot --path . res://scenes/showcase/appearance_showcase.tscn` has a clothing store, barber chair, wardrobe, an Angeles block and a Hellraiser corner, plus a live readout of recognition and reactions. Reference screenshots: `godot --path . res://tools/capture_appearance.tscn -- <output_dir>`.

## Tests

```sh
godot --headless --path . res://tests/test_runner.tscn
```
