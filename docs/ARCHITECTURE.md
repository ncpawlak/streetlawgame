# Architecture

Godot 4.7, GDScript, Forward+ renderer.

## Folder layout

```
project.godot          Engine config (autoloads, layers)
scenes/                .tscn scenes (main, player, ui...)
scripts/
  autoload/            Global singletons (see below)
  framework/           Reusable gameplay frameworks (core, content, interaction, location, dialogue); see below
  combat/              Shared combat logic (Hitscan, Projectile, Explosion, FireZone, WeaponInventory, WeaponSlot, WeaponPickup)
data/<type>/            Content .tres files (weapons, actions, locations, occupants, interiors, dialogues...), one per id
  data/                Resource classes for data-driven content (weapons, businesses, crew)
  npc/                 AI characters (GangMember)
  player/              Player controller
  ui/                  HUD and menus
  vehicles/            Vehicle controller
  world/               Main scene, city generation, territories
assets/                Models, textures, audio (binary files; consider Git LFS once large)
tests/                 Headless smoke tests
docs/                  Design & architecture docs
```

## Autoloads

| Name | Role |
| --- | --- |
| `InputSetup` | Registers input actions in code so bindings are readable and diffable. |
| `EventBus` | Global signals (`cash_changed`, `territory_captured`, `notify`...). Systems talk through it instead of referencing each other. |
| `GameState` | Run state: cash, respect, gangs, territories, businesses, crew, flags, income timer. Future save/load serializes this. |
| `ContentDB` | Content registry: `.tres` defs by (type, id), scanned from `res://data/<type>/` plus override roots (mods). |
| `Locations` | Enterable buildings: placement, lookup/queries, enter/exit, status ticking, serializable state. |
| `Operations` | Runs the operations simulation (`OperationsModel`) on a timer: sites, crew jobs, production, sales, plugs, risk. See [OPERATIONS.md](OPERATIONS.md). |

## Key classes

| Class | Extends | Responsibility |
| --- | --- | --- |
| `Player` | `CharacterBody3D` | On-foot movement, orbit camera, shooting, entering vehicles, health and respawn. |
| `Vehicle` | `VehicleBody3D` | Driving, chase camera, drive-by shooting, running over NPCs, health/crash damage, smoke/fire/explode states. Built in code. |
| `GangMember` | `CharacterBody3D` | Rival NPC: wander, aggro, shoot, die and drop rewards. |
| `Territory` | `Node3D` | District bounds, owner gang, capture logic, map overlay. |
| `CityGenerator` | `Node3D` | Deterministic greybox city: roads, buildings, districts, defenders, parked cars. |
| `Hitscan` | `RefCounted` | Shared instant-hit firing (pellets, damage scale), aiming from the camera, tracers. |
| `Projectile` | `Node3D` | Thrown/launched explosives: ray-stepped flight, bounce/stick/explode on impact, fuses and remote detonation. |
| `Explosion` | `Node3D` | `detonate()`: radius damage with falloff and line of sight, physics impulse, visual, `EventBus.explosion`. |
| `FireZone` | `Area3D` | Burning area left by molotovs; damages bodies inside over time. |
| `WeaponInventory` | `Node` | Carried weapons, selection, fire rate, ammo and reload. Shared by `Player` and `GangMember`. |
| `WeaponSlot` | `RefCounted` | One carried weapon: `WeaponData` + magazine/reserve ammo. |
| `WeaponPickup` | `Area3D` | World pickup that grants a weapon or ammo. |
| `WeaponWheel` | `Control` | Radial selector; pauses the tree while open (`PROCESS_MODE_ALWAYS`). |
| `WeaponData`, `BusinessData`, `CrewMemberData` | `Resource` | Data-driven content definitions. |

## Gameplay frameworks (`scripts/framework/`)

