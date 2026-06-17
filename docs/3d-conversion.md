# 3D Conversion Plan

An implementation plan for moving Resource Isles from its current 2D presentation
(immediate-mode `_draw()` on `Node2D`, `Camera2D`) to a 3D one (`Camera3D`, code-generated
hex terrain, sprites as billboards). This is **direction, not yet implemented**.

Unlike the other docs here, this is engineering direction rather than game design — the
gameplay does not change at all. The target is a **2.5D** build: a real 3D camera and
code-generated hex terrain, but the existing 2D art reused as upright billboards. The path
to full 3D models is noted where it differs.

See also: [Player Unit and Manual Gathering](player-unit-and-manual-gathering.md) for the
robot's movement and verbs (the unit being converted in Phase 3), and the
[README](../README.md) for the overall structure.

## The Core Idea

The game is already cleanly split. The **simulation layer operates entirely on `Vector2i`
hex cells** — logical grid coordinates, never pixels. Nothing in `island_data`, `hex_grid`,
`hex_pathfinder`, `island_generator`, `building_manager`, `production_manager`,
`power_manager`, `resource_manager`, `quest_manager`, or `world_data` touches rendering
coordinates. The only float `Vector2` uses in the sim are worldgen distance math (grid-space)
and the `visual_size_tiles` / `visual_offset_tiles` fields, which are *tile fractions* and
map directly onto 3D XZ scale.

So this is **not a rewrite of the game**. It is a rewrite of the **presentation layer**,
concentrated in four files: [`island_renderer.gd`](../scripts/island/island_renderer.gd),
[`player_unit.gd`](../scripts/player/player_unit.gd), [`main.gd`](../scripts/main.gd) (camera
and input), and [`floating_text.gd`](../scripts/ui/floating_text.gd).

**Guiding rule:** keep `IslandRenderer`'s public interface stable — `render`,
`get_cell_center`, `cell_to_world`, `set_hovered_world_position`, `try_place_hovered_building`,
`get_hovered_building_type`, `hovered_cell`. If those keep their names, `main.gd`,
`player_unit.gd`, and the UI barely notice the change; only the *return types* shift from
`Vector2` to `Vector3`.

## What Carries Over Unchanged

- **All sim/logic scripts** above — zero changes. Saves (cell/inventory data) are unaffected,
  so there is no save-format break.
- **The entire UI layer.** Every panel is `CanvasLayer` / `Control`: `resource_bar`,
  `building_menu`, `building_info_panel`, `action_bar`, `quest_log_view`,
  `quest_tracker_view`, `world_map`, `toast`, `screen_fade`. 3D does not touch them.
- **The hex coordinate system.** `hex_grid.gd` (odd-r offset neighbors, the corner math) is
  dimension-free; only the `cell → world` mapping changes.

## What Gets Rebuilt

The one piece that genuinely does not port is the hand-drawn water (the shimmer and
shoreline foam in `island_renderer.gd`); it is rebuilt as a shader on a water plane. The
manual depth-sort of drawn objects is *deleted* — the 3D depth buffer replaces it for free.

## Phases

Sequenced so the game stays runnable at the end of each phase. Phases 0–1 are low-risk and
make everything downstream concrete; Phase 2 holds essentially all the risk.

### Phase 0 — Scaffolding (~½ day)

Goal: the 3D scene boots with a camera; nothing is drawn yet.

- `project.godot`: Jolt 3D physics is already enabled; keep the `mobile` renderer.
- [`game.tscn`](../game.tscn): root `Node2D` → `Node3D`.
- [`main.gd`](../scripts/main.gd): `extends Node2D` → `extends Node3D`.
- Add a `WorldEnvironment` and a `DirectionalLight3D` (sun) so meshes are lit.

Breaking: `position` / `global_position` on the root and its children become `Vector3`.
Compiles, renders nothing — expected.

### Phase 1 — Coordinate mapping (~½ day, the keystone)

Everything downstream depends on this. Port `cell_to_world` from the renderer with Y → Z:

```gdscript
func cell_to_world(cell: Vector2i) -> Vector3:
    return Vector3(
        (cell.x + _row_column_offset(cell.y)) * cell_size.x,
        0.0,
        cell.y * cell_size.y * 0.75
    )
```

`get_cell_center` returns a `Vector3` (center on XZ, Y at tile-top height). `_row_column_offset`
and all of `hex_grid.gd` stay exactly as they are.

### Phase 2 — Terrain renderer (~2–4 days, the big one)

