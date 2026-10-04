# Resource Isles — Low Poly Workshop art direction

Art direction proposal, 3 October 2026. This is a proposed asset standard; current game assets and movement are unchanged.

## Reference boards

| Board | Status | Use |
| --- | --- | --- |
| [building-style-palette-v2-low-poly.png](../art/style/building-style-palette-v2-low-poly.png) | **Current** kit reference | Overall style, palette, prop density |
| [iron-coal-deposits-v1.png](../art/concepts/iron-coal-deposits-v1.png) | **Current** for the resource deposits | Dense outcrops of chunky, flat-topped blocks: iron veined in rust orange, coal a black core under a grey cap slab. Stone (not on the board) follows the same style |
| [logger-camp-v3-low-poly.png](../art/style/logger-camp-v3-low-poly.png) | Superseded | History only: the roofed logger camp, replaced by the [workbench style](#workbench-style) |
| [building-style-palette-v1.png](../art/style/building-style-palette-v1.png) | Superseded | History only: the earlier painterly direction |

Each board's generation prompt sits next to it as a `.prompt.txt`. The boards are concepts generated with the built-in imagegen tool. Their drawn swatches and proportions are illustrative; the palette values and scale table in this doc are authoritative. Where a board conflicts with this doc, follow the doc (see [Board corrections](#board-corrections)).

## Direction

Low poly, flat-shaded miniature architecture with a frontier-workshop identity: timber and stone buildings, terracotta roofs, teal salvaged machinery, and the cream-and-teal robot. Map readability comes from clear silhouettes, not detail.

- **Geometry:** where a building has a roof, broad planar roofs (2–4 planes, no individual tiles); wide rectangular timber beams with almost no individual planks, six- or eight-sided cylinders, faceted rocks, conifers as 2–3 stacked polygonal cones.
- **Composition:** each building has one dominant structure, one identifying machine, and at most two prop groups. No scattered grass, pebbles, fences, lanterns, ropes, barrels, or trim.
- **Materials:** solid-color matte materials. No painted textures, wood grain, weathering, or scratches.
- **Shading:** visible flat-face shading. Don't smooth or bevel away the facets.
- **Bases:** no terrain tile, deck, or plinth under a building. The game's hex tile is the base.
- **Robot and icons:** use the same low-sided geometry standard as the buildings.

## Workbench style

The player must tell buildings apart at a glance, and roofs don't help: from the game camera a roof hides what's under it, and one terracotta roof looks like another. So a production building is a workbench, not a house. Its working machine *is* the building:

- **No full roof.** Height and silhouette come from the building's own work machine.
- **One signature shape per building**, recognisable from across the map: the logger camp's big raised axe over a chopping block, the sawmill's huge upright blade, the quarry's vertical spiral drill, the mines' rock portal. If two buildings would be told apart only by color or a small prop, give one of them a different big shape.
- **Face the camera.** Turn the signature face toward the yard (Blender −Y), as the sawmill's blade is. Keep beams and walls from crossing in front of it.
- **Lay stock so it reads.** Logs and lumber lie crosswise so their long sides show. Seen end-on from the high camera, they read as upright posts or crates.
- **Same layout as before:** everything in the back of the tile, an open yard in front with the `WorkSpot` (see [Footprint and work space](#footprint-and-work-space)).

Roofed buildings, such as a windmill's house or a future home, still use the roof guidance in this doc.


## Material palette

| Material / purpose | Hex (sRGB) | Linear RGB (Blender Base Color) | Use |
| --- | --- | --- | --- |
| Warm cream | #E7D9B8 | 0.799, 0.694, 0.479 | Robot shell, plaster, windmill tower |
| Timber | #98623D | 0.314, 0.122, 0.047 | Beams and lumber; lighter cut ends |
| Terracotta | #B85F43 | 0.479, 0.114, 0.056 | Roofs; broad planes, few seams |
| Workshop teal | #397E80 | 0.041, 0.209, 0.216 | Machinery and robot panels; sparse accents |
| Stone | #89938D | 0.250, 0.292, 0.266 | Foundations, quarry stone |
| Iron | #3F5057 | 0.050, 0.080, 0.095 | Blades, frames, mine openings |
| Pine | #486A4C | 0.065, 0.144, 0.072 | Forest foliage; lighter upper planes |
| Amber | #E5B653 | 0.784, 0.468, 0.087 | Robot eyes and powered indicators |

Blender's Principled BSDF Base Color takes linear values, so use the linear column in build scripts; `tools/lowpoly_kit.py` provides it as `PALETTE`, converted from these hex values. Typing the hex digits in as 0–1 fractions makes every color too light.

Secondary tones are mixed from the palette (in sRGB, by the given fraction) rather than picked freely, so they stay in the same family:

| Tone | Mix | Use |
| --- | --- | --- |
| Plank | Timber → cream, 0.25 | Boards and walls, lighter than beams |
| Cut wood | Timber → cream, 0.6 | Log ends, finished lumber |
| Steel | Iron → stone, 0.6 | Saw blades, rails, cable |
| Dark stone | Stone → iron, 0.45 | Shadowed or weathered rock |
| Cut stone | Stone → cream, 0.45 | Freshly cut quarry blocks |
| Dust | Stone → cream, 0.7 | Worked quarry ledges |
| Shaft | Iron → black, 0.7 | Tunnel depth |
| Iron ore | Terracotta → iron, 0.35 | Rust-colored ore |
| Coal | Iron → black, 0.55 | Coal |

All materials are matte and non-metallic. The game disables reflected light (`main.gd` sets `REFLECTION_SOURCE_DISABLED`), so metallic surfaces lose their diffuse color and render darker than authored.

Use timber, stone, or cream for most of a building and teal for its machine or a trim accent; terracotta is for roofs, where a building has one. Amber is a signal color only. Keep coal and iron deposits distinct through silhouette and material patches, not just by recoloring every surface.

## Lighting and outlines

Author every asset under the same neutral lighting and let the game light it. Avoid baked directional shadows, heavy ambient occlusion, and glossy surfaces.

**Decided: no outlines.** Every map object now uses its own imported materials with no outline. The resource deposits used to be flat-tinted with banded toon shading and a dark inverted-hull outline; that path was removed when they were rebuilt with the kit.

## Shape palette

| Asset | Primary read | Secondary read |
| --- | --- | --- |
| Logger camp | Trip-hammer axe on a timber fulcrum over a chopping block | split firewood, crosswise log pile and shared PTO generator |
| Sawmill | Huge upright saw blade in an open timber frame | Shared PTO generator belted to the blade, logs and boards |
| Quarry | Spiral stone drill in a heavy open timber frame | Shared PTO generator and belt drive, squared stone block |
| Iron mine | Braced opening and stone arch | Rust-colored ore and cart |
| Coal mine | Dark low opening | Coal pile and stout supports |
| Burner generator | Compact vertical furnace | Chimney and teal housing |
| Windmill | Slim cream tower | Broad sails and teal cap |
| Dock | Horizontal timber pier | Posts and mooring |
| Forest | Three to five conifers | Small open foreground clearing |
| Stone deposit | Medium outcrop of grey blocks around one broad block | A broken face of lighter cut stone, a leaning slab |
| Iron deposit | Tall, dense mound of packed grey blocks | Rust-orange ore veins down the cracks, ore chunks |
| Coal deposit | Wide, low mound under a flat grey cap slab | Black coal block core, spilled coal |
| Robot | Cream head/body silhouette | Teal panels, amber eyes |

These silhouettes must stay readable at the normal map zoom. In particular:
- **Logger camp vs sawmill:** the camp chops with a big axe, broad face toward the camera; the sawmill owns the spinning circular blade and cuts lumber. Keep blades off the logger. Like the quarry's drill on its own block, the axe works its own round, so the camp reads correctly wherever the neighbouring trees stand.
- **Quarry vs stone deposit:** the quarry reads as a man-made drilling machine with timber uprights and a squared stone workpiece. The deposit is natural, irregular boulders.
- **Quarry vs mines:** don't make them all the same shed or rock pile with a door.
- **Iron mine vs coal mine:** today they are one model told apart only by small ore lumps. Give each its own big shape when they are reworked.

## Board corrections

The boards get the style right but some of their designs break this standard. Don't copy these details:

- **v2 logger camp and sawmill** are nearly identical (timber shed, orange roof, teal machine). Both are now workbenches instead (see [Workbench style](#workbench-style)).
- **v2 quarry** is superseded by the stone-drill design: open timber frame, spiral bit, shared PTO generator, belt drive and front work spot.
- **v2 windmill** has an attached house, which widens the footprint beyond the slim-tower target. Drop the house.
- **v2 robot** keeps some rounded details. Use angular low-sided forms.

## Current asset inventory

| Asset | Source | Gap to this standard |
| --- | --- | --- |
| Sawmill, coal mine, iron mine | Scripted builds in `tools/build_*.py` on the shared `tools/lowpoly_kit.py` | Palette colors, no bevels, low-sided cylinders, no base platforms. The sawmill is a workbench at true tile scale, with a work spot. Remaining for the mines: the same treatment, with prop density cut to the two-group rule (bolts, rivets, chips, lantern). |
| Logger camp | `tools/build_logger_camp.py`, at true tile scale with front work spot | Powered chopping axe (trip hammer): timber fulcrum and helve, broad iron axe head with a steel bit, chopping block with a split round, cam and gearbox belted from the shared hand-PTO generator, split halves and three harvested logs. Authored raised; powered, it drops 26 degrees onto the round every 1.6 s. No terrain base. 0.784 tiles wide, 0.556 tall (axe raised). `tools/logger_model_check.gd` checks imported docking and the chop stroke. |
| Quarry | `tools/build_quarry.py`, at true tile scale with front work spot | Stone-drill workbench after the supplied reference: heavy timber frame, rotating spiral bit over a squared block, shared teal hand-PTO generator and belt drive. Two stock groups, no terrain base; 0.787 tiles wide and 0.69 tall. Socket alignment and powered motion checked by `tools/quarry_model_check.gd`. |
| Windmill (`windmill2.glb`), crashed spaceship, pine forest, player robot, dog | Imported meshes with image textures | Furthest from the standard. Rework these first. |
| Stone, iron and coal deposits | Scripted builds in `tools/build_deposit.py` (one run per variant: `-- stone`, `-- iron` or `-- coal`) at true tile scale, with footprint (no work spot: the robot harvests from the tile or any neighbour) | Meets the standard. Each is packed from the kit's flat-topped, straight-sided `block()`s (convex hulls, like its `rock()`), after the iron and coal concept board. Stone: a broad main block split open to lighter cut stone, a slab leaning on it, a lower block behind, and lower blocks, the broken-off chunk and rubble around its foot (0.704 tiles wide, 0.454 tall). Iron: a tall mound of grey blocks with bright rust-orange veins wedged between them, ore chunks and rubble at the foot (0.736 wide, 0.580 tall). Coal: a wide, low mound of black coal blocks under a flat grey cap slab, wrapped in grey blocks, coal lumps spilled in front (0.752 wide, 0.301 tall). Each tile turns its deposit up to 45° either way, fixed per cell. |
| Dock | Scripted build in `tools/build_dock.py` at true tile scale over a line of three tiles (see [Building footprints](building-footprints.md)), with work and boat spots | Meets the standard. A stone quay and cargo crates on the shore tile; a crosswise-boarded pier on pilings over the coast tile, widening into a T-head with a mooring post and a teal beacon post with an amber lamp; the salvage skiff (`tools/build_salvage_skiff.py`) moored stern-to off the pier head on the third, water tile. |
| Burner generator | Scripted build in `tools/build_burner_generator.py` at true tile scale, with work spot | Meets the standard. A compact vertical furnace: stone firebox with a glowing mouth facing the yard, iron boiler drum and tall chimney; a steam pipe to the teal dynamo on the right, split firewood stacked on the left. 0.579 tiles wide, 0.602 tall. |
| Icons and building sprites in `assets/icons`, `assets/buildings` | Painterly 2D with dark outlines | Re-render from approved models (see [Icon standard](#icon-standard)). |


## Scale standard

Let T = 128 world units, the current tile bounding width. Values below are initial art targets, to be checked in the actual camera. Width is maximum X/Z extent; height is vertical extent.

| Asset | Target width / T | Target height / T |
| --- | --- | --- |
| Robot | 0.20–0.24 | 0.42–0.48 |
| Dog | 0.16–0.20 | 0.20–0.26 |
| Workbench building (logger camp, sawmill) | 0.55–0.68 | 0.45–0.60 |
| Roofed building | 0.58–0.68 | 0.65–0.85 |
| Low quarry / mine | 0.58–0.70 | 0.35–0.60, crane up to 0.90 |
| Forest cluster | 0.60–0.70 | 0.80–1.10 |
| Rock deposit | 0.70–0.78 | 0.28–0.60 |
| Windmill | Body 0.35–0.45; sails up to 0.75 | 1.00–1.25 |

Unit scale is deliberately exaggerated for map readability; the style does not require a literal human-to-building scale. The robot is roughly half an ordinary roof's height, with a much narrower footprint.

Today, most buildings render at 0.85T width and the forest at 0.90T, which leaves little access space. The rock deposits, authored at true tile scale, are 0.70–0.75T wide. The logger camp is now a powered chopping axe (0.784T wide, 0.556T tall with the axe raised) with a shared PTO generator and an open front operator yard. The sawmill (0.73T wide, 0.57T tall) is over it: the shared PTO generator, its flywheel and the log pile widen it, though everything still fits the tile and leaves the yard open. The robot now meets its height target (0.45T, down from 0.65T), but its arms make it about 0.31T wide, above the 0.20–0.24T target. Static models are scaled by width in `IslandRenderer._spawn_model`, and the robot by a hard-coded native height in `PlayerUnit._ready`. Setting both `visual_size_tiles` components to the same number does not enforce equal width and height. Measure actual bounds and enforce separate footprint and height targets. Uniform scale preserves proportions; reauthor assets that are too tall or wide instead of stretching them.

The crashed ship renders at 1.6T width from a one-cell anchor. Treat it as a landmark and reserve space matching its actual visual extent.

## Footprint and work space

Every asset needs a solid footprint, an open access area, and a work position. Color and shading can't stop the robot clipping into geometry; layout and movement have to.

For compact one-tile assets, a starting layout is:
- a 0.60T-wide, 0.45T-deep solid structure, centered about 0.13T toward the back of the tile;
- a work spot about 0.30T toward the front.

With a robot radius of about 0.11T, this leaves roughly 0.095T clearance from the front wall. Validate it against the actual hex polygon, every asset rotation, and neighboring geometry. Access belongs to the asset and rotates with it; don't define "front" relative to the camera.

Export the layout with the model. Each build script should add empties named `WorkSpot` and `Footprint` with the kit's `marker()`: `Footprint` is a box empty whose scale is the solid footprint's half extents. They come through the `.glb` as `Node3D`s, so the game can read them and they rotate with the model. Empties have no mesh, so they don't change the measured bounds.

To make the layout survive the game's width-based scaling, author at true tile scale:
- Use `lowpoly_kit.TILE` (2 units) per tile width, with the model origin at the tile centre and the open front toward Blender −Y (glTF/Godot +Z, facing the game camera at its default yaw).
- Set the definition's `visual_size_tiles` to the model's width ÷ `TILE`, so one unit is exactly half a tile in the game.
- Preview with `render_preview(true_tile=True)`. It draws one game tile (pointy along Y, as in the game), stands a robot-sized figure on `WorkSpot`, and uses a camera close to the game's.

`tools/build_logger_camp.py` and `tools/build_sawmill.py` are the references: a chopping-axe camp 0.784 tiles wide and 0.556 tall, and a sawmill 0.73 tiles wide and 0.57 tall, each with its work spot 0.30 tiles forward. Both use the [shared PTO generator](shared-generator-model.md), with its socket placed under the robot's right hand at the work spot and moving parts kept under pivots.

The movement changes needed to actually use work spots are tracked in [TODO.md](../TODO.md) under "Robot access and clipping".

## Icon standard

Render icons from the approved models with a common isometric camera and neutral light. Use a transparent background, a generous safe margin, and consistent framing. Large build-menu icons may show the whole building. Tiny action and resource icons should use a simplified emblem (blade, log, boulder, lightning). Judge each icon at its actual UI size and simplify details that collapse into noise. Keep resource colors and machinery teal consistent with the map.

## Asset prompt

> Low poly flat-shaded 3D game asset for Resource Isles, a hex island resource strategy game. Frontier workbench style: the building is its working machine, open to the sky with no roof, built from wide rectangular timber beams, teal machinery, gray stone and dark iron. One big signature shape that tells it apart from every other building at map zoom, its face turned toward the viewer. Obvious large planar faces, 6- or 8-sided cylinders, faceted rocks, solid matte colors. One function-defining machine, at most two prop groups; stock such as logs and lumber laid crosswise. Subject: [asset and its dominant silhouette]. Compact solid footprint in the rear of the tile with a clear open front work area; no terrain tile, deck, or plinth. Readable at map zoom from a roughly 55-degree camera. No textures, wood grain, weathering, roof tiles, outlines, bevel-heavy rounding, glossy plastic, tiny wires, scattered props, or text. Pivot at the tile centre (so the structure sits behind it); Y-up; open front toward +Z (Blender −Y); applied transforms; WorkSpot and Footprint empties.

## Validation before rollout

Build one calibration scene containing the robot (at the target height), one workshop, a forest, rocks, and two adjoining hexes. Check default, near, and far zoom, shadows, and icon size. Approve this small set before remaking the rest. Once the movement work lands, also check that the robot reaches work spots without intersecting geometry and that manual operation still selects the intended building.
