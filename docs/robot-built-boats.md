# Robot-built boats — v2 concept

> **Latest direction (2026-10-04):** See [Rescue, first metals, and boat cargo](rescue-metals-and-cargo.md).
> The personal skiff is unique and upgradeable, with manual cargo transfers at suitable
> shores before docks exist. Other ships become autonomous cargo drones; earlier references
> below to unchanged boat tiers/costs are historical concept notes.

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
  until launched with the robot's **Pilot boat** action.
- **Open: K9-DA's space.** `CompanionSpot` leaves about 0.2 tiles of clear deck, but K9-DA
  walks at 0.55 tiles long (`dog.gd` `visual_size_tiles`). Either the dog gets a smaller
  seated pose aboard or the skiff gets longer, which would push the catamaran and tug up by
  the same ratios.

## Playable boarding and local navigation

- Walk to the finished pier, or an open shore tile beside a parked boat. Right-clicking
  the boat routes the robot to a reachable boarding tile; it does not board automatically.
- Press **Pilot boat** (power icon) to mount the helm. The robot uses its hand-PTO operating
  pose while the hull turns and moves with the usual right-click movement commands.
- Boats navigate coast and water cells, avoiding land, pier decks, unfinished docks and other
  boats. The hull stays at the visible water surface.
- Beside an open land tile or a finished deck, **Disembark** becomes available. Right-click
  a neighbouring landing tile to choose it, then press the action. The boat stays afloat;
  the robot can walk back and reboard it. Resource obstacles cannot be landing spots.
- Launched boats have independent world position and heading saved in `WorldData.boats`.
  Saving aboard restores the robot aboard, also out in open ocean. Moving or deleting the
  original dock does not take the launched boat with it or create a replacement boat.
- The islands and intervening ocean share a navigable hex lattice (`WorldNavigation`).
  Right-click water anywhere, or click a revealed island while aboard to sail to its shore.
  The camera can be panned freely; the bottom-right player portrait selects and centers on
  the robot. Approaching close enough to reveal an island discovers it and shows its name;
  landing activates the destination inventory.
- A paper chart sheet covers locked sea and islands. Its radius is the navigation frontier,
  expanded by quest ring rewards. Paths cannot cross it.
- K9-DA's boat pose, the screw animation and bobbing are future work. The companion resumes
  following after landing.

Check with `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tools/boat_navigation_check.gd`.
Pass `-- --screenshot` without `--headless` to also capture `.godot/boat_preview.png`.
`tools/world_sailing_check.gd` checks grid alignment, chart gating, crossing open ocean, reloading
at sea, landing on another island and reboarding there. Its `-- --screenshot` option captures
`.godot/world_sailing_sea.png`, `.godot/world_sailing_chart.png` and `.godot/world_sailing_overview.png`.

## Personal boat cargo

Implemented: each launched personal boat has two cargo slots, holding up to 20 units of
one resource each. Different resources use separate slots; unloading a stack completely
frees its slot. Cargo is separate from island stock and persists through sailing and saves.
Older boats without cargo data start with an empty hold.

Select the stationary robot aboard its boat, or stand beside the boat on a valid boarding
tile, then press **Cargo** in the action bar. The panel shows icon slots and quantities for
the island inventory and the two boat stacks. Drag an island resource onto an empty boat
slot, or onto its existing boat stack to top it up. Drag a boat stack back onto the matching
island resource slot to unload. Valid drop targets highlight while dragging.

Each drop asks for a stack size, defaulting to the maximum available amount that fits
(or the full boat stack when unloading). Confirm **Load** or **Unload**, or cancel without
moving anything. Stock, capacity, destination slot, and shoreline access are rechecked
before items move. A pending prompt closes when moving away or losing access to its stock.
Close the panel with **Close**, **Cargo** again, or Escape.

Transfers work beside a clear reachable shore or a finished dock. No Dock building is
needed at the destination: unload into the new island's stock while aboard, or after
disembarking beside the boat, and use those supplies for construction. While aboard, the
chosen valid landing shore determines the transfer island; sailing does not change the
active construction inventory. The hold can be inspected at sea, but movement and open
water disable transfers. Manual transfers do not count as newly gathered resources.

Opening cargo at the initial dock registers its moored skiff as a world-owned boat even
before boarding, so the hold survives independently of the dock. Boarding uses that same
boat. Restricting the world to exactly one personal boat and replacing automatic-route
ships with cargo drones remain separate TODOs.

Check with `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tools/boat_cargo_check.gd`.
The check covers a real mouse drag through Godot's drag/drop handling, maximum-stack defaults,
split transfers, merges, cancellation, changing stock, capacity limits, sailing with cargo,
unloading without a dock, and save/reload. Add `-- --screenshot` without `--headless` to
generate `.godot/boat_cargo_preview.png` and `.godot/boat_cargo_stack_preview.png`.

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
