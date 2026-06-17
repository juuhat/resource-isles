# 3D Conversion

How Resource Isles moved from a 2D presentation (immediate-mode `_draw()` on `Node2D`,
`Camera2D`) to a 3D one (`Camera3D`, code-generated hex terrain, sprites as billboards).
The **2.5D milestone is implemented** — a real 3D camera and code-generated hex terrain,
with the existing 2D art reused as upright billboards. The path to full 3D models is noted
where it differs.

Unlike the other docs here, this is engineering record rather than game design — the
gameplay did not change at all. See the *What's Left* section at the end for the remaining
polish and the full-3D upgrade path.

See also: [Player Unit and Manual Gathering](player-unit-and-manual-gathering.md) for the
robot's movement and verbs, and the [README](../README.md) for the overall structure.

## The Core Idea

The game was already cleanly split. The **simulation layer operates entirely on `Vector2i`
hex cells** — logical grid coordinates, never pixels. Nothing in `island_data`, `hex_grid`,
`hex_pathfinder`, `island_generator`, `building_manager`, `production_manager`,
`power_manager`, `resource_manager`, `quest_manager`, or `world_data` touches rendering
coordinates. The only float `Vector2` uses in the sim are worldgen distance math (grid-space)
and the `visual_size_tiles` / `visual_offset_tiles` fields, which are *tile fractions* that
map directly onto 3D XZ scale.

So this was **not a rewrite of the game**. It was a rewrite of the **presentation layer**,
concentrated in four files: [`island_renderer.gd`](../scripts/island/island_renderer.gd),
[`player_unit.gd`](../scripts/player/player_unit.gd), [`main.gd`](../scripts/main.gd) (camera
and input), and [`floating_text.gd`](../scripts/ui/floating_text.gd).

**Guiding rule (held):** `IslandRenderer`'s public interface stayed stable so `main.gd`,
`player_unit.gd`, and the UI barely changed; mostly the return types shifted from `Vector2`
to `Vector3`. Two methods were renamed during the work: `set_hovered_world_position(Vector2)`
became `set_hovered_from_ray(origin, direction)` (the camera now passes a ray, not a screen
point), and the old `queue_redraw()` contract became `refresh()`.

## What Carried Over Unchanged

- **All sim/logic scripts** above — zero changes. Saves (cell/inventory data) are unaffected;
  there was no save-format break.
- **The entire UI layer.** Every panel is `CanvasLayer` / `Control`: `resource_bar`,
  `building_menu`, `building_info_panel`, `action_bar`, `quest_log_view`,
  `quest_tracker_view`, `world_map`, `toast`, `screen_fade`. 3D does not touch them — the
  world-map mini widget still draws in 2D via `_draw()` inside its `CanvasLayer`, which is
  valid in a 3D scene.
- **The hex coordinate system.** `hex_grid.gd` (odd-r offset neighbors, the corner math) is
  dimension-free; only the `cell → world` mapping was added.

## Status by Phase

All six phases are **done**. What was actually built, and where it diverged from the
original plan:

### Phase 0 — Scaffolding ✅

- [`game.tscn`](../game.tscn): root `Node2D` → `Node3D`.
- [`main.gd`](../scripts/main.gd): `extends Node3D`; `_setup_camera_and_light()` builds a
  `Camera3D` on a pivot, a `DirectionalLight3D` sun, and a `WorldEnvironment` (sky color +
  ambient). Jolt 3D physics was already enabled; the `mobile` renderer is kept.

### Phase 1 — Coordinate mapping ✅

Added as **static helpers in [`hex_grid.gd`](../scripts/island/hex_grid.gd)** rather than
mutating the renderer, so the change was non-breaking and landed first on its own:
`cell_to_world_3d`, `cell_center_3d`, and `hex_corners_3d` (the ground-plane corner ring, in
the same winding as the 2D `hex_points`). They mirror the pointy-top, odd-r layout exactly,
placing cells on the XZ plane with Y left at 0 for the caller to raise by tile height.

### Phase 2 — Terrain renderer ✅

[`island_renderer.gd`](../scripts/island/island_renderer.gd) rewritten as a `Node3D` that
spawns mesh instances:

- **One shared hex-prism `ArrayMesh`** built with `SurfaceTool`, with **explicit per-face
  normals** (up for the cap, outward for walls) for crisp flat shading — `generate_normals()`
  smoothed the cap into the walls and made each tile read as a rounded, shaded bump.
- One `MeshInstance3D` per cell, positioned at the **cell center** (the prism mesh is centered
  on its origin) and scaled in Y by terrain height (water 6 → sand 14 → grass 20 → stone 26).
- Terrain tinted by reusing the `GRASS_COLOR` / `SAND_COLOR` / `STONE_COLOR` constants as
  material albedos; `cull_mode = CULL_DISABLED` makes it robust to winding.
