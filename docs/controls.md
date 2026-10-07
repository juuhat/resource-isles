# Controls

Keys and mouse controls for the current prototype. Input is handled in
[`main.gd`](../scripts/main.gd) (`_input`, `_unhandled_input`) and
[`camera_rig.gd`](../scripts/camera_rig.gd).

## Camera

- **Mouse wheel**: zoom. Keep zooming out to see neighbouring islands and, eventually, the
  whole disc.
- **Left or middle mouse drag**: pan. In the whole-disc overview, dragging orbits around the
  disc.
- **M**: pull back to the whole disc, or zoom back to play. **Esc** also zooms back in.
- **[** and **]**: look at the previous or next visited island; the robot stays where it is.
- **Space**: toggle the hex grid overlay.

## Robot

- **Left click on the robot**, or the **portrait** in the bottom-right corner: select the
  robot. The portrait also centres the camera on it.
- **Right click** with the robot selected: send it there. Tiles it can work are tinted green
  when hovered; it walks over and starts working: harvesting a resource node, operating
  (hand-powering) a building, building a blueprint, rescuing K9-DA, or boarding a boat.
- **Command bar**, to the left of the portrait: the actions the robot can take where it
  stands: Harvest, Operate, Build, Rescue, Pilot boat, Disembark and Cargo.

## Boat

- **Pilot boat**: walk beside a Dock's skiff or a parked boat and press **Pilot boat** on the
  command bar to board.
- **Right click** coast or open sea while aboard: sail there. Right click a shore to land there.
- **Left click on another island** while aboard (also from the overview): sail to its nearest
  reachable shore.
- **Disembark**: land beside a shore or a finished Dock, leaving the boat afloat.
- **Cargo**: open the boat's cargo hold and drag resources between the island and the boat.

Dark tiles beyond the radar frontier can't be sailed until quests expand it. Exploration fog
inside the frontier lifts as the robot sees the sea.

## Building

- **B** or the **BUILD** button: open or close the build menu. While it is open, **1-9** pick
  a card in the current tab. Cards show the cost against current stock (red when short);
  locked buildings appear as silhouettes naming the quest that unlocks them.
- **Left click**: place the selected building as a blueprint. The robot then walks over and
  builds it.
- **R** / **Shift+R**: turn the building being placed.
- **Right click** or **Esc**: stop placing (also the placement bar's **Cancel**).
- **Left click on a building**: show its info panel, with **Move** and **Delete**. On a Dock it
  also lists the Dock's trade routes and has a form to open a new route to another island with
  a Dock.

## Menus

- **MENU** button (top-left): the game menu. **New Game** replaces the current save after
  confirmation, **Save Game** saves now, and **Load Game** reloads the latest save. Manual
  saves and autosaves share one slot. The game pauses while the menu is open; **Resume** or
  **Esc** closes it.
- **T**: open or close the Quest Log. Active quests are also pinned on the right edge of the
  screen.
- **Esc**: close the cargo panel or Quest Log, leave the overview, or otherwise cancel the
  selected building and deselect the robot.

## Debug builds only

- **P**: add 1000 of every resource to the current island (also counts as gathered, so
  quests complete).
- **Delete**: delete the save and restart with a new game.
- **=**: reveal one more ring of islands.
- **Q** / **E**: orbit the camera; **R** / **F**: tilt it. **C** prints the current camera
  framing.
