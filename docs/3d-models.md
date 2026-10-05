# 3D Models

The [Low Poly Workshop art direction](building-style-palette.md) and
[Icons and 2D art](icons-and-2d-art.md) define the shared model/icon palette and style.
New flat art should match approved model renders rather than legacy painted sprites.

The player now uses the scripted cream-and-teal salvage robot with idle/walk clips. See
[Player model](player-model.md) for its rig, source, previews, and rebuild instructions.

How 3D presentation works in Resource Isles and how to add a 3D model. This is the
**integration / code** side; for *generating* the assets (Meshy prompts, style, export
settings) see [meshy-guide.md](meshy-guide.md).

The game runs a real 3D scene — `Camera3D`, code-generated hex terrain, a 3D player robot —
while most map objects are still upright billboards reusing the 2D art. Models are swapped in
**one asset at a time**: a definition gains a `model`, and the renderer instances it instead
of the flat texture. Nothing in the simulation layer is involved — adding a model is purely a
presentation change.

See also: [Player Unit and Manual Gathering](player-unit-and-manual-gathering.md) for the
robot, and the [README](../README.md) for overall structure.

## How the scene is built

The presentation layer lives in four files:
[`island_renderer.gd`](../scripts/island/island_renderer.gd) (terrain, objects, water, grid,
hover, placement preview), [`player_unit.gd`](../scripts/player/player_unit.gd) (the robot),
[`main.gd`](../scripts/main.gd) (camera, input, picking), and
[`floating_text.gd`](../scripts/ui/floating_text.gd) (world-anchored popups).

- **Coordinate mapping.** Static helpers in [`hex_grid.gd`](../scripts/island/hex_grid.gd):
  `cell_to_world_3d`, `cell_center_3d`, `hex_corners_3d`. They place pointy-top, odd-r cells on
  the XZ plane with Y at 0 for the caller to raise by tile height. **Everything new must anchor
  to the cell *center* (`cell_center_3d`), not the `cell_to_world` top-left anchor**, or it sits
  half a tile off.
- **Terrain.** One shared hex-prism `ArrayMesh` (built with `SurfaceTool`, explicit per-face
  normals for crisp flat shading), one `MeshInstance3D` per cell, scaled in Y by terrain height
  (water 6 → sand 14 → grass 20 → stone 26) and tinted by the terrain color constants.
- **Camera.** `Camera3D` on a pivot; wheel zoom changes pivot-to-camera distance and pitch
  (low ~45° hero angle close in, tilting toward top-down when zoomed out). Picking is
  height-aware: ray-vs-land-plane for an approximate cell, then re-intersect at that cell's
  actual top height (`cell_from_ray`).
- **Objects.** Resource nodes, buildings, ground items, and the dock boat are drawn by
  `_rebuild_objects`. Each is either a flat **`Sprite3D` billboard** (the 2D texture) or, when a
  definition supplies one, a **3D model** via `_spawn_model`.

The unit of scale is large: **a hex tile is `cell_size = 128` world units wide** and tiles are
~6–26 units tall. Keep this in mind for anything sized in world units (see the `Label3D` gotcha
below).

## Definition fields that drive a model

Both [`ResourceNodeDefinition`](../scripts/resources/resource_node_definition.gd) and
[`BuildingDefinition`](../scripts/buildings/building_definition.gd) carry the same visual
fields:

| Field | Meaning |
| --- | --- |
| `texture` | Flat 2D art. Used as the billboard, and as the fallback when no model is set. Buildings with a model show a render of it in the build menu instead; the texture is the menu art only for buildings without one. |
| `model` | Optional `PackedScene` (a `.glb`/`.gltf`). When set, the renderer instances it **instead of** the texture. |
| `visual_size_tiles` | Target footprint in tiles. The model is uniformly scaled so its **width spans `visual_size_tiles.x * cell_size`**. `1.0` ≈ one hex. |
| `visual_offset_tiles` | XZ nudge from the footprint center, in tiles. |
| `visual_rotation_y` | Heading in **degrees** around Y, applied when instancing the model. |

## What `_spawn_model` does

