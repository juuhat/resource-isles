# Resource Isles

Resource Isles is a cozy resource management and building game made with Godot. It is played on
a Civilization VI style hex grid with building adjacencies, seen from a three-quarter top-down
camera in a low-poly 3D style. The aim is Factorio's readable building layouts and Anno's
inter-island supply lines, in the calm, small-scale feel of Stardew Valley.

A small salvage robot crash-lands on a flat-disc planet. Its robot dog, Companion Unit K9-DA, is
thrown onto a neighbouring island. The robot bootstraps industry from island materials, builds a
boat and rescues the dog. Then it finds out the planet is rich enough to rebuild the ship (see
[Intro Story](docs/intro-story.md)).

## Status

Early prototype. The opening is playable from the crash through the K9-DA rescue, copper
smelting and the radar repair, the first iron smelting and the first generators. Autonomous
cargo drones and the rest of the ship repair are still to come. See the [To-do list](TODO.md)
for outstanding work and playtest feedback.

## Gameplay Loop

1. **Gather by hand.** The robot wakes beside its crashed ship, recovers its scattered tools,
   and harvests wood and stone.
2. **Build.** Place a blueprint from the build menu; the robot walks over and prints the
   building. Buildings have terrain and neighbour rules, and earn Civ VI style adjacency
   bonuses.
3. **Power.** At first the robot powers buildings by hand with **Operate**; later Burner
   Generators and Windmills supply MW.
4. **Process.** A Sawmill turns logs into planks; a Furnace smelts copper or iron ore into
   ingots.
5. **Sail.** A Dock launches the robot's personal boat. The robot sails out through the fog of
   exploration to K9-DA's island nearby, rescues K9-DA and finds copper there, and carries it
   home in the boat's small cargo hold.
6. **Repair.** Copper ingots fix the crashed ship's radar, which charts the first ring of
   islands further out, each with its own inventory.
7. **Connect.** Trade routes between Docks move goods between islands; every island keeps
   producing while the robot is elsewhere.

Quests drive the progression. They complete by playing (no spending) and unlock buildings,
robot abilities and more of the map.

## Core Design

- Islands are small and should generally fit within one view; building space is
  intentionally limited.
- The player starts on a single island with limited resources.
- Quests and technology unlock new buildings, recipes, logistics tools and islands.
- New islands bring new resources, larger deposits, or better production opportunities.
- Inter-island logistics become a major challenge: ships, pipes, power cables and other
  transport.
- Power is simple and capacity-based: generators supply MW and consumers draw it.
- Every player sails the same hand-made world map (see
  [World Map and Island Designs](docs/world-map-and-island-designs.md)).

## Art Direction

A relaxing little evening game: calm, readable, cozy, and a little darker than a bright
tropical island game. Muted blue-green water, darker grass and sand, soft shorelines, and
effects that support the quiet mood.

Models follow the **Low Poly Workshop** style: chunky angular silhouettes, flat faces, solid
matte colours, no outlines or painted texture. Buildings are robot-built salvage: local wood,
stone and canvas, with fat, readable robot tech bolted on and teal as the recurring tech accent.

- [Low Poly Workshop art direction](docs/building-style-palette.md): palette, materials and
  reference boards
- [Icons and 2D art](docs/icons-and-2d-art.md): how the style carries into UI icons
- [3D Models](docs/3d-models.md): how models are integrated in the game

## Requirements

- Godot 4.6 or newer (developed and tested with **Godot 4.6.3-stable**), at
  `C:\Users\rasek\godot\Godot_v4_6_3_stable_win64\`. The project uses the Mobile renderer
  and Jolt Physics.
- Blender 5.0, at `C:\Program Files\Blender Foundation\Blender 5.0`, only for rebuilding 3D
  models.

## Running the Game

From the repository root in PowerShell:

```powershell
$godotExe = 'C:\Users\rasek\godot\Godot_v4_6_3_stable_win64\Godot_v4.6.3-stable_win64_console.exe'
& $godotExe --path .
```

Add `--editor` to open the project in the editor instead. The main scene is `game.tscn`.

The game saves to `user://savegame_v3.sav`. Older save versions aren't loaded. See
[Controls](docs/controls.md) for keys and mouse controls, including debug-build cheats.

## Running the Checks

`tools/*_check.gd` are headless check scripts. Run them all, or some with `-Filter`:

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_checks.ps1
powershell -ExecutionPolicy Bypass -File tools/run_checks.ps1 -Filter boat,furnace
```

The runner uses Godot from `-Godot <path>`, `$env:GODOT`, or the console build on `PATH`. Each
check gets its own empty `user://` folder, so checks never see each other's saves and your
real save is never touched. **Use the runner** rather than running a check directly with
`--script`.

