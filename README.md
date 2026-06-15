# Resource Isles

Resource Isles is a 2D resource management and building game made with the Godot game engine. It uses a 3/4 top-down perspective, aiming for the readable building layouts of Factorio with the cozy spatial feel of games like Stardew Valley.
Also Civilization VI style hex grid, with building adjanciencies.

The project is currently in early development. The core idea is to start on one small island, build a compact production base, unlock new technologies, and expand to nearby islands with new or larger resource deposits.

## Core Design

- Islands are relatively small and should generally fit within one view.
- The player starts on a single island with limited resources and building space.
- Technology unlocks access to new buildings, recipes, logistics tools, and additional islands.
- New islands introduce new resources, larger deposits, or better production opportunities.
- Building space is intentionally limited, especially toward the end game.
- Inter-island logistics become a major challenge, inspired by Anno-style trade and supply routes.
- Resources can move between islands using systems such as ships, pipes, power cables, and other transport infrastructure.
- Power management is simple and capacity-based, using generated MW to support production and logistics.

## Art Direction

Resource Isles should feel like a relaxing little evening game: calm, readable, cozy, and a little darker than a bright tropical island game.

- Use muted, blue-green water with a big soft depth gradient.
- Keep water motion sparse and gentle, with subtle shimmer rather than busy waves.
- Favor darker, calmer grass and sand colors over saturated or sunny colors.
- Terrain should stay readable at a glance, but avoid harsh tile boundaries where possible.
- Shorelines should feel soft and peaceful, with restrained foam and gradual water color changes.
- Visual effects should support the quiet mood instead of calling attention to themselves.

### Asset Style

Resource and building sprites should lean simple, cartoony, and board-game-like rather than painterly or realistic.

- Use chunky, readable silhouettes that still work at normal zoom.
- Favor flat colors, bold simple shapes, and thick dark outlines.
- Keep detail broad and symbolic; avoid tiny leaves, noisy texture, gradients, soft rendering, or dense concept-art detail.
- Use olive greens, yellow-greens, blue water, warm browns, muted oranges, and calm earthy accents.
- Sprites should feel like compact, iconic map tokens placed on the hex map. They should read clearly by silhouette before small details matter.
- Single-tile resources and buildings should fit within one tile of visual width. Tall sprites may extend upward, but should not spill sideways into neighboring hexes.
- A resource tile can represent a larger concept than one object. For example, a forest tile should show a small cluster of trees, while still occupying one gameplay tile.
- Generated assets should use transparent PNG output or a clean chroma-key background that can be removed.

### Building And House Style

Building sprites should read as iconic map tokens first and architectural drawings second. Their job is to communicate function, category, and mood instantly at normal gameplay zoom. Use the `assets/references/Houses/` images as the main style reference for houses and landmark buildings.

- Favor big, rounded, iconic silhouettes with thick black or very dark outlines.
- Use the same thick outline language for important internal details such as doors, roof edges, log ends, windows, signs, and trim.
- Use a readable top-down map perspective that sits naturally on hex tiles: show enough roof/top surface to anchor the building to the tile, while keeping the front face, doorway, and signature feature visible. Avoid realistic perspective, deep vanishing lines, or side-heavy angles that make the sprite feel detached from the hex grid.
- Use flat fills with one-step shadow and highlight shapes. Avoid gradients, painterly texture, tiny material noise, or realistic lighting.
- Make the roof, doorway, and one signature feature carry most of the identity. For example, a shop can use an awning and sign, a lighthouse can use stripes, and a castle can use towers.
- Keep doors and windows oversized, simple, rounded, and readable at normal gameplay zoom.
- Use warm creams, muted browns, olive greens, roof reds, saturated-but-simple blues, soft grays, and occasional earthy accents.
- Color variants should mostly recolor roofs, flags, awnings, or trim while preserving the same silhouette.
- Let specialty buildings be symbolic and playful: shell houses, tree houses, mushroom houses, ruins, towers, and windmills should still follow the same chunky outline and flat-color rules.
- Avoid dense roof shingles, small bricks, realistic wood grain, narrow outlines, thin antennas, and decorative details that disappear at map scale.
- When building sprites are tall, leave visual height above the tile but keep their footprint compact so they do not spill sideways into neighboring hexes.
- Final gameplay building sprites should usually be around 256 px wide for single-tile buildings. Use 128 px wide for very small/simple props, and reserve 384-512 px wide only for large landmarks or multi-tile buildings. Generated source images may be larger, but final imported assets should be cropped, transparent, and downscaled to the smallest size that stays crisp in-game.

