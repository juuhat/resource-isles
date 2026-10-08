# Copper and the radar — 2026-10-07

Implemented. After the rescue, K9-DA's island teaches the next step: the robot finds copper,
learns to carry it home by boat, smelts it at the crash site and wires it into the ship's radar,
the first part of the ship it repairs. The repaired radar charts the first ring of islands. This
replaces Set Sail revealing ring 1 and the rescue unlocking the Furnace
([Rescue, first metals, and boat cargo](rescue-metals-and-cargo.md) and [Furnace](furnace.md)
record the earlier order).

## The home waters

K9-DA's island (`copper_isle`) now lies in the **home waters**: the sea the boat can sail from
the start, about 0.75 rings (37 cells) from the middle of the world
(`WorldData.HOME_WATERS_RINGS`). It sits about 20 cells from the crash site, closer than the
first ring (50 cells out). Like the start island, it's open "straight away": no quest reveals
it, and K9-DA's signal pings on the chart from the start of the game.

`WorldData.frontier_rings()` is the one place the frontier is worked out: the home waters while
no ring is revealed, then half a ring past the last revealed ring as before. Sailing
(`WorldNavigation.sailing_radius`), what counts as revealed (`WorldData.is_revealed`) and the
chart's frontier (`WorldView`) all read it.

The map rules (`tools/world_map_rules.gd`) check that all of K9-DA's island, coast included,
lies in the home waters, and that no other island's centre does: the rest wait for the radar.

## The chain

| Milestone | Objectives | Reward |
| --- | --- | --- |
| Set Sail | Build a Dock | None; the signal is already on the chart |
| Follow the Signal | Discover K9-DA's island | — |
| **Copper Glint** | Rescue K9-DA; gather 6 copper ore | The boat's cargo hold (`RobotUpgrade.CARGO_HOLD`) |
| **Haul It Home** | Unload 6 copper ore from the boat at the start island | Furnace |
| **First Melt** | Build a Furnace; smelt 3 copper ingots | Repairing the ship (`RobotUpgrade.REPAIRING`) |
| **Eyes on the Horizon** | Repair the radar | Reveals ring 1 |
| Strike Iron | Gather 5 iron ore (on a ring-1 island) | Iron Mine, Coal Mine |
| Light the Forge | Smelt 6 iron ingots | Burner Generator |

The amounts line up: 6 copper ore make 3 copper ingots, which is what the radar takes. The
rescue (the MAIN quest) no longer has a reward of its own; Copper Glint asks for it, so the
chain waits there until K9-DA is aboard.

- **Copper Glint.** Copper lies only on K9-DA's island, so it's mined by hand there.
- **Haul It Home.** The cargo hold is locked until Copper Glint: the Cargo action is hidden and
  the hold won't open (`BoatController.has_cargo_hold`). Nothing before needs it. Copper ore
  unloaded at the start island counts (`Stat.COPPER_ORE_SHIPPED_HOME`); loading doesn't.
- **First Melt.** The Furnace smelts copper over a wood fire. The crash site has wood and no
  coal.
- **Eyes on the Horizon.** See [Repairing the ship](#repairing-the-ship).

## Furnace recipes

The Furnace has two recipes (`BuildingDefinition.recipes`), each 1 ingot every 6 s:

| Recipe | Inputs |
| --- | --- |
| Copper ingot | 2 copper ore + 1 wood |
| Iron ingot | 2 iron ore + 1 coal |

A new Furnace starts on copper, the first in the list. Its info panel has a button for each
recipe; switching takes effect from the next batch. The choice is kept on the building
(`recipe` in the building entry, `IslandData.get_recipe`) and goes with it when it's moved.
Furnaces from saves made before recipes existed only ever smelted iron, so loading keeps them on
iron (`BuildingManager.migrate_recipes`). Production asks `BuildingManager.get_recipe` what a
building makes and what it costs.

The copper ingot icon comes from the shared ingot builder:
`blender --background --python tools/build_ingot.py -- copper` (`-- iron` rebuilds the iron
one).

## Repairing the ship

The crashed ship's parts are repaired one after another, in `GameTypes.ShipPart` order. The radar
is the only part so far. `ShipRepairs` holds each part's name, materials and work time; progress
is `WorldData.ship_repairs` (part → 0..1), which is saved.

| Part | Materials | Robot work |
| --- | --- | --- |
| Radar | 3 copper ingots | 8 s |

Once First Melt unlocks repairing, the wreck lights up green under the hover. Right-clicking it,
or pressing **Repair** while standing beside it, starts the next part. The materials come out of
the island's stock when the repair starts; without them, a toast says what it takes. The robot
works like it builds. Pausing, walking off or leaving the island stops the work. The progress
stays, and resuming doesn't pay again. A finished part counts toward `Stat.SHIP_PARTS_REPAIRED`.

The chart's radar sweep (`uncharted_chart.gdshader`, `radar_sweep`) only circles the map once
the radar works (`WorldData.is_radar_online`). It fades in over 2 s when the repair finishes, as
the frontier rolls back to ring 1. Saves that charted ring 1 before the radar existed count as
online.

The sweep and the repaired dish on the wreck turn together. Both point where
`WorldView.radar_sweep_angle()` says, which turns clockwise (seen from the camera) once every
`WorldView.RADAR_SWEEP_SECONDS` (24 s) on real time. It keeps turning while the game is paused, as
the sweep always has. The chart gets it as its `sweep_angle` uniform every drawn frame, and
`ShipWreck` turns the dish to face the same way.

The wreck model shows the radar too. The mast is snapped and the dish lies on the ground until the
repair starts. While the repair runs, or is paused part way, the new radar is printed up inside a
hologram. Once repaired, the dish turns. See [Spaceship model](spaceship-model.md).

Checked by `tools/radar_repair_check.gd`. The chain is checked in `tools/furnace_check.gd`,
`tools/dog_rescue_check.gd` and `tools/boat_cargo_check.gd`.

## Existing saves

- A saved game keeps its islands where they were saved, so `copper_isle` stays on ring 1 there.
  Start a new game to get the home-waters layout.
- A save already past Strike Iron has the new milestones marked done when it loads (the chain is
  linear), which also unlocks the cargo hold, the Furnace and repairing. The radar stays
  unrepaired, but the ring it would reveal is already open.
- A save that has found K9-DA's island but not yet done Strike Iron continues with Copper Glint.

## Still open

- Later ship parts and what they unlock: see [Ship repair roadmap](ship-repair-roadmap.md).
- Playtest the amounts: 6 copper ore is a short stretch of hand mining, and the boat's 20-unit
  slots carry it in one trip.
