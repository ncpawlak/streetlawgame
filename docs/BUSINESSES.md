# Businesses (#36)

Businesses are **types** (`data/business_types/`) placed as many **sites** (`data/business_sites/`),
so one type like the gun store can repeat across the map. Each site has its own owner. This first
pass ships the 9 North End types and sites. Clout is a basic per-district score.

## Rules

- **Buying:** a site's door has a **Buy business** action. It needs:
  - your gang to control the site's district (`TurfControlCondition`);
  - any `purchase_conditions` set on the site, such as `CloutCondition`;
  - the site's price (`BusinessPriceCost`).
- **Price and income:** the type's base value (or the site's override) × the area's tier multiplier.
  `AreaData.tier` runs 1–5, giving ×1, ×2.5, ×5, ×15 or ×30. The prototype areas are tier 1.
- **Owned sites:**
  - pay income on every `GameState.pay_income()` cycle (`Businesses.total_income()`);
  - add the type's `clout_value` to their district;
  - get `hangout_crew_count` idle crew out front.

  Hangout crew are in the `hangout_crew` group, not `gang_members`. They're ambient and don't fight.
- **Shops:** retail types list `shop_item_ids` (`data/shop_items/`). The door gets a **Shop** action
  that opens `ShopPanel`.
  - Price = item base × tier, ×0.5 **only at a site you own**. The discount is per site, not
    chain-wide.
  - Items apply `effects`, such as `GiveWeaponEffect` and `HealEffect`.
- **Losing sites:** `Businesses.lose_site(id, reason)` removes the site's clout and crew. Nothing
  calls it yet; rival raids are #8.
- **Clout:** the `Clout` autoload keeps a per-district score from 0 to 100 (`clout_of`, `add`,
  `set_clout`) and emits `EventBus.clout_changed`. For now it gates purchases only.

## Prototype placement

`Businesses.place_sites()` runs after `LocationPlacer`. It puts each site on a free building lot in
its district. The prototype map has no North End yet, so its neighbourhoods map onto Southside:

| Neighbourhood | Prototype district | Sites |
| --- | --- | --- |
| Tamarack Row | `the_bottoms` (yours at start) | corner store, barbershop, liquor store |
| Northgrove | `rail_yards` (Vipers) | pawn shop, pharmacy, tattoo parlor |
| Mangona | `old_harbor` (Syndicate) | chop shop, gun store (needs 10 clout), hardware store |

## Adding content (no code)

- **New site of an existing type:** add `data/business_sites/<id>.tres` with `type_id`,
  `district_id` and `display_name`. You can also set `price_override`, `income_override` and
  `purchase_conditions`.
- **New type:** add `data/business_types/<id>.tres` with `category`, `base_price`, `base_income`,
  `clout_value`, `hangout_crew_count`, `shop_item_ids` and `color`.
- **New shop item:** add `data/shop_items/<id>.tres` with `base_price` and `effects`.

## Public API

| `Businesses` | |
| --- | --- |
| `site(id)`, `type_of(id)`, `all_sites()`, `sites_in(district)` | Lookups |
| `is_owned(id)`, `owned_sites()` | Ownership |
| `price_of(id)`, `income_of(id)`, `total_income()`, `tier_of(id)` | Pricing |
| `purchase_block_reason(id)`, `purchase(id)`, `acquire(id, reason)`, `lose_site(id, reason)` | Buying and losing |
| `shop_items(id)`, `shop_price(id, item)`, `buy_item(id, item, actor)`, `open_shop(id, actor)` | Shops |
| `crew_at(id)` | Hangout crew |
| `to_dict()`, `from_dict()`, `clear()` | Save state (`Clout` saves separately) |

EventBus signals: `business_acquired(site_id, reason)`, `business_lost(site_id, reason)`,
`shop_purchase(site_id, item_id, price)`, `clout_changed(district_id, clout, previous)`.

## Follow-ups

- Per-area gang influence levels (Lv 1–5) from clout.
- Clout multipliers on income and drug prices, and clout as raid defense.
- Rival raids on sites (#8).
- The rest of the type and site catalogue across the real map.
- The neutral, cash-only Hangar.

## Tests

`tests/business_tests.gd` covers content, placement, turf and clout gating, cash, the per-site
discount, income, clout grant and loss, hangout crew, tier pricing, shops and save/load.
