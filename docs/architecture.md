# Architecture

What each script does, and how buildings, placement and production fit together. For how 3D
models are presented see [3D Models](3d-models.md); for the world map format see
[World Map and Island Designs](world-map-and-island-designs.md).

The game is one 3D scene, `game.tscn`, driven by `scripts/main.gd`. Gameplay data lives in
static catalogs (buildings, quests, resources, resource nodes, island designs and the world
map); managers hold the generic logic and never per-item numbers.

## Core

- `scripts/main.gd` (`Game`) builds the world from the world map and owns the `WorldData`, the
  current island and the managers. Each frame it runs power and production for **every**
  island, so islands keep producing while the robot is elsewhere, plus the trade routes and the
  robot. It also handles input, picking, building placement, moving and deleting, quest rewards
  and saving. Walking and work are split off into `RobotController`, and boats into
  `BoatController`; building placement is still to be split out (see [TODO](../TODO.md)).
- `scripts/game_types.gd` holds the shared enums (`Terrain`, `BuildingType`,
  `ResourceNodeType`, `ResourceType`, `AdjacencyKind`, `UnitAction`, `QuestId`, `Stat`, ...)
  and `NO_CELL`, so data and manager classes stay decoupled.
- `scripts/camera_rig.gd` is the orbit camera: one continuous zoom from the play view out to
  the whole disc. Past the play range the pivot drifts to the disc centre and the view
  flattens into a three-quarter shot against the stars; `overview_amount()` drives the chart
  and island labels.
- `scripts/save_manager.gd` writes the save atomically to `user://savegame_v3.sav`. The data
  classes serialize themselves (`to_dict`); this layer assembles the payload and stamps a
  version. Older versions aren't loaded.
- `scripts/game_logger.gd` is the `Logger` autoload.

## World

- `scripts/world/world_map.gd` reads `assets/world/world_map.cfg`: which island design goes
  where, how it is turned, and its role. Every player sails the same map.
- `scripts/island/island_design.gd` reads a hand-made island from an `.island` text file in
  `assets/world/islands/` (a hex grid drawn one character per cell, plus landmarks and named
  spots) and stamps it onto the world at any centre, turned and mirrored, with a coast ring
  around its land.
- `scripts/world/world_builder.gd` builds every island on the map up front, so the whole
  archipelago is one persistent world. A saved game also gains islands added to the map later.
- `scripts/world/world_data.gd` holds every island keyed by its centre cell, the start and
  current islands, how many rings are revealed (the frontier starts at the home waters), K9-DA's
  rescue state and the crashed ship's repairs. An island counts as discovered once the robot's
  sight reaches it (`IslandData.visited`).
- `scripts/world/world_navigation.gd` defines the world lattice: one hex grid shared by every
  island and the sea between them. Island data, units and boats all use its cells. It finds
  water routes and enforces the quest-controlled radar frontier.
- `scripts/world/ship_repairs.gd` lists the crashed ship's parts in repair order, with what
  each takes (see [Copper and the radar](copper-and-the-radar.md)).
- `scripts/world/exploration_map.gd` records which cells the robot has seen; everything else
  inside the frontier is drawn as exploration fog.
- `scripts/world/world_view.gd` is the playable world: the flat-disc planet at full game scale
  (see [Intro Story](intro-story.md)). One open sea sits inside a frozen mountain range over a
  rocky underside, with water spilling off the edge into a starfield. Every revealed island has
  its own `IslandRenderer` where the world map puts it. Beyond the radar frontier lie near-black
  tiles no boat can sail; inside it, slate fog covers what the robot hasn't seen. Undiscovered
  islands aren't shown; only K9-DA's signal pings where its island lies. Zoomed out, the
  charted rings show a navigator's grid with a gold frontier line and island names. Its shaders
  live in `assets/shaders/world_map/`.
- `scripts/world/trade_route.gd` and `scripts/world/trade_manager.gd` are inter-island trade
  routes: a boat based at a Dock shuttles one resource out and optionally another back between
  two islands' inventories. Routes are opened and removed from a Dock's info panel (see
  [Island Unlocks](island-unlocks.md)).

