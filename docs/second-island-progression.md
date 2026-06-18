# Second Island Progression

> **Current power-ladder note:** This document predates the newer chosen power spine:
> `Ring 0 Robot + Wood Burner -> Ring 1 Coastal Windmill -> Ring 2 Coal Generator -> Ring 3 Oil -> Late Nuclear`.
> It still describes the older ring-1 iron+coal colony. Treat the coal-specific parts below as
> the ring-2 fuel-power plan unless/until the second-island arc is rewritten around coastal
> wind and non-coal frontier resources.

Design notes for the player's **second** island in Resource Isles — the first stop off the
starter rock (ring 1, rowboat range). This is direction, not implementation. Where island 1
teaches *"you are the economy,"* island 2 teaches **automation, power pressure, and the first
trade route** — the systems island 1 deliberately withheld.

See also: [Island Generation, Biomes, and Resources](island-generation.md) for the profile /
seeding / resource-class architecture this island is the first concrete instance of,
[First Island Progression](first-island-progression.md) for what island 1 teaches and why
automation is dead weight there, [Island Unlocks](island-unlocks.md) for the rings / boat tiers /
trade-route bootstrap, [Intro Story](intro-story.md) for the iron-reframe story beat, and
[Progression, Build Restrictions, and Power](progression-and-power.md) for the power pool.

## The Core Idea: an iron + coal mining colony

Island 2 is the first **frontier biome** — a ring-1 island whose resource set is **iron + coal**
(see the per-ring pools in [Island Generation](island-generation.md)). It is the richer frontier
the story promised (iron is "ship-grade"; see [Intro Story](intro-story.md), the motivation
handoff), but it cannot feed itself: it has **no wood and no stone of its own** (the construction
commodities live at ring 0), so it depends on the home island for the materials to build with.

This is deliberate. It turns the **first trade route from an abstract logistics toy into a
diegetic necessity.** [Island Unlocks](island-unlocks.md) already wrote the rule for exactly this
case:

> The danger case: you arrive on an island with no wood, so you cannot build anything... **the
> dock comes first and enables a trade route, so scarcity is a logistics problem to solve, not a
> wall.**

So island 2 is an Anno-style **specialist colony**: the frontier mines metal, the home island
ships the construction commodities, and the route carries goods both ways.

