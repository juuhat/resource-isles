# To-do list

## Rescue, metals, and manual shipping

See [Rescue, first metals, and boat cargo](docs/rescue-metals-and-cargo.md) for the latest
design direction. Numbers and the copper/drone unlock are proposed starting points.

- [ ] Delay electricity until after the actual K9-DA rescue on island 2. Remove the island-1 Burner Generator reward and gate the Windmill; keep robot Operate as direct mechanical power beforehand.
- [ ] Add a fuel-fired Furnace that needs no electricity or iron to build. Proposed cost: 12 stone + 4 wood; proposed smelting recipe: 2 iron ore + 1 coal -> 1 iron ingot. Unlock the Furnace after rescue and before ingot objectives.
- [ ] Add iron ingots and change the Burner Generator construction recipe to use them. Proposed cost: 6 iron ingots + 4 stone + 2 planks; unlock it after the first smelting lesson.
- [ ] Keep island 2's iron/coal/stone resources; introduce copper on another ring-1 island as the next exploration target. Design copper processing and its later uses in wiring/drone controls.
- [ ] Make the robot's boat a unique, upgradeable personal vehicle. Prevent extra docks, dock moves/deletion, and save/load from creating duplicate personal boats; keep K9-DA's passenger space separate from cargo.
- [x] Add a small personal-boat cargo hold (two resource slots of 20 units each), with island/boat icon slots and drag-and-drop transfers. Ask for stack size after dropping, defaulting to the maximum that fits. See [Boat cargo controls](docs/robot-built-boats.md#personal-boat-cargo).
- [x] Allow personal-boat cargo transfers at any suitable reachable shoreline, without a Dock building. Unload starter supplies into a new island's stock before constructing its first buildings.
- [x] Persist boat cargo through sailing, landing, and save/load; enforce stock and capacity limits without duplication or item loss. Checked by `tools/boat_cargo_check.gd`.
- [ ] Replace the early automatic-route lesson with a manual construction-supply delivery to island 2; tune cargo capacity and recipes so the first furnace does not require tedious repeated trips.
- [ ] Delay automatic trade routes until after manual hauling, proposed after copper. Make other ships autonomous cargo drones requiring docks at both endpoints; reserve player travel for the personal boat.
- [ ] Reconcile old boat-tier, dock-bootstrap, quest, and power-ladder plans with this direction. Verify a fresh-game bootstrap with no pre-rescue generator and handle existing saves explicitly.

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
- [ ] Gate the Windmill behind a quest instead of unlocking it by default. Add a milestone that introduces fuel-free coastal power and rewards the Windmill unlock; show the required quest in the build menu while it is locked.
- [x] Show a red 3D lightning-bolt power indicator above each unpowered building that requires power. Keep it readable at gameplay zoom, and remove it as soon as generator power or the robot's Operate action powers the building.

## Robot access and clipping

The robot walks through buildings (so the player can't wall it in) but around resource nodes, and never parks on either; it works them from beside them or from a building's `WorkSpot` (see [docs/player-unit-and-manual-gathering.md](docs/player-unit-and-manual-gathering.md), checked by `tools/robot_access_check.gd`).

- [x] Block resource nodes in pathfinding (buildings stay walkable) and interact from an adjacent free cell. Keep the clicked cell as the action target, and tie action checks to the target rather than requiring the robot's cell to equal it. Update the manual power and gathering arrival checks at the same time.
- [x] Handle packed islands where a target has no reachable free neighbor. Paths cross an obstacle only as a last resort, and a fully enclosed target is worked from on top of it.
- [x] Route to each asset's exported `WorkSpot` instead of a neighboring cell. The robot takes the shortest route straight onto the building's tile, its last step going onto the spot, then turns to face the building. The logger camp and sawmill export one so far; buildings without one are still worked from a neighbouring tile. Sub-tile waypoints or a navigation mesh would still help on dense maps.
- [x] Revalidate paths when construction changes the map, and never place geometry over the robot's (or K9-DA's) current position.
- [ ] Re-author the other buildings as true-tile workbenches with `WorkSpot`/`Footprint` markers (quarry, mines; then the windmill model), and set their `visual_size_tiles` to width / `TILE`. The logger camp, sawmill, dock and burner generator are done. Give the iron and coal mines different big shapes: today only their ore lumps differ.
- [ ] The crashed ship renders 1.6 tiles wide from one cell, so it overlaps its neighbours, including the robot's spawn cell. Reserve its real extent with a multi-tile footprint ([docs/building-footprints.md](docs/building-footprints.md)) or scale it down.
- [ ] Footprint follow-ups: switch the logger camp and sawmill to `true_tile_model` (same scale, no measured fit); show the R / Shift+R rotate hint while placing, not only in the build menu.
- [ ] While the robot stands in a building's yard, left-clicking that tile selects the robot rather than the building. Decide which should win.
- [ ] Optionally add a selection ring or occlusion silhouette so the robot stays visible behind roofs. This helps visibility only; it doesn't prevent clipping. Don't disable depth testing globally.
