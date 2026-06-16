# Island Unlocks, the Dock, and the World Map

Design notes for how the player discovers, reaches, and unlocks new islands in Resource
Isles. This is direction, not implementation.

See also: [Player Unit and Manual Gathering](player-unit-and-manual-gathering.md) for the
robot and the "go there, do the thing" verb, and
[Progression, Build Restrictions, and Power](progression-and-power.md) for how per-island
economy is gated (space, adjacency, power).

## The Core Question

The game starts on one small island ([README](../README.md)). New islands are the main
expansion axis and the home of new resources and larger deposits. So: **what gates reaching
a new island, and how does the player choose where to go?**

Three obvious gate models, and why the first two are weak on their own:

- **Pure resource cost** — a *soft* gate. The progression notes already establish that
  resource cost "throttles the opening, but once camps produce wood passively it stops
  mattering." Pay-N-wood-to-unlock is weightless by the time you can afford a dock. Cost
  still has a role (per-boat build cost, below), but it cannot be the primary gate.
- **Achievement / milestone** — the least *diegetic* option, and the progression notes
  deliberately avoid gates that "feel arbitrary unless tied to something diegetic." Useful
  only as flavor (e.g. an island appears on the map once you can reach it), not as the gate.
- **Tech tree** — already the stated plan: the README says *"Technology unlocks access to new
  buildings, recipes, logistics tools, and additional islands."* This is the intended
  mechanism.

## Decision: fuse island unlocks with the win condition

The narrative already gives us a progression spine — the robot's crashed ship, rebuilt module
by module, is the win condition. Rather than run "island unlocks" as a *separate* tech branch,
**make island reach and ship repair the same loop:**

> repair a ship module -> unlocks the next **boat tier** -> the boat reaches a **farther,
> rougher island** -> that island yields a **rare resource** found nowhere earlier -> that
> resource repairs the next module -> ... -> final module -> fly home.

This is fully diegetic, it restores weight to resource cost (the gating resource only exists
on an island you cannot reach yet), and it answers "why go there?" with **need (pull)** rather
than a checkbox (push). Each new island earns its place by holding something the player now
requires.

## The Dock and the Boat Tiers

- **Dock** — the first `Logistics`-category building. Water-adjacent
  (`required_adjacent` = water). Building it is the capability gate that opens sea travel.
  Uses `assets/buildings/dock.png`.
- **Boat tiers** — built at the dock, each tier a craftable that reaches farther / rougher
  water:

  ```text
  rowboat -> sailboat -> ship -> (later tiers)
  ```

  Distance equals difficulty (a Civ/Anno idea): the rowboat only reaches the nearest islands;
  rougher, richer islands need a better hull. Each tier doubles as the in-fiction step toward
  the rebuilt ship.

## The Gate Has Three Layers

The unlock for the next island is a **capability + a need**, not a price tag:

| Layer | Role | Why it works |
| --- | --- | --- |
| **Boat tier** (tech) | rowboat -> sailboat -> ship; each reaches farther / rougher water | The real gate. Diegetic, tied to the dock you already build. Distance = difficulty. |
| **Resource cost** (per boat) | each boat tier costs resources, and higher tiers cost the *rare resources from earlier new islands* | Restores weight to cost: the tier-2 boat needs island-1's rare material, so the player cannot skip ahead. |
| **Discovery** (pull) | a locked island appears on the world map only once a reachable boat tier exists | "Map fills in as you progress" feel — milestone flavor without an arbitrary achievement gate. |

So "what resources unlock a new island?" resolves to: **the rare resource from the island
before it**, spent on the boat that reaches the next one. The cost is always something the
player had to expand to obtain — exactly the expansion spiral the game wants.

## The World Map: rings expanding outward

The world map is the navigational backbone (a strategic zoom-out / overlay), and **the
starter island sits at the center**. Islands are arranged in concentric **rings** outward:

```text
        ( ring 2 )
     o     o     o
  o    ( ring 1 )    o
     o    [S]    o          [S] = starter island (center)
  o     o     o     o       ring 1 = rowboat range
     o     o     o          ring 2 = sailboat range, rougher water, richer
        ( ring 2 )
```

- **Distance from center = difficulty and reward.** Outer rings are rougher water (need a
  higher boat tier) and hold rarer resources / larger deposits.
- **Ring = boat tier.** Each boat tier unlocks reaching the next ring out. This makes the
  abstract "tech tier" legible as a literal radius on the map.
- **Calm center, wild edge** — fits the art direction's cozy-but-a-little-darker mood: home
  waters are safe, the frontier is where the rare stuff (and the road home) lies.

### Fixed islands per ring (decided): 3, radius grows, count does not

The hex layout makes ring *k* hold 6*k* cells, so it is tempting to fill more islands the
further out you go. **Don't.** Decouple two things that look like one:

- **Ring radius grows** each ring — reinforces farther = harder = better loot, and maps to the
  boat tier needed to reach it.
- **Island count per ring stays fixed at 3**, evenly spaced (every 120°), with water between.

