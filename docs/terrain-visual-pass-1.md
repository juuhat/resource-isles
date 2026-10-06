# Terrain visual pass 1

Implemented the baseline and terrain-shader passes from [the visual TODO](visual-improvements-todo.md)
on 2026-10-05. Before images were captured from gameplay code at `c23ade2`, before the shader,
lighting, and grid changes in this pass.

## Changes

- One terrain shader with cached per-terrain materials and world-space surface patterns.
- A shared seamless 512 × 512 noise texture generated at load, with mipmaps for distant views.
  No authored texture images were added.
- Muted olive grass with soil patches, weathered grey stone, and softly varied warm sand.
- Darker soil/rock sidewalls, subtle height bands, and damp side faces at the waterline.
- Per-instance hover and discovery flags; adjacent tiles continue sharing their materials.
- Quieter grid in play (alpha 0.045), stronger grid while placing (0.18), preserving the grid toggle.
- Warm sunlight with a cooler ambient fill; sun direction retained after the baseline review.

Terrain geometry, picking heights, resource layout, walkability, and saved data are unchanged.
Visual profiles, decoration scatter, and landmarks remain on the TODO for subsequent passes.
Optional sand-top shoreline shading is deferred; this pass uses the side-face waterline band.

## Images

| View | Before | After |
| --- | --- | --- |
| Starter, normal zoom | [Before](../art/previews/terrain/before/starter_normal.png) | [After](../art/previews/terrain/after/starter_normal.png) |
| Starter, close zoom | [Before](../art/previews/terrain/before/starter_close.png) | [After](../art/previews/terrain/after/starter_close.png) |
| Mining, normal zoom | [Before](../art/previews/terrain/before/mining_normal.png) | [After](../art/previews/terrain/after/mining_normal.png) |
| Mining, close zoom | [Before](../art/previews/terrain/before/mining_close.png) | [After](../art/previews/terrain/after/mining_close.png) |
| Seven-island overview | [Before](../art/previews/terrain/before/overview.png) | [After](../art/previews/terrain/after/overview.png) |

Additional rendered checks:
[ordinary hover](../art/previews/terrain/after/hover_normal.png),
[action hover](../art/previews/terrain/after/hover_action.png),
[placement](../art/previews/terrain/after/placement.png),
[discovery silhouette](../art/previews/terrain/after/unexplored.png), and
[shoreline sidewalls](../art/previews/terrain/after/shore_side.png).
The silhouette capture deliberately toggles only the island renderer, so the separately rendered robot remains visible.

## Performance sample

Godot 4.6.3, Mobile/D3D12, AMD Radeon RX 9070 XT, 1600 × 900, seed 1, VSync disabled.
Each view warms for 120 frames, then samples 120 frames. Seven islands are revealed.
Discovery fades finish before sampling; scene processing is frozen so gameplay and camera motion
do not alter the views. Shader water animation still runs, so the water pixels are not identical.

| View | Draw calls, before → after | GPU render ms, before → after | Mean wall frame ms, before → after |
| --- | --- | --- | --- |
| Starter normal | 1138 → 1138 | 0.434 → 0.537 | 0.810 → 0.989 |
| Starter close | 941 → 941 | 0.433 → 0.538 | 0.809 → 0.981 |
| Mining normal | 886 → 886 | 0.360 → 0.455 | 0.694 → 0.869 |
| Mining close | 689 → 689 | 0.349 → 0.454 | 0.684 → 0.857 |
| Overview | 2875 → 2875 | 0.908 → 0.899 | 1.621 → 1.805 |

Draw calls are unchanged. Play-view GPU time increased by about 0.10 ms in this sample.
These are short desktop rendering samples, not mobile-device or full gameplay benchmarks;
timings include run-to-run scheduling and GPU clock variation. CPU rendering measurements
and frame-time p95 are included in the raw [before](../art/previews/terrain/before/metrics.json)
and [after](../art/previews/terrain/after/metrics.json) reports.

## Validation

Passed `terrain_material`, `action_hover`, `world_discovery`, `placement_preview`, and
`robot_access` checks using the isolated-save check runner. The terrain regression covers
independent hover on shared materials, hover reset, discovery/rebuild state, coast visibility,
grid strength/toggle behavior, picking at terrain heights, and unchanged serialized island data.
Rendered captures compiled successfully and were visually inspected on Mobile/D3D12.

The repeatable capture tool is `tools/terrain_visual_capture.gd`. It creates a fixed-seed game
with save loading/writing disabled, takes an output directory as its first user argument, and
optionally accepts `--interactions` for the extra visual checks. Store future runs in a new folder
under `art/previews/terrain/` to preserve the baseline. `.gdignore` prevents importing review images
as game assets. This workflow is documented here rather than in the project launch README.
