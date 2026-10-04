# Icons and 2D art

Updated 2026-10-04: UI icons and 2D illustrations share the approved 3D models' Low Poly
Workshop style. The [workshop palette](building-style-palette.md#material-palette) defines
the colors and materials; this document defines how they carry into flat images.

## Visual standard

- Angular, chunky silhouettes with broad flat faces and simple facet shading.
- Solid matte colors, without painted texture, wood grain, scratches, weathering, glossy
  reflections, or heavy ambient occlusion.
- No drawn outlines. Separate shapes through silhouette, material color, and face shading.
- Manufactured robot equipment uses warm cream shells (#E7D9B8), workshop teal panels
  (#397E80), dark iron fittings (#3F5057), and sparse amber signals (#E5B653).
- Raw resources keep their material identity: timber logs, grey stone, rust-colored iron
  ore, and dark coal. Do not turn every item into cream-and-teal machinery.
- One recognizable subject per icon. Use a few broad functional details; omit tiny bolts,
  wires, decorative trim, and props that disappear at UI size.

Use the approved [salvage robot](player-model.md), [shared generator](shared-generator-model.md),
and [personal boat](robot-built-boats.md) as visual references. Legacy outlined, painterly
PNGs are migration references for subject identity only; their rendering style is superseded.

## Framing and output

Use a consistent three-quarter isometric view, with the top and two identifying sides
visible, and neutral lighting. Center the subject in a square transparent PNG with about
8–12% safe margin. Preserve actual alpha; do not draw a checkerboard, backdrop, floor,
terrain tile, or cast shadow. Leave text, quantity badges, borders, and selection feedback
to the UI.

Check action icons at 48 px and inventory icons around 56 px, as well as at full size.
At small sizes, the overall silhouette and main material blocks must carry the meaning.
Large building-menu images can show the full approved building; tiny icons may simplify
its signature machine or use a recognizable emblem.

## Authoring workflow

Prefer rendering an approved model with the shared camera and lighting. If no suitable
model exists, generate a matching raster asset with actual model previews as style
references and the explicit palette/material constraints above. Save the final image in
the project and its exact prompt beside it as `.prompt.txt`. Inspect the result in its UI
before considering it complete. Do not copy a preview's studio platform into the icon.

For robot equipment, shared casing and mechanical shapes convey the family. Paired eyes
belong to the robot; its signature antenna is not generic cargo decoration. A cargo box
should read as a container through its lid, handles, and latch.

## Cargo icon reference

[cargo_crate.png](../assets/icons/cargo_crate.png) is the current Cargo action icon:
cream shell, teal lid and corner framing, dark iron base and latch, one amber indicator.
It was revised from the initial wooden outlined crate using the approved crewed-skiff
preview as the style reference. [Generation prompt](../assets/icons/cargo_crate.prompt.txt).
This defines the visual direction for manufactured-item icons; it does not change the
boat's cargo capacity or resource materials.

## Raster prompt template

> Transparent inventory/action icon for Resource Isles: [subject]. Match the approved
> low-poly 3D workshop models: chunky angular forms, broad flat faces, solid matte colors,
> simple facet shading, no drawn outlines or painted textures. [Subject-specific materials
> from the workshop palette.] One clear silhouette with only a few functional details.
> Three-quarter isometric view, neutral light, centered square framing, 8–12% safe margin,
> real transparent alpha. Readable at 48 px. No text, UI borders, floor, terrain base, cast
> shadow, wood grain, weathering, glossy reflections, tiny wires, or decorative clutter.
