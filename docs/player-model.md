# Salvage robot — first pass

Created 2026-10-04. The player now uses `assets/models/units/salvage_robot.glb`, replacing the
previous textured mesh in the runtime preload. The original `assets/player/player_model.glb`
remains available for comparison.

## Design

Flat-shaded miniature robot matching the [workshop palette](building-style-palette.md):
cream shell, teal panels, amber eyes, iron joints, steel claws, and a timber-colored utility
belt. Its broad visor, compact backpack, sturdy feet, and open grippers carry the silhouette.
Materials are solid colors with no image textures.

The head top, which the game camera sees most, carries a teal service hatch and, on the
right rear corner, a short antenna with a softly emissive amber beacon. The antenna is the
player's signature: nothing else on the map has it, so the robot stays identifiable from
above among buildings and future units.

The native standing height is 1.20 Blender/glTF units to the head top; the antenna rises to
1.445 and is left out of the runtime scaling, so the body keeps its size. Feet rest at zero; Blender front is -Y,
which exports as Godot +Z to match the player's existing facing code. Runtime height remains
0.45 of a tile. The preview's hex plinth is studio scenery and is not exported in the model.

## Animation and integration

This is a rigid mechanical pivot rig rather than a skinned character. The body, head, arms,
and legs animate independently through parented nodes, which are preserved in the GLB.

- **Idle:** 3-second loop with gentle body movement, head scanning, and arm movement. The
  antenna trails the head scan slightly.
- **Walk:** 0.8-second loop with alternating legs, opposing arm swings, and a small body bob.
  The antenna nods with each step and sways a beat behind the body.
  It is an in-place cycle; gameplay code provides translation and turning. Each boot is
  planted for half the loop, sliding back under the hip at a constant rate so it holds still
  on the ground as the body moves over it, then eases forward with a small lift.
  The game no longer plays it while moving (see Run); it stays for slower movement later.
- **Run:** the gait played while moving, a bounding trot. Each boot is planted for only a
  quarter of the loop, sliding back through a 0.55-radian swing, so the robot is airborne for
  the rest of each half: it pushes off, floats a little above the line between push-off and
  landing, and lands on the other boot. It leans into the run with the head up, bent arms
  pumping against the legs, and the antenna whipping on each landing.
  Runtime playback scales with movement speed and model size: `PlayerUnit` matches the body's
  distance per loop (`RUN_CYCLE_DISTANCE`, 1.652 native units; Walk's is 0.527) to the
  movement speed, about 4 loops (8 steps) a second at gameplay speed, so a planted boot holds
  still on the ground. A model without a Run clip falls back to Walk. Idle and work clips
  retain their authored playback rate. `tools/player_model_check.gd` follows the boots in
  world space to check they hold still on the floor and leave it between steps.
- **Chop:** 1.0-second loop swinging the axe: a slow wind-up overhead, a fast level blow into
  the trunk with the body leaning and twisting into it, a recoil, and back to ready. The
  antenna whips forward on impact.
- **Mine:** 1.2-second loop with the pickaxe: a higher wind-up and a steeper blow down into
  the rock, bending further in.
- **Build:** 1.2-second loop with the wrench (`HeldWrench`): two quick taps at chest height,
  bent in over the work with the head down and the free arm reaching forward to steady the part.
  `main.gd` plays it with `set_work("build")` while the robot raises a blueprint (see
  [Construction](building-footprints.md#construction)).

The swings use the same axe and pickaxe as the ground pickups (`build_axe` and
`build_pickaxe` from [tools/build_robot_tools.py](../tools/build_robot_tools.py)), each merged
into one mesh, `HeldAxe` and `HeldPickaxe`. They sit in the robot's own right hand (the
`LeftArmPivot`, named as seen from the front) on a `ToolPivot` wrist between the gripper fingers,
which the swings rotate for the wrist snap. The key poses are in `SWINGS` in the builder.

Each pivot has an NLA track per clip in Blender, exported into combined clips. Idle is enabled
in the saved Blender source; switch the matching tracks together to preview another clip.
`PlayerUnit` finds the imported AnimationPlayer, loops every clip, and blends between them.
It hides both held tools at load. `set_work("chop")` or `set_work("mine")` plays that swing
while parked and pops its tool into the hand. Walking plays the walk clip with the tool put
away, and the swing resumes once parked again. `set_work("")` goes back to idle. `main.gd`
starts the chop for trees and the mine for stone, ore and coal when harvesting begins, and
stops it when harvesting ends. Operating still uses the idle pose.

## Files and rebuilding

- [Builder](../tools/build_player_robot.py): deterministic geometry and animation source.
- [Blender source](../art/blender/salvage_robot.blend): editable model, rig, clips, and studio.
- [GLB](../assets/models/units/salvage_robot.glb): game asset with all four animation clips.
- [Still preview](../art/previews/salvage_robot.png).
- [Walk preview](../art/previews/salvage_robot_walk.gif).
- Swing previews: ten side-on frames each in `art/previews/salvage_robot_chop/` and
  `art/previews/salvage_robot_mine/`.

Run Blender 5.0 with `--background --python tools/build_player_robot.py`. This exports the GLB,
saves the Blender source, and renders the still, twelve walk frames and the swing frames. Run
`tools/assemble_robot_preview.py` with a Python environment containing Pillow to assemble
the walk GIF. Reimport in Godot after rebuilding the asset.

`tools/player_model_check.gd` checks imported clips, moving pivots, absence of root motion,
and idle/walk transitions through an actual movement command without touching saves. It also
checks the swings: each plays with only its own tool showing, the tool is put away while
walking and returns once parked, and stopping work goes back to idle.
The existing robot-access check also passed with the new model and building work spots.

## Next visual pass

- Judge size, silhouette, and walk rhythm at normal gameplay zoom.
- Add building, operating, and rescue clips, with matching gameplay hooks.
- Update the command-bar portrait to match the accepted robot design.
- Refine proportions and personality after the first in-game playtest.
