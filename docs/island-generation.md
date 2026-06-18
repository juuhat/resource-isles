# Island Generation, Biomes, and Resources

Design notes for how islands are generated in Resource Isles — the architecture that lets new
biomes be added as *data*, the role randomness plays, and how resources are distributed across
the world. This is direction; parts propose a refactor of the current
[`island_generator.gd`](../scripts/island/island_generator.gd) and are flagged as such.

See also: [Island Unlocks](island-unlocks.md) for the rings / boat tiers / trade-route bootstrap,
[Second Island Progression](second-island-progression.md) for the first concrete frontier biome,
and [Progression, Build Restrictions, and Power](progression-and-power.md) for placement gating.

## The Core Principle: contract vs. expression

> **A biome profile guarantees the *contract*. The seed varies the *expression*.**

- **Contract (authored, guaranteed):** which biome this is, *which* resources it holds, that it
  has a sand shoreline a dock can sit on, that it has enough buildable space to not soft-lock.
  Critical-path resources are never left to chance — a "random" iron island that rolls zero iron
  is a bug, not variety.
- **Expression (seeded-random, varied):** the silhouette, exact deposit positions, counts within
  a range, cluster orientation. This is what makes two islands of the same biome feel different
  without either failing its job.

This dissolves the "hard-coded vs procedural" tension: with a fixed seed, a procedural island is
*reproducible*, so it reads as designed while still being generated. "Authored" and "random" are
just the two ends of one spectrum — the starter sits at the constrained end, frontier islands a
little looser, but all run through the same engine.

## Determinism: one world seed × coord

```text
island_seed = hash(world_seed, coord)

world_seed = 1  (default)   → every player gets the identical archipelago
        × coord             → each slot is stable and distinct within that world
```

- **`world_seed` defaults to `1`**, so all players currently play the **same designed world** —
  good for development, testing, sharing, and a hand-made feel.
- An island's seed is derived from its **hex coord**, so a slot's layout is *intrinsic* to where
  it is, not to *when* it was discovered. (The current generator increments a counter in
  generation order — [`main.gd`](../scripts/main.gd) — which we are replacing for this reason.)
- **Per-run variety is a later one-line toggle:** at new-game, set `world_seed` to a random value
  and save it. Every island re-derives from it — a fresh archipelago per run, still coord-stable
  *within* the run. Nothing else in the pipeline changes.

## Resources: two classes, distributed by ring

Resources split into two roles, and **both wood and stone are in the first bucket** (you trade
stone exactly like wood):

- **Construction commodities — `wood` + `stone`.** What buildings cost. Concentrated at **ring 0
  (home)**. These are the "bricks and boards" shipped *outward* to colonize the frontier.
- **Specialty resources — `iron`, `coal`, `copper`, …** Ring 1+. The reason to expand; shipped
  *back* toward home and the crashed ship.

```text
        specialty goods flow IN  ◄──────────────┐
  ring 0 (home)                          ring 1 (frontier)
  wood + stone  ──── construction goods OUT ───►  iron + coal
  the breadbasket                              extraction colony
```

This hub-and-spoke (Anno-style "bring tools to the new world") is the shape of the whole trade
network, and it only exists because **nothing is guaranteed on every island.**

### Per-ring resource pools

| Ring | New resources this tier | Notes |
| --- | --- | --- |
| 0 | wood, stone | Home breadbasket — the construction commodities, at their source. |
| 1 | iron, coal, copper *(glass via sand?)* | Metals / fuel tier — feeds smelting, wiring, and ship-hull repair. |
| 2 | TBD (gold? crystal? oil?) | Rarer materials for later ship modules. |

> `sand` is on every beach, so "sand → glass" could be a *universal* secondary the player can
> always set up, rather than a ring-locked deposit. Held in reserve.

### Three resources per island (small islands, tight identity)