Current visual references:

- `assets/resources/forest.png`: flat symbolic tree cluster with thick dark outlines.
- `assets/resources/stone.png`: flat symbolic stone cluster with thick dark outlines.
- `assets/references/Houses/`: chunky, rounded, flat-color house and landmark references with strong token silhouettes and thick dark outlines.
- Reference screenshot style: simple board-game hex tiles with flat fills, heavy outlines, and icon-like terrain objects.

## Project Status

Early prototype setup:

- Godot project created
- Main scene scaffolded in `game.tscn`
- Mobile-friendly Godot renderer settings enabled
- Procedural hex island generation, terrain rendering, and camera controls in place
- Resource gathering, building placement with cost checks, adjacency rules/bonuses, and timed production implemented
- Tech progression, inter-island logistics, power, art, and balancing are still to be built

## Requirements

- Godot 4.6 or newer

The project is configured as a Godot 4 project and currently uses the mobile rendering method.

## Running the Game

1. Open Godot.
2. Click **Import**.
3. Select this repository's `project.godot` file.
4. Open the project.
5. Run the current scene or set `game.tscn` as the main scene once gameplay begins.

## Repository Structure

```text
.
+-- project.godot      # Godot project configuration
+-- game.tscn          # Current scene scaffold
+-- scripts/           # Procedural island prototype code
+-- icon.svg           # Project icon
`-- README.md          # Project documentation
```

## Current Prototype

The project now includes a code-driven hex-tile starter island scaffold:

- `assets/tiles/tile.png` provides a shared white hex mask that terrain draws and tints in code, leaving decorative PNGs free to layer on top.
- `assets/resources/tree.png`, `assets/resources/forest.png`, and `assets/resources/stone.png` provide the first harvestable map resources.
- `assets/buildings/crashed_spaceship.png`, `assets/buildings/logger_camp.png`, `assets/buildings/quarry.png`, `assets/buildings/burner_generator.png`, `assets/buildings/sawmill.png`, and `assets/buildings/dock.png` provide the first placeable buildings.
- `scripts/island/hex_grid.gd` provides pointy-top hex coordinates, neighbors, polygon points, and picking helpers.
- `scripts/island/island_data.gd` stores island size, terrain cells, resources, and buildings.
- `scripts/island/island_generator.gd` creates a small starter island from a seed, places a three-forest triangle cluster, and places two random stones.
- `scripts/island/island_renderer.gd` draws generated terrain, Y-sorted resources/buildings, hover highlighting, and placement preview.
- `scripts/game_types.gd` centralizes the shared gameplay enums (`Terrain`, `BuildingType`, `ResourceNodeType`, `ResourceType`, `AdjacencyKind`) so data and manager classes stay decoupled.
- `scripts/resources/inventory.gd` is a per-owner resource stock (amounts plus a `changed` signal); each island owns one, so inventory is per-island with no global pool.
- `scripts/resources/resource_manager.gd` is a thin facade over the *current* island's `Inventory`, giving the UI and placement logic a stable signal/API while the active island swaps underneath (`set_inventory`). The starter island begins with no resources (the player scavenges the first wood by hand); later islands arrive with just enough to build their first dock.
- `scripts/resources/resource_node_definition.gd` defines resource node properties such as footprint, visual bounds, extracted resource type, and one-time scavenge amount.
- `scripts/ui/floating_text.gd` is a world-space popup that rises and fades, used for scavenge feedback such as `+3 Wood`.
- `scripts/resources/resource_node_database.gd` registers resource node definitions such as trees.
- `scripts/buildings/building_definition.gd` defines building properties such as display name, category, texture, cost, footprint, placement rules, adjacency yields, and production output.
- `scripts/buildings/building_manager.gd` registers building definitions and owns placement validation (`can_place`/`try_place`), adjacency yield calculation, and per-tick production amounts.
- `scripts/buildings/production_manager.gd` runs the production tick, paying out each producing building's resource on its interval.
- `scripts/ui/resource_bar.gd` owns the always-visible top resource bar.
- `scripts/ui/building_menu.gd` owns the bottom building menu UI and emits building selection events.
- `scripts/ui/building_info_panel.gd` owns the building info UI shown when a placed building is clicked, including its live adjacency and production breakdown.
- `scripts/world/world_data.gd` holds every discovered island and a pointer to the current one, so islands persist (with their placed buildings) when the player switches between them.
- `scripts/ui/world_map.gd` is a CanvasLayer overlay (not a separate scene) that lays out discovered islands as clickable tokens in concentric rings around the starter island, and asks `main` to travel to the selected one.
- `scripts/ui/screen_fade.gd` is a reusable full-screen fade used as the transition between islands until a literal sailing animation exists.
- `scripts/main.gd` generates and displays islands, owns the `WorldData` and the current island pointer, drives the production tick for the current island each frame, and handles travel between discovered islands.

Naming note: resource nodes are permanent map objects such as forests and stones, while resources are stored inventory items such as wood and stone. For example, scavenging a `GameTypes.ResourceNodeType.TREE` yields `GameTypes.ResourceType.WOOD`.
Building footprints can be larger than one tile, though the current prototype buildings occupy one hex. `BuildingManager` computes footprint cells and stores them with each placed building.
The starter island (World 1) starts with a required central crashed spaceship — the win-condition wreck the robot begins beside; later discovered islands do not. Buildings require resources to place. Logger's camps and quarries cost 6 Wood, burner generators cost 4 Wood plus 2 Stone, sawmills cost 8 Wood plus 4 Stone, docks cost 10 Wood plus 5 Stone, and additional crashed spaceships cost 8 Wood plus 4 Stone. The dock is the first `Logistics` building: it is built on shoreline sand and must sit next to water, the future launch point for inter-island travel (see `docs/island-unlocks.md`).

### Placement Rules And Adjacency

Buildings declare data-driven placement and adjacency behavior on their `BuildingDefinition`:

- `category`: the menu grouping for the building (`Resources`, `Power`, `Processing`, `Logistics`, or `Utility`).
- `required_terrain`: the terrain every footprint cell must sit on. For example, a logger's camp is built on grass, while a quarry is built on stone.
- `required_adjacent`: each entry must have at least one matching neighbor, or placement is blocked. For example, a logger's camp must be built next to a forest, and a quarry must be built next to a stone deposit.
- `forbidden_adjacent`: placement is blocked if any neighbor matches.
- `adjacency_yields`: Civilization VI style bonuses, where each neighbor matching a `{ kind, type, amount }` rule contributes `amount`. A logger's camp earns +1 per adjacent forest but -1 per adjacent logger's camp, while a quarry earns +1 per adjacent stone deposit but -1 per adjacent quarry.

The placement preview tints red when a rule is unmet, and the building info panel shows the live adjacency breakdown for a placed building.

### Production

Producing buildings declare a `production_resource_type`, `production_base_amount`, and `production_interval_seconds`. Each interval the building pays out `base + adjacency total` (clamped to zero) of its resource into the inventory. A logger's camp produces Wood every 3 seconds, scaling with the number of adjacent forests; a quarry produces Stone every 3 seconds, scaling with adjacent stone deposits. Newly placed buildings wait one full interval before their first payout.

Prototype controls:

- **Left click**: place the selected building
- **Left click on a building**: show building info
- **Left click on a forest or stone**: scavenge it once for a one-time resource burst (shows a floating `+N` popup)
- **Buildings button**: open or close the building menu
- **Esc**: clear the selected building
- **Enter**: generate a new island and travel to it (previously visited islands persist)
- **[** and **]**: switch to the previous or next discovered island
- **M**: open or close the world map (click an island token to travel there)
- **Space**: toggle the hex grid overlay
- **Mouse wheel**: zoom camera
- **Right or middle mouse drag**: pan camera

## Planned Direction

Potential systems for the game:

- 3/4 top-down island maps with clear tile and building readability
- Small island map generation or authored island layouts
- Resource nodes such as wood, stone, food, ore, or energy
- Buildings for gathering, storage, crafting, transport, and population needs
- Construction costs and build placement rules
- Production chains and resource logistics
- Tech tree progression that unlocks new buildings, recipes, and island capabilities
- Power generation and management with simple MW capacity
- Power progression through windmills, solar, coal or oil generators, and possible late-game nuclear power
- Inter-island transport with ships, pipes, power cables, or other logistics networks
- Simple economy, upgrades, or progression goals
- UI for inventory, building selection, and island management

## Development Notes

Keep Godot-generated local files out of version control. The `.gitignore` already excludes `.godot/` and Android export output.

As the project grows, consider documenting:

- Controls
- Core gameplay loop
- Scene organization
- Autoloads and global managers
- Resource and building data formats
- Build/export steps