Every check installs `tools/check_watchdog.gd`. A failed `CheckWatchdog.require()` (used
instead of `assert()`, which only stops the current function and leaves headless Godot idling)
exits with code 1 straight away, and a check still running after 30 s is stopped. When a
single check is run directly, the watchdog backs up the save first and restores it however the
check ends.

## Tools

- **Model builders.** The `tools/build_*.py` scripts build a model headlessly in Blender. Each
  writes the `.glb` to `assets/models/<kind>/`, the `.blend` source to `art/blender/`, and a
  preview render to `art/previews/`. They share primitives, export and the preview studio
  through `tools/lowpoly_kit.py`, which also holds the workshop palette as linear RGB.

  ```powershell
  & 'C:\Program Files\Blender Foundation\Blender 5.0\blender.exe' --background --python tools/build_quarry.py
  ```

- **World map preview.** `tools/world_map_preview.gd` draws the world map
  (`assets/world/world_map.cfg`) as one image, with every island, the ring frontiers, and any
  island that breaks a map rule circled. It needs a window, so leave out `--headless`:

  ```powershell
  & $godotExe --path . --script res://tools/world_map_preview.gd -- [output.png] [--around 25,-29] [--cells 40]
  ```

- **Captures.** `tools/*_capture.gd` and `tools/*_screenshot.gd` render comparison images
  for visual passes. They never touch the save.

## Repository Layout

```text
.
+-- project.godot   # Godot project configuration
+-- game.tscn       # Main scene
+-- scripts/        # Game code (see docs/architecture.md)
+-- assets/         # Models, icons, shaders, audio, island designs and the world map
+-- art/            # Blender sources, concepts, style boards and previews (not loaded by the game)
+-- tools/          # Checks, the check runner, Blender model builders, previews and captures
+-- docs/           # Design and technical notes
`-- TODO.md         # Outstanding work and playtest feedback
```

## Docs

Some older design docs open with a note pointing to the newer direction that replaces them.

**Code**

- [Architecture](docs/architecture.md): what each script does, and how buildings,
  placement and production work
- [Controls](docs/controls.md)
- [Building Footprints](docs/building-footprints.md): multi-tile buildings, rotation and
  construction

**Story and progression**

- [Intro Story](docs/intro-story.md)
- [Quest Design Review](docs/quest-design.md)
- [Copper and the Radar](docs/copper-and-the-radar.md): the copper chain after the rescue, Furnace
  recipes and repairing the ship (latest progression)
- [Ship Repair Roadmap](docs/ship-repair-roadmap.md): the planned ship parts after the radar, up
  to the Power Core
- [Rescue, First Metals, and Boat Cargo](docs/rescue-metals-and-cargo.md)
- [First Island Progression](docs/first-island-progression.md) and
  [Second Island Progression](docs/second-island-progression.md)
- [Island Unlocks, the Dock, and the World Map](docs/island-unlocks.md)
- [Progression, Build Restrictions, and Power](docs/progression-and-power.md) and
  [Power Sources](docs/power-sources.md)
- [Furnace](docs/furnace.md)
- [Postgame Leaderboards](docs/postgame-leaderboards.md)

**World and islands**

- [World Map and Island Designs](docs/world-map-and-island-designs.md)
- [Island Generation, Biomes, and Resources](docs/island-generation.md)
- [Island Visual Variety](docs/island-visual-variety.md)

**Robot and boats**

- [Player Unit and Manual Gathering](docs/player-unit-and-manual-gathering.md)
- [Robot-Built Boats](docs/robot-built-boats.md)

**Art and models**

- [Low Poly Workshop art direction](docs/building-style-palette.md),
  [Icons and 2D Art](docs/icons-and-2d-art.md), [3D Models](docs/3d-models.md)
- [Player Model](docs/player-model.md), [K9-DA Model](docs/k9-da-model.md),
  [Spaceship Model](docs/spaceship-model.md),
  [Shared Generator Model](docs/shared-generator-model.md)
- [Meshy Guide](docs/meshy-guide.md)
- [Terrain Visual Pass 1](docs/terrain-visual-pass-1.md) and
  [Visual Improvements TODO](docs/visual-improvements-todo.md)

## Development Notes

- Godot's local `.godot/` folder, Android export output and Blender `.blend1` backups are
  ignored by git.
- Gameplay data lives in static catalogs: add buildings in
  `scripts/buildings/building_definitions.gd`, quests in `scripts/quests/quest_catalog.gd`,
  resources in `scripts/resources/resource_database.gd`, and islands in
  `assets/world/islands/` plus `assets/world/world_map.cfg`.
