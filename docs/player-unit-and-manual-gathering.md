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
| Travels tile-to-tile across the hex grid | Walks cell-to-cell along a shortest land path: straight through buildings, around resource nodes |
| Spends movement points per turn | **Real-time** walk at a constant `move_speed` (no turns, no MP) |
| Worker "build improvement" / "repair" actions | Harvest (chop minigame), later construct & ship repair |
| Occupies / blocks its tile | Doesn't block movement, but nothing can be built on its tile (or K9-DA's) |
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
| **Right-click** (on release) | Order the robot to walk to the hovered tile; on a green tile it starts the action on arrival |
| Hover with the robot selected | A tile the robot can work (harvestable node, powered building, stranded K9-DA) tints green |
| Pickaxe **Harvest** button (left edge) | Appears when parked beside a node; starts the chop minigame |
| **Left-click** | Select/inspect buildings, place a selected building |
| **Middle-drag** | Pan the camera |
| Mouse wheel | Zoom |

## The Core Loop: "go there, do the thing"

The player unit has **one interaction verb** — travel to a tile, then perform a manual
action on arrival. That single verb covers everything:

- **Harvest** — the chop/mine minigame (below), requiring the robot on/adjacent to the node.
- **Operate (implemented)** — park on any **power-consuming building** and run it by hand: the
  robot *is* the tier-0 power source, so while it operates a building that building is powered
  for free; it stalls the moment the robot leaves (see [power-sources.md](power-sources.md)).
  There is no separate Manual Generator building — that was folded into this verb (see
  [first-island-progression.md](first-island-progression.md)). This extends the bootstrap arc to
  *power* — being the power source yourself is the "before" that makes the self-running burner
  generator feel like liberation, just as hand-chopping does for the logger camp. With one robot
  you cannot chop and power at once, which is the intended early friction.
  While operating, the robot plays its **Operate** clip: the hand-PTO docking pose from
  [the concept](../art/concepts/player-building-hand-pto-v2-neutral.png). It stands upright with
  its right elbow at 90 degrees, the forearm level, and a spindle (`HeldPTO`) spinning out of
  the wrist into the building's [shared generator](shared-generator-model.md) socket
  (`main._on_operate_pressed` → `player_unit.set_work("operate")`). The socket only lines up for
  buildings fitted with the generator at their `WorkSpot` (the sawmill so far). Elsewhere the
  arm just points at the building.
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
   Dijkstra over land tiles using `HexGrid.neighbors`. Buildings are walked through, so the player
   can never wall the robot in. Resource nodes are walked around: stepping onto one costs `OBSTACLE_COST`, so a route crosses one only when there is no other way (no generated island needs this; `tools/robot_access_check.gd` sweeps 60). Nothing is ever unreachable.
3. **DONE — Input rework in `main.gd`**: **right-click (on release)** commands the robot
   (`_command_unit_to_hovered`) — it pathfinds to the clicked tile. The robot's **command bar**
   ([`scripts/ui/action_bar.gd`](../scripts/ui/action_bar.gd), Civ 6 unit-command style) is a
   persistent robot **portrait button in the bottom-right corner** (mirroring the building-menu
   button in the bottom-left); clicking it selects the robot. Whatever actions apply to the
   robot's current tile appear as icon buttons **to the left of the portrait** — currently
   *Harvest* on a resource node and *Operate* on a manual generator. The action row shows only
   while a parked, selected robot has an applicable action and hides when the robot moves away;
   the portrait is always visible. The bar is a pure view fed by `main._refresh_action_bar()`;
   add a new robot action by appending a descriptor there and handling its id in
   `_on_action_pressed`. With the robot selected, hovering a tile it can work tints the tile
   green (`main._is_actionable_cell`, fed to `IslandRenderer.is_cell_actionable`): a resource
   node once harvesting is unlocked, a building that draws power, or the stranded K9-DA. Not in
   placement mode, where right-click cancels. Right-clicking such a tile starts the work as
   soon as the robot arrives (`_start_action_at`): harvest, operate or rescue, the same as
   pressing the button. Work already running there is left alone, so a second right-click
   doesn't cancel it. `tools/action_hover_check.gd` covers both. **Left-click** also selects the
   robot / places buildings on the map,
   and **middle-drag** pans the camera. The robot spawns next to the crashed spaceship each
   time the island generates.
4. **DONE — Crashed spaceship start**: the generator force-places the crashed spaceship
   ([`island_generator.gd`](../scripts/island/island_generator.gd)); it uses the
   `crashed_spaceship.png` art, is named "Crashed Spaceship", and is the future ship-repair
   build target. Robot spawns adjacent.
5. *(Later)* Construction-as-blueprint, ship-module repair win condition, buildable extra
   robots for parallelism (another automation-flavored progression axis).

### Phase 1 simplifications (revisit later)

- **Resolved — robot access.** The robot walks through buildings but around resource nodes, and it never parks on either: it works
  them from beside them (`_plan_approach` in `main.gd`). Clicking one sends the robot to the
  best open neighbour, preferring the camera side. It turns to face the target and leans in
  `WORK_LEAN_TILES`. A building whose model exports a `WorkSpot` marker (the logger camp and
  sawmill, see [building-style-palette.md](building-style-palette.md#footprint-and-work-space))
  is worked from its own yard instead: the robot takes the shortest route straight onto the
  building's tile, its last step going onto the parking spot, and turns to face the building. A fully enclosed target falls back to standing on it. A moving robot re-plans when
  a building is placed on its route. `tools/robot_access_check.gd` covers all of this.
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
   of terrain? Decided: it doesn't block other units, but buildings can't be placed on it.
4. **Node depletion vs. infinite harvest** — currently infinite. Revisit if it makes manual
   gathering feel weightless or breaks the push toward automation.
