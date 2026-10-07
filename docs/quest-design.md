# Quest design review — 2026-10-04

> **Later design decisions:** [Rescue, first metals, and boat cargo](rescue-metals-and-cargo.md)
> takes precedence over the proposed teaching sequence below: rescue before electricity,
> a fuel-fired Furnace before the iron-built Burner Generator, manual boat deliveries before
> automatic trade. [Copper and the radar](copper-and-the-radar.md) (2026-10-07) then puts
> K9-DA's copper island in the home waters and has its copper repair the ship's radar, which
> reveals ring 1. The implementation snapshot below is kept up to date with current behavior.

This records the current quest chain and the proposed next design pass. The recommendations
below are not implemented or final balance decisions. Each milestone should teach one clear
action, demonstrate its payoff, and unlock the next step before requiring it.

## Current implementation

The catalog in [quest_catalog.gd](../scripts/quests/quest_catalog.gd) has one independent main
quest, **Rescue K9-DA**, and a linear milestone chain:

| Milestone | Current objectives | Reward |
| --- | --- | --- |
| Recover Your Tools | Collect the axe, pickaxe, and wrench | Harvesting |
| Break Ground | Gather 6 wood and 6 stone | Logger's Camp and Quarry |
| Lay the Foundations | Build a Logger's Camp and a Quarry | Operate (hand-power buildings) |
| Live Wire | Operate a building; gather 20 wood and 20 stone | Sawmill |
| Refine | Build a sawmill; gather 12 planks | Dock |
| Set Sail | Build a dock | No mechanical reward |
| Follow the Signal | Discover K9-DA's island by sailing close enough to chart it | No mechanical reward |
| Copper Glint | Rescue K9-DA; gather 6 copper ore | The boat's cargo hold |
| Haul It Home | Unload 6 copper ore at the start island | Furnace |
| First Melt | Build a Furnace; smelt 3 copper ingots | Repairing the ship |
| Eyes on the Horizon | Repair the ship's radar (3 copper ingots) | Reveal ring 1 |
| Strike Iron | Gather 5 iron ore | Iron Mine and Coal Mine |
| Light the Forge | Smelt 6 iron ingots | Burner Generator |
| Power On | Build a Burner Generator | Windmill |
| The Supply Line | Establish a route; ship 20 goods | No mechanical reward; chain ends here |

Rescue K9-DA now requires the actual Rescue action on the dog's island; simply reaching another
island does not complete it. It runs independently of the milestones and has no reward of its
own; Copper Glint asks for it, so the chain waits there. See
[Copper and the radar](copper-and-the-radar.md) for the copper milestones and
[Furnace](furnace.md) for recipes, power gates, and existing-save behavior.

Follow the Signal sits between Set Sail and Copper Glint. K9-DA's island lies in the home
waters, sailable from the start, but it keeps its patch of uncharted map until the player sails
close enough to discover it. Discovery opens the patch, revealing resources and then stranded
K9-DA once it has fully opened, before landing.
Only discovering K9-DA's specific island completes Follow the Signal. Existing saves retain
credit for an already discovered rescue island.

Gathering and construction objectives use global lifetime totals, not current inventory or
progress since a quest began. Spending materials does not reduce quest progress. Previously
completed actions can satisfy a newly activated milestone immediately.

Light the Forge unlocks the Burner Generator. Power On teaches its construction and unlocks the Windmill. There are
no dedicated objectives for building a windmill or proving a mine is automatically powered.
Haul It Home is the first objective to deliver a particular resource to a particular island:
copper ore, unloaded from the boat at the start island.

## Changes needed next

### 1. Shorten the first gathering lesson

Break Ground now asks for **6 wood and 6 stone**, matching construction costs: the Logger's
Camp costs 6 wood and the Quarry costs 6 stone. Completing the lesson leaves the player exactly
able to build both extractors without another gathering stretch (quest progress is a lifetime
total, so materials spent along the way still count). Validate this budget in playtesting.

### 2. Replace the 100-resource gate with a practical lesson

Done: the old Scale Up milestone (build both extractors, then gather 100 wood and 100 stone)
is now **Lay the Foundations**, which only asks the player to place a Logger's Camp and a
Quarry. It teaches the build menu and placement, and Break Ground's 6 + 6 leaves exactly
enough to afford both. Both extractors are required, so earlier first-island notes describing
them as optional are superseded for the tutorial.

Still open: follow-up objectives that prove a building actually produced (see section 3).

### 3. Teach manual power before automatic power