`_spawn_model(scene, cells, size_tiles, offset_tiles, rotation_y_degrees)` in
[`island_renderer.gd`](../scripts/island/island_renderer.gd) normalizes an arbitrarily-scaled,
arbitrarily-centered model at runtime:

1. Instantiates the scene and applies `visual_rotation_y` **first**.
2. Measures the (rotated) world AABB (`_instance_aabb`, merged over all child `MeshInstance3D`s).
3. Uniformly scales so the AABB width (`max(x, z)`) spans `size_tiles.x * cell_size.x`.
4. Positions at the footprint's ground center (+ `offset`) and lifts by the bounds' min-Y so the
   model's **lowest point rests on the tile**.

Because the lift is derived from the measured AABB, models with different origins (feet at
`y=0` vs vertically centered) both land correctly without a hand-tuned offset.

> The player robot is the exception: [`player_unit.gd`](../scripts/player/player_unit.gd) does
> **not** use `_spawn_model`. It hard-codes `MODEL_NATIVE_HEIGHT` and a `MODEL_YAW_OFFSET`
> because it also needs a facing direction it can turn during movement. New static map objects
> should go through `_spawn_model`.

## Adding a 3D model

1. Generate/clean the asset per [meshy-guide.md](meshy-guide.md) and drop the `.glb` under
   `assets/models/` (Godot writes the `.import` on next editor load).
2. `preload` it in the relevant database and assign it to the definition's `model`:
   - Resource nodes → [`resource_node_database.gd`](../scripts/resources/resource_node_database.gd)
     (see `forest.model = PINE_FOREST_MODEL`, and `_add_deposit` for the rock deposits).
     Resource nodes take `true_tile_model` like buildings, plus `visual_yaw_variation` for a
     per-cell heading.
   - Buildings → [`building_definitions.gd`](../scripts/buildings/building_definitions.gd)
     (see `crashed_spaceship.model = CRASHED_SPACESHIP_MODEL`).
3. Tune the visuals on the definition:
   - `visual_size_tiles` — bump above `1.0` for landmarks that should spill past their tile
     (the spaceship uses `1.6`).
   - `visual_rotation_y` — set a heading so the model isn't grid-aligned (the spaceship uses
     `35°` for a crashed look).
   - `visual_offset_tiles` — only if it needs to sit off-center.
4. The renderer's existing `model != null` branch in `_spawn_resource` / `_spawn_building` picks
   it up automatically — no renderer changes needed. Keep the `texture` too: it stays as the
   fallback. The build menu, placement bar and placement ghost all switch to the model too.

## Current models vs billboards

- **Models:** the robot (`player_model.glb`), the forest (`pine_forest.glb`), the stone, iron
  coal and copper deposits (`resources/<stone|iron|coal|copper>_deposit.glb`, built by
  `tools/build_deposit.py -- <variant>`; `true_tile_model`s with their heading varied per cell by
  `visual_yaw_variation`), the crashed-spaceship building (`crashed_spaceship.glb`), and the dock
  (`dock.glb`, built by `tools/build_dock.py`), and the burner generator (`burner_generator.glb`,
  built by `tools/build_burner_generator.py`). The dock covers three tiles and is a
  `true_tile_model`: fixed scale, origin placed directly on the ground, turned with its footprint.
  See [Building footprints](building-footprints.md).
- **Ground items:** the robot's three lost tools (`assets/models/items/axe.glb`, `pickaxe.glb`,
  `wrench.glb`, built by `tools/build_robot_tools.py`) lie flat on their cells. Each keeps its
  classic head (bearded axe, pick with point and chisel, open-end wrench) on a robot-built handle:
  an iron socket plug with an amber status light that fits the robot's arm tool socket, teal
  collars, a timber grip wrap and a cream head housing. They are 0.3 tiles long, about two
  thirds of the 0.45-tile robot's height. `_spawn_item` places them at the fixed
  true-tile scale and turns each to an angle derived from its cell. `ITEM_TEXTURES` stays as
  the fallback for the axe and pickaxe (the wrench has no flat icon).
