# Ship Repair Roadmap — 2026-10-08

Direction, not implementation. Only the radar is in the game
([Copper and the radar](copper-and-the-radar.md)). This is the plan for the rest of the ship:
which parts the robot repairs, what each needs, and what each gives back. The numbers are first
guesses to playtest.

It puts the [Intro Story](intro-story.md)'s act 4 into practice: each island's rare material
repairs one more ship module. It follows the [Power Sources](power-sources.md) ladder (wood,
windmill, coal, oil, nuclear) and the ring-by-ring map from [Island Unlocks](island-unlocks.md).
For the wreck model and its part slots, see [Spaceship model](spaceship-model.md).

## The pattern

The radar sets the shape every repair follows:

1. **A material from the waters just reached.** Each part needs something the last ring opened
   up, so the robot keeps bringing finds home to the wreck at the centre of the disc.
2. **One new piece of tech.** A building or a recipe that turns the find into a ship part, and
   stays useful afterwards.
3. **A reward that fits the part.** A working radar sees further; a sealed hull teaches a better
   boat. Rewards take turns between **seeing** further (revealing a ring) and **reaching**
   further (a boat that gets there), so the player can always see one step past where they can go.

A repair is paid when it starts and worked by the robot at the wreck, as the radar is today
(`ShipRepairs`, `WorldData.ship_repairs`). On the wreck, each part is printed into place inside a
hologram while it's repaired (`ShipWreck`).

## The parts

| # | Part | Materials | New tech | Reward | Ring |
| --- | --- | --- | --- | --- | --- |
| 1 | **Radar** (done) | 3 copper ingots | Furnace, copper recipe | Reveals ring 1 | Home waters |
| 2 | **Hull** | 6 iron plates | Plate Press | The next boat hull, which reaches ring 2 | Ring 1 |
| 3 | **Windshield** | 4 glass, 2 resin | Furnace glass recipe, Resin Tapper | Cockpit console: reveals ring 2 and charts deposits | Ring 1 |
| 4 | **Engine** | Steel, copper wire coils; fuel to test-fire | Steel Mill, Wire Drawer, Oil Refinery | The engine idles and powers the crash site | Rings 2–3 |
| 5 | **Wing** | Light alloy, steel | Alloy Smelter | Flight surfaces done; the ship can steer | Rings 3–4 |
| 6 | **Power Core** | Fuel rods, steel casing, copper wire, glass | Uranium Mine, Fuel Rod Fabricator | Fly home, or choose to stay | Rim |

### 1. Radar (done)

Copper from K9-DA's island, smelted over a wood fire. The repaired radar reveals ring 1 and
starts the chart's sweep. See [Copper and the radar](copper-and-the-radar.md).

### 2. Hull

The breach on the wreck's side gets a riveted iron patch.

- **Materials:** about 6 iron plates.
- **New tech:** a **Plate Press** turns iron ingots into iron plates (say 2 ingots to 1 plate).
  It needs power, so it falls after the first generator. Plates are later the stock for boat
  hulls and the Steel Mill's buildings.
- **Reward:** riveting the ship's plating teaches the robot a stronger boat: the next boat tier
  ([Robot-built boats](robot-built-boats.md)), the one that reaches ring 2.
- **Ring:** ring 1, where iron and coal are mined
  ([Second island progression](second-island-progression.md)).

### 3. Windshield

The shattered canopy over the cockpit gets new glass, sealed with resin.

- **Materials:** about 4 glass and 2 resin.
- **New tech:**
  - **Glass:** a third Furnace recipe, 2 sand + 1 coal → 1 glass. Coal burns hot enough;
    wood doesn't. Sand comes from any beach: the robot digs it by hand, and a **Sand Pit**
    automates it later. Sand is cheap; the coal is what ties glass to ring 1.
  - **Resin:** a **Resin Tapper** beside the start island's pine forest. It gives the starter
    island a late reason to matter.
- **Reward:** with the cockpit sealed, its **console** works. It reveals ring 2, and the chart
  marks the deposits on every charted island, so the player can plan trips before sailing.
- **Ring:** ring 1 (coal), with sand and resin from home.

### 4. Engine

The knocked-over engine bell is set straight, rewound and test-fired.

- **Materials:** steel and copper wire coils for the rebuild, then refined fuel for the test
  fire. It can be split into two repairs (rebuild, then ignition) if one is too big a step.
