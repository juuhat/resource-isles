# To-do list

## Rescue, metals, and manual shipping

See [Rescue, first metals, and boat cargo](docs/rescue-metals-and-cargo.md) for the latest
design direction. Numbers and the copper/drone unlock are proposed starting points.

- [x] Delay electricity until after the actual K9-DA rescue on island 2. Remove the island-1 Burner Generator reward and gate the Windmill; keep robot Operate as direct mechanical power beforehand. Light the Forge unlocks the Burner Generator after rescue and first smelting; Power On asks for its construction and unlocks the Windmill.
- [x] Add a fuel-fired Furnace with animated bellows driven by robot Operate or 2 MW; it needs no iron to build. Cost: 12 stone + 4 wood; recipe: 2 iron ore + 1 coal -> 1 iron ingot every 6 seconds. Unlock it after rescue and before ingot objectives. See [Furnace](docs/furnace.md) and `tools/furnace_check.gd`.
- [x] Add iron ingots and change the Burner Generator construction recipe to use them. Cost: 6 iron ingots + 4 stone + 2 planks; unlock it after the first smelting lesson.
- [x] Make the K9-DA rescue island a copper + stone island (no iron or coal); iron/coal/stone stay on the other ring-1 islands. Harvestable copper applies to new worlds.
- [x] Design copper processing: the Furnace's copper recipe (2 copper ore + 1 wood) and the radar repair it feeds. See [Copper and the radar](docs/copper-and-the-radar.md).
- [ ] Design copper's later uses in wiring/drone controls.
- [ ] Make the robot's boat a unique, upgradeable personal vehicle. Prevent extra docks, dock moves/deletion, and save/load from creating duplicate personal boats; keep K9-DA's passenger space separate from cargo.
- [x] Add a small personal-boat cargo hold (two resource slots of 20 units each), with island/boat icon slots and drag-and-drop transfers. Ask for stack size after dropping, defaulting to the maximum that fits. See [Boat cargo controls](docs/robot-built-boats.md#personal-boat-cargo).
- [x] Allow personal-boat cargo transfers at any suitable reachable shoreline, without a Dock building. Unload starter supplies into a new island's stock before constructing its first buildings.
- [x] Persist boat cargo through sailing, landing, and save/load; enforce stock and capacity limits without duplication or item loss. Checked by `tools/boat_cargo_check.gd`.
- [ ] Replace the early automatic-route lesson with a manual construction-supply delivery to island 2; tune cargo capacity and recipes so the first furnace does not require tedious repeated trips.
- [ ] Delay automatic trade routes until after manual hauling, proposed after copper. Make other ships autonomous cargo drones requiring docks at both endpoints; reserve player travel for the personal boat.
- [ ] Reconcile old boat-tier, dock-bootstrap, quest, and power-ladder plans with this direction. Verify a fresh-game bootstrap with no pre-rescue generator and handle existing saves explicitly.

## Copper and the radar

See [Copper and the radar](docs/copper-and-the-radar.md). K9-DA's copper island now lies in the home waters, open from the start; after the rescue, copper is mined by hand, hauled home in the newly unlocked cargo hold, smelted at the crash site and wired into the ship's radar, which reveals ring 1.

- [x] Move K9-DA's island into the home waters (0.75 rings, `WorldData.HOME_WATERS_RINGS`), closer than ring 1, with map rules keeping it there and every other island out.
- [x] Add the Copper Glint, Haul It Home, First Melt and Eyes on the Horizon milestones; Set Sail no longer reveals ring 1 and the rescue no longer unlocks the Furnace.
- [x] Lock the boat's cargo hold until Copper Glint.
- [x] Give the Furnace a copper and an iron recipe, picked in its info panel; old Furnaces stay on iron.
- [x] Add the robot's Repair action at the wreck, with saved progress (`ShipRepairs`, `WorldData.ship_repairs`). Checked by `tools/radar_repair_check.gd`.
- [ ] Playtest the chain from a fresh game: the 6-ore / 3-ingot amounts, the sail between the crash site and K9-DA's island, and whether the signal showing from the very start reads well.
- [x] Hide the chart's radar sweep until the radar is repaired; it fades in when the repair finishes.
- [ ] Show the radar on the wreck model (broken, then working).
- [ ] Design the next ship parts and what each unlocks.
- [ ] Existing saves keep `copper_isle` on ring 1 where it was saved; decide whether to move it or leave old saves as they are.

## Quest design

See [Quest design review](docs/quest-design.md) for the current chain, proposed teaching sequence,
and unresolved budgets and unlock decisions. These recommendations are not yet implemented.

- [x] Replace the Scale Up 100-resource gate with a construction lesson: *Lay the Foundations* asks for one Logger's Camp and one Quarry.
- [ ] Add objectives teaching manual Operate power followed by automatic power.
- [ ] Make the first supply-line objective track wood manually delivered by personal boat from home to the frontier colony; teach autonomous routes later.
- [ ] Define the payoff after trade; unlock smelting before requiring ingots when the metal-production chain is added.
- [ ] Reconcile the older power progression: ring-1 coal supports the first Furnace, while electricity waits for rescue and dedicated coal generation can arrive later.
- [ ] Verify new quest objectives and unlocks with fresh games and existing saves.

## Player model

- [x] Create a first cream-and-teal salvage robot model with an editable mechanical pivot rig and idle/walk clips; integrate movement-driven animation switching. See [Player model](docs/player-model.md).
- [ ] Playtest the new robot's proportions, visibility, and walk rhythm at gameplay zoom.
- [ ] Add harvesting, building, operating, and rescue animations with gameplay hooks.
- [ ] Update the robot command-bar portrait to match the accepted model.

## Robot construction

- [x] Make construction a robot task: choose a building in the build menu, place a blueprint, then automatically command the robot to walk to a reachable work spot and build it. Avoid requiring a second Build click for every placement.
- [x] Reserve construction materials when placing the blueprint and return them if it is cancelled. Reserve the footprint and show a transparent 3D building preview until construction finishes. (The blueprint is a teal hologram the real model prints up through; see [Construction](docs/building-footprints.md#construction).)
- [x] Use a short construction time. Leave interrupted blueprints and their progress in place, provide a Build action in the robot's command bar to resume them, and persist blueprints, reserved materials, and progress through save/load.
- [x] Start the completed building's power consumption and production only after construction finishes. Count quest construction objectives on completion rather than blueprint placement.
- [x] Teach blueprint placement and completed robot construction in an early quest (Lay the Foundations). Keep moving completed buildings instant for now so layout experimentation stays easy.
- [ ] Follow Lay the Foundations with an Operate lesson (see Quest design above).
- [ ] Playtest construction: build time (6 s default), the hologram and seam readability at gameplay zoom, and whether the robot should auto-resume blueprints after loading a save.

## Playtest feedback — 2026-10-03

- [x] Replace the tool pickups' ground icons with readable 3D models. Make the axe, pickaxe, and hammer (now a wrench) look like equipment designed for the robot, using the game's salvage-tech style and teal accents.
- [ ] Reduce the first gathering quest (Break Ground) from 20 wood and 20 stone. Try around 5 of each, and tune the targets and building costs together so the player has enough materials to build the next quest's buildings without another long gathering stretch. Currently, the Logger's Camp and Quarry cost 6 wood each, so 5 wood alone would not cover both.
- [x] Use 3D building models in the placement preview, matching the model, size, and orientation of the finished building. Preserve valid/invalid placement feedback and make sure the preview matches the final footprint.
- [x] Gate the Windmill behind a quest instead of unlocking it by default. Power On grants the unlock after building the first Burner Generator; the build menu shows that requirement. A dedicated coastal-wind teaching milestone remains a future refinement.
- [x] Show a red 3D lightning-bolt power indicator above each unpowered building that requires power. Keep it readable at gameplay zoom, and remove it as soon as generator power or the robot's Operate action powers the building.

## Robot access and clipping

The robot walks through buildings (so the player can't wall it in) but around resource nodes and the crashed spaceship, and never parks on either; it works them from beside them or from a building's `WorkSpot` (see [docs/player-unit-and-manual-gathering.md](docs/player-unit-and-manual-gathering.md), checked by `tools/robot_access_check.gd`).

- [x] Block resource nodes in pathfinding (buildings stay walkable) and interact from an adjacent free cell. Keep the clicked cell as the action target, and tie action checks to the target rather than requiring the robot's cell to equal it. Update the manual power and gathering arrival checks at the same time.
- [x] Handle packed islands where a target has no reachable free neighbor. Paths cross an obstacle only as a last resort, and a fully enclosed target is worked from on top of it.
- [x] Route to each asset's exported `WorkSpot` instead of a neighboring cell. The robot takes the shortest route straight onto the building's tile, its last step going onto the spot, then turns to face the building. The logger camp and sawmill export one so far; buildings without one are still worked from a neighbouring tile. Sub-tile waypoints or a navigation mesh would still help on dense maps.
- [x] Revalidate paths when construction changes the map, and never place geometry over the robot's (or K9-DA's) current position.
- [ ] Re-author the other buildings as true-tile workbenches with `WorkSpot`/`Footprint` markers (quarry, mines; then the windmill model), and set their `visual_size_tiles` to width / `TILE`. The logger camp, sawmill, dock and burner generator are done. Give the iron and coal mines different big shapes: today only their ore lumps differ.
- [ ] The crashed ship renders 1.6 tiles wide from one cell, so it overlaps its neighbours, including the robot's spawn cell. Reserve its real extent with a multi-tile footprint ([docs/building-footprints.md](docs/building-footprints.md)) or scale it down.
- [ ] Footprint follow-ups: switch the logger camp and sawmill to `true_tile_model` (same scale, no measured fit); show the R / Shift+R rotate hint while placing, not only in the build menu.
- [ ] While the robot stands in a building's yard, left-clicking that tile selects the robot rather than the building. Decide which should win.
- [ ] Optionally add a selection ring or occlusion silhouette so the robot stays visible behind roofs. This helps visibility only; it doesn't prevent clipping. Don't disable depth testing globally.

## Code structure

Follow-ups from the code review and the world-cell refactor.

- [ ] Play-test the refactored game by hand; the checks run headless and never look at the screen. Cover hovering and selecting on land and at sea, sailing (including clicks right next to an island), landing, K9-DA following between islands, placing and moving buildings, and the water around islands. Saves are now version 3 in `savegame_v3.sav`, and older saves aren't loaded.
- [ ] Finish splitting `main.gd`: move building placement into a `BuildingPlacement` controller, the way `RobotController` and `BoatController` were split off. It takes the selected building, placing blueprints, moving, cancelling and deleting buildings, the placement preview, and putting a building lifted mid-move back for a save (`_try_place_selected_building`, `_select_building`, `_select_no_building`, `_on_building_move_requested`, `_try_finish_move`, `_cancel_building_move`, `_on_building_delete_requested`, `_apply_selected_building`, and the move handling in `save_game`). Let it connect the build menu's and info panel's signals itself, as `BoatController` does with the cargo panel, and update the checks that call those functions on `game`.
- [ ] In `RobotController`, replace the three task flag and cell pairs (`is_harvesting`/`harvest_cell`, `is_operating`/`operate_cell`, `is_constructing`/`construct_cell`) with one current task and its target. Only one runs at a time already.
- [ ] Give building entries an API or a typed class. `build_progress` and `boat_launched` are still read and written straight on the dictionaries outside `IslandData` (`HexPathfinder.deck_cells`, `WorldNavigation`, `BuildingManager`, `BoatController`, `IslandRenderer`, `main.gd`).
- [ ] Define shared world constants once: `RING_SPACING` (`WorldView` and `WorldNavigation`), the 128-unit cell size (`IslandRenderer.cell_size` and `WorldNavigation.CELL_SIZE`) and sea level (`IslandRenderer.WATER_TOP_Y` and `WorldNavigation.SEA_Y`). Today they only agree by having the same values.
- [ ] Share small duplicated helpers: the turning code in `PlayerUnit` and `Dog`, the hex cap mesh (`IslandRenderer`, `PlayerUnit`), `_resource_icon` (three UI scripts), `_clear` (`IslandRenderer`, `BuildingInfoPanel`, `WorldView`), and the four cached-material builders in `IslandRenderer`.
- [ ] Remove dead code: `IslandRenderer._tile_material` and `get_hovered_resource_node_type`, `BuildingManager.get_label`, the never-set scavenge state (`IslandData.can_scavenge` and `mark_scavenged`; `scavenged_cells` is still saved), the unused argument of `WorldView.set_current_coord`, and the no-op match arm in `main.gd`'s `_apply_reward`.
- [ ] Update stale descriptions: `IslandRenderer`'s header still describes the old 2D sprite renderer, and the README opens by calling the game 2D.
- [ ] `IslandRenderer.refresh()` rebuilds every model on the island for any change, such as an item picked up or a building placed. Update just what changed once islands get bigger.
- [ ] Headless checks only see class names Godot has registered, which happens when the editor rescans the project or on `--import`. Right after adding a `class_name` script, a check run can fail with "not declared" until then. Consider an `-Import` switch on `tools/run_checks.ps1`, only safe while the editor is closed.

## World map and island designs

See [World map and island designs](docs/world-map-and-island-designs.md). Replace generating the world at game start with a premade, hand-placed map of islands and islets, the same for every player. Islets are just smaller islands; the map keeps today's 4-ring disc.

- [x] Add the island design (`.island`) and world map (`world_map.cfg`) formats, loading and placing designs, and a check that loads every design. Checked by `tools/island_design_check.gd`. The first design is `assets/world/islands/atoll_small.island`.
- [x] Bake today's seed-1 world into designs and a world map, and check that building from the map gives the same cells. A one-off tool (removed in the next step; see commit 807ad51) wrote `assets/world/world_map.cfg` and 13 designs, and compared every island cell for cell. Island ids follow the progression docs (`crash_site`, `copper_isle`, `iron_isle`, …).
- [x] Build new games from the world map: islands keyed by their centre cell with their map id saved, loops over islands instead of slots, reveal by distance, island-sized water planes and click reach, discovery exploring the sea under an island's patch, trade trip time between centres, save version 3 (version 2 saves aren't converted). A saved game gains islands added to the map later. The seed-sweeping checks now check the islands on the map.
- [x] Remove the free dock supplies (`WorldBuilder._stock_bootstrap_supplies`): new islands start with an empty stock, and dock materials come by boat.
- [ ] Play-test sailing to the ring-1 islands: an island now owns its land and two coast rings rather than a 30 × 24 rectangle of water, so the robot's sight discovers it about 10 cells from its land instead of 15 to 17. Widen the sighting range for islands if that feels too late.
- [x] Add `tools/world_map_check.gd`: islands don't overlap and stay within the sea, every island has a dock shore, nothing is walled in by deposits, the start island has the wreck and tools, and K9-DA waits on an island in the home waters at a spot reachable from the shore. The rules are in `tools/world_map_rules.gd`.
- [x] Add `tools/world_map_preview.gd`: the whole map as an image (`art/previews/world_map/world_map.png`), or a close-up with `--around column,row --cells n`, with ground colours, deposits, island ids and centres, a coordinate grid, the ring frontiers, and rule problems circled in red.
- [ ] Before placing islets close to other islands, handle overlapping water planes: each island draws its own toon-water plane, reaching about 12 cells past its land, and a neighbour's plane draws over its shore.
- [ ] Turn the generator into a design tool (`tools/design_island.gd`) whose land blob scales with the profile's size.
- [ ] Design and place new islands and islets across the map.
- [ ] Later: an island painter that reads and writes `.island` files.
