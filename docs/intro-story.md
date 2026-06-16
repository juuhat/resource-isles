# Intro Story and the Narrative Spine

The opening fiction for Resource Isles, and how it maps onto systems that already exist in
code. This is direction, not implementation — but every story beat below is pinned to a real
mechanic so the narrative and the game teach the same thing at the same time.

See also: [First Island Progression](first-island-progression.md) for what island 1 teaches,
[Island Unlocks](island-unlocks.md) for the rings/boat-tier/ship-repair loop, and
[Player Unit and Manual Gathering](player-unit-and-manual-gathering.md) for the robot verbs.

## Logline

> A little builder robot and his robot dog — **Companion Unit K9-DA** — are shot down over a
> flat-disc planet. The dog
> is thrown clear and stranded on a neighboring island; the ship crashes dead-center on the
> starter island. With scattered tools and a knack for building, the robot must gather, build a
> boat, and rescue the dog — and in doing so discovers the planet is rich enough to rebuild the
> ship and fly home.

The rescue is **not** the ending. It is the inciting incident that reveals the world is bigger
than the starter rock. That reveal turns every island into a promise and the crashed ship into
a long-term goal.

## The Cold Open

A short, mostly-non-interactive sequence before control is handed over:

1. **The chase.** A spaceship runs from pirates across open space. Two passengers: the **player
   robot** (small, plucky, a builder) and his robot dog, **Companion Unit K9-DA**.
2. **The hit.** A pirate laser clips the ship. It begins falling toward the nearest planet —
   which in this universe is **not a sphere but a flat disc** (flat-earth style). This is the
   worldbuilding that justifies discrete, edged islands and a map that expands in rings.
3. **The disintegration.** As the ship nears the planet's center, it starts breaking apart. The
   **dog is flung out** and lands on a different island (a ring-1 island — "island 2").
4. **The crash.** The ship slams into the exact center of the starter island — which is also
   the center of the whole disc. The wreck becomes the **`CRASHED_SPACESHIP`** landmark
   (placed by worldgen, never by the player — see
   [`building_definitions.gd`](../scripts/buildings/building_definitions.gd)).
5. **Wake up.** The player robot reboots beside the wreck. Control is handed over here.

### The reveal beat (stagger it)

Don't tell the player the dog survived up front — *discover* it. Wake → see wreckage → **then**
a distress beep / flare from across the water reveals the dog is alive and stranded. Mild dread
("did the dog make it?") resolved into purpose is a stronger hook than knowing it the whole
time. Keep a periodic beacon on the horizon so the goal stays present on-screen during the
early grind.

The robot's first line sets the plucky, resourceful tone (not sad — this is a cozy builder):

> "With my tools and building skills, I can gather enough to build a boat — and get the dog!"

## How the Opening Maps to Systems

The quests are split into one persistent **main objective** — `RESCUE_THE_DOG`, always shown at
the top of the on-screen tracker — and a short **linear milestone chain** played one at a time
beneath it (see [`quest_catalog.gd`](../scripts/quests/quest_catalog.gd) and
[`quest_manager.gd`](../scripts/quests/quest_manager.gd)). The main objective is the north star;
each milestone is a concrete step toward the boat that reaches the dog. A milestone can grant
**several rewards at once**.

| Story beat | System (in code) | Teaches |
| --- | --- | --- |
| **Main objective:** rescue the dog | `RESCUE_THE_DOG` (MAIN) — completes on `Stat.ISLANDS_REACHED` ≥ 1 | The north-star goal: sail out and bring the dog home |
| Wake by the wreck | `CRASHED_SPACESHIP` spawn landmark | Spawn point + future win target |
| Tools flung loose in the crash | `ItemType.AXE` / `PICKAXE` / `HAMMER` pickups; milestone `HELLO_WORLD` | Walk-over collection; unlocks `RobotUpgrade.HARVESTING` |
| Break ground | `BREAK_GROUND` (20 wood + 20 stone) → `LOGGER_CAMP` + `QUARRY` + `FAST_STEPS` | Hand-gather wood *and* stone; first buildings |
| Scale up | `SCALE_UP` (100 wood + 100 stone) → `SAWMILL` + `BURNER_GENERATOR` + `AUTO_GATHER` | Refining + steady power |
| Build the boat | `SET_SAIL` (12 planks + 3 buildings) → `DOCK` | Capability gate for sea travel → **sail to the dog** |

