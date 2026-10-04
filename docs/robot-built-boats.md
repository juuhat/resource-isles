# Robot-built boats — v2 concept

[Concept board](../art/concepts/robot-built-boats-v2.png), generated with built-in imagegen.
[Prompt history](../art/concepts/robot-built-boats-v2.prompt.txt).

Proposed replacement for the rowboat / sailboat / ship visual progression. The salvage skiff is
built and moored at the dock (below); boat tiers, costs and progression are unchanged.

## Chosen layouts for modelling

| Part | Salvage skiff | Cargo catamaran | Freight tug |
| --- | --- | --- | --- |
| Hull | Narrow open timber hull, angular armored bow | Two faceted timber pontoons, iron keel edges | Broad iron hull, straight sides, clipped bow corners and flat transom |
| Cargo | One small bow crate | Two large crates side by side | Exactly three crates in one fore-aft line behind cabin |
| Navigation | Player at neutral hand-PTO post | Low slanted instrument console | Tall forward cabin |
| Motor | One small stern drive block | One aft drive block feeding both hulls | One stern drive block, offset to starboard |
| Propulsion | One aft screw | Two aft screws, one per hull | One aft centreline screw |
| Crane | None | None | Stern centreline base, cream boom stowed straight aft within hull width |
| Signal | Cream stern post, amber cap | Taller aft console mast, amber cap | Tall cabin mast, amber cap |

Use a continuous dark window/sensor band on the console and cabin, with a single amber
status lamp outside the band. Paired eye dots belong to the player robot only. Keep the
shared teal casing, cream octagonal service inlet and amber indicator from the generator
family. Preserve real deck clearance for the player and K9-DA on the skiff; reserve the
dog's space without treating it as a cargo slot.

The final board corrects the extra tug cargo box and motor and shows both catamaran
propellers. It remains concept art, not a measured turnaround: the propellers are drawn
exposed beside the stern and the service openings are simplified inconsistently. Model
marine screws below the stern waterline with axes parallel to vessel length, rather than
copying apparent side-facing paddlewheels. Use the actual cream octagonal generator inlet
instead of the tug's illustrated vent. The layout table above governs ambiguous details.

## Built: salvage skiff

`tools/build_salvage_skiff.py` builds `assets/models/boats/salvage_skiff.glb` (12 meshes,
about 1,200 triangles) and four previews in `art/previews/`: `salvage_skiff.png` (hero),
`salvage_skiff_top.png` (overhead), `salvage_skiff_crewed.png` (with the real robot docked in its
Operate pose) and `salvage_skiff_dock_check.png` (spindle in the post socket, close up).

- **Scale.** The skiff is at true tile scale: 1.70 × 0.78 model units (0.85 × 0.39 tiles), next
  to the 0.45-tile robot. Bow along +X, origin on the waterline at mid-hull; the keel and screw
  sit below it.
- **Helm.** The robot stands at `PilotSpot` facing the bow. The PTO post's socket (`DockPoint`)
  is placed with the sawmill's docking offsets: 0.20 ahead, 0.41 up and 0.2175 to starboard.
  The crewed preview confirms the spindle docks.
- **Moored at the dock.** The dock is a line of three tiles: quay on the shore, pier over the
  coast, and a berth on the water beyond (coast or open water). The skiff lies on the berth,
  stern-to off the pier head with its bow out to sea. The renderer hangs it off the dock's
  `BoatSpot`, so it turns with the dock and shows in the placement ghost. It is a moored prop
  only: no bobbing, spinning screw or boarding yet.
- **Open: K9-DA's space.** `CompanionSpot` leaves about 0.2 tiles of clear deck, but K9-DA
  walks at 0.55 tiles long (`dog.gd` `visual_size_tiles`). Either the dog gets a smaller
  seated pose aboard or the skiff gets longer, which would push the catamaran and tug up by
  the same ratios.

## Scale and overview readability

Initial blockout targets, with skiff length normalized to 1:

| Tier | Length | Beam |
| --- | --- | --- |
| Skiff | 1.00 | 0.45 |
| Catamaran | 1.30 | 0.72 |
| Tug | 1.65 | 0.95 |

These are proposed relative dimensions, not implemented game scale values. Preserve the
ratios rather than independently resizing every model to the same maximum extent.
Judge them together in the world overview: `scripts/world/world_view.gd` currently makes
a placeholder about one cell long. The distinguishing overhead reads are narrow single
hull, split twin hull, and broad rectangular hull with cream boom. Tall beacon posts
provide the vertical contrast previously supplied by the placeholder sail. A wake can
support movement later; do not rely on it to distinguish stationary boats.

Before final assets, make a shared-scale 3D blockout and render its hero and overhead
views from the same geometry. Check all three at actual overview zoom, then fit the
robot's operating pose and dog clearance to the skiff. Those checks, rather than this
generated board alone, establish modelling readiness.
