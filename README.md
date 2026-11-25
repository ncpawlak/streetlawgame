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

## Cutscenes, dialogue & phone

Reusable narrative systems (no mission content) live in `scripts/framework/narrative/`, and the `Narrative` autoload is the hub for them.

- **Cutscenes** (`CutsceneDef` resources in `data/cutscenes/`) are run by `Narrative.play_cutscene(def_or_id, stage, bindings)`. A cutscene is a list of steps. Each step can block, or set `wait = false` to overlap the next one. `ParallelStep` groups steps. Step types:
  - **Camera:** cut, blend, dolly or orbit between `Marker3D`s, and look-at.
  - **Letterbox** and **Fade**.
  - **Actor:** place, move-to, face and play-animation on a `CharacterVisual`.
  - **Line:** a subtitle with a speaker and duration.
  - **Dialogue:** a timed `DialogueDef`, with choices.
  - **Event:** emits an EventBus/story event.
  - **Wait** and **Parallel**.

  While a cutscene plays, player input is locked and the HUD is hidden. Hold Space or Enter to skip. Skipping fast-forwards every remaining step's end state and runs `on_skip` effects, so the world always ends in the authored state. The director emits `started`, `skipped` and `finished(id, skipped)`.
- **Dialogue** (`scripts/framework/dialogue/`) adds the following to nodes:
  - `speaker_name`; `player` lines show as "You".
  - Linear `next`.
  - `conditions` with an `else_next` redirect, and `on_enter` effects.
  - New effects: `StoryEventEffect`, `AddFlagEffect`, `PlayCutsceneEffect`, `PhoneCallEffect` and `BarkEffect`.
  - A new condition, `FlagAtLeastCondition`.
- **Talking to NPCs:** add a `TalkTarget` to an NPC (interact prompt, camera framing on the speaker, then the runner). Code can also call `Narrative.talk(npc, def)`. It works in and out of cutscenes.
- **Barks:** use a `Barker` node (proximity, with a cooldown) or `Narrative.bark(node, text)` for floating one-liners.
- **Phone:** `ContactDef` resources live in `data/contacts/` and `PhoneCallDef` resources in `data/phone_calls/`.
  - `Narrative.phone.schedule_call(id, delay)` rings the phone with the caller name and a phone-in-hand pose.
  - Y answers and N declines.
  - An answered call plays its dialogue as subtitles while you keep control.
  - Declined or unanswered calls become missed calls.
  - P opens the contacts list, where you can call people back.
  - Calls wait while a cutscene or talk is playing.
- **Showcase:** `scenes/showcase/narrative_showcase.tscn` plays a hospital wake-up cutscene and has a talkable witness, a barking thug, and a call that rings 6 s later. C replays the cutscene and K rings the phone now. Add `-- --capture <dir>` to save a screenshot tour.
- **Sample data:** regenerate the sample `.tres` files with `godot --headless --path . res://tools/build_narrative_samples.tscn`.
## Tests

```sh
godot --headless --path . res://tests/test_runner.tscn
```