> **Note on terrain.** Island 2 *looks* rocky (its `primary_terrain` is stone), but terrain is
> visual identity, **not** a placement gate — see [Island Generation](island-generation.md). You
> can place any building on its land. The trade-route necessity comes from the **absence of wood
> and stone resources**, not from a terrain rule. (This supersedes an earlier "all-stone terrain
> blocks grass buildings" framing.)

## Why island 2 (and not island 1) is the automation tutorial

[First Island Progression](first-island-progression.md) is explicit: passive production, the
power budget, adjacency quality, and crowding are **economically dead on the fixed-demand starter
island** and only earn their place once demand is ongoing and the single robot is spread thin.
That moment is island 2:

- **Demand is ongoing**, not a one-off lump sum — you are building a standing iron economy and a
  trade route home, not just enough to leave.
- **The robot is spread thin** — it cannot hand-mine iron, tend the smelter, *and* manage the
  supply line at once, so passive mines/generators finally beat hand-gathering.
- **Power finally bites** — the iron chain draws real power, and (see below) the only local fuel
  is coal, forcing a genuine generation decision.

So the Logger's Camp / Quarry / "the burner frees the robot" beats that were optional time-savers
on island 1 become the actual game here.

## The new production chain: iron + coal -> smelting

```text
Iron deposit ──► Iron Mine ──► iron ore ─┐
                                          ├─► Smelter ──► iron ingot ──► sailboat / ship repair
Coal seam ────► Coal Mine ──► coal ───────┤
                                          └─► Coal Generator ──► island power pool
```

Coal pulls **double duty** — smelter reductant *and* the island's power source. That is what makes
the treeless island cohere: the wood Burner Generator has no fuel here, so coal becomes the only
way to run anything unattended.

### New enum entries (`game_types.gd`)

| Enum | Add |
| --- | --- |
| `ResourceNodeType` | `IRON_ORE`, `COAL` (map deposits, like `TREE` / `STONE`) |
| `ResourceType` | `IRON_ORE`, `COAL`, `IRON_INGOT` (carried stock) |
| `BuildingType` | `IRON_MINE`, `COAL_MINE`, `SMELTER`, `COAL_GENERATOR` |
| `Stat` | `IRON_ORE_GATHERED`, `COAL_GATHERED`, `IRON_INGOTS_GATHERED`, `IRON_MINES_BUILT`, `SMELTERS_BUILT` |
| `QuestId` | `STRIKE_IRON`, `THE_SUPPLY_LINE`, `LIGHT_THE_FORGE`, `SET_SAIL_AGAIN` |

### New buildings (mirror the existing definitions)

Placeable on any land tile (terrain does not gate — see [Island Generation](island-generation.md));
the extractors still require adjacency to their resource node.

| Building | Category | Needs adjacent | Produces | Consumes | Power | Modeled on |
| --- | --- | --- | --- | --- | --- | --- |
| **Iron Mine** | RESOURCES | iron-ore node (+1 ea, −1 per mine) | iron ore | — | draws | Quarry |
| **Coal Mine** | RESOURCES | coal node (+1 ea, −1 per mine) | coal | — | draws | Quarry |
| **Smelter** | PROCESSING | — (pulls from stock) | iron ingot | iron ore + coal | draws | Sawmill |
| **Coal Generator** | POWER | — | — | coal (fuel) | generates > Burner | Burner Generator |

The one genuinely new mechanic is the **Smelter's two-input recipe** (iron ore *and* coal). The
current Sawmill models only a single `input_resource_type` / `input_amount`. Two clean options:

1. **Reuse the existing `fuel_*` fields** for the second consumable (ore via `input_*`, coal via
   `fuel_*`). Minimal model change — but `fuel_*` is currently wired to power generation, so this
   needs verifying against `building_manager` / `power_manager` before relying on it.
2. **Extend `BuildingDefinition`** to a small list of inputs. Cleaner long-term, slightly more work.

Decide at implementation time; option 1 first if it works without rewiring fuel.

## The Cascade (consequences of "no wood, no stone")

These fall straight out of the resource set and are load-bearing — easy to miss, expensive to
discover late.

1. **No local construction commodities → the supply line is mandatory.** Island 2 has neither
   wood nor stone resources, so *every* building's materials must be imported from ring 0 via a
   trade route. This is the necessity, and it comes from resource absence — not from any terrain
   placement rule (you can build anywhere; see [Island Generation](island-generation.md)).
2. **No wood → the wood Burner is dead → the Coal Generator is local power.** No wood = no burner
   fuel. The robot's free Operate-power still bootstraps a single building, but running the
   mine + smelter chain unattended needs the Coal Generator burning local coal.
3. **Keep the sand shoreline.** The island still needs its coastal sand ring, or the Dock (sand
   tile + adjacent coast) has nowhere to go and the player soft-locks on arrival.
4. **Trade routes become a hard prerequisite.** Island 2 is unplayable until the trade-route layer
   exists (step 6 in [Island Unlocks](island-unlocks.md)). This couples three things into one act-2
   feature — see "Build order" below.

## Decision: the route carries construction commodities

Building on island 2 costs wood and stone, and it has neither — so the trade route brings them in.
This is the deliberate maximal-logistics version: the frontier is a pure extraction colony fed by
the home breadbasket (the two-resource-class model in
[Island Generation](island-generation.md) — *you trade stone exactly like wood*).

The honest risk is a **cold-start grind**: a deliberately weak first route trickling in materials
while the player waits to build anything. The fix is **generous bootstrap supplies** — a new
island arrives with enough to build the Dock *and* the first essential building or two, so the
route *scales* the colony rather than *starting* it. ([Island Unlocks](island-unlocks.md)'s
bootstrap was "exactly the dock's materials"; bump it for this fuller dependency.)

Open lever: island 2's **third resource slot**. Leaving it at iron + coal keeps the colony fully
import-dependent; adding **stone** makes it a gentler first colony (build locally, only import
wood); adding **copper** makes it richer but a two-good import. See Open Questions.

## The Milestone Arc

Continues the linear milestone chain after `SET_SAIL`. These complete by playing on island 2;
iron deposits exist only out here, so the chain is geographically self-gating even though
completion state is global (see [`quest_manager.gd`](../scripts/quests/quest_manager.gd)).

| # | Milestone | Do this | Unlocks |
| --- | --- | --- | --- |
| 1 | **Strike Iron** | Hand-mine ~5 iron ore (the discovery beat: walk up, mine by hand, mirroring the island-1 wood/stone intro) | Iron Mine, Coal Mine, Coal Generator — and fires the reframe line: *"This is ship-grade. The wreck back home — I could actually repair it."* |
| 2 | **The Supply Line** | Build the Dock + establish your first **trade route** (home → island 2, carrying wood + stone) | The trade-route tutorial, motivated diegetically by "this rock has no trees and no quarry stone." |
| 3 | **Light the Forge** | Build the iron + coal chain, forge N iron ingots | Smelter (proves the iron economy runs unattended on coal power) |
| 4 | **Set Sail Again** | Build the **sailboat** (imported planks + local iron) | Reveals ring 2 |

This reuses the island-1 teaching rhythm exactly: *hand-gather a little → unlock the building that
automates it → unlock the thing it feeds.*

## The Iron Reframe (story payoff)

Milestone 1 is the emotional hinge of the whole game, per [Intro Story](intro-story.md): the first
sight of iron converts the crashed ship from sad scenery into **the way home**. Stagger it —
discovery first (mine the ore), reframe line second. After this beat the wreck at the map's center
stops being a gravestone and becomes a build target the player keeps returning to, fed by each new
island's rare material (hull → engine → nav → power core). Iron is module one.

> Note: carrying iron *back* to the wreck for repair needs trade routes too, and the wreck is on
> island 1. For the first cut, milestone 4's payoff is the **sailboat built locally** (planks in,
> iron in) — the ship-module repair loop is the longer arc once routes are mature and the player
> is running freight in both directions.

