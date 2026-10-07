# World Map and Island Designs

> **Status (2026-10-07):** steps 1 to 3 of the [order of work](#order-of-work) are done: the game
> runs on the world map instead of generating its world at game start
> ([Island Generation, Biomes, and Resources](island-generation.md)); the generator stays, as a
> tool for making island designs. See [Decisions](#decisions) for what was settled.

Design notes for a premade world: every player sails the same hand-placed map, from full colony
islands to small islets (atolls, sandbars, rocks) scattered across the open sea. Islands are built
from **island design** files and placed by one **world map** file.

See also: [Island Generation](island-generation.md) for the generator and biome profiles that
become the design tool, [Island Unlocks](island-unlocks.md) for rings and the sailing frontier,
and [Island Visual Variety](island-visual-variety.md) for making islands look distinct.

## Why

Until step 3, the world was generated when a new game started:

- **Same for everyone, but not premade.** The world seed was fixed at 1, so every player got
  the same archipelago, on the same build. It worked like a Minecraft seed: a change to the
  generator or the biome profiles, or a Godot update that changes `hash()` or
  `RandomNumberGenerator`, gave new games a different world. Saves kept the islands they already
  had, but islands added when the disc grew came from whatever the code was then.
- **Islands only on slots.** An island's key was its slot, and its position was computed from the
  key: the centre plus three slots per ring, rings 50 cells apart. The disc is 4 rings, about
  240 cells in radius, and held 13 islands; neighbours on ring 4 are about 400 hexes apart. The
  sea between them is empty.
- **One island size.** The generator's land blob is a hard-coded ~11 × 9 cells whatever the
  profile asks for, so it can't make a small islet.

The goal is a world that is **designed rather than seeded** (a Stardew Valley or Anno scenario
map, not a Minecraft seed): islands of any size anywhere on the sea, placed by hand, identical
for every player, and unchanged by code edits. Exploring the sea between the big islands should
turn up something.

## The model

Two kinds of plain-text file, both shipped with the game:

```text
IslandGenerator (tool) ──┐
hand-written text ───────┼──► assets/world/islands/*.island ──► assets/world/world_map.cfg ──► new game
island painter (later) ──┘          island designs                 where each design goes
```

- **Island design:** what one island looks like: its land, deposits, items and landmarks. A
  design can be placed more than once.
- **World map:** every island in the world: which design, where, turned which way, and its role.

A new game builds the world from the map. The generator no longer runs in the game; it becomes
one of the ways to make designs.

## Island design files

One file per design in `assets/world/islands/`, e.g. `atoll_small.island`:

```text
# A ring of sand around a lagoon, with one tree and a stone deposit.
[grid]
. . s s s . .
 . s g T s s .
. s g . . g s
 s S . . g s .
. s g g g s .
 . . s s s . .
```

**The grid.** One character per hex, separated by spaces. Odd rows are indented by one space:
the game's hexes use odd-r rows (every second row sits half a hex to the right, see
[`hex_grid.gd`](../scripts/island/hex_grid.gd)), so the text looks like the island. A design can
be any size, and a row can stop early: the rest of it is water. The cell in the middle of the
grid is the one a placement's `center` puts on the map.

**Draw land only.** `.` is water. The shallow coast around land, and in lagoons, is added when
the design is loaded, by the pass the generator uses today (`_classify_coastal_water`, 2 rings).
An island owns its land and that coast ring; everything further out is open sea. (A generated
island today owns a whole 30 × 24 rectangle, mostly water.)

**One shared legend** (`IslandDesign.LEGEND`). Each object letter also sets the ground under it:
deposits sit on rock and trees on grass, as `IslandData._terrain_for_resource` requires. New
terrain or objects (a salvage crate, say) get a new letter there.

| Char | Ground | On it |
| --- | --- | --- |
| `.` | water | — |
| `s` | sand | — |
| `g` | grass | — |
| `r` | rock (`Terrain.STONE`) | — |
| `T` | grass | tree |
| `S` | rock | stone deposit |
| `I` | rock | iron ore |
| `C` | rock | coal |
| `U` | rock | copper ore |
| `a` / `p` / `w` | grass | the robot's axe / pickaxe / wrench |

**Optional sections** for things that don't fit one character per cell. Positions are
`column,row` in the grid, counted from the top-left cell starting at 0.

```text
[landmarks]
# Multi-hex buildings: type, anchor cell, rotation in 60° steps.
crashed_spaceship 14,10 0

[markers]
# k9da: where K9-DA waits, if the world map strands it on this island.
k9da 8,6
```

A landmark is placed under the same rules as a player's building (`BuildingManager.try_place`),
and turns with the island. A building can't be mirrored, so on a mirrored island it faces the
mirrored direction instead. A marker needs open land: no deposit, item or landmark on it.

A `#` starts a comment, to the end of the line.

**Mistakes are reported with their line**, e.g. `atoll_small.island:5: 'x' isn't in the legend`,
by `tools/island_design_check.gd`, which loads and builds every design in all twelve
orientations.

**Editing in Godot:** the FileSystem dock hides file types it doesn't know. Add `island` to
Editor Settings → Docks → FileSystem → TextFile Extensions to see the designs there and open them
in the script editor.

## The world map file

One file, `assets/world/world_map.cfg`, read with Godot's `ConfigFile` (so `Vector2i` values work
as written). One section per island; the section name is the island's id:

```ini
[crash_site]
design = "starter"
center = Vector2i(0, 0)
start = true

[copper_isle]
design = "copper_01"
center = Vector2i(-25, -58)
k9da = true

[little_atoll]
design = "atoll_small"
center = Vector2i(22, -24)
rotation = 2                    ; 60° steps, counter-clockwise
```

| Key | Meaning | Default |
| --- | --- | --- |
| `design` | The design file in `assets/world/islands/`, without `.island` | required |
| `center` | The world cell the design's middle lands on, in the same cell coordinates as the rest of the game | required |
| `rotation` | Turn in 60° steps, counter-clockwise seen from above | `0` |
| `mirror` | Flip east–west before turning | `false` |
| `name` | Name shown on the map | `World N`, in map order |
| `start` | The robot starts here, at the crash site. Exactly one island. | `false` |
| `k9da` | K9-DA is stranded here, at the design's `k9da` marker. Exactly one island. | `false` |

**Islets are just smaller islands.** There is no separate kind: the same file format, the same
rules, a name on the map, and they count toward Islands Reached like any island. The robot can
land, build and dock on them, and trade routes can reach them.

**No free supplies.** A new island starts with an empty stock. The materials for its first dock
come on the robot's boat ([Rescue, first metals, and boat cargo](rescue-metals-and-cargo.md)), so
islands no longer arrive with them as generated islands did.

Turning one design and mirroring it gives up to twelve different-looking placements, so a handful
of islet designs can fill a lot of sea.