- **Grid:** a single `PRIMITIVE_LINES` mesh tracing the top hexagon of every land cell, just
  above each tile top, toggled by `set_show_grid()` (SPACE).
- **Hover:** the cell under the cursor is **recolored in place** (a brightened terrain
  material), restoring the previous cell — no floating overlay mesh.
- **Placement preview:** flat hex-cap markers (green/red) over the footprint plus a
  translucent ghost building billboard.
- Buildings, resource nodes, ground items, and dock boats are **`Sprite3D` billboards**
  (`BILLBOARD_FIXED_Y`, alpha-scissor) reusing the existing textures, sized by
  `visual_size_tiles`. The manual depth-sort is gone — the depth buffer handles ordering.
- **Water (Civ-style, data-driven):** water is classified into two real terrain types at
  island-gen time — `COAST` (shallow, within `COAST_RINGS` of land) and `WATER` (deep ocean) —
  by a multi-source flood from land in `island_generator._classify_coastal_water`. Both render
  as flat hex tiles like land (short prisms at water height), colored light/dark from the
  classification, and they're full tiles: hoverable, selectable, and available to gameplay
  (docks require `COAST` adjacency; pathfinding treats both as non-walkable via
  `GameTypes.is_water`). Two animated water shaders ([`water.gdshader`](../assets/shaders/water.gdshader),
  [`water_depth.gdshader`](../assets/shaders/water_depth.gdshader)) and the shader-plane path in
  `_rebuild_water` are **parked** — kept for an optional animated surface layer over the tiles.

### Phase 3 — Player unit ✅

[`player_unit.gd`](../scripts/player/player_unit.gd): `Node3D` holding the robot **3D model**
(`player_model.glb`, instantiated and scaled to the on-map size; feet at origin so it stands on
the tile) and a flat `CylinderMesh` disc as the selection/ground marker. Movement loop is the
same logic in `Vector3`, and the model smoothly turns to face its travel direction
(`_face_direction`, `turn_speed`). The model is static (no animations yet), so it slides
rather than walks.

### Phase 4 — Camera, input, and picking ✅

In [`main.gd`](../scripts/main.gd): `Camera3D` on a pivot at a fixed 55° pitch; wheel zoom →
pivot-to-camera distance; drag → pivot pan on XZ; `_center_camera()` frames the island via
`get_map_center()` / `get_map_radius()`. **Picking is height-aware:** it intersects the
camera ray with the land plane for an approximate cell, then re-intersects at that cell's
actual top height (`cell_from_ray`) so the hover lands on the tile under the cursor regardless
of elevation.

### Phase 5 — Floating text ✅

[`floating_text.gd`](../scripts/ui/floating_text.gd): `Node2D` + `_draw()` → a billboarded
`Label3D` that rises and fades, then frees itself.

## What's Left

The 2.5D build is complete and playable. Remaining items are polish or the full-3D path —
none block play:

- **Grid line thickness.** 3D `PRIMITIVE_LINES` render at 1px regardless of zoom, so the grid
  looks thin when zoomed out. A bolder, zoom-stable grid needs thin quad strips along each edge
  or baking the grid into the tile material/shader.
- **Terrain batching (perf).** Terrain is one `MeshInstance3D` per cell. Fine for current
  island sizes, but `MultiMeshInstance3D` per terrain type would collapse it to a few draw
  calls if islands grow. (In-place hover recolor would then need a shader param instead of a
  material swap.)
- **Lighting polish.** The `DirectionalLight3D` has no shadows enabled, and `ambient_light_energy`
  is a flat `0.5`. Enabling shadows and tuning ambient would add depth; bigger elevation gaps
  make the darker side walls more prominent and want more ambient to compensate.
- **Camera rotation.** Yaw is fixed (no orbit-around control), pitch is a constant. A rotate
  binding is easy to add on the pivot if wanted.
- **Full 3D models (the upgrade path).** The robot is now a real 3D model
  (`player_model.glb`); buildings, resource nodes, and the boat are still billboards. Swapping
  each remaining `Sprite3D` for a model is isolated inside the renderer — incremental, and the
  larger cost is the art (modeling each asset), not code.

## Notes for Future Work

- **Pick-plane refinement** assumes roughly flat-topped tiles at known heights; if terrain ever
  gets per-cell variable height, switch to a physics raycast against tile colliders (Jolt is
  enabled) instead of the plane-intersection refine.
- **Coordinate parity:** terrain, units, objects, grid, hover, and picking all resolve through
  `cell_center_3d`. Anything new must use the cell *center*, not the `cell_to_world` anchor, or
  it will sit half a tile off (the bug that made early hover target the wrong row).
