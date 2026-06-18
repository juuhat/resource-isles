# Power Sources

Design notes for possible power buildings and energy progression in Resource Isles. This is
direction, not implementation.

## Power Model

Start with a simple island-wide capacity model:

```text
generated MW - consumed MW = surplus or deficit
```

Generators add capacity. Production buildings draw capacity while active. Early power should
not need wires, range, or per-building connections; the interesting planning pressure comes
from space, fuel logistics, reliability, and inter-island supply.

Later, power cables can exist at the inter-island scale as a logistics unlock, not as a
same-island wiring puzzle.

## Design Goals

- Keep power readable and cozy, not a heavy electrical simulation.
- Make generators compete for scarce island space.
- Make fuel-based power reliable but logistically hungry.
- Make renewable power clean but location-sensitive or storage-dependent.
- Use rare terrain features to make new islands exciting.

## Recommended Progression

Current chosen ladder:

```text
Ring 0: Robot hand-power + Wood Burner
Ring 1: Coastal Windmill
Ring 2: Coal Generator
Ring 3: Oil
Late:   Nuclear
```

The intent is to keep power tied to the island/resource-node progression without turning
same-island power into a wiring puzzle. Power remains an island-wide capacity budget, while each
new source adds a different placement, fuel, or logistics pressure.

### Tier 0: Starter Power

Small, crude, and local.

- **The robot itself (implemented)** — the tier-0 power source
  - There is **no Manual Generator building.** Instead the robot *is* the bootstrap power
    source: park it on any power-consuming building and press **Operate** in the command bar
    (`scripts/ui/action_bar.gd`) to hand-power that building for free. It stalls the instant the
    robot walks away or is sent elsewhere.
  - Implemented as: `main._building_consumes_power` gates the Operate action on
    `power_consumed > 0`; while operating, `power_manager._allocate_power` marks the operated
    building powered and excludes its draw from the island pool (the robot supplies it).
  - This is the **power half of the bootstrap arc**: being the power source yourself is the
    "before" that makes the self-running Burner Generator feel like liberation, exactly as
    hand-chopping makes the logger camp feel like liberation
    (see [player-unit-and-manual-gathering.md](player-unit-and-manual-gathering.md)). The
    friction — one robot cannot chop and power at the same time — is the point. Folding the old
    Manual Generator building into the robot also removes the "born-dead building" beat (build a
    camp, find it needs a second building to run); see
    [first-island-progression.md](first-island-progression.md).

- **Burner Generator (implemented)**
  - Consumes Wood.
  - Reliable starter power; the first *automatic* generator — the upgrade from the manual wheel.
  - Teaches that buildings need MW.

- **Campfire Generator / Heat Hut**
  - Even simpler visual version of the burner generator.
  - Tiny output, cheap cost.
  - Largely redundant now that the robot itself is the ultra-soft opening power step.

### Tier 1: Coastal Mechanical Renewables

Low output, low maintenance, strong fit for the island mood.

- **Coastal Windmill (chosen for ring 1)**
  - No fuel.
  - Requires a land tile adjacent to Coast.
  - Makes shoreline matter before the game has many water buildings beyond the Dock.
  - Generates modest, steady baseline power so treeless islands are not forced immediately into
    fuel power.

- **Inland Windmill**
  - Alternative if later biomes need non-coastal wind.
  - Better on hills, exposed grass, or tiles with few adjacent blockers.
  - Held as a variant; the coastal version is the current fit for small islands.

- **Waterwheel**
  - Requires water adjacency.
  - Reliable low power.
  - Strong cozy identity and good placement puzzle.
  - Deprioritized for now: it reads more river/valley than small-island.

- **Small Solar Panel**
  - No fuel.
  - Needs open land.
  - Best when paired with batteries if day/night or weather exists.
  - Good candidate to revisit, but not currently on the main ladder; it risks competing with the
    cleaner early identity of coastal wind.

### Tier 2: Reliable Fuel

This tier creates a clean-vs-compact tradeoff.

- **Coal Generator (chosen for ring 2)**
  - High reliable output.
  - Requires Coal logistics.
  - Coal should arrive after the first coastal renewable, so it feels like a stronger but dirtier
    throughput answer rather than the first non-wood solution.
  - Best when coal competes with another use, such as smelting, so fuel power has an opportunity
    cost.

- **Steam Plant**
  - Burns Wood, Coal, Oil, or Fuel depending on tech tier.
  - May require water adjacency.
  - Flexible bridge from early to midgame power.
  - Alternative wrapper for coal power if the building fantasy wants boilers instead of a direct
    generator.

