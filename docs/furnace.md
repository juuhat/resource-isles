# Furnace — first smelting

Implemented 2026-10-04; copper recipe added 2026-10-07 ([Copper and the radar](copper-and-the-radar.md)).
The Furnace is the first metal-processing building, unlocked by **Haul It Home** once copper
ore from K9-DA's island reaches the crash site. It smelts copper over a wood fire, or iron with
coal; the robot powers its bellows with **Operate** for the first ingots. Later, a generator can
drive the same bellows. It needs no metal to construct.

| Property | Initial balance |
| --- | --- |
| Construction | 12 stone + 4 wood |
| Placement | Any clear land tile; no adjacent deposit required |
| Copper recipe | 2 copper ore + 1 wood -> 1 copper ingot |
| Iron recipe | 2 iron ore + 1 coal -> 1 iron ingot |
| Batch interval | 6 seconds |
| Bellows power | Robot Operate, or 2 MW from a generator |

A new Furnace starts on the copper recipe; its info panel switches between the two. Inputs come
from the island's stock. The entire input batch is checked before spending any ingredient.
A missing input stalls the building without consuming the others. Once supplies return, it
completes one overdue batch and schedules the next; it does not produce an accumulated backlog.
Blueprints do not process materials. Smelting pauses without robot operation or generator power.
Generator-powered Furnaces keep working while the player is on another island.

## Progression and saves

Live Wire now unlocks only the Sawmill; early Operate remains the robot's mechanical power
source. The copper milestones come first (see [Copper and the radar](copper-and-the-radar.md)):
**Haul It Home** unlocks the Furnace, and **First Melt** asks for one Furnace and three copper
ingots, which go into the ship's radar. **Light the Forge** follows Strike Iron: smelt six iron
ingots. It unlocks the Burner Generator. **Power On** follows: build one Burner Generator to
unlock the Windmill, then continue to the existing Supply Line milestone. Electricity remains
gated behind rescue and first smelting.

The Burner Generator now costs **6 iron ingots + 4 stone + 2 planks**. Its wood fuel and
5 MW output are unchanged. Bring construction supplies by personal boat; a destination
dock or automatic route is not required to bootstrap the Furnace. Replacing the old
automatic Supply Line tutorial with manual delivery remains a separate TODO.

New building, resource, quest, and stat enum values are appended to preserve existing
save IDs. Existing ingot inventory and Furnace production timers use the normal island
save format. A Furnace saved before it had recipes stays on iron when loaded. Older completed
trade milestones do not silently complete Light the Forge or Power On: those saves receive the
new smelting lesson. Existing built generators are preserved; new generator construction follows
the revised unlock and cost rules.

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
- Ingot icons are rendered from the ingot model by the [ingot builder](../tools/build_ingot.py):
  `--background --python tools/build_ingot.py -- iron` (matte steel) or `-- copper` (the copper
  deposit's seam colour). [Iron ingot icon](../assets/icons/iron_ingot.png),
  [copper ingot icon](../assets/icons/copper_ingot.png); editable sources in `art/blender/`.

BuildingDefinition's `recipes` list holds the Furnace's recipes, `{output, inputs}` each, and
the building entry keeps which one runs (`IslandData.get_recipe`). `BuildingManager.get_recipe`
answers what any producer makes and pays per batch: its chosen recipe, or for a single-recipe
building `production_resource_type` and `get_production_inputs()`, which still covers the
sawmill's single-input fields. Both building UI panels show every ingredient.

## Checks

Run `powershell -ExecutionPolicy Bypass -File tools/run_checks.ps1 -Filter furnace`.
The check covers blueprint inactivity, manual operation, generator takeover and bellows animation, missing-input
conservation, resupply, save round trips, both recipes and switching between them, keeping old
Furnaces on iron, existing sawmill processing, quest unlocks, legacy milestone migration, model
bounds and real-scene placement/stat/UI integration, including the panel's recipe buttons.
Without `--headless`, add `-- --screenshot` for `.godot/furnace_preview.png`.
