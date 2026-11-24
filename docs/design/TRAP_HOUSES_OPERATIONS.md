# Trap houses & Operations plan (#14 / #27)
This plan builds on the existing Operations framework (#32 and #34): items, recipes, sites, jobs, plugs, markets and risks. Most of it is **data**; the code changes needed are listed in the engineering section.

## Decisions (user)
- **Drug ladder:** Weed → Pills → Coke → Meth → Heroin. Each drug has its own plug.
- **Trap house upgrades** unlock production rooms. There are no separate lab sites (the legacy `riverside_lab` becomes a trap house with a lab room).
- **Selling works both ways:** you manage it from a menu, and dealers also spawn visibly on their corners when you're nearby, where you can protect them (or lose them).
- **Player role:** you're the manager, plus optional missions (supply runs, deliveries, defense).
- **Pickup collection:** cash piles up in the trap house safe. You or a crew runner must collect it, and the safe can be robbed.

## Drug ladder
| Drug | Plug (where) | Reveal | Buy-in | Room needed | Input → output | Cycle | Street $/unit | Heat | Zone |
|---|---|---|---|---|---|---|---|---|---|
| **Weed** | Lake boat-ramp grower (Mangona) | Start (tutorial) | $500 | Grow room | grow kit → 10 weed | 4 min | $20 | Low | 1 |
| **Pills** | Hospital orderly (Northgrove) | Tip from burgling the pharmacy, or 15 clout in Northgrove | $2k | Pill press | precursor (pharmacy loot or plug) → 8 pills | 5 min | $35 | Low–med | 1 |
| **Coke** | Harbor Syndicate contact (port) | Own 1 Zone 2 district | $10k | Cut & bag room | coca paste → 6 coke | 6 min | $90 | Medium | 2 |
| **Meth** | Glades cook (trailer park) | Reach the Glades, plus a mission | $15k | Meth lab | chem kit → 8 meth | 7 min | $70 | **High** (can explode) | 3 |
| **Heroin** | Airport cargo contact | Late game: high total clout | $40k | Heroin cutting room | raw → 5 heroin | 8 min | $150 | Very high | 4 |

- **Demand varies by district:** weed and pills sell everywhere; coke sells in rich and nightlife areas; meth in rural and industrial areas; heroin in poor urban areas. This goes in a `MarketProfile` per district type.
- **Saturation** already exists. Selling too much in one district lowers the price, which pushes you to spread dealers across your turf.

## Trap houses
### Getting one
- **Take over a rival trap** (raid → take over), or **buy an abandoned spot** in a district you own (cheap, empty, starts at Lv 1).
- **Torching** a rival trap destroys it. You get no site, but the rival loses income and clout.
- **Losing the district** suspends the trap house (that rule already exists). If rivals raid it while you hold the district, you can lose it outright (ties to #8).

### Levels & rooms
Each level adds room slots and capacity. Rooms take slots and are bought separately.

| Level | Cost (tier 1) | Room slots | Worker slots | Stash cap | Safe cap |
|---|---|---|---|---|---|
| 1 Spot | — | 1 | 2 | 50 | $2k |
| 2 House | $3k | 2 | 4 | 150 | $6k |
| 3 Compound | $10k | 3 | 6 | 400 | $20k |

Upgrade costs scale with `AreaData.tier` (×1/2.5/5/15/30, as for businesses).

| Room | Effect | Cost |
|---|---|---|
| Grow room | Weed production | $1k |
| Pill press | Pills production | $3k |
| Cut & bag | Coke production | $8k |
| Meth lab | Meth production; risk of a lab accident | $12k |
| Heroin cutting | Heroin production | $25k |
| **Security** (not a production room) | Reinforced door, cameras and a guard post. Lowers raid chance and success | $2k |
| **Counting room** (not a production room) | Doubles the safe cap and lets a runner collect automatically | $4k |

### Jobs (the existing cook / dealer / guard jobs, plus one new one)
- **Cook:** works one production room. Skill speeds up cycles.
- **Dealer:** assigned to a **corner** in a district you own. Sells from the trap house stash.
- **Guard:** reduces risk (mitigation already exists).
- **Runner (new):** moves cash from the safe to you, and stock between your sites. Takes a 10% cut and can be robbed on the way.

## Selling: corners
- **Each district you own has 2–4 corners** (world spots). A dealer works one corner, and their stock comes from the nearest trap house you own in that zone.
- **Off-screen**, sales are simulated in the menu (the current `SalesBehavior`).
- **On-screen** (when you're nearby), the dealer spawns at the corner with buyers walking up. If rivals or cops show up, you can intervene. If the dealer is robbed or arrested while you're away, the existing risk fires.
- **Busy corners** earn more and draw more heat.

## Cash collection (pickup)
- **Sales cash goes to the trap house safe,** not straight to your wallet. Cash that doesn't fit in the safe is lost (shown as a warning).
- **Collect it** by walking in and using the safe, or have a runner collect it (needs the counting room).
- **A full safe is a target.** Rival raid chance goes up with the cash on hand, so collecting is part of the loop.

## Missions (optional, hands-on)
| Mission | Trigger | Reward |
|---|---|---|
| Supply run | Buy precursor from the plug in bulk; drive it back | 30% cheaper than having it delivered; risk of an intercept |
| Bulk order | A buyer requests N units within a time limit | 1.5× price, plus clout |
| Defend the house | Rival raid incoming (warning ~60 s before) | Keep the house; win clout |
| Get it back | A dealer was robbed | Track the robbers, recover the stock |
| Lab accident | Meth lab explosion | Put out the fire or evacuate before the cops arrive |

## Risks (the existing RiskData, retuned)
| Risk | Scales with | Effect |
|---|---|---|
| Police raid | Site heat | Seize stock, arrest crew, lock the site for a while |
| Rival raid | Cash in the safe, a weak rival nearby | Steal cash and stock; can take the site if undefended |
| Dealer robbed | Corner heat, rival presence | Steal the dealer's stock and cash |
| Runner robbed | Cash being carried | Lose the cash |
| Plug burned | Missed or late orders, plug relationship | Prices go up; the plug cuts you off |
| Lab accident | Meth lab only, cook skill | Fire, heat, lost stock |

**Heat** builds per site and decays over time. Laying low (pausing dealers) cools it faster.

## Ties to other systems
- **Clout:** each trap house you own counts as a territory marker (#37) and gives clout in its district. Income levels also feed influence levels later (future).
- **Hit locations (#15):** raiding a Viper trap leads to takeover. Pharmacy burglary pills and hardware-store lab gear can be put into your stash as inputs.
- **Businesses (#36):** the pharmacy discount lowers the cost of pill precursor, and the hardware store lowers the cost of room upgrades (−20%). Owning the chop shop helps with supply runs (car swaps lower intercept risk).

## North End content (milestone)
| Site | District | How you get it | Starting rooms | Notes |
|---|---|---|---|---|
| **The Spot** | Tamarack Row | Raid the Vipers (story beat) | Grow room | First trap house; tutorial for cook, dealer and collect |
| **Grove stash house** | Northgrove | Raid → take over (roster #16) | Empty, Lv 1 | Natural home for a pill press |
| **Lakeside trailer** | Mangona | Buy (abandoned, $2k) | Empty | Meth-ready location for later |

- **Corners:** Tamarack Row ×3, Northgrove ×3, Mangona ×2.
- **Plugs:** weed at the Mangona boat ramp (existing `weed_plug_meet`, moved there) and pills from the Northgrove hospital orderly. Coke, meth and heroin plugs are outside Zone 1.
- **Target:** with 2 trap houses at Lv 2, weed + pills and 4 dealers should earn about $1.5–2.5k per in-game hour. That's enough that it becomes the main income after the opening.

## Engineering deltas (when built)
- `SiteData.level` with level tables (`room_slots`, `worker_slots`, `stash_capacity`, `safe_capacity`).
- `SiteRoomData`: id, cost, `adds_site_tags`, risk modifiers. Recipes already gate on `site_tags`.
- **Site safe:** `SalesBehavior` pays into the site safe instead of `GameState`, and there's a collect action.
- **`RunnerBehavior`** (new `JobBehavior`).
- **Corner `LocationDef`s** (kind `corner`), plus dealer assignment to a corner, plus a visible dealer spawn when nearby.
- **Missions** triggered by model events, likely with a small mission framework shared with #38.
- **Content:** items `pills`, `pill_precursor`, `meth`, `chem_kit`, `heroin`, `heroin_raw`; recipes, plugs and markets for each.
- **Migrate** `riverside_lab` to a trap house with a cut & bag room.

## Further decisions
1. A **meth lab accident damages** the house (lost stock, heat, repair cost) but never destroys it.
2. **Gang size caps staffing:** the total crew count limits how many sites and corners you can staff. Influence levels will later raise gang size.
3. **The player can personally sell** in a pinch. You work a corner yourself for a lower price and more heat; it's not meant to be the main loop.