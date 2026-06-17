# Meshy 3D Model Guide

Notes for generating Resource Isles 3D models with Meshy or similar image-to-3D / text-to-3D
tools. The current game supports real 3D terrain and a 3D player model, while most buildings,
resource nodes, and boats are still `Sprite3D` billboards. Generated models should be made so
they can replace those billboards one asset at a time.

See also: [3d-conversion.md](3d-conversion.md).

## Best Workflow

Use the existing 2D PNG as a reference image whenever possible. The first good pine forest
result came from using `assets/resources/pine_forest.png` as a visual reference, then asking
Meshy to convert the silhouette, palette, and composition into a clean 3D model.

For best results:

1. Upload the matching 2D sprite as the reference image.
2. Tell Meshy to preserve the silhouette, color palette, and resource-node composition.
3. Explicitly say it should be a 3D model, not a flat billboard or image plane.
4. Ask for a stylized low-poly / hand-painted game asset.
5. Require a centered bottom pivot and no terrain base unless the asset truly needs one.

## Shared Style

Use this style language across prompts:

```text
Stylized low-poly / hand-painted 3D game asset for a cozy hex-tile resource strategy game.
Cute board-game proportions, clean chunky shapes, soft bevels, saturated colors, simple
materials, readable from an isometric camera at about 55 degrees. Avoid realism and tiny
fragile details.
```

The game reads best when assets are compact and icon-like. Prefer strong shapes over detail.

## Godot Requirements

Generated models should be easy to place at `cell_center_3d` in Godot.

Ask for:

- `glb` / `gltf` output when available.
- A single centered asset.
- Pivot/origin at the center bottom of the model.
- Upright vertical orientation suitable for Godot import.
- No terrain tile, ground base, or built-in hex unless explicitly needed.
- Clean topology and simple materials.
- Compact footprint that fits on one hex cell.
- Readability from the fixed 55-degree camera.

Avoid:

- Full environment scenes.
- Large landscape bases.
- Text, labels, signs, or UI markers.
- Photoreal materials.
- Thin branches, loose wires, or other tiny fragile pieces.
- Models that only look correct from one front-facing angle.

## Resource Node Prompt Template

```text
Create a stylized low-poly 3D game resource node for a hex-tile resource strategy game.

Use the reference image for composition, silhouette, color palette, and clustered resource-node
shape. Convert it into a clean 3D model, not a flat billboard.

Subject: <describe the resource node>.

Style: cute board-game / cozy city-builder style, stylized low-poly, hand-painted materials,
clean chunky shapes, soft bevels, saturated colors, strong readable silhouette.

Model requirements:
- Single centered asset intended to sit on the center of one hex tile.
- Pivot/origin at the center bottom of the model.
- Upright vertical orientation suitable for Godot import.
- Compact one-tile footprint.
- Readable from an isometric camera at about 55 degrees.
- No ground base, no terrain tile, no hex base.
- Game-ready model with clean topology and simple materials.

Avoid: photorealism, tiny fragile details, full environment scene, scattered loose objects,
text, labels, terrain base, flat billboard, image plane.
```

## Pine Forest Example

Use `assets/resources/pine_forest.png` as the reference image.

```text
Create a stylized low-poly 3D game resource node: a compact cluster of pine forest trees for a
hex-tile resource strategy game.

Use the reference image for composition, silhouette, color palette, and clustered resource-node
shape. Convert it into a clean low-poly 3D model, not a flat billboard.

Make 7-8 evergreen pine trees grouped tightly into one readable resource node. Use varied tree
heights: one taller central pine, medium trees behind and on the sides, smaller front trees.
Each tree should have layered triangular conifer foliage, chunky rounded shapes, thick
simplified silhouettes, and short brown trunks visible at the bottom.

Style: stylized low-poly / hand-painted 3D, clean shapes, soft bevels, no realism, no thin
fragile branches. Use saturated forest greens with lighter yellow-green highlights on upper
foliage layers, darker blue-green shadow sides, warm brown trunks, and subtle dark edge
definition through geometry and color contrast.

Model requirements:
- Single centered asset intended to sit on the center of one hex tile.
- No ground base, no rocks, no grass patch, no terrain tile.
- Game-ready model with clean topology and simple materials.
- Upright vertical orientation suitable for Godot import.
- Pivot/origin at the center bottom of the cluster.
- Footprint should be compact, like a map resource node.
- Readable from an isometric camera at about 55 degrees.
- Keep it charming, simple, and icon-like rather than realistic.

Avoid: realistic forest, individual detailed needles, loose scattered trees, huge environment
scene, terrain base, roots, dead branches, photoreal materials, text, labels, snow, animals,
buildings.
```

Suggested output name: `pine_forest_node.glb`.

## Building Prompt Notes

Buildings can be taller and more detailed than resource nodes, but should still keep a compact
footprint and bottom-centered pivot.

Ask for:

- The same palette and materials as the 2D building reference.
- Slightly exaggerated chunky proportions.
- Clear front/read direction, but acceptable from all isometric angles.
- No terrain base unless the building needs small attached props.

Avoid making buildings too realistic or too tall. They should feel like board-game pieces on
hex terrain, not miniature dioramas.

## Import Checklist

After generating a model:

1. Import it into Godot as `glb` or `gltf`.
2. Confirm the origin is at the bottom center.
3. Place it at the cell center, not the cell anchor.
4. Check scale against the existing billboard asset.
5. View it from the normal gameplay camera angle.
6. Confirm it is readable on grass, sand, stone, and coast-adjacent tiles.
7. If the model has a built-in shadow or ground base, regenerate or remove it.
