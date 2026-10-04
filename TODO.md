# To-do list

## Player model

- [x] Create a first cream-and-teal salvage robot model with an editable mechanical pivot rig and idle/walk clips; integrate movement-driven animation switching. See [Player model](docs/player-model.md).
- [ ] Playtest the new robot's proportions, visibility, and walk rhythm at gameplay zoom.
- [ ] Add harvesting, building, operating, and rescue animations with gameplay hooks.
- [ ] Update the robot command-bar portrait to match the accepted model.

## Playtest feedback — 2026-10-03

- [ ] Replace the tool pickups' ground icons with readable 3D models. Make the axe, pickaxe, and hammer look like equipment designed for the robot, using the game's salvage-tech style and teal accents.
- [ ] Reduce the first gathering quest (Break Ground) from 20 wood and 20 stone. Try around 5 of each, and tune the targets and building costs together so the player has enough materials to build the next quest's buildings without another long gathering stretch. Currently, the Logger's Camp and Quarry cost 6 wood each, so 5 wood alone would not cover both.
- [ ] Use 3D building models in the placement preview, matching the model, size, and orientation of the finished building. Preserve valid/invalid placement feedback and make sure the preview matches the final footprint.
- [ ] Gate the Windmill behind a quest instead of unlocking it by default. Add a milestone that introduces fuel-free coastal power and rewards the Windmill unlock; show the required quest in the build menu while it is locked.
- [x] Show a red 3D lightning-bolt power indicator above each unpowered building that requires power. Keep it readable at gameplay zoom, and remove it as soon as generator power or the robot's Operate action powers the building.

## Robot access and clipping

The robot walks through buildings (so the player can't wall it in) but around resource nodes, and never parks on either; it works them from beside them or from a building's `WorkSpot` (see [docs/player-unit-and-manual-gathering.md](docs/player-unit-and-manual-gathering.md), checked by `tools/robot_access_check.gd`).

- [x] Block resource nodes in pathfinding (buildings stay walkable) and interact from an adjacent free cell. Keep the clicked cell as the action target, and tie action checks to the target rather than requiring the robot's cell to equal it. Update the manual power and gathering arrival checks at the same time.
- [x] Handle packed islands where a target has no reachable free neighbor. Paths cross an obstacle only as a last resort, and a fully enclosed target is worked from on top of it.
- [x] Route to each asset's exported `WorkSpot` instead of a neighboring cell. The robot takes the shortest route straight onto the building's tile, its last step going onto the spot, then turns to face the building. The logger camp and sawmill export one so far; buildings without one are still worked from a neighbouring tile. Sub-tile waypoints or a navigation mesh would still help on dense maps.
- [x] Revalidate paths when construction changes the map, and never place geometry over the robot's (or K9-DA's) current position.
- [ ] Re-author the other buildings as true-tile workbenches with `WorkSpot`/`Footprint` markers (quarry, mines; then the windmill, burner generator and dock models), and set their `visual_size_tiles` to width / `TILE`. The logger camp and sawmill are done. Give the iron and coal mines different big shapes: today only their ore lumps differ.
- [ ] The crashed ship renders 1.6 tiles wide from one cell, so it overlaps its neighbours, including the robot's spawn cell. Reserve its real extent or scale it down.
- [ ] While the robot stands in a building's yard, left-clicking that tile selects the robot rather than the building. Decide which should win.
- [ ] Optionally add a selection ring or occlusion silhouette so the robot stays visible behind roofs. This helps visibility only; it doesn't prevent clipping. Don't disable depth testing globally.