Each island holds **at most ~3 resource node types**, picked beforehand by its profile from {its
ring's pool}. Three is a cap, not a quota — the starter runs lean on two.

- **Legibility:** three icons tell you what an island is at a glance.
- **Specialization + branching choice:** ring 1 has **3 islands** ([Island Unlocks](island-unlocks.md))
  drawing from a ~4-resource pool, so each can offer a different mix — the FTL "which do I invest
  in first?" decision. e.g. `iron+coal+stone` (easy colony, only import wood) vs.
  `iron+coal+copper` (richer, but import *both* wood and stone).
- **Stone is a differentiator, not a constant.** Its presence on a given frontier island is a
  deliberate per-island lever (gives an easy first colony), *not* a guarantee — which is what
  keeps islands from feeling samey.

Soft-lock is **not** prevented by guaranteeing a local resource; it is prevented by the
[bootstrap rule](island-unlocks.md): a new island arrives with the dock's materials, the dock
enables a trade route, and the route imports whatever is missing.

## Terrain is identity + bonus, not a placement gate

Base terrain (green grass vs. grey rock, etc.) is the biome's **visual identity** and an optional
source of **adjacency bonuses** — it does **not** block building placement. You can put any
building on any land tile. The two genuinely spatial rules stay:

- **Dock** — sand shoreline + adjacent water (a real water-access puzzle).
- **Extractors** (logger camp, quarry, iron mine…) — adjacency to their **resource node**.

This drops the awkward "a rocky island can't place grass buildings" cascade while *preserving*
the trade-route necessity, because that now comes from **resource absence** (no wood nodes), not
from terrain technicalities. Biome identity lives almost entirely on the **resource set**, which
is where it belongs. (The existing `required_terrain` field stops being a hard gate for general
buildings — keep it only for the dock's water rule; consider repurposing it as a soft bonus.)

## The Generator Architecture (proposed refactor)

```text
IslandProfile (DATA, authored)      ← "what this biome IS" — one entry per biome
        │
        ▼
IslandGenerator (ENGINE, generic)   ← generic passes, parameterized by the profile
        │
        ▼
hash(world_seed, coord)             ← deterministic per-slot seed
        │
        ▼
validate(profile) → reroll if failed ← contract safety net
```

**`IslandProfile`** is where each biome's personality lives:

```text
IslandProfile:
  biome             # STARTER, STONE, (FOREST, VOLCANIC, …)
  size, sand_border_width, coast_rings
  primary_terrain   # visual base — GRASS, STONE, … (NOT a placement gate)
  terrain_features  # optional scattered patches (e.g. starter's stone patch)
  resource_table    # [ {node_type, count_range, placement: single|cluster}, … ]  ≤ ~3 types
  landmarks         # forced placements: CRASHED_SPACESHIP, STARTER_TOOLS (usually starter-only)
```

The engine becomes profile-driven — the passes that already exist, parameterized:

```text
generate(profile, seed):
  fill_water → carve_blob(profile.primary_terrain) → smooth → add_sand_border
  → scatter(profile.terrain_features) → place(profile.landmarks)
  → place_resources(profile.resource_table) → classify_coast → validate(profile)
```

Almost every current function maps onto this: `_carve_grass_blob` generalizes to
`carve_blob(terrain)`, `_place_trees` / `_place_stones` become `resource_table` entries, etc.
The new **`validate` step** asserts the contract (dock-able shoreline exists, required resources
present, minimum buildable area) and **re-rolls the seed if a roll fails** — free variety without
soft-locks.

**Biome → slot mapping:** start with a simple **coord → profile** assignment (`CENTER` → STARTER,
a designated ring-1 slot → STONE, others → a generic default). Upgrade to **ring-based rules**
(ring 1 = these biomes, ring 2 = those) once more biomes exist.

## What randomness does and does not do

| Randomized (expression) | Guaranteed (contract) |
| --- | --- |
| Island silhouette / edge noise | Biome and its resource set |
| Deposit positions | Presence of every required resource |
| Counts within a range | A sand shoreline a dock can use |
| Cluster orientation | Minimum buildable area (no soft-lock) |

For a cozy, persistent builder with a fixed ring structure and designed rare resources, this is
**controlled variety, not chaos** — exactly enough to make two islands of a biome distinct,
never enough to break a critical-path resource.

## Open Questions

1. **Biome → location:** fixed coord assignment now, ring-based rules later — confirm the
   threshold for switching.
2. **Terrain adjacency bonuses:** worth adding (e.g. a smelter near rock runs hotter), or keep
   terrain purely cosmetic for now?
3. **`world_seed` storage:** confirm it is saved per-world so the later per-run-random toggle is a
   clean drop-in.
4. **Ring 1 third resource:** `copper` (classic iron/coal/copper trio) vs. holding ring 1 to
   iron/coal until a second production line is designed.
