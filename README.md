# Resource Isles

Resource Isles is a 2D resource management and building game made with the Godot game engine. It uses a 3/4 top-down perspective, aiming for the readable building layouts of Factorio with the cozy spatial feel of games like Stardew Valley.

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

## Project Status

Early prototype setup:

- Godot project created
- Main scene scaffolded in `game.tscn`
- Mobile-friendly Godot renderer settings enabled
- Gameplay systems, UI, art, and balancing are still to be built

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

The project now includes a code-driven terrain-only starter island scaffold:

- `assets/tiles/water.png`, `assets/tiles/sand.png`, and `assets/tiles/grass.png` provide the current terrain tiles.
- `assets/resources/tree.png` provides the first harvestable map resource.
- `assets/buildings/crate.png` provides the first placeable building.
- `scripts/island/island_data.gd` stores island size, terrain cells, resources, and buildings.
- `scripts/island/island_generator.gd` creates a small starter island from a seed and places two random trees.
- `scripts/island/island_renderer.gd` draws generated terrain, Y-sorted resources/buildings, hover highlighting, and placement preview.
- `scripts/resources/resource_manager.gd` tracks current resource amounts.
- `scripts/resources/resource_node_definition.gd` defines resource node properties such as footprint, visual bounds, extraction output, and extraction interval.
- `scripts/resources/resource_node_database.gd` registers resource node definitions such as trees.
- `scripts/ui/resource_bar.gd` owns the always-visible top resource bar.
- `scripts/ui/building_menu.gd` owns the bottom building menu UI and emits building selection events.
- `scripts/ui/building_info_panel.gd` owns the building info UI shown when a placed building is clicked.
- `scripts/main.gd` generates and displays the island when the game starts.

Naming note: resource nodes are permanent map objects such as trees, while resources are stored inventory items such as wood. For example, `IslandData.ResourceNodeType.TREE` currently extracts into `ResourceManager.ResourceType.WOOD` once per extraction interval.

Prototype controls:

- **Left click**: place the selected building
- **Left click on a building**: show building info
- **Left click on a tree**: extract 1 Wood when its extraction interval is ready
- **Buildings button**: open or close the building menu
- **Esc**: clear the selected building
- **Enter**: regenerate the island with the next seed
- **Space**: toggle the tile grid overlay
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