Layered so each one only depends on the ones above it. Other systems (districts #24, production #27)
build on the same pieces.

| Layer | Key classes | Notes |
| --- | --- | --- |
| `content/` | `ContentDB`, `ContentDef`, `VisualSpec` | Every def has `TYPE`, `id` (= file basename), `tags`, `validate()`. `ContentDB.add_content_root(path)` layers an override folder on top of `res://data/`: same id replaces, new ids add. `VisualSpec` points to a scene/mesh, with a greybox fallback built in code. |
| `core/` | `ActionContext`, `Condition`, `Cost`, `Effect` (+ stock subclasses) | Strategy vocabulary shared by every framework. Template methods: subclasses override `_evaluate`/`_reason`, `_can_pay`/`_pay`, `_apply`; the public methods stay on the bases. `MethodCondition`/`MethodEffect` call into code without a new class. |
| `interaction/` | `Interactable`, `InteractionAction`, `Interactor`, `InteractionPrompt`, `InteractionMenu` | Any node gets actions by carrying an `Interactable`. Actions are data (conditions, costs, effects, channel time). The player's `Interactor` focuses the best target and arbitrates E with entering vehicles. |
| `location/` | `LocationDef`, `OccupantDef`, `Location`, `LocationState`, `Locations`, `LocationPlacer`, `InteriorStrategy` | Buildings placed on city lots (per-district caps, `min_count`, `unique`). Interiors are pluggable: `DoorOnlyInterior` puts everything on the door, and `PocketInterior` streams a room far above the city. State is plain data (`to_dict`/`from_dict`). |
| `dialogue/` | `DialogueDef`, `DialogueNode`, `DialogueChoice`, `SkillCheck`, `DialogueRunner`, `DialogueView` | Conversation graphs. Choices reuse conditions, costs and effects. `SkillCheck` strategies (`PersuadeCheck`, `IntimidateCheck`, `FixedCheck`) resolve risky choices. `DialogueRunner` is UI-agnostic. `DialogueView` pauses the game. |

**Swapping things:** to change content, edit or replace its `.tres` file, or add an override root. To
change visuals, set the def's `VisualSpec`. To change behaviour, plug in a different `Condition`,
`Cost`, `Effect`, `InteriorStrategy` or `SkillCheck` resource, or set `Locations.district_resolver`.
No gameplay code hardcodes `res://` content paths. See [CONTENT.md](CONTENT.md).

## Operations framework

`scripts/framework/{items,jobs,sites,economy,risk,conditions,operations}/` holds the reusable operations framework (stash, crew jobs, production, sales, suppliers, risk). It is driven by content in `data/{items,recipes,jobs,sites,plugs,markets,risks,crew}/`. New kinds of work plug in as `JobBehavior` resources. Details, API and extension points: [OPERATIONS.md](OPERATIONS.md).

## Conventions

- **Damage:** anything with `take_damage(amount: float, source: Node)` can be shot.
- **Decoupling:** emit on `EventBus` for cross-system events, and read shared state from `GameState`.
- **Physics layers:** 1 `world`, 2 `player`, 3 `npc`, 4 `vehicle`.
- **Render layers:** layer 2 `map_only` holds overlays and markers that only the minimap camera renders. Gameplay cameras mask it out.
- **Groups:** `player`, `vehicles`, `gang_members`, `projectiles`, `fires`.
- **Content as data:** new guns, buildings, actions, dialogues and so on should be `.tres` resources looked up through `ContentDB`, not new code paths. New behaviour goes in a new `Condition`/`Cost`/`Effect`/strategy subclass.
- Tabs for indentation, static typing everywhere (`:=`, typed params and returns).

## Testing

```sh
godot --headless --path . res://tests/test_runner.tscn
```

Exits non-zero on failure. Add a check to `tests/run_tests.gd` for every new gameplay rule. Framework tests live in `tests/framework_tests.gd`, `location_tests.gd` and `dialogue_tests.gd`; they run in a sandbox far below the city.
