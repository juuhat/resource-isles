# Building footprints

A building can cover more than one hex tile, in any connected shape, and the player turns that shape in 60-degree steps while placing it. The dock is the first multi-tile building: a sandy shore tile, the coast tile beside it and a water berth beyond, in a line.

See also: [3D Models](3d-models.md) for how models are placed, and [Low Poly Workshop art direction](building-style-palette.md) for authoring them.

## Defining a shape

`BuildingDefinition.footprint` lists the tiles as **axial hex offsets** from the building's anchor tile. The anchor, `Vector2i.ZERO`, comes first. Write the other tiles with the six direction constants in [`hex_grid.gd`](../scripts/island/hex_grid.gd), summed for tiles further out:

```
          NORTH_WEST   NORTH_EAST
     WEST          ZERO          EAST
          SOUTH_WEST   SOUTH_EAST
```

| Shape | `footprint` |
| --- | --- |
| One tile (the default) | `[Vector2i.ZERO]` |
| Two tiles | `[Vector2i.ZERO, HexGridScript.AXIAL_EAST]` |
| Triangle of three | `[Vector2i.ZERO, HexGridScript.AXIAL_EAST, HexGridScript.AXIAL_NORTH_EAST]` |
| Line of three (the dock) | `[Vector2i.ZERO, HexGridScript.AXIAL_EAST, HexGridScript.AXIAL_EAST * 2]` |
| Flower of seven | `ZERO` plus all six directions |

Axial offsets mean the same step on every row, unlike the map's odd-r offset coordinates (`Vector2i(x, y)` cells), where a "north-east" neighbour has a different offset on odd and even rows. `HexGrid.footprint_cells(anchor, shape, rotation)` converts a shape to map cells.

## Placement rules

- **Terrain:** every tile must be on one of `required_terrains`. Use `footprint_terrains` to give individual tiles their own rule, with one entry per footprint tile and an empty array for "use `required_terrains`". The dock is `[[], [GameTypes.Terrain.COAST], [GameTypes.Terrain.COAST, GameTypes.Terrain.WATER]]`: anchor on sand, pier tile on coast, berth on coast or open water.
- **Free tiles:** no tile may hold a resource node or another building, or be under the robot or K9-DA.
- **Adjacency:** `required_adjacent`, `forbidden_adjacent` and `adjacency_yields` look at the tiles around the *whole* footprint, so a big building touches more neighbours and can earn more from them.
- **Rotation:** **R** turns the shape counter-clockwise while placing and **Shift+R** turns it back. One-tile buildings don't turn: their yard and work spot are laid out facing the camera. `auto_rotate = true` makes placement try the other five rotations when the player's choice doesn't fit, so the dock swings its pier toward whichever side the water is on. Leave it off for "building tetris" pieces, so a shape doesn't flip around under the cursor.

A placed building keeps its tiles and rotation (`IslandData.buildings[anchor] = {type, cells, rotation}`), in saves too. Moving it keeps its rotation, and clicking any of its tiles selects it. If an older save holds fewer tiles than the building's footprint now has, `BuildingManager.migrate_footprints` re-fits it on load.

## The model

Author multi-tile models with the low-poly kit at true tile scale and set `true_tile_model = true`:

- Lay the model out for rotation 0, using `lowpoly_kit.TILE` (2 units) per tile. Neighbouring tile centres sit `TILE` apart along X (east), or at `(+-TILE/2, +-TILE*sqrt(3)/2)` diagonally. Blender +Y is north, as is Godot -Z.
- Put the origin at the **centroid of the footprint's tile centres**, on the anchor tile's ground. For the dock's line of three that's the middle (pier) tile's centre. For a triangle, it's the corner the three tiles share.
- The renderer then uses a fixed scale (`TILE` units per tile), puts the origin right there, and turns the model with the footprint. Parts may reach below the ground, like the dock's pilings standing on the seabed.
- Markers: `WorkSpot`, where the robot stands to work it (must be on a land tile; the robot walks to whichever footprint tile it falls on), `Footprint`, and `BoatSpot` (the dock's berth: the renderer hangs the salvage skiff off it, bow along the marker's +X, so it turns with the building and shows in the placement ghost).
- Preview it with `render_preview(true_tile=True, tiles=[...])`, one plinth per land tile centre, and `hex_tile()` for water or other preview tiles. [`tools/build_dock.py`](../tools/build_dock.py) is the reference.