Introduce **Operate** on a power-consuming building before unlocking the Burner Generator.
Let the player see that the robot can power one machine but is occupied while doing so. Then
demonstrate that a fueled generator keeps production running while the robot leaves to do
other work.

Done (first half): Operate is now a Lay the Foundations reward, and the next milestone, **Live
Wire**, asks the player to Operate a building (`Stat.BUILDINGS_OPERATED`) and reach 20 wood and
20 stone gathered (lifetime totals, so Break Ground's 6 + 6 count). Stockpiling both makes the
player shuttle the robot between the camp and the quarry, which sets up the Burner Generator it
unlocks alongside the Sawmill. Still open: an objective proving the generator runs production
while the robot is elsewhere.

Add objective tracking for those actions. A lifetime resource total alone cannot prove that
production came from the intended building or power source. Prefer an actual production event
under the relevant condition over an arbitrary waiting-time objective.

### 4. Unlock coastal wind through a frontier quest

Follow the chosen power ladder in [Power Sources](power-sources.md):

`Ring 0 robot + wood burner -> Ring 1 coastal windmill -> Ring 2 coal generator -> Ring 3 oil -> late nuclear`.

Proposed milestone: **Catch the Wind**. Reaching a new ring-1 island completes the discovery
beat and rewards the Windmill unlock. A subsequent objective asks the player to build a
windmill and run a mine with automatic power. The locked build-menu entry should identify the
unlocking quest.

The Windmill must be unlocked before any objective requires its construction. Final ordering
relative to Strike Iron and the supply-line lesson remains to be tuned; frontier construction
also depends on imported wood.

### 5. Make the first trade objective useful and specific

Replace the generic "ship 20 goods" lesson with a shipment of **wood from home to the treeless
colony**. This shows why the colony needs a supply line. Choose the quantity from the cost of
the next useful frontier building rather than an unrelated threshold.

Track resource, destination, and actual unloading; route creation alone does not prove useful
delivery. Existing frontier islands contain local stone, so the first lesson need not import
stone as well. Keep the dock bootstrap so the player can establish the route on arrival.

### 6. Define the payoff after the supply line

For the next content expansion, introduce smelting and a concrete use for iron ingots: a ship
repair stage or the next boat tier. Raw ore currently has no processing chain or onward quest.

Unlock the Smelter **before** asking the player to forge ingots. The older second-island
milestone table awards the Smelter after an ingot objective, which would create a circular
dependency if implemented literally. Two-input recipes and the metal-production content are
separate implementation work, beyond the initial opening/windmill design pass.

## Proposed teaching sequence

This is a sequence of lessons, not a finalized list of quest IDs or rewards:

1. Recover tools.
2. Gather a small starting budget.
3. Place the first production building.
4. Operate it manually and see output.
5. Use automatic power and free the robot for other work.
6. Process wood into planks.
7. Build the dock and reveal the frontier.
8. Explore and rescue K9-DA (the rescue remains an independent main goal).
9. Discover frontier resources and unlock coastal wind.
10. Import useful construction materials and power frontier production.
11. Later: refine metal and spend it on the next meaningful progression target.

The windmill discovery can precede trade, but its construction may need the first wood
shipment. Keep both objectives reachable in the final milestone ordering.

## Decisions still needed

- Is the first construction lesson one extractor or both? The 6 wood / 6 stone budget covers
  both.
- Is the Burner Generator mandatory to prove automatic power, or an optional early unlock?
- How many planks should the opening require, and what spends them? Currently 12 planks gate
  the quest, but the Dock itself costs only wood and stone; the salvage skiff comes moored
  with the Dock rather than as a separate build.
- Does ring 1 keep coal deposits while coal power waits for ring 2, or does the frontier resource
  profile change? Current non-starter islands all use the iron/coal/stone profile.
- Which quest rewards follow the rescue and useful trade? Choose a bounded first-playable
  endpoint before adding the larger ship-repair campaign.

## Implementation and validation notes

- Add the required operation, production, windmill, and targeted-delivery tracking. Keep
  lifetime accomplishment goals distinct from current-stock or active-building requirements.
- Append new saved enum IDs instead of reordering existing ones. Define how existing completed
  quests receive new unlocks without replaying one-shot ring-reveal rewards.
- Update the older first- and second-island documents when the proposed sequence is finalized.
- Playtest from an empty save without cheats: check material budgets, first power use, recovery
  from fuel shortages, frontier bootstrap, and completion without circular unlocks.
- Verify save/load preserves objective progress and grants each unlock correctly.
