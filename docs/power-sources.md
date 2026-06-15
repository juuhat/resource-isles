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

### Tier 0: Starter Power

Small, crude, and local.

- **Burner Generator**
  - Consumes Wood or Charcoal.
  - Reliable starter power.
  - Teaches that buildings need MW.
  - Good first implementation target.

- **Campfire Generator / Heat Hut**
  - Even simpler visual version of the burner generator.
  - Tiny output, cheap cost.
  - Useful only if the game needs an ultra-soft opening step.

### Tier 1: Cozy Mechanical Renewables

Low output, low maintenance, strong fit for the island mood.

- **Windmill**
  - No fuel.
  - Better on coast, hills, exposed grass, or tiles with few adjacent blockers.
  - Can be steady for simplicity, or variable later.

- **Waterwheel**
  - Requires water adjacency.
  - Reliable low power.
  - Strong cozy identity and good placement puzzle.

- **Small Solar Panel**
  - No fuel.
  - Needs open land.
  - Best when paired with batteries if day/night or weather exists.

### Tier 2: Storage And Reliable Fuel

This tier creates a clean-vs-compact tradeoff.

- **Battery Bank**
  - Stores surplus renewable power.
  - Smooths wind/solar if variability is implemented.
  - Consumes space but no fuel.

- **Coal Plant**
  - High reliable output.
  - Requires Coal logistics.
  - More industrial; use sparingly if the cozy tone matters.

- **Oil Generator**
  - Compact and strong.
  - Requires Oil or Refined Fuel.
  - Good for inter-island trade pressure.

- **Steam Plant**
  - Burns Wood, Coal, Oil, or Fuel depending on tech tier.
  - May require water adjacency.
  - Flexible bridge from early to midgame power.

- **Biomass Plant**
  - Consumes Wood, crops, or organic waste.
  - Renewable but logistics-heavy.
  - Fits the cozy/sustainable lane better than coal.

### Tier 3: Special Island Power

Terrain-gated sources that make exploration valuable.

- **Geothermal Plant**
  - Requires geyser, hot spring, volcanic, or thermal vent feature.
  - Reliable and strong.
  - Great reward for a rare island.

- **Tidal Generator**
  - Requires coast.
  - Reliable or rhythmic output.
  - Good island-themed alternative to fossil power.

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

### Tier 4: Late Game Dense Power

Expensive, compact, and supply-chain-heavy.

- **Gas Turbine**
  - Very reliable.
  - Consumes Refined Fuel or Natural Gas.
  - Strong backup for renewable-heavy islands.

- **Nuclear Reactor**
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
Burner Generator -> Windmill -> Waterwheel -> Solar + Battery -> Biomass/Fuel -> Geothermal/Tidal -> Nuclear/Fusion
```

This path keeps the early game cozy and readable, makes midgame logistics matter, and gives
new islands a reason to exist beyond more space.

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