Why fixed 3, not doubling or 3*k*:

- **Bounded content.** 3 per ring = 3*R* total. Doubling (3, 6, 12, 24) hits **45 islands by
  ring 4** — a balance and authoring nightmare and a sprawling map. 3*k* alternating still hits
  30. Fixed 3 stays at 12.
- **Clean choice.** Unlocking a ring presents exactly **3 destinations** — the ideal
  FTL-style branching count. Six-plus is overwhelming.
- **Ring 1 is the intended picture** — three islands at 120° with water between
  (water-island-water-island-water-island).

If outer rings ever feel thin, bump to a gentle *linear* count (3, 4, 5) — never double.
Implemented as `ISLANDS_PER_RING` in [`world_map.gd`](../scripts/ui/world_map.gd): index 0 is
the center, then rings of 3 with the radius growing per ring.

## The FTL Question: a branching choice map

FTL's sector map gives the player a **branching route with meaningful choices** — you see the
nodes ahead, pick a path, and cannot reach everything on one run. The question is whether to
borrow that here. The answer is **borrow the topology, drop the roguelike pressure**, because
Resource Isles is a *persistent cozy builder*, not a tense single-run roguelike.

**Keep (fits the game):**

- **Branching choice of where to go next.** From your current ring you can reach two or three
  islands in the next ring; you choose which to invest in first. This is a real strategic
  decision (which rare resource / which deposit / which adjacency profile do I want now?)
  without any harsh mechanics.
- **Risk/reward island variety.** Outer islands trade rougher access (higher boat tier, more
  cost) for richer payoff — FTL's "is this detour worth it?" tension, mapped onto rings.
- **A partially revealed frontier.** You see hints of what is one ring out before you can
  reach it, creating pull.

**Drop (fights the cozy, persistent premise):**

- **Permadeath / one-way travel.** Islands persist and their buildings keep producing while
  you are away ([player-unit notes](player-unit-and-manual-gathering.md): automation runs
  without the robot). You always keep what you built and can return — the opposite of a
  roguelike run.
- **A pursuing threat forcing forward momentum** (FTL's rebel fleet). No time pressure; this
  is a "relaxing little evening game."
- **Can't-visit-everything.** Eventually the player *can* unlock the whole archipelago. The
  FTL-style choice is about **order and investment priority**, not permanent exclusion.

**Net:** the FTL *choice structure* is a great fit and adds depth cheaply; the FTL *roguelike
stakes* are too much and clash with the mood. If a tense run-based mode is ever wanted, it
belongs as a separate optional "voyage" mode, not the core loop.

## Inventory, Boats, and Island Bootstrap

This is the model for how goods are stored and moved — decided, not just implied. The
reference is **Anno**, but only the parts that fit: per-island storage, no global pool, and a
harbor as the first building on any new island. We deliberately **drop Anno's manual cargo
loading** — there is no loading a ship's hold by hand. Movement of goods is handled entirely by
**automated trade routes** (below). Transit of the robot to a new island is just travel, not a
cargo step.

### Per-island inventory (decided)

Each island has its **own** inventory. There is **no global player inventory** and **no global
pool**. A global pool was considered and rejected: it makes shipping automatic and collapses
the entire inter-island logistics challenge — the game's stated endgame — into one shared
bucket. Anno does not do this, and neither should we.

**Implemented:** [`inventory.gd`](../scripts/resources/inventory.gd) is a per-owner stock
(amounts + `changed` signal); each [`IslandData`](../scripts/island/island_data.gd) owns one.
[`resource_manager.gd`](../scripts/resources/resource_manager.gd) is now a thin facade over the
*current* island's inventory (`set_inventory` on island switch), so the UI and placement logic
keep a stable signal/API. The starter island begins with **no** resources (the opening
scavenge loop, see [progression-and-power.md](progression-and-power.md)); later islands arrive
with **exactly the dock's cost** (derived from the dock's `BuildingDefinition`) — enough to
establish the first dock and never soft-lock. This dock-materials start is the **permanent**
design, not a placeholder. Still pending (the transfer half): **trade routes** that move goods
between island inventories, plus simulating away islands' production into their own stock.

### Trade routes move goods (no manual cargo)

Goods move between islands **only** through automated **trade routes**, never by hand-loading a
boat. A route is a standing link between two docks that ferries a chosen resource from one
island's inventory to another's over time. The player sets up the route once; it then runs on
its own. This keeps the logistics interesting (which routes, between which islands, for which
goods) without the busywork of manually filling holds every trip.