- **Boats:** the salvage skiff (`assets/models/boats/salvage_skiff.glb`, built by
  `tools/build_salvage_skiff.py`), tier 1 of the [robot-built boats](robot-built-boats.md). It is
  at true tile scale with its bow along +X and its origin on the waterline, and it carries
  `PilotSpot`, `DockPoint`, `CompanionSpot` and a spinnable `PropellerPivot` (about +X). The
  renderer moors one at every dock's `BoatSpot` (`_moor_boat`), on the dock's third tile. The
  world map's trade-route boats are still the code-built sailboat in `world_view.gd`.
- **Still billboards:** the remaining buildings. Swapping each
  is just dropping in an asset and setting `model` — the cost is the art, not code.

## Gotchas

- **`Label3D` pixel size.** `Label3D` defaults to `pixel_size = 0.005`, microscopic at this
  scene's scale, so a popup renders as an invisible speck. [`floating_text.gd`](../scripts/ui/floating_text.gd)
  sets `pixel_size = pixel_world_size` (currently `1.5`). Anything new using `Label3D` in-world
  needs the same.
- **Cell center, not anchor.** Terrain, units, objects, grid, hover, and picking all resolve
  through `cell_center_3d`. Using `cell_to_world` puts an object half a tile off.
- **Facing convention.** glTF forward is `-Z`, but generated models don't reliably honor it.
  `visual_rotation_y` is the per-asset fix for anything through `_spawn_model`; the robot has
  its own `MODEL_YAW_OFFSET`.

## Open question — model import pipeline

Models come from **Meshy** (AI generation) with likely **Blender** cleanup, and there's no
enforced convention yet, so each asset arrives at a different scale, orientation, and origin and
`_spawn_model` compensates at runtime. Worth standardizing:

1. **Normalize at export or at runtime?** Preferred: normalize in **Blender** — origin at the
   base/footprint center, forward = `-Z`, apply all transforms (scale = 1), real-world-ish units
   so a single scale rule works. That would let us drop the per-spawn AABB measure.
2. **Meshy export settings.** Confirm `.glb`, Y-up, and a consistent export scale.
3. **Blender cleanup pass.** Minimum: decimate/retopo for low, consistent poly counts; recenter
   origin; orient forward; apply transforms; possibly bake to vertex colors / a flat material to
   match the cel-style terrain (Meshy's baked PBR can clash).
4. **A documented per-model checklist** (scale, origin, forward, materials, naming) so new assets
   drop in predictably instead of being hand-tuned each time.

## Background — the 2D → 3D conversion

This presentation started in 2D (immediate-mode `_draw()` on `Node2D`, `Camera2D`) and moved to
3D without touching gameplay. The game was already cleanly split: the **simulation layer
operates entirely on `Vector2i` hex cells**, never pixels — `island_data`, `hex_grid`,
`hex_pathfinder`, `island_generator`, `building_manager`, `production_manager`, `power_manager`,
`resource_manager`, `quest_manager`, `world_data` all stayed unchanged, and saves were
unaffected. The entire `CanvasLayer` / `Control` UI carried over untouched (the world-map mini
widget still draws in 2D inside its `CanvasLayer`, which is valid in a 3D scene).

The conversion was concentrated in the four presentation files above. `IslandRenderer`'s public
interface was kept stable so callers barely changed (mostly `Vector2` → `Vector3` return types);
two methods were renamed — `set_hovered_world_position(Vector2)` → `set_hovered_from_ray(origin,
direction)` (the camera passes a ray now) and the old `queue_redraw()` contract → `refresh()`.

The water surface is a single translucent plane driven by a toon shader
([`water_toon.gdshader`](../assets/shaders/water_toon.gdshader)), built in `_rebuild_water` /
`_make_toon_water_material`. Everything keys off the distance to the nearest land hex: exact near
the shore (the shader tests the neighbouring cells against a per-cell land mask) and a coarse baked
`shore_distance` field further out. From that it draws banded shallow/mid/deep colours, a foam rim
tracing the hex coastline, swell lines rolling in toward the shore, and sparse offshore wave
strokes. Colours and animation are tuned in the shader's uniform defaults. Other deferred polish:
zoom-stable grid lines (3D `PRIMITIVE_LINES` are always 1px), terrain batching via
`MultiMeshInstance3D` if islands grow, shadow/ambient lighting tuning, and camera yaw/orbit
control.