So the entire island-1 chain *is* the rescue mission. The player isn't doing chores; every
milestone is a step toward the boat, with `RESCUE_THE_DOG` floating above as the reason why.
`SET_SAIL` unlocking the `DOCK` lets the robot sail out, and reaching the new island
(`ISLANDS_REACHED`) completes the main objective — the narrative climax of act one.

> Note: the tool-recovery scatter (`HELLO_WORLD`) is the diegetic reason the robot starts unable
> to harvest — `HARVESTING` is gated behind picking the tools back up. The crash took your
> hands; the first thing you do is get them back.

## The Motivation Handoff (the most important design note)

Watch the gap *after* the dog is rescued. The dog was the entire reason to build the boat — once
he's safe, what pulls the player onward? The answer is already baked into the world; the game
just has to **say it out loud** at the right moment:

- The starter island is **deliberately scarce** (wood, stone — see
  [First Island Progression](first-island-progression.md)). It's a humble teaching cage.
- **Island 2 holds something the starter never had** — a richer/advanced material (iron is the
  natural first step). The first sight of it is a dopamine spike: *there is more out there.*
- On finding it, the robot reframes the wreck: **"This is ship-grade. The wreck back home — I
  could actually *repair* it."**

That single line converts the crashed ship from sad scenery into **the way home**, and converts
the rescue story into the engine for the whole game. The dog is the hinge between "survive the
crash" and "rebuild and escape."

```text
Act 1  Crash & scarcity   →  build a boat        →  rescue the dog        (starter island)
Act 2  Discovery          →  iron on island 2    →  "I can fix the ship"  (the reframe)
Act 3  Expansion          →  ring by ring        →  rarer materials       (the long loop)
Act 4  Restoration        →  repair the wreck     →  fly home / choose to stay
```

## The Ship as the Center of the Map

The wreck sits at the literal center of the disc, and the world map radiates outward in rings
from it ([Island Unlocks](island-unlocks.md)). Lean into that geometry:

- The crash site is a **permanent landmark and a build target you keep returning to.** Each new
  island's rare material repairs **one more ship module** (hull → engine → nav → power core),
  fused with the boat-tier ladder that reaches the next ring.
- The map literally **radiates from the goal**: explore outward → bring rare materials back to
  the center → restore the ship piece by piece. Calm center (home, the dog), wild rim (the road
  home).
- Optionally let the player **salvage parts from the wreck** early (hull plating, wiring) so the
  crash feeds early crafting and the center of the map has lasting meaning from minute one.

## The Pet Dog Beyond the Rescue

The dog shouldn't vanish into a cutscene reward. Cheap, high-charm ways to keep him alive in the
loop after rescue (all optional, none designed yet — flagged as direction):

- **A companion that follows the robot** between islands — a warm presence on the boat and the
  frontier, reinforcing "home" wherever you are.
- **A second pair of hands** much later (a light automation/scout helper) — but only on island
  2+, where the single-robot bottleneck actually bites
  ([First Island Progression](first-island-progression.md) is explicit that automation is dead
  weight on the fixed-demand starter island). Don't undercut the island-1 "you are the economy"
  lesson by handing over a helper too early.

## One Open Question That Shapes the Ending

Is the ending **"leave the planet"** or **"choose to stay"**? It changes the ship's emotional
role:

- **Leave** — classic escape-the-island; ship repair is a literal countdown to launch, the
  wreck is a **clock**.
- **Stay** — the robot and dog build a home; the repaired ship becomes optional/exploration and
  the disc's rim or other discs are the real frontier, the wreck is a **trophy**.

Not urgent to answer, but it determines whether the ship is a clock or a trophy, and therefore
how much tension the back half of the game should carry. Given the stated "relaxing little
evening game" mood ([Island Unlocks](island-unlocks.md) drops FTL's time pressure), **lean
toward trophy / "stay" with leaving as an optional triumph** — but leave the door open.

## Tone Guardrails

- **Plucky, not grim.** The robot is resourceful and upbeat; stakes stay light. Cozy-but-a-
  little-darker, matching the art direction's "calm center, wild edge."
- **Show through systems, not text dumps.** Each tool pickup, each quest, each new material does
  the storytelling. The cold open is the only heavy narrative moment; after that, the world
  talks through play.
- **The dog is the heart.** Keep the beacon on the horizon in act one; keep the dog present in
  the loop after. He's the reason the player cared in the first 30 seconds — don't spend that.
