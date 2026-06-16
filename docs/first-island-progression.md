# First Island Progression

Design notes for the player's opening island in Resource Isles — what it teaches, what
buildings belong on it, and why. This is direction; parts of it propose **changes** to the
current implementation (notably folding the Manual Generator into the robot) and are flagged
as such.

See also: [Player Unit and Manual Gathering](player-unit-and-manual-gathering.md) for the
robot and the "go there, do the thing" verb, [Power Sources](power-sources.md) for the
generator catalog, [Progression, Build Restrictions, and Power](progression-and-power.md) for
how the per-island economy is gated, and [Island Unlocks](island-unlocks.md) for the dock,
boat tiers, and the win condition.

## The Core Question

The first island is small and **deliberately resource-scarce** — only a few forests and a few
stone deposits. The win goal for the island is narrow: gather enough to build the **Dock** and
a **Rowboat** and sail to the next island. So what is the right progression, and how manual
should it be?

## The Guiding Principle (why automation does *not* belong on island 1)

> **A passive production building is economically dominated whenever (a) total demand is fixed
> and (b) the robot can supply that demand directly by hand.**

Island 1 has *both* properties. The wood/stone needed for the Dock, Sawmill, and boat is a
fixed lump sum, and the single robot can hand-gather all of it. A Logger's Camp costs wood and
only *trickles* output, so it must **amortize** over time — but a leave-island gives it no time
to amortize. A player who does the math correctly will skip the camp and just hand-chop, which
means the camp isn't a teaching moment here, it's a trap.

The clean way to say it: **on island 1, the robot *is* the Logger's Camp.** It is the sole
wood supply, and that is fine because it has nothing else to do yet.

Automation is not pointless in general — it is pointless *on a fixed-demand leave-island*. It
becomes mandatory the moment demand goes **ongoing** and the robot gets **spread thin** (trade
routes, ship-module repair, multiple chains, exploration). That is **island 2+**, and that is
where the Logger's Camp, Quarry, adjacency bonuses, and the crowding penalty finally earn
their place. None of those systems can even matter on a fixed-demand island.

## Decisions

### Island 1 is honestly manual

The opening island teaches **"you are the economy"** plus the **single-robot bottleneck** — not
production automation. Manual gathering (chop wood, mine stone) is the tactile "before" the
whole game is built around. Do not force automation onto island 1 by inflating numbers or by
hard gates; let it stay small and hand-driven.

### The Sawmill is the one forced building

The boat (Rowboat) is gated behind **planks**, and planks only come from the **Sawmill**. So
the Sawmill is the single mandatory building on island 1 — the one structure the player *must*
construct to leave.

```text
Hand-chop wood  ─┐
                 ├─►  Sawmill (forced: planks gate the boat)  ──► planks ──► Rowboat
Hand-mine stone ─┘         ▲
                           └── needs power
```

- **Dock** = raw wood + stone (cheap; the *capability* that opens sea travel).
- **Rowboat** = planks (forces the Sawmill, and therefore the wood supply + power sub-problem).

### Logger's Camp and Quarry are cut from island 1

Both are economically dominated by hand-gathering here (see the Guiding Principle). They move
to **island 2+**, where ongoing demand and a spread-thin robot make passive production win, and
where adjacency / crowding / tall-vs-wide actually have room to operate.

### The robot is the tier-0 power source — drop the Manual Generator *building* (implemented)

**Implemented.** The Manual Generator was previously a placeable building the robot stood on
and operated. The problem it created on island 1: the player hand-gathers wood to build a
Logger's Camp, only to discover the camp is **born dead** (it needs power), and must then
unlock/build a *second* building to revive the first. As the player's very first taste of
automation, that beat reads as a bug, not a reward.

The fix, now in code, **generalizes the existing `Operate` verb into the robot itself**: the
robot *is* the tier-0 power source. Walk it to any power-consuming building, press **Operate**,
and that building runs off the robot while it stays there; it stalls when the robot leaves. The
Manual Generator building, its `BuildingType` enum entry, and the `requires_operator` field are
all removed ([`main.gd`](../scripts/main.gd) `_building_consumes_power` / `_on_operate_pressed`,
[`power_manager.gd`](../scripts/buildings/power_manager.gd) `_allocate_power`).