## Build Order

This design couples three pieces into one act-2 feature, and they must land roughly together:

1. **Trade routes** — the unbuilt critical-path piece ([Island Unlocks](island-unlocks.md) step 6).
   Island 2 is unplayable without them.
2. **Island-2 biome profile + the generator refactor** — the profile-driven generator and the
   STONE biome (iron + coal deposits, sand shoreline, no wood/stone resources) described in
   [Island Generation](island-generation.md).
3. **The iron/coal building set + milestones** — enum entries, four building definitions, the
   two-input smelter recipe, and the four-milestone arc above.

The iron/coal building set (3) can be authored and unit-tested first against the existing systems;
it just cannot be *reached* in normal play until (1) and (2) exist.

## Open Questions

1. **Smelter recipe model** — reuse `fuel_*` for coal (minimal, needs verifying), or extend
   `BuildingDefinition` to a proper inputs list (cleaner)?
2. **Coal vs. cozy art direction.** [Progression and Power](progression-and-power.md) steers power
   toward windmills / waterwheels / solar, *not* smokestacks, unless "the fantasy is industry." A
   coal generator + smelter pushes industrial. Lean on the "calm center, **wild edge**" license —
   the frontier is allowed to be grittier — but style the smelter and coal generator as
   cozy-mechanical (a stone kiln, not a smokestack tower).
3. **How many iron ingots gate the sailboat?** Tune so the smelter is clearly worth building but
   island 2 stays a reasonable act-2 length, not a grind.
4. **Island 2's third resource slot** — leave it at iron + coal (fully import-dependent), add
   **stone** (gentler first colony: build locally, import only wood), or add **copper** (richer,
   but import both wood and stone)? This sets how heavy the supply line is. *Undecided.*
5. **Bootstrap generosity** — exactly how much a new island arrives with, so the cold-start isn't
   a grind but the route still matters (see "Decision: the route carries construction commodities").