- **Battery Bank**
  - Stores surplus renewable power.
  - Smooths wind/solar if variability is implemented.
  - Consumes space but no fuel.
  - Documented as an option, but not currently on the main ladder. Add when variable generation
    exists; otherwise it is UI/system weight without much payoff.

### Tier 3: Dense Fuel And Special Island Power

- **Oil Generator / Gas Turbine (chosen for ring 3)**
  - Compact and strong.
  - Requires Oil or Refined Fuel.
  - Good for inter-island trade pressure and boat/vehicle fuel.
  - Should not just be "coal but later"; tie it to mobility and refined-fuel logistics.

- **Oil Seep / Offshore Oil Well**
  - Best node/feature form for small islands.
  - A land Oil Seep is the simple version; Offshore Oil makes the coastline/water layer matter
    more once the player has the infrastructure for it.

- **Biomass Plant**
  - Consumes Wood, crops, or organic waste.
  - Renewable but logistics-heavy.
  - Fits the cozy/sustainable lane better than coal.
  - Alternative to coal/oil if a future island adds `KELP`, `ALGAE`, `PEAT`, or other organic
    nodes. Not on the current main ladder.

### Other Special Island Power

Terrain-gated sources that make exploration valuable.

- **Geothermal Plant**
  - Requires geyser, hot spring, volcanic, or thermal vent feature.
  - Reliable and strong.
  - Great reward for a rare island.

- **Tidal Generator**
  - Requires coast.
  - Reliable or rhythmic output.
  - Good island-themed alternative to fossil power.
  - Strong future candidate because it uses the same shoreline economy as docks and coastal
    windmills. Held back for now so ring 1 stays readable.

- **Wave Generator**
  - Requires coast or offshore placement.
  - Moderate output, possibly weather-sensitive.

- **Offshore Wind Farm**
  - Requires coastal/offshore space.
  - Strong renewable.
  - Good late-midgame expansion sink.

- **Solar Tower / Mirror Field**
  - Requires large open area, ideally desert or sunny island.
  - High daytime output.
  - Large footprint makes it a serious space decision.

### Late Game Dense Power

Expensive, compact, and supply-chain-heavy.

- **Gas Turbine**
  - Very reliable.
  - Consumes Refined Fuel or Natural Gas.
  - Strong backup for renewable-heavy islands.

- **Nuclear Reactor (chosen for late game)**
  - Huge output.
  - Requires Uranium, Water, and advanced materials.
  - Optional waste/heat management if the game wants more friction.

- **Fusion Reactor**
  - Endgame clean power.
  - Requires rare advanced resources.
  - Very high output, very high cost.

## Full Energy Source Catalog

### Natural And Renewable

- Solar
- Wind
- Waterwheel
- Hydroelectric dam
- Tidal
- Wave
- Geothermal
- Biomass
- Animal power
- Manual or mechanical power

### Fuel-Based

- Wood
- Charcoal
- Coal
- Peat
- Oil
- Refined fuel
- Natural gas
- Biofuel
- Hydrogen
- Methane or biogas

### Storage And Buffering

- Battery storage
- Capacitors
- Flywheel storage
- Pumped hydro storage
- Thermal storage
- Compressed air storage

### Advanced

- Nuclear fission
- Fusion
- Gas turbine
- Fuel cell
- Space solar relay

### Fantasy Or Special Sources

- Crystal generator
- Volcano core
- Ancient ruin reactor
- Lightning collector
- Mana or essence well
- Sun shrine
- Storm turbine
- Deep-sea thermal vent

## Best Fit For Resource Isles

The strongest fit is:

```text
Robot hand-power -> Wood Burner -> Coastal Windmill -> Coal Generator -> Oil -> Nuclear
```

This path keeps the early game cozy and readable, makes the shoreline useful early, saves fossil
fuels for later resource-node progression, and gives late islands a reason to exist beyond more
space.

Alternatives intentionally kept on the shelf:

- **Solar + Battery**: good small-island fit, but better once day/night, weather, or variable
  generation exists.
- **Waterwheel**: cozy, but less island-flavored than coastal wind.
- **Biomass**: good if future islands add organic coastal/wetland nodes such as kelp, algae, or
  peat.
- **Tidal / Wave / Geothermal**: excellent special-island power, but not part of the current main
  spine.

## First Implementation Slice

For a minimal first pass:

1. Add `POWER` as a resource-like island stat measured in MW.
2. Add a `power_generated` field to generator building definitions.
3. Add a `power_consumed` field to production building definitions.
4. Sum generation and consumption per island.
5. If consumption exceeds generation, pause or throttle production buildings.
6. Add one generator first: **Burner Generator** or **Windmill**.

The simplest useful first building is the **Windmill**: no fuel loop, clear cozy identity,
and it immediately makes power placement visible.
