# Quest design review — 2026-10-04

This records the current quest chain and the proposed next design pass. The recommendations
below are not implemented or final balance decisions. Each milestone should teach one clear
action, demonstrate its payoff, and unlock the next step before requiring it.

## Current implementation

The catalog in [quest_catalog.gd](../scripts/quests/quest_catalog.gd) has one independent main
quest, **Rescue K9-DA**, and a linear milestone chain:

| Milestone | Current objectives | Reward |
| --- | --- | --- |
| Recover Your Tools | Collect the axe, pickaxe, and wrench | Harvesting |
| Break Ground | Gather 20 wood and 20 stone | Logger's Camp and Quarry |
| Scale Up | Build a camp and quarry; gather 100 wood and 100 stone in total | Sawmill and Burner Generator |
| Refine | Build a sawmill; gather 12 planks | Dock |
| Set Sail | Build a dock | Reveal ring 1 |
| Strike Iron | Gather 5 iron ore | Iron Mine and Coal Mine |
| The Supply Line | Establish a route; ship 20 goods | No mechanical reward; chain ends here |

Rescue K9-DA now requires the actual Rescue action on the dog's island; simply reaching another
island does not complete it. It runs independently of the milestones.

Gathering and construction objectives use global lifetime totals, not current inventory or
progress since a quest began. Spending materials does not reduce quest progress. Previously
completed actions can satisfy a newly activated milestone immediately.

The Windmill currently has no quest reward gating it, so it is available by default. There are
no dedicated objectives for manually operating a building, building a windmill, proving a mine
is automatically powered, or delivering a particular resource to a particular island.

## Changes needed next

### 1. Shorten the first gathering lesson

Try **5 wood and 5 stone** for Break Ground, following the playtest feedback. Tune construction
costs and quest targets together so completing the lesson leaves the player able to build the
next required structure without another long gathering stretch.

Currently the Logger's Camp and Quarry cost 6 wood each, so 5 wood cannot pay for both. Decide
whether the first construction quest requires one building or both, then set the budget around
that choice. Five of each is a starting hypothesis for playtesting, not a settled economy.

### 2. Replace the 100-resource gate with a practical lesson

Scale Up currently makes both extractors mandatory and asks for 100 of each resource. Replace
the large totals with placement and actual production objectives. Building a machine, operating
it, and seeing it produce teaches more than extending a collection counter.

Earlier first-island notes describe camps and quarries as optional. Resolve that conflict:
the proposed pass introduces an early construction/operation lesson, but whether it requires
both extractors remains open. Avoid requiring buildings solely to fill out the tutorial.

### 3. Teach manual power before automatic power

Introduce **Operate** on a power-consuming building before unlocking the Burner Generator.
Let the player see that the robot can power one machine but is occupied while doing so. Then
demonstrate that a fueled generator keeps production running while the robot leaves to do
other work.

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

- Is the first construction lesson one extractor or both? What costs make 5 wood/stone a
  sufficient opening budget?
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