## Islands

- `scripts/island/hex_grid.gd`: pointy-top hex coordinates, axial direction offsets,
  neighbours, 3D cell centres and corners, and picking helpers. Anchor new things to the cell
  centre (`cell_center_3d`).
- `scripts/island/hex_pathfinder.gd`: shortest paths over hex cells, for walking an island and
  for sailing (through `WorldNavigation`).
- `scripts/island/island_data.gd`: one island's terrain, resource nodes, ground items,
  buildings, blueprints and inventory, keyed by world cell.
- `scripts/island/island_renderer.gd`: draws an island in 3D: code-generated hex-prism terrain
  under one terrain shader, building and resource-node models, ground items, boats, hover
  highlighting and the placement preview.
- `scripts/island/construction_site.gd`: a blueprint on the map. The real model is printed up
  from the ground to the build progress under a teal hologram of the finished building.
- `scripts/island/power_indicator.gd`, `powered_spinner.gd` and `blade_spinner.gd`: per-model
  helpers that animate themselves (the red unpowered bolt, powered moving parts, windmill
  blades), so the renderer needs no per-frame loop.
- `scripts/island/island_generator.gd`, `island_profile.gd` and `island_profiles.gd` generate
  an island from a biome profile and a seed. This is a tool for making island designs, not
  part of the running game (see [Island Generation](island-generation.md)).

## Robot, K9-DA and boats

- `scripts/player/player_unit.gd`: the robot's 3D model, walking a queued path of cells, its
  tools and animations.
- `scripts/player/robot_controller.gd`: the robot at work: walking to where it can work a
  target (a building's `WorkSpot`, or a neighbouring tile), harvesting, operating
  (hand-powering a building), building blueprints, repairing the crashed ship, rescuing K9-DA,
  and the work actions on the command bar. See
  [Player Unit and Manual Gathering](player-unit-and-manual-gathering.md).
- `scripts/player/boat_controller.gd`: launching a Dock's skiff and boarding it, sailing,
  choosing where to land, disembarking, the boat's cargo hold and the boat actions on the
  command bar.
- `scripts/player/boat_cargo.gd`: exact transfers between an island's stock and the boat's
  cargo slots, never partially spending stock (see [Robot-Built Boats](robot-built-boats.md)).
- `scripts/player/robot_blink.gd`: the amber eye blink, shared by the world robot and the
  command-bar portrait.
- `scripts/units/dog.gd`: Companion Unit K9-DA. It waits on its island until rescued, then
  follows the robot between islands.

## Resources

- `scripts/resources/resource_database.gd` and `resource_definition.gd`: every resource's
  display name, popup colour, icon and lifetime "gathered" stat. Add a resource there.
- `scripts/resources/resource_node_database.gd` and `resource_node_definition.gd`: resource
  nodes (forest, stone, iron, coal and copper deposits): model, footprint, extracted resource,
  and the amount a harvest yields.
- `scripts/resources/inventory.gd`: a resource stock with a `changed` signal. Each island owns
  one; there is no global pool. Boat cargo holds reuse it.
- `scripts/resources/resource_manager.gd`: a facade over the **current** island's inventory,
  giving the UI and placement logic a stable API while the active island swaps underneath.
  Every island begins empty: the robot gathers the first resources by hand, and brings
  materials for a new island's first buildings by boat.

## Buildings

- `scripts/buildings/building_definition.gd`: one building's data: name, category,
  description, model, cost, build time, footprint, placement rules, adjacency yields,
  production, power and fuel.
- `scripts/buildings/building_definitions.gd`: the catalog of every building and its numbers.
  Add buildings here.
- `scripts/buildings/building_manager.gd`: placement validation (`can_place`/`try_place`),
  footprint cells, adjacency yields and per-tick production amounts.
- `scripts/buildings/production_manager.gd`: the production tick, paying each producer's
  output into its own island's inventory.
- `scripts/buildings/power_manager.gd`: the MW balance: running generators add capacity,
  consumers draw it, and fuel burns on its interval. The robot's Operate powers the building
  it works.

## Quests

- `scripts/quests/quest_catalog.gd`: every quest's data: kind (the main Rescue K9-DA goal or a
  milestone in the linear chain), title, description, objectives and rewards. Add quests here.
