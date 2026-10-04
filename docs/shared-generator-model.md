# Shared hand-PTO generator

Reusable part based on [the neutral-pose concept](../art/concepts/player-building-hand-pto-v2-neutral.png).
The part uses the workshop palette, solid matte materials, an octagonal cream socket,
recessed six-spline bore, amber indicator and six-spoke flywheel. No textures or terrain
are included in the exported model. Nine mesh groups keep the rotating pieces separate.

- [Game asset](../assets/models/parts/shared_generator.glb): instantiate as a child of any building.
- [Blender source](../art/blender/shared_generator.blend): append the `SharedGenerator` collection.
- [Preview](../art/previews/shared_generator.png).
- [Builder](../tools/build_shared_generator.py): `build_shared_generator(location, parent, name)`
  can also be called from other Blender builders after they reset their scene.

## Placement and motion

Authored at the same native scale as the building kit: 2 units per tile width. Bottom
mounting feet rest at the root's zero height. Bounds are 0.71 wide, 0.50 deep and 0.47 high.
Front is Blender -Y, exported as Godot +Z. Give the part the same scale as the building.

`DockPoint` is the socket entrance: Blender (0, -0.265, 0.25), Godot (0, 0.25, 0.265).
The cream collar has a 0.326 outer diameter; the female sleeve's clear bore is 0.156
before the six inward splines. Position the module on the accessible front edge of a
building, with the entrance facing its operator standing spot. A mount height of 0.16
puts the inlet at 0.41 above the ground as an initial neutral-arm placement; confirm
against the eventual operating pose before applying this height to all buildings.

`FlywheelPivot` rotates around Blender/Godot local X. `SocketRotor` rotates around Blender
local Y / Godot local Z. Rotate these pivots while powered; keep the root and `DockPoint`
stationary. `OutputShaft` marks the outside flywheel axle for a building-specific belt or
shaft. The indicator is a separate amber mesh/material so a caller can control its state.
The part itself contains no animation or power gameplay logic. In the game, `IslandRenderer`
gives every power consumer a `PoweredSpinner` that turns any `POWERED_SPIN_PARTS` its model
carries (these two pivots, plus a building's own, such as the sawmill's `SawBladePivot`) while
the building is powered, easing up and coasting down.

To build the part into a building, call `build_shared_generator()` after the builder's
`reset_scene()`. The kit's `export(join_label=...)` merges only unparented meshes, so the
part's pivots survive. Place the root so `DockPoint` sits under the robot's right hand at the
`WorkSpot`: 0.2175 units to its right (+X, as it faces the building), 0.20 ahead and 0.40 up
(root height 0.15). Use `true_tile_model` in the building definition so that offset is exact.
`tools/sawmill_model_check.gd` asserts this for the sawmill.

## Fitted buildings

- **Sawmill** ([builder](../tools/build_sawmill.py)): on a timber cradle at the front right of
  the yard, the flywheel belted to a cross shaft and gearbox that drive the blade.
- **Quarry** ([builder](../tools/build_quarry.py)): on the same front-right cradle and hand
  alignment, belted up to a cross shaft and right-angle gearbox driving a vertical spiral
  stone drill. `DrillPivot` and `DrillPulleyPivot` turn with the generator while powered.
  `tools/quarry_model_check.gd` checks the imported docking alignment, ground clearance and
  powered motion, including the stationary socket entrance.

The robot's Operate clip ([builder](../tools/build_player_robot.py)) holds its right forearm
level with the `HeldPTO` spindle nose 0.345 native units (0.26 at game scale) ahead of the
elbow, so it sits about 0.06 inside the socket. `tools/player_model_check.gd` checks the nose.

From the game camera, the robot's body covers most of the socket and its docked forearm while
it operates. The flywheel is seen edge-on (its axle runs across the screen), so neither reads
as motion; the spinning blade does. Buildings without a big face-on moving part need a
different powered cue. `tools/sawmill_screenshot.gd` renders the game views plus a low side view
where the docking and belt are clear.

Rebuild with `blender --background --python tools/build_shared_generator.py`.
Import with Godot, then run `--headless --path . --script tools/shared_generator_check.gd`
to check the imported bounds, pivots and stationary docking point.