```text
Build a building ──► Operate (robot powers it) ──► runs NOW
                       │
                       └─ robot leaves ──► stalls
```

What this buys:

- **No born-dead building / no chicken-and-egg.** Anything the player builds works the instant
  it is placed, as long as the robot operates it.
- **The Manual Generator building disappears.** It was always half-redundant with `Operate`
  (the docs already describe operating it via the same verb). The "generator" is now the robot.
- **It removes the "skippable building" problem.** There is no Manual Generator to skip or to be
  dominated — the robot is free, always-available bootstrap power from turn one.
- **The single-robot friction is unchanged.** One robot operates **one** building at a time, so
  powering a camp by hand means you cannot chop, mine, or build meanwhile.

The mechanic is kept dead simple: **present = powered**. While the robot operates a building,
`power_manager` marks that building powered for free and leaves its draw out of the island
generation pool entirely (the robot supplies it). (A literal *battery* the robot charges at a generator
and carries to run a distant building for a while is a cooler, richer version — but that is a
later-island depth toy, not island 1.)

### The Burner Generator stays — it is the liberation beat

The Burner Generator is the first thing that feeds the **island-wide power pool**, so multiple
buildings run **unattended**. That is the "I'm free" moment, cleanly expressed:

```text
Robot operates ONE building by hand     ──►     Burner Generator feeds the island POOL
(tied up, one thing at a time)                  (everything runs unattended at once)
```

On island 1 the Burner is a **time-saver, not a mandatory beat** — a patient player can
hand-feed power via `Operate` and skip it. That is acceptable; not every building must be
forced. The Burner's full payoff (and the camp's) really lands on **island 2**, where demand is
ongoing and the freed robot finally has somewhere else to be.

## Island 1 Build Menu (resolved)

| Building | On island 1? | Role |
| --- | --- | --- |
| Crashed Spaceship | Yes (forced start) | Spawn point; future ship-repair win target |
| Sawmill | **Yes — mandatory** | Wood → planks; planks gate the boat |
| Burner Generator | Yes — optional | Island-pool power; frees the robot (time-saver here) |
| Dock | **Yes — mandatory** | Capability gate for sea travel |
| Logger's Camp | **No — moved to island 2+** | Dominated by hand-chopping on a fixed-demand island |
| Quarry | **No — moved to island 2+** | Same as above |
| Manual Generator | **Removed as a building** | Folded into the robot's `Operate` verb |

## The Island 1 → Island 2 Curve

- **Island 1:** *You are the economy.* Manual gather + one forced processing building (Sawmill)
  + the single-robot power friction. Honestly manual; small; ~15-minute on-ramp. Scarcity here
  doubles as the **pull** toward island 2 (you've maxed this rock; the frontier has more —
  see [Island Unlocks](island-unlocks.md)).
- **Island 2+:** *Automation liberates you,* because now the robot is spread thin (trade routes,
  ship repair, multiple chains). The Logger's Camp / Quarry / Burner-frees-the-robot beats land
  here, where the math finally favors them, and where adjacency and crowding start to bite.

## Open Questions

1. **Force the automation lesson onto island 1 anyway?** Only if island 1 *must* be the
   automation tutorial: make stone **un-hand-mineable** (stone only from a powered Quarry), so
   the dependency chain (dock needs stone → Quarry → power → operate) forces the player through
   automation + power before leaving. Contrived and contradicts "hand-mine stone"; **recommended
   against** unless the tutorial framing demands it.
2. **Rowboat cost in planks** — how many planks gate the boat? Tune so the Sawmill is clearly
   worth building but island 1 stays a short on-ramp.
3. **Does the robot-as-power source add to the island pool, or only to the building it stands
   on?** On a one-generator island it does not matter; revisit if multiple operable buildings
   coexist. Leaning: add to the pool while operating (simplest), capped so one robot powers
   roughly one building's worth.
