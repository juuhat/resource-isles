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
  It is an in-place cycle; gameplay code provides translation and turning. The stance boot
  stays on the ground while the swing boot lifts.

Each pivot has Idle and Walk NLA tracks in Blender, exported into two combined clips. Idle is
enabled in the saved Blender source; switch the matching tracks together to preview Walk.
`PlayerUnit` finds the imported AnimationPlayer, loops both clips, and blends between them
according to movement state. Harvesting and operating currently use the idle pose.

## Files and rebuilding

- [Builder](../tools/build_player_robot.py): deterministic geometry and animation source.
- [Blender source](../art/blender/salvage_robot.blend): editable model, rig, clips, and studio.
- [GLB](../assets/models/units/salvage_robot.glb): game asset with both animation clips.
- [Still preview](../art/previews/salvage_robot.png).
- [Walk preview](../art/previews/salvage_robot_walk.gif).

Run Blender 5.0 with `--background --python tools/build_player_robot.py`. This exports the GLB,
saves the Blender source, and renders the still plus twelve walk frames. Run
`tools/assemble_robot_preview.py` with a Python environment containing Pillow to assemble
the walk GIF. Reimport in Godot after rebuilding the asset.

`tools/player_model_check.gd` checks imported clips, moving pivots, absence of root motion,
and idle/walk transitions through an actual movement command without touching saves.
The existing robot-access check also passed with the new model and building work spots.

## Next visual pass

- Judge size, silhouette, and walk rhythm at normal gameplay zoom.
- Add chopping, mining, building, operating, and rescue clips, with matching gameplay hooks.
- Update the command-bar portrait to match the accepted robot design.
- Refine proportions and personality after the first in-game playtest.
