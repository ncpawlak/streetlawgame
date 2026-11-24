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
data/<type>/            Content .tres files (weapons, actions, locations, occupants, interiors, dialogues, areas, districts, safehouses, capture_rules...), one per id
  data/                Resource classes for data-driven content (weapons, businesses, crew, territory/)
  npc/                 AI characters (GangMember)
  player/              Player controller
  ui/                  HUD and menus
  vehicles/            Vehicle controller
  territory/           District, Safehouse, runtime state, capture rules (rules/)
  world/               Main scene, city generation
assets/                Models, textures, audio (binary files; consider Git LFS once large)
tests/                 Headless smoke tests
docs/                  Design & architecture docs
```

## Autoloads

| Name | Role |
| --- | --- |
| `InputSetup` | Registers input actions in code so bindings are readable and diffable. |
| `EventBus` | Global signals (`cash_changed`, `district_captured`, `notify`...). Systems talk through it instead of referencing each other. |
| `GameState` | Run state: cash, respect, gangs, businesses, crew, flags, income timer. Future save/load serializes this. |
| `ContentDB` | Content registry: `.tres` defs by (type, id), scanned from `res://data/<type>/` plus override roots (mods). |
| `Turf` | Territory authority (areas → districts → safehouses): id-based ownership queries (`owner_of`, `district_at`, `districts_in_area`, `owned_districts`, `area_owner`, `income_for`...), `set_district_owner()` as the only way ownership changes, area bonuses, `to_dict()`/`from_dict()`. Installs itself as `Locations.district_resolver`. |
| `Locations` | Enterable buildings: placement, lookup/queries, enter/exit, status ticking, serializable state. |

## Key classes

| Class | Extends | Responsibility |
| --- | --- | --- |
| `Player` | `CharacterBody3D` | On-foot movement, orbit camera, shooting, entering vehicles, health and respawn. |
| `Vehicle` | `VehicleBody3D` | Driving, chase camera, drive-by shooting, running over NPCs, health/crash damage, smoke/fire/explode states. Built in code. |
| `GangMember` | `CharacterBody3D` | Rival NPC: wander, aggro, shoot, die and drop rewards. |
| `District` | `Node3D` | District bounds, safehouse, guards/patrols, map overlay; ticks its `CaptureRule`. Generated or placed by hand with a `district_id`. |
| `Safehouse` | `Node3D` | A district's safehouse: visual from `SafehouseData` (scene or greybox), door, guard points, `can_claim/claim`, `can_manage/manage`. |
| `CaptureRule` | `Resource` | Pluggable capture mechanic (`SafehouseCaptureRule` default, `ClearAndHoldCaptureRule`). Per-district progress lives in `DistrictState`. |
| `CityGenerator` | `Node3D` | Deterministic greybox city: roads, buildings, districts from content (reserving a safehouse lot each), parked cars. |
| `Hitscan` | `RefCounted` | Shared instant-hit firing (pellets, damage scale), aiming from the camera, tracers. |
| `Projectile` | `Node3D` | Thrown/launched explosives: ray-stepped flight, bounce/stick/explode on impact, fuses and remote detonation. |
| `Explosion` | `Node3D` | `detonate()`: radius damage with falloff and line of sight, physics impulse, visual, `EventBus.explosion`. |
| `FireZone` | `Area3D` | Burning area left by molotovs; damages bodies inside over time. |
| `WeaponInventory` | `Node` | Carried weapons, selection, fire rate, ammo and reload. Shared by `Player` and `GangMember`. |
| `WeaponSlot` | `RefCounted` | One carried weapon: `WeaponData` + magazine/reserve ammo. |
| `WeaponPickup` | `Area3D` | World pickup that grants a weapon or ammo. |
| `WeaponWheel` | `Control` | Radial selector; pauses the tree while open (`PROCESS_MODE_ALWAYS`). |
| `WeaponData`, `BusinessData`, `CrewMemberData` | `Resource` | Data-driven content definitions. |
| `AreaData`, `DistrictData`, `SafehouseData` | `Resource` | Turf content: area bonuses, district owner/income/defenders/layout hints, safehouse visuals and claim settings. |

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

Exits non-zero on failure. Add a check to `tests/run_tests.gd` for every new gameplay rule. Framework tests live in `tests/framework_tests.gd`, `location_tests.gd` and `dialogue_tests.gd`; they run in a sandbox far below the city. Turf checks live in `tests/turf_tests.gd`.
