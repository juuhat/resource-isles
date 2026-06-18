# Second Island Progression

Design notes for the player's **second** island in Resource Isles — the first stop off the
starter rock (ring 1, rowboat range). This is direction, not implementation. Where island 1
teaches *"you are the economy,"* island 2 teaches **automation, power pressure, and the first
trade route** — the systems island 1 deliberately withheld.

See also: [First Island Progression](first-island-progression.md) for what island 1 teaches and
why automation is dead weight there, [Island Unlocks](island-unlocks.md) for the rings / boat
tiers / trade-route bootstrap, [Intro Story](intro-story.md) for the iron-reframe story beat, and
[Progression, Build Restrictions, and Power](progression-and-power.md) for the power pool.

## The Core Idea: a treeless mining island

Island 2 is a **stone / iron / coal island** — its interior is entirely `Terrain.STONE`, with
**no forest**. It is the richer frontier the story promised (iron is "ship-grade"; see
[Intro Story](intro-story.md), the motivation handoff), but it cannot feed itself: there is no
wood, so it depends on the forested home island for organics.

This is deliberate. It turns the **first trade route from an abstract logistics toy into a
diegetic necessity.** [Island Unlocks](island-unlocks.md) already wrote the rule for exactly this
case:

> The danger case: you arrive on an island with no wood, so you cannot build anything... **the
> dock comes first and enables a trade route, so scarcity is a logistics problem to solve, not a
> wall.**

An all-stone island is the purest version of that scenario — an Anno-style **specialist colony**
where the frontier mines metal and the home island ships the planks that build the boat out.

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

All sit on `Terrain.STONE` — there is no grass to place the island-1 grass buildings on.

| Building | Category | Sits on | Needs adjacent | Produces | Consumes | Power | Modeled on |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **Iron Mine** | RESOURCES | stone | iron-ore node (+1 ea, −1 per mine) | iron ore | — | draws | Quarry |
| **Coal Mine** | RESOURCES | stone | coal node (+1 ea, −1 per mine) | coal | — | draws | Quarry |
| **Smelter** | PROCESSING | stone | — (pulls from stock) | iron ingot | iron ore + coal | draws | Sawmill |
| **Coal Generator** | POWER | stone | — | — | coal (fuel) | generates > Burner | Burner Generator |

The one genuinely new mechanic is the **Smelter's two-input recipe** (iron ore *and* coal). The
current Sawmill models only a single `input_resource_type` / `input_amount`. Two clean options:

1. **Reuse the existing `fuel_*` fields** for the second consumable (ore via `input_*`, coal via
   `fuel_*`). Minimal model change — but `fuel_*` is currently wired to power generation, so this
   needs verifying against `building_manager` / `power_manager` before relying on it.
2. **Extend `BuildingDefinition`** to a small list of inputs. Cleaner long-term, slightly more work.

Decide at implementation time; option 1 first if it works without rewiring fuel.

## The Cascade (consequences of "all stone, no trees")

These fall straight out of the treeless decision and are load-bearing — easy to miss, expensive
to discover late.

1. **Half the island-1 buildings can't be placed here.** Sawmill, Burner Generator, and Logger's
   Camp all require `Terrain.GRASS`. With no grass, none are buildable on island 2 — by design.
   The consequence: **the player cannot mill planks locally** (no sawmill), so finished planks
   must be imported.
2. **The wood Burner is dead → the Coal Generator is the only local power.** No wood = no burner
   fuel. The robot's free Operate-power still bootstraps a single building, but running the
   mine + smelter chain unattended needs the Coal Generator burning local coal.
3. **Keep the sand shoreline.** "All stone" means the *interior* is stone — the island still
   needs its coastal sand ring, or the Dock (sand tile + adjacent coast) has nowhere to go and the
   player soft-locks on arrival. Worldgen must not make the island literally 100% stone.
4. **Trade routes become a hard prerequisite.** Island 2 is unplayable until the trade-route layer
   exists (step 6 in [Island Unlocks](island-unlocks.md)). This couples three things into one act-2
   feature — see "Build order" below.

## Decision: the route carries planks, buildings cost stone

Everything on island 2 costs something, and that something has to come from somewhere. Two models
were considered:

| Model | Route carries | Feel |
| --- | --- | --- |
| A. Pervasive dependency | raw **wood**; buildings keep their wood costs | Every building waits on the import trickle. Maximum logistics pressure, but the early island-2 economy is hostage to a deliberately weak first route → risks feeling slow and grindy. |
| **B. Gated progression (chosen)** | finished **planks**, for the boat | Island-2 buildings are **stone-costed** (built from local rock). The iron economy runs entirely on local stone / iron / coal — no import bottleneck on *operation*. The route's job is to deliver the planks for the **sailboat** that reaches ring 2. |

**Chosen: B.** It keeps "scarcity is a logistics problem, not a wall," makes the route the clear
gate to the next ring, and avoids the trap where the intentionally weak first route makes the
whole island feel like waiting. The first trade route teaches the mechanic by unblocking the
**boat** (a satisfying payoff), not by drip-feeding the ability to function.

Implication: re-cost the new island-2 buildings to be **stone-heavy** (little or no wood), so a
treeless island can build its iron economy from what it has underfoot.

## The Milestone Arc

Continues the linear milestone chain after `SET_SAIL`. These complete by playing on island 2;
iron deposits exist only out here, so the chain is geographically self-gating even though
completion state is global (see [`quest_manager.gd`](../scripts/quests/quest_manager.gd)).

| # | Milestone | Do this | Unlocks |
| --- | --- | --- | --- |
| 1 | **Strike Iron** | Hand-mine ~5 iron ore (the discovery beat: walk up, mine by hand, mirroring the island-1 wood/stone intro) | Iron Mine, Coal Mine, Coal Generator — and fires the reframe line: *"This is ship-grade. The wreck back home — I could actually repair it."* |
| 2 | **The Supply Line** | Build the Dock + establish your first **trade route** (home → island 2, carrying planks) | The trade-route tutorial, motivated diegetically by "this rock has no trees." |
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
2. **Treeless-island worldgen** — an all-stone interior with a sand shoreline ring, plus iron-ore
   and coal deposit nodes.
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
4. **Does island 2 get a Quarry role?** Stone is abundant here, so the island-1 Quarry finally has
   room to operate. Worth confirming stone is a *local building material* (decision B) rather than
   an export, at least until later islands need it.
