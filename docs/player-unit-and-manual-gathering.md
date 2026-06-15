# Player Unit, Crashed Ship, and Manual Gathering

Design notes for the player-controlled robot and the manual minigame loop in Resource
Isles. The chop minigame and the player unit (movement, hex pathfinding, click-to-move,
chop-on-arrival — Phase 1 below) are **implemented**. The crashed-ship framing and later
phases are **direction, not yet implemented**.

See also: [Progression, Build Restrictions, and Power](progression-and-power.md) for how
this loop feeds the broader economy.

## The Narrative Frame

A little robot's ship crashes on the planet. The wreck **replaces the starting Hub** as a
crashed spaceship, and the robot's mission is to **rebuild a working ship and fly home** —
the game's win condition. This gives the economy a *purpose* (gather → build → escape) and
turns the builder into a goal-driven game rather than an open-ended sandbox.

The robot is the emotional throughline: the lone unit hand-chopping the first few trees is
the "before" that makes the first automated building feel like liberation. The unit and the
automation theme reinforce each other.

## The Core Loop: "go there, do the thing"

The player unit has **one interaction verb** — travel to a tile, then perform a manual
action on arrival. That single verb covers everything:

- **Harvest** — the chop/mine minigame (below), requiring the robot on/adjacent to the node.
- **Construct** — placing a building drops a *blueprint/ghost*; the robot must walk there and
  build it (construction minigame or timer). Makes placement feel earned and reuses the loop.
- **Repair / ship assembly** — the endgame: haul resources to the crashed ship and repair its
  modules, module by module. Same loop, narrative payoff.

One verb covering harvest, build, and win condition keeps the design cohesive and very
Civ-worker in feel.

## The Chop Minigame (implemented)

Manual gathering is a timing minigame instead of a single click. A marker sweeps across a
bar; the player swings (click / space / enter) to land hits:

- **Perfect** (center zone) — bigger yield, builds a combo (combo ≥2 adds a bonus).
- **Good** (wider zone) — smaller yield, resets combo.
- **Miss** — no yield, wasted swing, resets combo.
- The node has several "chunks"; clearing them all ends the session and grants the total.
- The marker speeds up slightly per hit for rising tension.

Files: [`scripts/ui/chop_minigame.gd`](../scripts/ui/chop_minigame.gd) (the `ChopMinigame`
overlay). It is now triggered on the robot's **arrival** at a node (`_on_unit_arrived` →
`chop_minigame.start`) rather than on click, and the yield is granted in `_on_chop_finished`
in [`scripts/main.gd`](../scripts/main.gd).

### Decisions on the minigame

- **Skill beats flat yield.** A node played well out-yields the old flat scavenge amount (e.g.
  ~7 wood vs. 3). Manual effort is rewarded so the player isn't punished for lacking
  automation yet.
- **Nodes are infinitely scavengeable.** The `can_scavenge` / `mark_scavenged` one-shot gate
  was removed — the same forest/stone can be chopped repeatedly. (`IslandData.can_scavenge` /
  `mark_scavenged` are now unused by this path; left in place pending a possible regrowth/
  depletion model.)
- **In-world overlay, not a full-screen modal.** Since gathering happens many times, the
  swing bar is a light overlay over the world rather than a heavy modal that yanks the player
  out each time. Reserve a true full-screen modal for rare, big events (an ancient tree, etc.).

## The Movement Model

**Real-time, not turn-based.** The sim already ticks in real time (production/power update off
`_process` and `Time.get_ticks_msec`), so turn-based movement would fight it. Instead:

> click a tile → robot pathfinds along hexes at a walk speed → on arrival, if the tile is
> actionable, trigger the minigame.

This keeps the Civ *feel* (select unit, click destination, see the path, watch it travel)
without the turn structure. The minigame opens on **arrival**, not on click — this replaces
the current "instant minigame on click" wiring.

Hex A* is a contained, low-risk add: `HexGrid.neighbors()`, `island.is_in_bounds()`,
`get_terrain()`, and the renderer's land checks already provide everything needed to pathfind
over land tiles.

## The Friction Question (the main design risk)

Gating manual actions behind "walk there first" adds friction. That friction is the best or
worst part of the idea depending on framing:

- **Good:** early game is deliberately tactile and slow — one robot, one pair of hands. The
  laboriousness is the pressure that makes the player crave automation.
- **Bad:** if it never goes away, mid-game becomes "babysit the robot," a chore.

**Decision: the robot is a bootstrap, not a permanent bottleneck.** Manual gathering and
construction are robot-gated, but **once a building is built it runs fully independently** —
the robot is never required to keep automation flowing. Friction is meaningful early and
irrelevant late, which is the intended curve.

## Phased Build Plan

Phases 1–4 are the playable core; everything after is content.

1. **DONE — `PlayerUnit`** ([`scripts/player/player_unit.gd`](../scripts/player/player_unit.gd)):
   a `Node2D` with current cell, walk speed, and a path queue; renders the robot + a ground
   selection marker; emits `arrived` when its path is consumed.
2. **DONE — Hex pathfinding** ([`scripts/island/hex_pathfinder.gd`](../scripts/island/hex_pathfinder.gd)):
   BFS over walkable (land) tiles using the existing `HexGrid.neighbors`. Uniform step cost,
   so BFS gives a shortest path.
3. **DONE — Input rework in `main.gd`**: left-click commands the robot
   (`_command_unit_to_hovered`) — it pathfinds to the clicked tile and, on arrival, opens the
   chop minigame if a node is there. Building placement still takes priority when a building
   type is selected. The robot spawns next to the Hub each time the island generates.
4. **Reskin Hub → crashed ship**: the generator already force-places a Hub
   ([`island_generator.gd:152`](../scripts/island/island_generator.gd)); swap art + name and
   mark it the build target. Robot spawns adjacent.
5. *(Later)* Construction-as-blueprint, ship-module repair win condition, buildable extra
   robots for parallelism (another automation-flavored progression axis).

### Phase 1 simplifications (revisit later)

- **Walkability is land-only.** Buildings and resource nodes do *not* block movement yet, so
  the robot can stand on a node's tile to chop it (matches "do the minigame when it's in the
  tile"). Refine to obstacle-aware pathfinding / adjacency-based interaction if the overlap
  reads badly.
- **The robot renders above everything** (separate `Node2D`, `z_index = 10`) rather than
  depth-sorting with buildings. Fine for visibility; revisit if it looks wrong behind tall
  buildings.
- **No path preview.** Click issues an immediate move; the path isn't drawn.

## Open Questions

1. **Does construction require the robot to walk over and build it**, or can buildings be
   placed instantly (robot only matters for harvesting)? *Biggest fork — decides whether the
   robot is central or a side mechanic.* Leaning: construction **does** require the robot
   (more cohesive).
2. **One robot, or buildable extras later?** Leaning: build for a single unit but keep data
   structures plural-friendly.
3. **Does the robot occupy/block its tile** like a Civ unit, or is it purely cosmetic on top
   of terrain? Leaning: does not block tiles, for now.
4. **Node depletion vs. infinite harvest** — currently infinite. Revisit if it makes manual
   gathering feel weightless or breaks the push toward automation.
