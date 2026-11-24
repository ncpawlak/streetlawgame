# Authoring & modding content

Gameplay content is `.tres` resources under `res://data/<type>/`, loaded by the `ContentDB` autoload.
Code looks content up by `(type, id)` and never hardcodes `res://` paths, so you can swap any of it
without touching scripts.

## Rules

- **One def per file.** The file basename **is** the id: `data/locations/corner_store.tres` must
  have `id = &"corner_store"`. `ContentDB.validate()` (run by the tests) enforces this and each def's
  own `validate()` (missing links, empty slots, bad ids).
- **Folder = type.** Each def class declares `const TYPE`. The folder name must match it.

| Folder | Class | What it is |
| --- | --- | --- |
| `weapons/` | `WeaponData` | Guns, melee, explosives. |
| `actions/` | `InteractionAction` | Things the player can do (rob, recruit, talk...): conditions, costs, effects, channel time. |
| `locations/` | `LocationDef` | Building kinds: placement rules, interior, door actions, occupants, register cash, clear rewards. |
| `occupants/` | `OccupantDef` | People inside buildings: friendly (actions, dialogue, nerve/greed) or hostile (gang, weapon, count). |
| `interiors/` | `InteriorStrategy` subclasses | How a building is entered (`DoorOnlyInterior`, `PocketInterior`). |
| `dialogues/` | `DialogueDef` | Conversation graphs. |
| `business_types/` | `BusinessTypeDef` | Business kinds: base price/income, clout, hangout crew, shop stock. |
| `business_sites/` | `BusinessSiteDef` | One buyable business: type, district, name, overrides, purchase conditions. |
| `shop_items/` | `ShopItemDef` | Things a business shop sells: base price and effects. |

Other systems add their own folders (districts, items, production...) the same way. See
[BUSINESSES.md](BUSINESSES.md) for businesses.

## Lookup

```gdscript
var store := ContentDB.get_def(LocationDef.TYPE, &"corner_store") as LocationDef  # errors if missing
var maybe := ContentDB.find_def(&"actions", &"talk")                               # null if missing
for def in ContentDB.with_tag(&"locations", &"business"): ...
```

`ContentDB.all(type)` is sorted by id, so code that iterates it is deterministic.

## Swapping content and mods

```gdscript
ContentDB.add_content_root("user://mods/my_mod")  # contains locations/, actions/, ...
```

Defs in an added root **replace** same-id defs and **add** new ids. Remove the root and call
`ContentDB.reload()` to go back to the built-in content. `ContentDB.register(type, resource)` adds a
def from code (tests, procedural content).

## Swapping visuals

Defs with a `VisualSpec` (`exterior`, `visual`) point at a `scene_path` or `mesh_path`. When neither is
set or loads, a greybox `greybox_shape`/`greybox_size`/`greybox_color` is built in code. Drop in a
real model by setting `scene_path`; nothing else changes.

## Swapping behaviour

Behaviour is assembled from small strategy resources, edited in the inspector:

- **Condition:** gates an action or choice. Examples: `CashCondition`, `RespectCondition`,
  `FlagCondition`, `WeaponDrawnCondition`, `CooldownCondition`, `LocationStatusCondition`,
  `LocationOwnerCondition`, `LocationFlagCondition`, `All`/`AnyCondition`. Every condition has
  `invert`, `failure_text` and `hide_when_unmet`.
- **Cost:** paid up front, all or nothing. Examples: `CashCost`, `RespectCost`.
- **Effect:** what happens. Examples: `CashEffect`, `RespectEffect`, `NotifyEffect`, `SetFlagEffect`,
  `RobLocationEffect`, `TakeOutEffect`, `IntelEffect`, `RecruitEffect`, `HeatEffect`,
  `DispositionEffect`, `StartDialogueEffect`, `SetLocationFlagEffect`.
- **InteriorStrategy:** how entering works.
- **SkillCheck:** odds for risky dialogue choices: `PersuadeCheck`, `IntimidateCheck`, `FixedCheck`.
  Tune them with `bonus`, `min_chance`, `max_chance` and their weights.

There are two ways to add new behaviour:

- Subclass the base and override only its template hooks: `_evaluate`/`_reason`, `_can_pay`/`_pay`/`_describe`,
  `_apply`, or `_chance`.
- For one-offs, use `MethodCondition`/`MethodEffect` with `on` (which context node to call), `method` and `args`.

Text fields support `{vars}`: `{cash}`, `{respect}`, `{target}`, `{location}` and `{occupant}`, plus
anything an effect puts in `ctx.vars` (e.g. `{cash_gained}`).

## Recipes

**A new robbable shop:** add `data/locations/pawn_shop.tres`:

- `kind = &"business"`, `cash_capacity`, `cash_regen_per_minute`, `max_per_district`
- `interior` = `small_room`
- `occupant_ids = [&"clerk"]`
- `door_action_ids = [&"enter_building"]`

The placer puts it on city lots automatically. Set `auto_place = false` if another system places it.

**A new buyable business:** add a `data/business_sites/<id>.tres` with a `type_id` and `district_id`.
`Businesses` places it on a free lot in that district, using the shared `data/locations/business.tres`
door. See [BUSINESSES.md](BUSINESSES.md).

**A new conversation:**

1. Add `data/dialogues/fence.tres`. Its nodes have `id`, `text` and `choices`. Each choice has:
   - `conditions`, `costs` and an optional `check`
   - `effects` and `next`
   - `fail_effects` and `fail_next`
2. Set `dialogue_id = &"fence"` on an occupant. It now gets a **Talk** action automatically (shared
   `data/actions/talk.tres`).

A node with no choices ends the conversation. A node's `outcome` is reported on
`EventBus.dialogue_ended`.

**A once-per-building reward:** gate the choice or action with a `LocationFlagCondition`
(`invert = true`). Then add a `SetLocationFlagEffect` with the same flag to its effects.