Routes have **throughput** — how much they move per unit time. The first route the player can
afford (built alongside the second island's dock) is intentionally **very weak**: a trickle,
enough to bootstrap but not to run an economy. Throughput is the progression lever.

This gives boat tiers / route upgrades a **second axis** beyond *reach* (which ring): *capacity*
(route throughput). `rowboat` = trickle, `sailboat` = more, `ship` = real trade volume. Reach
and throughput scale together up the tier ladder.

### Bootstrap: the dock is the first building on a new island

Landing on a new island must **never soft-lock** the player. The danger case: you arrive on an
island with no wood (or no stone), so you cannot build anything — and you cannot import,
because importing needs a dock you cannot afford to build. That is a dead end.

**Rule: the dock is the first thing established on any new island, kept deliberately simple.**
A newly reached island simply **starts with exactly the dock's materials** (no cargo step — see
"Trade routes" above), so the first dock is always buildable. Once the dock exists, the island
can be the endpoint of a **trade route**, so a resource-barren island is never a trap — you
route in what it lacks. The very first route you can afford is a weak trickle, enough to begin.
Keep this lightweight; do not gate the first dock behind local resources the island might not
have.

This is the deliberate answer to "what if there's no wood here": **the dock comes first and
enables a trade route, so scarcity is a logistics problem to solve, not a wall.**

See also the inter-island transfer discussion in
[progression-and-power.md](progression-and-power.md).

### The boat is a dock attachment, not a building (implemented)

For rendering, the boat is drawn on the **water tile next to the dock** as an attachment — the
dock stays a one-tile building on sand; the boat is a separate sprite on the adjacent water
([`island_renderer.gd`](../scripts/island/island_renderer.gd), `_draw_boat` /
`_dock_boat_cell`). It is **not** routed through the building placement system (no footprint,
no terrain rule, and it will move during travel — vehicle behavior, not building behavior).
Art lives in `assets/vehicles/`, alongside the robot's `assets/player/`, not in
`assets/buildings/`.

A general "buildings annex a neighbor cell via upgrades" system is **not** built yet. The boat
is the first such attachment; the docs hint at a second (a windmill beside a camp,
[progression-and-power.md](progression-and-power.md)). Generalize when that second concrete
case lands — not from this single example.

## Phased Build Plan

Start tiny; do not build a sprawling tech UI up front.

1. **DONE — Dock building** — a data-driven `Logistics` building, water-adjacent (sand
   shoreline + required water neighbor), using `dock.png`
   ([`building_definitions.gd`](../scripts/buildings/building_definitions.gd)). Placeable
   only; no travel yet.
2. **DONE — Multi-island state** — [`WorldData`](../scripts/world/world_data.gd) holds every
   discovered `IslandData` plus a current-island pointer; `main.gd` renders/simulates the
   current island and switches between persistent islands (Enter generates a new island and
   travels to it; `[` / `]` cycle discovered islands, which keep their placed buildings).
   Only the current island is simulated for now; background simulation of away islands is a
   later step (matters once travel and per-island inventory exist).
3. **Rowboat + one neighbor** — build a rowboat at the dock; reveal and travel to a single
   ring-1 island. View-swap with a short sailing transition. The robot travels; the starter
   island keeps producing.
4. **World map DONE (hex grid + generate-on-click)** — [`world_map.gd`](../scripts/ui/world_map.gd)
   hosts a flat-color, thick-outline hex grid ([`world_map_grid.gd`](../scripts/world/world_map_grid.gd)):
   starter at the center, concentric rings of water with three island slots per ring. Toggled
   with `M`. Clicking a generated island travels there; clicking an unexplored slot (`?`)
   **generates** the island at that hex coord and travels to it (the old `Enter`-to-spawn key is
   gone). Islands are keyed by hex coordinate in [`WorldData`](../scripts/world/world_data.gd).
   Travel uses a [`screen_fade.gd`](../scripts/ui/screen_fade.gd) transition. How many rings are
   revealed lives on [`WorldData`](../scripts/world/world_data.gd) (`revealed_rings`, starting at
   `STARTING_REVEALED_RINGS`) and grows via `reveal_additional_rings()` — currently driven by a
   temporary `=` debug key. Still to add: a real boat-tier system to drive that reveal, and
   per-island art on the hex tokens (now stylized placeholders).
5. **Boat tiers + rare-resource gating** — sailboat/ship reach outer rings; higher tiers cost
   earlier islands' rare resources; fuse with ship-module repair toward the win condition.
6. **Per-island inventory storage DONE** ([`inventory.gd`](../scripts/resources/inventory.gd)
   per island, `resource_manager.gd` facade over the current island; starter starts empty,
   later islands start with the dock's materials). *(Later)* **trade routes** that move goods
   between island inventories at a throughput, weak at first and improving with boat tiers —
   the logistics layer. No manual cargo.

## Open Questions

1. **One traveling robot, or one robot per island?** Leaning one traveling robot early
   (cohesive with the narrative), data kept plural-friendly.
2. ~~Per-island inventory now or later?~~ **Resolved:** per-island inventory, no global pool;
   implemented later in order (step 6) but designed-for now. See "Inventory, Boats, and Island
   Bootstrap".
3. **How many islands per ring, and how many reachable choices at once?** Tunable; start with
   2-3 reachable in ring 1 to introduce the branching choice without overwhelm.
4. **Are some islands optional vs. required for the win path?** Leaning: a critical path of
   rare resources for ship modules, plus optional islands for extra economy / flavor.