Rewrite [`island_renderer.gd`](../scripts/island/island_renderer.gd). It stops being a
`Node2D` with `_draw()` and becomes a `Node3D` that spawns and pools mesh instances.

- Build **one shared hex-prism mesh** with `SurfaceTool` (top cap + 6 side quads), reusing the
  same corner math as `hex_grid.hex_points`. Alternatively, a `CylinderMesh` with
  `radial_segments = 6` and equal top/bottom radii *is* a hex prism with no custom geometry —
  fine for prototyping.
- Instance the prism per cell at `cell_to_world(cell)`, tinted by terrain. Reuse the existing
  `GRASS_COLOR` / `SAND_COLOR` / `STONE_COLOR` constants as material albedos.
- **Elevation for free:** grass prisms taller than sand, water lowest — layered island look,
  no extra art.
- If perf needs it, use `MultiMeshInstance3D` per terrain type (thousands of identical tiles
  in one draw call).
- **Water:** the hand-drawn shimmer and shoreline foam become a flat plane + a `ShaderMaterial`
  (or a flat stub initially). This is the only piece that is rebuilt rather than ported.
- **Grid / hover / placement preview:** the `_draw`-based overlays become a ground
  decal/shader or thin outline meshes. Hover = highlight the prism material; placement preview
  = tinted ghost meshes over the footprint cells.
- **Deleted:** the manual `_draw_sorted_objects` y-sort — the depth buffer handles ordering.

Buildings and resource nodes (still owned by the renderer) each become a `Sprite3D` billboard
using the **existing textures**, positioned at the cell and scaled by the existing
`visual_size_tiles` / `visual_offset_tiles` fields.

> **Full-3D upgrade path:** swap each `Sprite3D` for a model `MeshInstance3D`. Nothing else in
> the renderer changes, so this is incremental and can come later.

### Phase 3 — Player unit (~½ day)

[`player_unit.gd`](../scripts/player/player_unit.gd): `Node2D` + `_draw()` → `Node3D` with a
`Sprite3D` child for the robot texture and a flat ring mesh/decal replacing the drawn ground
marker. The movement loop in `_process` is unchanged logic — just `Vector2` → `Vector3` and
drop `queue_redraw()`.

### Phase 4 — Camera, input, and picking (~1–2 days)

In [`main.gd`](../scripts/main.gd):

- `Camera2D` → `Camera3D`, mounted on a pivot `Node3D` for a tilted top-down / orbit view.
- **Zoom:** `camera.zoom` → camera distance along local Z (or FOV).
- **Pan:** the drag handler moves the pivot on the XZ plane.
- **Picking (the real change):** today `world_to_cell` takes a `Vector2` from
  `get_global_mouse_position()`. In 3D, raycast from `camera.project_ray_origin` /
  `project_ray_normal` onto the ground plane (Y = 0), then feed the resulting XZ into a 3D
  `world_to_cell`. Jolt is enabled, so this can hit tile colliders, but plain plane-intersection
  math is cheaper and recommended.
- `_center_camera` repositions the pivot instead of a `Camera2D`.

### Phase 5 — Floating text (~½ day)

[`floating_text.gd`](../scripts/ui/floating_text.gd): `Node2D` → `Label3D` (billboarded,
world-anchored), or keep it 2D and project the cell's 3D position to screen. The UI layer
needs no other changes.

## Effort Summary

| Phase | Files | Effort |
| --- | --- | --- |
| 0 Scaffolding | game.tscn, main.gd, project | ½ day |
| 1 Coordinate mapping | hex_grid / renderer | ½ day |
| 2 Terrain + water + billboards | island_renderer.gd | 2–4 days |
| 3 Player unit | player_unit.gd | ½ day |
| 4 Camera + picking | main.gd | 1–2 days |
| 5 Floating text | floating_text.gd | ½ day |
| — UI | (none) | 0 |

**~1–1.5 weeks for a working 2.5D build that reuses all current art.** No save-format break,
no sim-logic break. The only genuinely new authoring is the water shader; the only real risk
concentration is Phase 2.

## Risks and Notes

- **Water shader** is the single piece with no 2D equivalent to port. Stub it flat first; treat
  the shader as polish.
- **Pointy-top vs flat-top orientation.** The current layout is pointy-top
  (`hex_points` puts a corner at top-center). A generated prism may need a 30° Y rotation to
  match; verify against `hex_grid.neighbor` directions so picking and rendering agree.
- **Art is the larger half of *full* 3D.** Code-generated terrain needs no art, but real 3D
  buildings/resource nodes/robot/boat need models. The 2.5D billboard approach defers all of
  that — which is why it is the recommended first target.