- **New tech:**
  - **Steel Mill:** iron ingots + coal → steel, a powered building for ring 2's coal power.
  - **Wire Drawer:** copper ingots → copper wire. Copper becomes useful again after the radar.
  - **Oil Refinery:** ring 3's oil → refined fuel, as [Power Sources](power-sources.md) plans
    for oil (tied to mobility and fuel logistics).
- **Reward:** the engine runs at idle and the wreck becomes a strong power source for the start
  island. It's the first repair that makes the wreck useful day to day, not only a goal.
- **Ring:** rings 2 and 3.

### 5. Wing

The starboard wing, snapped off in the crash, is rebuilt.

- **Materials:** a light alloy for the skin, and steel for the spar.
- **New tech:** an **Alloy Smelter** for a rare, light ore found only in ring 3 or 4 (aluminium,
  or a made-up metal like "skylite"). It's the first ore the starting rings don't have, a reason
  to push toward the rim.
- **Reward:** the ship can steer. It's the last step before it can fly, and nothing is left to
  repair but its power.
- **Ring:** rings 3 and 4.

### 6. Power Core

The finale. The ship's reactor was what the pirates' laser hit; without it the engine can only
idle on refined fuel, never lift off.

- **Materials:** nuclear fuel rods, a steel casing, copper wire and a glass inspection port. It
  draws on every chain the robot has built.
- **New tech:**
  - **Uranium Mine** on uranium deposits found only on the rim islands by the frozen mountains.
  - **Fuel Rod Fabricator:** uranium → fuel rods. It needs the large, steady power the oil
    turbines give, so it falls at the end of the power ladder, where
    [Power Sources](power-sources.md) puts nuclear.
- **Reward:** the ship is whole. The robot and K9-DA can **fly home**, or **choose to stay** on
  the disc they've built up ([Intro Story](intro-story.md), act 4). The intact ship model
  (`spaceship.glb`) replaces the wreck for the lift-off.
- **Ring:** the rim.

The reactor could also lead into a postgame (e.g. a Nuclear Reactor building for the islands,
using the same fuel rods); see [Postgame leaderboards](postgame-leaderboards.md).

## Optional extras

- **Landing gear.** A cheap iron repair between the radar and the hull, if that stretch feels
  long. The intact ship already stands on three legs; the wreck would get broken ones.
- **Salvage the wreck early.** The Intro Story suggests stripping hull plating and wiring from
  the wreck for early crafting. The hull breach, ribs showing, already looks stripped.

## New materials and buildings

| Material | Made from | Where |
| --- | --- | --- |
| Iron plate | Iron ingots | Plate Press |
| Sand | Dug by hand from beaches | Sand Pit |
| Glass | 2 sand + 1 coal | Furnace |
| Resin | Pine forest | Resin Tapper |
| Steel | Iron ingots + coal | Steel Mill |
| Copper wire | Copper ingots | Wire Drawer |
| Refined fuel | Oil | Oil Refinery |
| Light alloy | Rare ore (ring 3–4) | Alloy Smelter |
| Fuel rods | Uranium ore | Uranium Mine, Fuel Rod Fabricator |

Glass reuses the Furnace's recipe switching. Sand and resin come from the start island. The
Steel Mill, the refinery and the reactor fuel chain are the big new buildings.

## Building it in the game

Each repair needs:

1. A `GameTypes.ShipPart`, appended (the parts are saved as ints and repaired in enum order).
2. A `ShipRepairs.PARTS` entry: name, cost, work seconds and `model_node`.
3. Its materials, buildings and recipes, and a milestone that asks for the repair
   (`Stat.SHIP_PARTS_REPAIRED`) with the part's reward.
4. On the model: the windshield, hull, wing and engine already have broken and repaired versions
   in the wreck. The **Power Core** and **landing gear** need new slots in
   `tools/build_spaceship.py` (a glowing core behind a hull hatch would read well), added to its
   `PARTS` and to `ShipRepairs.MODEL_NODES`. See [Spaceship model](spaceship-model.md).

## Open questions

- Whether the hull's reward is the next boat tier, or the boat tiers stay quest rewards of
  their own and the hull gives something else.
- Whether sand is a resource node on beaches or dug from any Sand tile.
- Whether the engine is one repair or two (rebuild, then test-fire).
- The rare light ore: real (aluminium from bauxite) or made up (skylite), and which ring.
- What "choose to stay" offers: a postgame on the disc, or only an ending.
