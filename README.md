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
- `scripts/island/island_renderer.gd` draws generated terrain, resources, placed buildings, hover highlighting, and placement preview.
- `scripts/ui/building_menu.gd` owns the bottom building menu UI and emits building selection events.
- `scripts/main.gd` generates and displays the island when the game starts.

Prototype controls:

- **Left click**: place the selected building
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
