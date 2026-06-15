# Player Unit, Crashed Ship, and Manual Gathering

Design notes for the player-controlled robot and the manual minigame loop in Resource
Isles. The chop minigame and the player unit (movement, hex pathfinding, click-to-move,
chop-on-arrival — Phase 1 below) are **implemented**. The crashed-ship framing and later
phases are **direction, not yet implemented**.

See also: [Progression, Build Restrictions, and Power](progression-and-power.md) for how
this loop feeds the broader economy.

## The Narrative Frame

A little robot's ship crashes on the planet. The wreck is the starting **crashed spaceship**,
and the robot's mission is to **rebuild a working ship and fly home** —
the game's win condition. This gives the economy a *purpose* (gather → build → escape) and
turns the builder into a goal-driven game rather than an open-ended sandbox.

The robot is the emotional throughline: the lone unit hand-chopping the first few trees is
the "before" that makes the first automated building feel like liberation. The unit and the
automation theme reinforce each other.

## The Player Character (a Civ 6 worker / scout unit)

The robot is modelled directly on a **Civ 6 worker/scout-type unit** — a single, selectable
figure that the player orders around the hex map, not a cursor or a disembodied "hand". It is
the *Builder* (manual labor: harvest, construct, repair) and the *Scout* (the thing that moves
through the world and reveals/reaches tiles) rolled into one little robot.

What carries over from the Civ worker/scout, and what deliberately doesn't:

| Civ 6 worker/scout | Resource Isles robot |
| --- | --- |
| One unit you select and command | One unit, selected by default (`selected = true`) |
| Click a hex to issue a move order | **Right-click** a hex to order a move |
| Travels tile-to-tile across the hex grid | Walks cell-to-cell along a BFS path over land hexes |
| Spends movement points per turn | **Real-time** walk at a constant `move_speed` (no turns, no MP) |
| Worker "build improvement" / "repair" actions | Harvest (chop minigame), later construct & ship repair |
| Occupies / blocks its tile | **Does not block tiles** (Phase 1 simplification) |
| Can be lost in combat | No combat — the robot is never threatened or destroyed |

### Concrete properties (as implemented)

Defined in [`scripts/player/player_unit.gd`](../scripts/player/player_unit.gd) (`PlayerUnit`, a
`Node2D`):

- **Identity** — holds a `current_cell` (its hex) and a `selected` flag; renders the
  `player_robot.png` sprite with its feet anchored near the cell center.
- **Selection marker** — a flattened ground ellipse under the robot: a cyan ring when
  `selected`, a faint shadow otherwise (the Civ "this unit is selected" footprint).
- **Movement** — `follow_path()` takes a queue of cells and walks them at `move_speed`
  (world units/sec) in `_process`, lerping toward each cell center; emits **`arrived(cell)`**
  once the whole path is consumed so the caller can react (show the harvest button).
- **Spawn** — placed next to the crashed spaceship on every island generation
  (`_find_unit_spawn_cell` in `main.gd`), with a fallback to any open land tile.
- **Draw order** — `z_index = 10`, so it renders above terrain and buildings for visibility.

### Controls

| Input | Action |
| --- | --- |
| **Right-click** (on release) | Order the robot to walk to the hovered tile |
| Pickaxe **Harvest** button (left edge) | Appears when parked on a node; starts the chop minigame |
| **Left-click** | Select/inspect buildings, place a selected building |
| **Middle-drag** | Pan the camera |
| Mouse wheel | Zoom |

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
3. **DONE — Input rework in `main.gd`**: **right-click (on release)** commands the robot
   (`_command_unit_to_hovered`) — it pathfinds to the clicked tile. On arrival at a node, a
   **pickaxe harvest button** ([`scripts/ui/harvest_button.gd`](../scripts/ui/harvest_button.gd))
   appears on the left edge of the screen; pressing it starts the chop minigame. The button
   reappears after each chop (nodes are infinite) and hides when the robot moves away.
   **Left-click** stays for selection / building placement, and **middle-drag** pans the
   camera. The robot spawns next to the crashed spaceship each time the island generates.
4. **DONE — Crashed spaceship start**: the generator force-places the crashed spaceship
   ([`island_generator.gd`](../scripts/island/island_generator.gd)); it uses the
   `crashed_spaceship.png` art, is named "Crashed Spaceship", and is the future ship-repair
   build target. Robot spawns adjacent.
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
