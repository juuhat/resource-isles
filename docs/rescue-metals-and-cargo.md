# Rescue, first metals, and boat cargo — 2026-10-04

Implementation update: [Furnace](furnace.md) records the delivered stone kiln, ingot recipe,
iron-built Burner Generator, rescue/smelting power gates, and save behavior. Personal-boat
cargo is also implemented. Copper deposits and manual gathering are implemented for new
worlds; copper processing, autonomous drones and the manual-delivery quest remain TODOs.

Current design direction from the playtest discussion. These are implementation TODOs,
not changes already made to gameplay. This direction supersedes older plans for an
island-1 Burner Generator, immediate automatic trade routes, and multiple player boats.
Recipe amounts, cargo capacity, and the exact copper unlock remain proposals to playtest.

## Rescue before electricity

Island 1 stays hand-driven. The robot's Operate action represents direct mechanical power
for the sawmill and extractors before electricity is available.

Island 2 is K9-DA's rescue island and introduces iron and coal. Rescue K9-DA before
unlocking electricity generation. Move the Burner Generator out of the island-1 rewards,
and gate the Windmill too so it cannot bypass this sequence.

Suggested teaching sequence:

1. Sail to island 2, discover iron and coal, and rescue K9-DA.
2. Unlock and build a stone Furnace; bring construction supplies by personal boat.
3. Smelt the first iron ingots with coal and robot-operated bellows, before generated electricity.
4. Build an iron-based Burner Generator and demonstrate unattended production.
5. Explore another ring-1 island for copper.
6. Unlock autonomous freight after the player has learned to haul supplies manually.

The rescue unlocks the Furnace; smelting then unlocks the Burner Generator before any
quest requires building it. Ingot objectives must follow the Furnace unlock. Manual
gathering and Operate must suffice to bootstrap the whole chain.

| Proposed recipe | Ingredients | Notes |
| --- | --- | --- |
| Furnace construction | 12 stone + 4 wood | Stone body, wooden bellows/supports; no iron construction prerequisite. |
| Iron ingot | 2 iron ore + 1 coal | Coal heat; bellows require robot Operate or 2 MW. |
| Burner Generator construction | 6 iron ingots + 4 stone + 2 planks | First generator; keep its existing wood fuel for now. |

Use Furnace as the name for this first smelting building. Decide whether a later electric
Smelter is a separate upgrade when that tier is designed. Do not make the first furnace
depend on the generator it supplies.

## Ring-1 copper

Implemented: K9-DA's rescue island (the ring-1 slot from `WorldData.dog_slot_for_seed`) has
copper ore + stone (three deposits each) and no iron or coal, with wood imported. The other
ring-1 slots keep iron + coal + stone. Existing saved islands retain
their resources; start a new world to get the copper profile. Copper can be scavenged and
harvested by hand, carried in inventory and boat cargo, and saved like other resources.
There is no copper mine or processing recipe yet.

The low-poly model has a split rock ridge, warm copper seams, and green mineral faces.
Rebuild with `blender --background --python tools/build_deposit.py -- copper`; rebuild its
transparent inventory icon with `blender --background --python tools/build_copper_icon.py`.
Validate generation, definitions, save/load, and cargo with
`godot --headless --path . --script tools/copper_deposit_check.gd`.

(Superseded: copper now sits on the rescue island itself.) Original proposal: keep iron +
coal + stone on island 2 and specialize another ring-1 island as copper + stone, optionally wood. Copper gives the player a next destination after rescue
without adding another island trip to the first generator's prerequisites.

Proposed copper chain: copper ore -> copper ingot -> wire/control components. Use iron
for autonomous cargo-drone hulls and copper for their controls. Exact processing recipes,
drone costs, and the unlock milestone still need design. Copper is not required for the
first Burner Generator.

Coal is discovered in ring 1 for smelting; this does not require unlocking a dedicated Coal
Generator at the same time. Reconcile the older power ladder around post-rescue wood
generation, later coastal wind, and later coal generation.

## One personal boat, manual cargo first

The robot's boat is a unique, upgradeable personal vehicle. Do not manufacture duplicates
or assign it to automatic trade routes. K9-DA's passenger space is separate from cargo.
Future personal travel/range tiers upgrade this same boat; catamarans and freight tugs
become autonomous freight designs rather than additional player-piloted boats.

Suggested initial hold: **two resource slots, up to 20 units per slot**. Tune capacity so
a trip carries useful construction supplies rather than forcing repeated runs for a
single furnace. Keep cargo separate from any robot pocket inventory.

Load and unload while moored beside a reachable shoreline or finished dock. A Dock
building is not required for the personal boat's transfers:

- At a suitable landing, choose a resource and amount to move between that island's stock
  and the boat's cargo hold.
- Landing on an untouched island enables unloading into its island stock, so those
  materials can fund the first buildings before a dock exists.
- Cargo remains aboard during sailing, disembarking, and save/load. Transfers must respect
  available stock and capacity without creating or losing items.

The home dock can remain the initial boat launch point. Uniqueness needs to cover dock
construction, moving/deleting docks, and save migration: none should spawn a second
personal boat. Shoreline landing remains the way to start a new outpost.

## Autonomous freight later

Automatic production arrives after rescue; automatic transport arrives later, proposed
after copper. The first supply lesson should be a manual delivery of construction goods
from home to island 2, not an automatic route prerequisite.

Other ships are autonomous cargo drones: buildable fleet units that travel without the
robot/player. They require finished docks at both route endpoints. The player first
establishes an outpost using the personal boat, builds its dock, and later assigns a
drone to repeated deliveries. Drone capacity and route controls remain to be designed.

Verify the revised progression in a fresh game and migrate existing saves with early
generator unlocks, multiple boats, or automatic routes deliberately.
