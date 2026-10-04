# Furnace — first smelting

Implemented 2026-10-04. The Furnace is the first metal-processing building, unlocked by
the actual **Rescue K9-DA** quest. Coal supplies the heat; the robot powers its bellows with **Operate** for the first
ingots. Later, a generator can drive the same bellows. It needs no iron to construct.

| Property | Initial balance |
| --- | --- |
| Construction | 12 stone + 4 wood |
| Placement | Any clear land tile; no adjacent deposit required |
| Batch inputs | 2 iron ore + 1 coal |
| Batch output | 1 iron ingot |
| Batch interval | 6 seconds |
| Bellows power | Robot Operate, or 2 MW from a generator |

Ore and coal come from the island's stock. The entire input batch is checked before
spending either ingredient. Missing ore or coal stalls the building without consuming
the other input. Once supplies return, it completes one overdue batch and schedules the
next; it does not produce an accumulated backlog. Blueprints do not process materials.
Smelting pauses without robot operation or generator power. Generator-powered
Furnaces keep working while the player is on another island.

## Progression and saves

Live Wire now unlocks only the Sawmill; early Operate remains the robot's mechanical power
source. Rescue unlocks the Furnace independently of the milestone chain. **Light the Forge**
follows Strike Iron and precedes the existing Supply Line milestone: rescue K9-DA, build
one Furnace, and produce six iron ingots. It unlocks the Burner Generator and Windmill,
preventing either from producing electricity before rescue and first smelting.

The Burner Generator now costs **6 iron ingots + 4 stone + 2 planks**. Its wood fuel and
5 MW output are unchanged. Bring construction supplies by personal boat; a destination
dock or automatic route is not required to bootstrap the Furnace. Replacing the old
automatic Supply Line tutorial with manual delivery remains a separate TODO.

New building, resource, quest, and stat enum values are appended to preserve existing
save IDs. Existing ingot inventory and Furnace production timers use the normal island
save format. Older completed trade milestones do not silently complete Light the Forge:
those saves receive the new smelting lesson. Existing built generators are preserved;
new generator construction follows the revised unlock and cost rules.

## Model and icon

The Furnace is a squat stone kiln with a broad refractory mouth, short square flue,
accordion bellows with a rigid teal top, a coal bin and casting bench. Its shared
robot drive socket and flywheel turn a cam to compress and expand the bellows;
the Burner Generator keeps its taller boiler silhouette. Solid matte materials use the
[workshop palette](building-style-palette.md), with an open front WorkSpot and Footprint
marker at true tile scale. The bellows cycle every 1.6 seconds at full speed, easing into motion and coasting
to a stop with the shared powered machinery controller. The amber mouth is static model art.

- [Furnace model](../assets/models/buildings/furnace.glb), [editable source](../art/blender/furnace.blend), [preview](../art/previews/furnace.png).
- [Furnace builder](../tools/build_furnace.py): Blender `--background --python tools/build_furnace.py`.
- [Iron ingot icon](../assets/icons/iron_ingot.png) is rendered from the [ingot model](../assets/models/resources/iron_ingot.glb), using matte steel-colored iron. [Builder](../tools/build_iron_ingot.py), [editable source](../art/blender/iron_ingot.blend).

BuildingDefinition's `production_inputs` dictionary supplies the multi-input recipe.
`get_production_inputs()` also preserves the existing sawmill's single-input fields, and
both building UI panels show every ingredient.

## Checks

Run `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tools/furnace_check.gd`.
The check covers blueprint inactivity, manual operation, generator takeover and bellows animation, missing-input
conservation, resupply, save round trips, existing sawmill processing, quest unlocks,
legacy milestone migration, model bounds and real-scene placement/stat/UI integration.
Without `--headless`, add `-- --screenshot` for `.godot/furnace_preview.png`.