- `scripts/quests/quest_manager.gd`: completion state; completes the current quest once its
  objectives are met and applies its rewards.
- `scripts/quests/stat_tracker.gd`: lifetime, append-only play stats (wood ever gathered,
  buildings ever built...), so spending never un-completes an objective.
- `scripts/quests/objective.gd`, `quest.gd` and `quest_reward.gd`: the data types. A reward
  unlocks a building, grants a robot upgrade, or reveals more rings of the world. Nothing is
  spent on completion.

## UI

- `scripts/ui/resource_bar.gd`: the top stock readout; a resource appears once it has ever
  been gathered.
- `scripts/ui/building_menu.gd`: the BUILD launcher, the bottom build bar (category tabs over
  a row of building cards, unlocked buildings only), the hover details popup and the placement
  bar.
- `assets/ui/ui_theme.tres`: the project theme (`gui/theme/custom`), which sets Exo 2 Medium
  (`assets/fonts/`, SIL OFL) as the UI font. Headings use the bold variation,
  `assets/fonts/exo2_bold.tres`.
- `scripts/ui/building_info_panel.gd`: the panel for a clicked building: live adjacency and
  production breakdown, Move and Delete, and a Dock's trade routes. Move lifts the building
  off the map into a free placement preview; cancelling puts it back, and a save taken mid-move
  writes it at its original cell.
- `scripts/ui/action_bar.gd`: the robot's portrait and command bar (Civ VI unit-command style).
  A pure view fed by `Game.refresh_action_bar()`.
- `scripts/ui/boat_cargo_panel.gd` and `cargo_slot.gd`: the drag-and-drop cargo panel.
- `scripts/ui/quest_log_view.gd` (T) and `quest_tracker_view.gd` (always-on tracker).
- `scripts/ui/game_menu.gd`: New, Save, Load and Resume.
- `scripts/ui/toast.gd` and `floating_text.gd`: transient messages and world-space `+N`
  popups.

## Naming

Resource nodes are permanent map objects such as forests and stone deposits; resources are
stored inventory items such as wood and stone. Harvesting a `GameTypes.ResourceNodeType.TREE`
yields `GameTypes.ResourceType.WOOD`.

## Placement Rules and Adjacency

Buildings declare placement and adjacency behaviour on their `BuildingDefinition`:

- `category`: the build-menu tab (`Resources`, `Power`, `Processing`, `Logistics` or
  `Utility`).
- `footprint`: the tiles the building covers, as axial offsets from its anchor; the player
  turns it in 60-degree steps (see [Building Footprints](building-footprints.md)).
- `required_terrains` / `footprint_terrains`: the terrain the footprint must sit on. A logger's
  camp is built on grass; a quarry on stone.
- `required_adjacent`: each entry needs at least one matching neighbour, or placement is
  blocked. A logger's camp must be next to a forest.
- `forbidden_adjacent`: placement is blocked if any neighbour matches.
- `adjacency_yields`: Civ VI style bonuses, where each neighbour matching a
  `{ kind, type, amount }` rule adds `amount`. A logger's camp earns +1 per adjacent forest but
  -1 per adjacent logger's camp.

The placement preview tints red when a rule is unmet. Placing a building reserves its cost and
footprint as a blueprint; it starts producing and drawing power only once the robot has built
it.

## Production and Power

Producers declare `production_resource_type`, `production_base_amount` and
`production_interval_seconds`, and optionally inputs (`input_resource_type`/`input_amount`,
`production_inputs`), or a list of `recipes` to choose from (the Furnace). Each interval a
building pays out `base + adjacency total` (clamped to zero) into its island's inventory. A new
building waits one full interval before its first payout.

Generators declare `power_generated` and, if they burn fuel, `fuel_resource_type`,
`fuel_amount` and `fuel_interval_seconds`; consumers declare `power_consumed`. An unpowered
consumer pauses without advancing its timer. See [Power Sources](power-sources.md) and
[Furnace](furnace.md).
