# Spaceship — intact ship and repairable wreck

The robot's ship is built by `tools/build_spaceship.py` in the workshop palette, replacing the
imported Meshy wreck. One hull makes two models:

| Model | Use |
| --- | --- |
| `assets/models/buildings/spaceship.glb` | The ship as it flew, level on three landing legs. For the intro before the crash, and the lift-off once it's repaired. Not used in the game yet. |
| `assets/models/buildings/crashed_spaceship.glb` | The `CRASHED_SPACESHIP` landmark on the start island. |

A cream hull with a teal belly, nose and two bands, an amber canopy, a teal tail fin, a radar
dish behind the canopy and a single rear engine. The wreck is the same ship pitched nose-down,
rolled onto its starboard side and dug into the ground. Dirt is heaped round the nose, clods mark
the furrow behind the tail, and the hull is sooted at the nose and engine.

Both are `true_tile_model`s (2 units per tile, the robot's scale), about 1.6 tiles long. In the
model the nose points along +X and the starboard side faces the camera. The wreck's heading,
`visual_rotation_y = -12°`, points the nose east toward where the robot wakes. On the starter
island, that keeps the tail and the debris clear of the stone deposits west and south-west of
the wreck.

## Repairable parts

Each part the robot can repair is in the wreck twice: a `<Part>Broken` node and a
`<Part>Repaired` node. The intact ship has only the `Repaired` nodes, so an intro or lift-off
scene finds the same names.

| Part | Broken | Repaired | In the game |
| --- | --- | --- | --- |
| `Radar` | Snapped mast stub, cable down the hull; dish and mast thrown onto the ground | Mast, dish and feed horn; the dish (`RadarSpin`) turns | `ShipPart.RADAR` |
| `Windshield` | Dark open cockpit, a few panes standing, glass on the ground | Amber canopy glass | Not yet; stays broken |
| `Hull` | Hole into the dark interior, ribs showing, panel peeled off | Riveted patch plate | Not yet |
| `Wing` | Jagged starboard stub; the outer half lies on the ground | Full wing with teal tip and light | Not yet |
| `Engine` | Bell knocked askew, sooted throat, loose cables | Bell aligned, teal glow | Not yet |

`ShipWreck` (`scripts/island/ship_wreck.gd`) is added beside the wreck by the island renderer. It
shows one node of each pair, following `WorldData.ship_repairs`:

- **Not started:** `Broken`.
- **Under repair, or paused part way:** `Repaired`, printed up to the repair's progress inside a
  teal hologram of the finished part, the same effect as a blueprint (`ConstructionSite`, with
  its `progress_source` reading the repair).
- **Repaired:** `Repaired`. Its `<Part>Spin` node, if any, turns about its local up axis (the
  radar dish).

It polls each frame, so finishing a repair needs no re-render.

### Adding a repairable part

1. Model both states in `build_spaceship.py`: add the meshes to the part's `Broken` and
   `Repaired` groups (`self.add(...)`, or `ship.ground[...]` for pieces lying on the ground). Add
   new part names to `PARTS` and `ShipRepairs.MODEL_NODES`.
2. Give the `GameTypes.ShipPart` a `ShipRepairs.PARTS` entry with `model_node = "<Part>"`. The
   existing slots (`Windshield`, `Hull`, `Wing`, `Engine`) only need this step.

Parts are repaired in `ShipPart` order, so adding a `ShipPart` puts it in the repair queue.

## Rebuild

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.0\blender.exe' --background --python tools/build_spaceship.py
```

Outputs: both GLBs, the editable `art/blender/spaceship.blend` and `crashed_spaceship.blend`, and
the previews:

- `art/previews/spaceship.png`
- `art/previews/crashed_spaceship.png`, with every part broken
- `art/previews/crashed_spaceship_radar.png`, with the radar repaired
- `art/previews/crashed_spaceship_repaired.png`, with every part repaired

To see the wreck at game scale in each radar state, run `tools/ship_wreck_screenshot.gd`. It
needs a window and a throwaway `APPDATA`; its header has the command.
`tools/radar_repair_check.gd` checks that the wreck shows the radar broken, printing and repaired.