While placing, a building with a model shows it as a see-through ghost, sized and turned exactly as the placed building will be, over a green (or red) cap on each tile. Only buildings without a model fall back to their flat billboard.

## Example: a big end-game building

A three-tile triangle on grass:

```gdscript
var foundry := BuildingDefinitionScript.new()
foundry.id = GameTypes.BuildingType.FOUNDRY  # add to the enum
foundry.display_name = "Foundry"
foundry.footprint = [Vector2i.ZERO, HexGridScript.AXIAL_EAST, HexGridScript.AXIAL_NORTH_EAST]
foundry.required_terrains = [GameTypes.Terrain.GRASS]
foundry.model = FOUNDRY_MODEL  # tools/build_foundry.py, origin at the shared corner
foundry.true_tile_model = true
```

The anchor is the south-west tile, east is the south-east tile, and north-east is the top tile. Their shared corner, the model's origin, sits at `(TILE/2, TILE*sqrt(3)/6)` from the anchor's centre. In Blender, with the origin there, the three tile centres are `(-1, -0.577)`, `(1, -0.577)` and `(0, 1.155)`.

## Checks

`tools/footprint_check.gd` covers shape rotation on both row parities, the dock's placement and auto-rotation, its work and boat spots, the robot's approach from the pier tile, the save round trip, and old-save migration:

```
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tools/footprint_check.gd
```

## Construction

Placing a building from the build menu puts down a **blueprint**, not a finished building. The
blueprint holds its footprint (nothing else can be placed there) and its cost is paid at placement,
but it produces nothing, draws or generates no power, doesn't count as a dock for trade routes, and
doesn't count toward quest construction objectives. In the island data it is an ordinary building
entry carrying `build_progress` (0 to 1); `IslandData.complete_construction` drops the key. Entries
without one (every save from before construction) load as finished.

- **The robot builds it.** Placing a blueprint sends the robot to its work spot (or a neighbouring
  tile), and it starts building on arrival, playing the wrench *Build* clip. Construction takes
  `BuildingDefinition.build_seconds` of work (6 by default). If the robot is already building or
  heading to another blueprint, the new one waits. When it finishes one, it walks to the nearest
  blueprint left on the island.
- **Interrupting** (sending the robot elsewhere, or *Pause building* in the command bar) leaves the
  blueprint and its progress in place. Progress is saved. The command bar offers *Build* or
  *Resume (N%)* while the robot is parked at a blueprint, and right-clicking one with the robot
  selected sends it back to work (the hover shows green).
- **Finishing** starts production and power use, counts the building for quests, and offers
  *Operate* immediately if the building needs power and the robot is standing at it.
- **Cancelling** a blueprint (the info panel's *Cancel (refund)*) refunds its full cost. Blueprints
  can't be moved; finished buildings still move instantly and for free.

On the map ([construction_site.gd](../scripts/island/construction_site.gd)), a blueprint is a teal
plate on its tiles and a teal hologram of the finished building
([construction_hologram.gdshader](../assets/shaders/construction/construction_hologram.gdshader)).
The real model is printed up through it from the ground to the current progress
([construction_reveal.gdshader](../assets/shaders/construction/construction_reveal.gdshader)): a
glowing seam marks the cut, the open top is capped in dim teal, and sparks fly from the seam while
the robot works. `tools/construction_check.gd` covers the whole flow:

```
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tools/construction_check.gd
```
