# Visual Improvements TODO

Improve terrain richness and island identity while retaining the calm, readable low-poly style
and clear construction plots. Most of this work can be done programmatically; new generated
texture images are not required. Concept PNGs in `art/concept/` are visual references, not ground textures.

This is the implementation checklist for the design notes in
[Island Visual Variety](island-visual-variety.md). Everything here is visual only: it must not
change walkability, dock sites, resource placement, or save data. Work that does change those is
listed under [Generator work](#generator-work-tracked-separately) and needs its own design first.

## Baseline rendering setup (before Pass 1)

| Element | Current implementation |
| --- | --- |
| Ground | One `MeshInstance3D` per cell, sharing a code-generated hex prism scaled to the terrain height |
| Terrain appearance | Flat-colour `StandardMaterial3D` per terrain type; no ground texture images |
| Elevation | One fixed height per terrain type (`SAND_TOP_Y`, `GRASS_TOP_Y`, `STONE_TOP_Y`) |
| Hover and discovery | Swap the tile's `material_override` to a per-terrain highlight material or a shared silhouette material |
| Grid | Single translucent unshaded mesh, toggled by `show_grid` |
| Water | Shader using existing noise images plus programmatically generated land masks and shoreline-distance textures |
| Picking | Ray maths against per-terrain heights (`cell_from_ray`), not physics |
| Buildings and resources | Imported `.glb` models, with Blender builders and a shared material palette |
| Island layout | Seeded procedural generation controlled by island profiles |

Relevant files:

- `scripts/island/island_renderer.gd`: terrain meshes, materials, hover, water, and grid rendering.
- `scripts/island/island_generator.gd`: island generation.
- `scripts/island/island_profile.gd` and `island_profiles.gd`: terrain and resource contracts.
- `tools/lowpoly_kit.py`: shared model primitives and palette.
- `docs/building-style-palette.md`: current model style and materials.
- `docs/island-visual-variety.md`: visual-profile design notes.

## Ground rules

- **Mobile renderer first.** Sample a noise texture (the existing water noise or a `NoiseTexture2D`
  baked at load) rather than computing noise per fragment.
- **No per-node decoration.** Use one `MultiMeshInstance3D` per mesh/material combination per
  island: grass and pebbles need separate batches. Measure terrain draw calls in the actual renderer.
- **World-space shading.** The current shared prism has no UVs. World position and world normal
  give continuous patterns and consistent scale across tiles; height scaling would otherwise
  stretch side-face mapping (not necessarily top mapping).
- **Generate once.** Masks, scatter, and palettes are built when an island loads or changes,
  never per frame.

## Pass 0: baseline

- [x] Add a repeatable screenshot capture: fixed seed, fixed camera, starter island and one mining
  island, at normal gameplay zoom and close zoom. Capture the "before" set now; every later pass
  is compared against it.
- [x] Record frame time, rendering CPU/GPU time, and draw calls alongside the screenshots at
  the same resolution and camera settings, including an overview with several revealed islands.
- [x] Rough lighting pass: set sun direction, sun colour, and ambient so objects feel grounded and
  keep their authored palette. Palettes below are tuned under this light, so settle it before them.
- [x] Reduce grid prominence during ordinary play and strengthen it during placement. The grid is
  already a single mesh with one material, so this is a cheap, visible win.

## Pass 1: terrain shader

- [x] Replace the per-terrain `StandardMaterial3D`s with one terrain shader. Terrain type and
  palette come in as parameters.
- [x] Move hover, action-hover, and discovery silhouette into per-tile `instance uniform`s on that
  shader (supported on the Mobile renderer) instead of swapping `material_override`. This removes
  the `_highlight_materials` and `_action_highlight_materials` caches and the silhouette material.
  Verify hover, action hover, and unexplored islands look as they do today before moving on.
- [x] Tops: coherent, low-contrast colour patches spanning adjacent hexes, from broad world-space
  noise — grass/moss/soil on grass, weathering on stone, restrained close-up detail.
  No random per-tile colours and no visible texture repetition.
- [x] Sides: use the world normal to give exposed sides darker soil or layered rock, banded by height.
- [x] Waterline: darken side faces in a band just above `WATER_TOP_Y`. Sand tops sit well above the
  water, so a wet band on the sides reads better than wet tops.
- [ ] Optionally lighten or darken the outer edge of sand tops using the existing shoreline-distance
  data, if the waterline band alone isn't enough.

Passes 0–1 implemented on 2026-10-05. Captures and measured results are recorded in
[the terrain comparison report](terrain-visual-pass-1.md). The shader uses one shared seamless
`NoiseTexture2D` generated at load; the existing water noise produced visible tiling seams in
ground close-ups. Base palettes are currently renderer parameters; visual-profile data is Pass 2.

## Pass 2: palettes as data

- [ ] Add a visual profile (or visual skin field) alongside `IslandProfile`, holding the terrain
  shader's palette parameters. Keep the gameplay contract in `IslandProfile`.
- [ ] Derive profile selection from a stable existing seed/coordinate and biome, without adding
  save fields. A reload must retain the same visual identity.
- [ ] Author two palettes: starter and one mining island. Keep terrain and resource types legible.
- [ ] Compare against the baseline screenshots.

## Pass 3: decoration scatter

- [ ] Add small reusable meshes: pebbles, grass tufts, shoreline stones.
- [ ] Seeded scatter by terrain and context: pebbles near rocks, tufts at forest edges, stones on
  shorelines. Decorations must be clearly smaller and quieter than resources.
  Seed each cell independently so building changes do not rearrange decoration elsewhere.
- [ ] Building rule: decorations are hidden under building footprints and blueprints, and the
  scatter for an island is rebuilt when buildings are placed or removed.
  Removing a building restores the same seeded scatter.
- [ ] Check picking, hover, placement preview, and robot movement with scatter on; picking is
  ray maths, so decorations should not interfere, but confirm.
- [ ] Check frame time on the Mobile renderer with scatter on the largest current island and
  in the overview with several revealed islands. Measure rebuild time on placement/removal;
  narrow updates to affected cells if full-island rebuilds cause hitches.

## Pass 4: island identity

- [ ] Subtle worn ground around workshops and the crash site, as a procedural mask fed to the
  terrain shader.
- [ ] Basalt, limestone, and rusty ironstone visual profiles for the existing mining resource
  contracts: palette, rock silhouettes, and scatter set. No change to resource mechanics.
- [ ] One landmark per island family, starting with the mining island. Landmarks must fit outside
  usable construction plots without obscuring routes, resources, or docks, and must not look like
  functional buildings. Empty cells are not automatically unusable cells. If a suitable site
  requires reserving land or changing layout, move that landmark to generator work first.
- [ ] Compare against the baseline screenshots.

## Final polish

- [ ] Fine-tune sun and ambient against the finished palettes.
- [ ] Keep shoreline foam and water motion restrained and consistent with the calm art direction.
- [ ] Evaluate optional authored textures only if a specific painted look cannot be achieved well
  with procedural materials. Avoid the dense flowers and bright water of the concept previews.

## Generator work (tracked separately)

These change layout, walkability, or saves, so they belong with
[Island Generation](island-generation.md) and need their own design before starting:

- Breaking up the uniform sand border with rocky stretches, pebble beaches, and coves
  (affects walking routes and dock sites).
- Varied island silhouettes: crescents, elongated headlands, uneven beach widths. Must preserve
  connected walking routes, dock sites, required resources, and construction space.
- Decorative back-edge ridges and shelves.
- Per-cell elevation. `get_step_height`, `cell_from_ray`, building placement, resource positioning,
  and save data all assume one height per terrain type today.

## Asset requirements

| Improvement | Preferred method | New images required? |
| --- | --- | --- |
| Grass, dirt, and moss patches | Terrain shader with world-space noise | No |
| Stone weathering and cracks | Subtle procedural shader patterns | No |
| Soil sides and rock layers | Same shader, by world normal and height | No |
| Waterline and wet sand | Height band, optionally shore-distance data | No |
| Pebbles, tufts, and small rocks | Reusable meshes, seeded MultiMesh scatter | No; some mesh assets |
| Biome identity | Palette, scatter, and landmark profiles | No; one landmark model per family |
| Detailed flowers, shells, or painted patterns | Optional texture atlas or small meshes | Possibly, later |
