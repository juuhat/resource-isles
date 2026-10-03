# To-do list

## Playtest feedback — 2026-10-03

- [ ] Replace the tool pickups' ground icons with readable 3D models. Make the axe, pickaxe, and hammer look like equipment designed for the robot, using the game's salvage-tech style and teal accents.
- [ ] Reduce the first gathering quest (Break Ground) from 20 wood and 20 stone. Try around 5 of each, and tune the targets and building costs together so the player has enough materials to build the next quest's buildings without another long gathering stretch. Currently, the Logger's Camp and Quarry cost 6 wood each, so 5 wood alone would not cover both.
- [ ] Use 3D building models in the placement preview, matching the model, size, and orientation of the finished building. Preserve valid/invalid placement feedback and make sure the preview matches the final footprint.
- [ ] Gate the Windmill behind a quest instead of unlocking it by default. Add a milestone that introduces fuel-free coastal power and rewards the Windmill unlock; show the required quest in the build menu while it is locked.
- [x] Show a red 3D lightning-bolt power indicator above each unpowered building that requires power. Keep it readable at gameplay zoom, and remove it as soon as generator power or the robot's Operate action powers the building.

## Robot access and clipping

The robot currently walks through buildings: pathfinding allows every land cell and `PlayerUnit` visits cell centers, so traversal passes through occupied tiles. Shrinking models (see [docs/building-style-palette.md](docs/building-style-palette.md)) won't fix this on its own, and offsetting only the final destination isn't enough.

- [ ] Block occupied cells in pathfinding and interact from an adjacent free cell. Keep the clicked cell as the action target, and tie action checks to the target rather than requiring the robot's cell to equal it. Update the manual power and gathering arrival checks at the same time.
- [ ] Handle packed islands where a target has no reachable free neighbor.
- [ ] Route to each asset's exported `WorkSpot` instead of a neighboring cell: path through obstacles inflated by the robot radius plus a small gap, then face the target and gather or operate. Sub-tile waypoints or a navigation mesh will work better on dense maps.
- [ ] Reserve work spots during placement so another building can't cover them. Revalidate paths when construction changes the map, and never place geometry over the robot's current position.
- [ ] Optionally add a selection ring or occlusion silhouette so the robot stays visible behind roofs. This helps visibility only; it doesn't prevent clipping. Don't disable depth testing globally.
