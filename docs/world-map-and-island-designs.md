# World Map and Island Designs

> **Status (2026-10-07):** decided, not implemented. Replaces generating the world at game start
> ([Island Generation, Biomes, and Resources](island-generation.md)); the generator stays, as a
> tool for making island designs. See [Decisions](#decisions) for what was settled.

Design notes for a premade world: every player sails the same hand-placed map, from full colony
islands to small islets (atolls, sandbars, rocks) scattered across the open sea. Islands are built
from **island design** files and placed by one **world map** file. This is direction, not
implementation.

See also: [Island Generation](island-generation.md) for the generator and biome profiles that
become the design tool, [Island Unlocks](island-unlocks.md) for rings and the sailing frontier,
and [Island Visual Variety](island-visual-variety.md) for making islands look distinct.

## Why

Today the world is generated when a new game starts
([`world_builder.gd`](../scripts/world/world_builder.gd)):

- **Same for everyone, but not premade.** The world seed is fixed at 1
  ([`main.gd`](../scripts/main.gd)), so every player gets the same archipelago, on the same
  build. It works like a Minecraft seed: a change to the generator or the biome profiles, or a
  Godot update that changes `hash()` or `RandomNumberGenerator`, gives new games a different
  world. Saves keep the islands they already have, but islands added when the disc grows come
  from whatever the code is then.
- **Islands only on slots.** An island's key is its slot, and its position is computed from the
  key (`WorldNavigation.slot_axial`): the centre plus three slots per ring, rings 50 cells apart.
  The starting disc is 4 rings, about 240 cells in radius, and holds 13 islands; neighbours on
  ring 4 are about 400 hexes apart. The sea between them is empty.
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
islands no longer arrive with them as they do today.

Turning one design and mirroring it gives up to twelve different-looking placements, so a handful
of islet designs can fill a lot of sea.

**Ids.** Islands are keyed by their map id (`&"copper_isle"`) instead of a slot coord.
Everything that holds a coord today (`current_coord`, `dog_coord`, trade routes, the navigation
regions, the renderers) holds an id. An id doesn't change when an island moves on the map, and it
lets quests and story name a specific island.

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

`tools/world_map_check.gd`:

- Every design loads: known characters, consistent rows, deposits on legal ground, landmarks
  that fit.
- Every island lies inside the 4-ring disc.
- Islands don't overlap and leave open sea between them (at least ~3 cells) so boats can pass.
- Exactly one `start` island, with the crashed spaceship, and all three tools reachable from the
  robot's spawn.
- Exactly one `k9da` island, inside the first ring's frontier, with its marker on reachable open
  ground.
- Every island has a shore a dock can use (sand next to coast).
- Nothing is sealed in: every item and deposit can be reached (today's `robot_access_check`
  logic).

`tools/world_map_preview.gd` draws the whole map to an image (hexes coloured by ground, island
ids, a coordinate grid, the ring frontiers) so islands can be placed without sailing around in
the game.

The checks that loop over seeds today (`dog_rescue_check`, `robot_access_check`,
`copper_deposit_check`) move onto the designs and the map.

## Code changes

- **Loading.** New `IslandDesign` (parses a `.island` file) and `WorldMap` (parses
  `world_map.cfg`). Placing a design turns and mirrors it in axial coordinates
  (`HexGrid.rotate_axial`), shifts it to its centre, adds the coast ring, then places deposits,
  items, landmarks and K9-DA. `WorldBuilder.ensure_generated` builds from the map, and
  `seed_value`, `WorldBuilder.island_seed`, `WorldData.dog_slot_for_seed`,
  `IslandProfiles.biome_for_coord` and `WorldBuilder.choose_dog_cell` leave the game.
- **No free supplies.** `WorldBuilder._stock_bootstrap_supplies` goes, and new islands start with
  an empty stock.
- **Ids and centres.** Islands are keyed by id, and `IslandData` stores its centre cell (saved).
  Every `slot_position(coord)` in [`world_view.gd`](../scripts/world/world_view.gd) (picking, fog
  patches, chart cells, the opening animation, K9-DA's signal, labels, route lines) uses the
  centre instead.
- **Loops.** The loops over `WorldData.all_slots()` (generation in `world_builder.gd`; drawing,
  picking and labels in `world_view.gd`) loop over the islands instead, and generation over the
  map.
- **Reveal by distance.** `WorldData.is_revealed` and `WorldView.locked_island_hint` measure the
  centre's distance from the middle of the world, not `ring_of`.
- **Sizes from the island.** The water disc around each island
  (`IslandRenderer.WATER_PLANE_RADIUS`, sized today so slot neighbours never overlap) and the
  click radius (`WorldView.ISLAND_PICK_RADIUS`) come from the island's extent. Fog patches
  already do.
- **Trade trip time.** `TradeManager` measures trips in slot coords; measure between centres in
  cells instead, and rescale `SECONDS_PER_HEX`.
- **Saves.** The keys change, so this is save version 3, in its own file. By the rule in
  [`save_manager.gd`](../scripts/save_manager.gd), version 2 saves aren't loaded, and they aren't
  converted. Loading a version 3 save keeps its islands as saved, since they hold the player's
  buildings, and adds any map island whose id it doesn't have, unless it would overlap a saved
  one. New islets then show up in existing games.
- **Export.** `.island` and `.cfg` files aren't Godot resources: the export preset needs
  `assets/world/*` in its non-resource include filter, or exported builds won't contain the map.

## Order of work

1. **Formats** (done): `IslandDesign` ([`island_design.gd`](../scripts/island/island_design.gd)),
   `WorldMap` ([`world_map.gd`](../scripts/world/world_map.gd)), placing a design, and the shared
   legend, checked by `tools/island_design_check.gd`. Nothing in the game uses them yet.
2. **Bake today's world:** a tool writes the 13 seed-1 islands as designs plus a
   `world_map.cfg` with their current positions. A check confirms that building from the map
   gives the same cells as the seed-1 world, which tests the loader against known output. The
   current, tuned layout becomes the first version of the map.
3. **Switch the game to the map:** ids, centres, loops, reveal by distance, island-sized water
   and click radius, trade trip time, no free supplies, save version 3.
4. **`world_map_check` and `world_map_preview`.**
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