**Keys and ids.** The world keys an island by its centre: the world cell its design's middle sits
on, the `center` of its section. That is a cell anywhere on the lattice, so an island can sit
anywhere, not only on a ring slot, and everything that held a slot coord (`current_coord`,
`dog_coord`, trade routes, the navigation regions, the renderers) now holds a centre without
changing type. Each island also keeps its section's id (`IslandData.map_id`, saved), which is what
ties a saved island to its entry on the map: an id doesn't change when an island moves on the map,
and it lets quests and story name a specific island. (The first plan keyed islands by id outright;
keying by centre plus `map_id` gives the same behaviour without retyping every coord in the game.)
The map names its islands after the progression: `crash_site`, `copper_isle` (K9-DA's),
`iron_isle` and `windward_isle` on ring 1, then the power tiers planned for the outer rings
(`coal_isle`, `oil_isle`, `uranium_isle`, …). Each section's comment says what it is named for.
Saves store the ids, so renaming one now means a saved game no longer recognises that island.

**Size and rings.** The map covers today's disc: 4 rings (`WorldData.MIN_WORLD_RINGS`), about 240
cells in radius. Rings stay the way the sea opens up: the sailing frontier and the
`REVEAL_WORLD_RINGS` quest reward work as they do now (`WorldNavigation.sailing_radius`). Only
what counts as revealed changes: an island is revealed once its centre is inside the frontier,
instead of by its slot's ring number, so an islet halfway between rings appears as the frontier
passes it.

## Making designs

1. **By hand.** Edit the text in any editor, or ask Claude for one ("a horseshoe island with a
   coal seam in the bay").
2. **Generated.** `tools/design_island.gd` runs `IslandGenerator` with a biome profile and a seed
   and writes a `.island` file. Generate a batch, keep the good ones, touch them up by hand. The
   generator needs two fixes for this: the land blob scales with the profile's size (it's
   hard-coded today, `_carve_land_blob` in
   [`island_generator.gd`](../scripts/island/island_generator.gd)), and the output is trimmed to
   the land. The tool loads no scene, so it never touches a save.
3. **Painted (later).** A painter in the Godot editor or in the game that reads and writes the
   same files. Only worth building if editing text gets tedious.

## Checking and previewing the map

The generator re-rolled any island that broke its biome's contract. Hand-made designs need the
same safety net, as checks run with the others (`tools/run_checks.ps1`).

`tools/world_map_check.gd` (done) fails with every problem it finds, each naming the islands
involved and where, e.g. `[iron_isle] and [too_close] overlap at <cell>`. The rules live in
`tools/world_map_rules.gd`, so the preview can use them too:

- **The map and its designs read**, and every island builds (`island_design_check` also loads
  every design file, placed or not).
- **No two islands share a cell.** An island's coast reaches 2 cells past its land, so land needs
  about 5 cells of sea between islands; the coast between them is sailable, so boats pass. The
  game would leave the later island out.
- **Every island lies within the sea:** 4.5 rings of the centre, the sailing frontier with every
  ring revealed, inside the mountains.
- **Every island has a dock shore:** sand beside the coast with room for the pier.
- **Nothing is walled in:** the robot can reach every item, and a tile beside every deposit,
  without climbing over deposits: on the start island from where it wakes beside the wreck,
  elsewhere from any shore it can step onto from a boat.
- **The start island** is revealed from the start (within the home waters, 0.75 rings of the
  centre) and has the crashed spaceship and the axe, pickaxe and wrench.
- **K9-DA's island** isn't the start island, lies wholly in the home waters (sailable from the
  start, see [Copper and the radar](copper-and-the-radar.md)), and has a `k9da` marker reachable
  from the shore.
- **No other island** has its centre in the home waters: the rest wait for the radar.

The check also breaks a copy of the map one way at a time, to make sure each rule catches its
mistake.

`tools/world_map_preview.gd` (done) draws the map to an image so islands can be placed without
sailing around in the game: every island cell coloured by its ground, with dots for deposits,
tools, the wreck and K9-DA's spot; each island's id and centre; a grid of world cells numbered as
`world_map.cfg` writes them; the ring frontiers (the home waters, then what the radar and each later ring
reveal); the edge of the sea; and, circled in red and listed, any island that breaks a rule. It
draws the whole map by default ([`art/previews/world_map/world_map.png`](../art/previews/world_map/world_map.png)),
or a close-up for placing islets next to others:

```text
Godot_v4.6.3-stable_win64_console.exe --path . --script res://tools/world_map_preview.gd -- [output.png] [--around 25,-29] [--cells 40]
```

It writes text, so it needs a window (no `--headless`); it loads no scene and touches no save.

## Code changes

Done in step 3, except the export filter.

- **Loading.** `IslandDesign` parses a `.island` file and `WorldMap` parses `world_map.cfg`.
  Placing a design turns and mirrors it in axial coordinates (`HexGrid.rotate_axial`), shifts it
  to its centre, adds the coast ring, then places deposits, items and landmarks.
  `WorldBuilder.add_map_islands` builds the world from the map: the start island, K9-DA at its
  island's marker, and every other island. `seed_value`, `WorldBuilder.ensure_generated`,
  `island_seed`, `choose_dog_cell`, `WorldData.dog_slot_for_seed` and the slot helpers, and
  `IslandProfiles.biome_for_coord` are gone.
- **No free supplies.** `WorldBuilder._stock_bootstrap_supplies` is gone, and new islands start
  with an empty stock.
- **Keys and centres.** Islands are keyed by their centre cell and remember their `map_id`;
  `WorldData.start_coord` says which island the game started on. `WorldView.island_position`
  (formerly `slot_position`) is just the centre cell's position, and
  `WorldNavigation.island_at` (formerly `slot_at`) finds the island a cell belongs to.
- **Loops.** Drawing, picking and labels in [`world_view.gd`](../scripts/world/world_view.gd)
  loop over the islands that exist, not over `all_slots()`.
- **Reveal by distance.** `WorldData.is_revealed` measures the centre's distance from the middle
  of the world in rings (`WorldData.rings_out`) against the frontier
  (`WorldData.frontier_rings`): the home waters at first, then half a ring past the last revealed
  ring.
- **Sizes from the island.** Each island's water plane reaches past its land by the shore
  shading's reach and the fade (`IslandRenderer._water_radius`), never more than the old 3150
  units; deep toon water looks the same as the open sea, so a ring island looks as it did. The
  click reach (`WorldView.ISLAND_PICK_MARGIN`) and where trade lanes start
  (`WorldView.ROUTE_MARGIN`) are margins past the island's land, matching the old fixed radii for
  a ring island.
- **Chart cells.** Discovery explores every cell under the island's fog patch, sea included
  (`WorldView.island_chart_cells`), since an island no longer owns a rectangle of water.
- **Discovery distance.** An island owns its land and two coast rings, not a 30 × 24 rectangle
  of water, so the robot's sight (8 cells) discovers it about 10 cells from its land rather than
  15 to 17. Widen the sighting range for islands if that feels too late.
- **Trade trip time.** `TradeManager` measures trips in cells between centres
  (`SECONDS_PER_CELL`, 0.2 s, so a ring's hop still takes about 10 s).
- **Saves.** Version 3, in `savegame_v3.sav`. By the rule in
  [`save_manager.gd`](../scripts/save_manager.gd), version 2 saves aren't loaded or converted.
  Loading a version 3 save keeps its islands as saved, since they hold the player's buildings,
  and adds any map island whose id it doesn't have, unless it would overlap a saved one. New
  islets then show up in existing games.
- **Export.** `.island` and `.cfg` files aren't Godot resources: the export preset needs
  `assets/world/*` in its non-resource include filter, or exported builds won't contain the map.
  There is no export preset yet.
- **Close neighbours' water.** Each island's water plane reaches about 12 cells past its land, so
  the planes of two islands closer than that overlap, and one draws over the other's shore.
  Today's islands are far apart; placing islets near islands will need a look at this.

## Order of work

1. **Formats** (done): `IslandDesign` ([`island_design.gd`](../scripts/island/island_design.gd)),
   `WorldMap` ([`world_map.gd`](../scripts/world/world_map.gd)), placing a design, and the shared
   legend, checked by `tools/island_design_check.gd`.
2. **Bake today's world** (done): a one-off tool (`tools/bake_world_map.gd`, removed in step 3
   since it ran on the old world generation; see commit 807ad51) wrote the 13 seed-1 islands as
   designs (`starter`, `copper_01`, `stone_01` to `stone_11`) plus a `world_map.cfg` with their
   current positions, then built every island from the map and found the same cells as the
   seed-1 world, which tested the loader against known output. The current, tuned layout is the
   first version of the map.
3. **Switch the game to the map** (done): see Code changes. `island_design_check` also covers
   building a world from the map, and the checks that swept seeds (`dog_rescue_check`,
   `robot_access_check`, `copper_deposit_check`) now check the islands on the map.
4. **`world_map_check` and `world_map_preview`** (done).
5. **The design tool:** a size-aware land blob and `.island` output.
6. **Content:** new islands and islets across the map.
7. **Later:** the island painter.

## Decisions

Settled 2026-10-07:

1. **Islets are just smaller islands.** No separate kind and no flag: they can be landed on,
   built on and docked at, get a name on the map, and count toward Islands Reached. (No quest
   reads that stat today, so many small islands can't complete one early.)
2. **Version 2 saves aren't converted.** Save version 3 starts fresh, as the save rule says.
3. **The map keeps today's size:** the 4-ring disc, with rings still opening the sea.
4. **No free dock supplies.** New islands start with an empty stock; dock materials come by boat.
5. **One world for everyone is the long-term plan.** The per-run random seed that
   [Island Generation](island-generation.md) planned as a later toggle is dropped. This also
   suits [postgame leaderboards](postgame-leaderboards.md).

## Open Questions

1. **The painter:** a Godot editor plugin, or an edit mode in the game? Only matters once
   editing text gets tedious.
