# Progression, Build Restrictions, and Power

Design notes for how building progression is gated in Resource Isles. This captures
decisions and open questions; it is direction, not yet implemented.

See also: [Power Sources](power-sources.md) for the generator catalog and recommended power
progression path.

## The Core Question

Should building counts (e.g. logger's camps) be unlimited? If not, what restricts them,
and how does the player progress — by building *more* (wide) or *upgrading* existing
buildings (tall)?

## What Already Gates Building (and What Doesn't)

- **Resource cost** — a *soft* gate. It throttles the opening, but once camps produce wood
  passively it stops mattering. Not a real endgame limit.
- **Space + adjacency quality** — the *real* lever, and already half-built. Forest-adjacent
  tiles are scarce on a small island, and the logger's camp `-1 per adjacent camp` rule
  already punishes clustering. The map itself acts as the cap.
- **A hard count cap** (e.g. "max 3 camps") — avoided. Feels arbitrary unless tied to
  something diegetic.

## Decisions

### No build-count cap

Buildings are unlimited to place. The restrictions are:

1. **Scarce adjacency-good tiles** — good spots run out, so extra camps are progressively
   weaker.
2. **The crowding penalty** — `-1` yield per adjacent same-type building (already
   implemented), giving natural diminishing returns.
3. **Power budget** — see below. This is the chosen hard restriction.

### Progression is tall, not wide

The "second camp vs. upgrade the logger" choice is the classic tall/wide axis. Both exist,
but **space forces the choice** rather than a cap:

- **Wide (more camps):** cheap, but good forest spots run out and the crowding penalty bites.
- **Tall (upgrade a camp):** costs tech/resources, no extra tiles. Upgrades can raise base
  output, increase the adjacency multiplier (e.g. +2 per forest instead of +1), or extend
  reach (count forests two hexes away).

Intended tension: *"I'm out of good spots — cram in a weak 5th camp, or pour resources into
upgrading my best one?"* This falls straight out of the existing adjacency system.

### Minimal start

Start with the Hub only (or Hub + one camp). The player scavenges for the wood to afford
their first camp — this is the opening loop and the reason the one-off scavenge mechanic
earns its place.

### Power is the hard restriction (population is not)

Population/worker mechanics are **dropped** — one budget (power), not two. Power is what
stops the player running pointless camps.

- **Single island-wide pool** — power is a per-island capacity budget, **not** distributed by
  cables. There is intentionally no wiring/reach requirement, so power never competes with
  buildings for tile space. Matches the README's "simple, capacity-based MW". Generators add
  capacity; buildings draw it while active.
- **Cost is paid regardless of placement quality** — a logger's camp next to one lonely tree
  still eats its full power cost for +1 wood. *That* is the punishment for a pointless camp:
  every camp becomes an "is this worth the power?" decision.
- **Over-capacity = brownout** — if draw exceeds supply, buildings throttle or shut off,
  forcing the player to expand generation or tear down deadweight.

Power reinforces the adjacency system: it makes high-adjacency camps more desirable (more wood
per unit of power), pushing the player toward efficient, sustainable placement over sprawl.

### Inter-island transfer is the logistics layer

Because power stays a simple island-wide pool, the *logistics* depth comes later from
**moving things between islands**, not from wiring within one. Each new island has its own
local power pool; the endgame challenge becomes transferring resources (and possibly power)
across islands via ships, pipes, cables, or other transport — the Anno-style supply-route
problem already noted in the README. Keeping intra-island power frictionless is deliberate:
it reserves the spatial/logistics puzzle for the inter-island scale.

## Art Direction Implication

Power as a restriction does **not** require an industrial factory aesthetic. The chosen lane is
**cozy-mechanical / solarpunk**, keeping the existing thick-outline, board-game, muted-green
identity:

- Power is low-tech mechanical energy — **windmills, waterwheels, solar** (all already in the
  README's plan), not smokestacks.
- A logger's camp stays a camp; it gets a small windmill/waterwheel beside it or draws from a
  nearby one.
- This keeps the README's stated straddle intact: Factorio-style *systems* with Stardew-style
  *visuals*. Power lands on the systems side; the art stays cozy.

**Reference:** Timberborn (wooden mechanical power, sustainability/drought theme, cozy not
industrial), The Settlers, and solarpunk builders. Only switch to factory art if the fantasy
*is* industry itself (conveyors, smokestacks as the payoff) — not the direction for a
"relaxing little evening game".

## Open Questions

1. **Upgrade model:** in-place tiers (Tier 1 → Tier 2 on the same tile, each building is an
   investment decision) vs. a global tech that buffs all camps at once (simpler but flatter)?

## Resolved

- **Power distribution:** a single island-wide pool. No cables or generator-reach requirement —
  power must never compete with buildings for tile space. The logistics/spatial depth is
  deferred to **inter-island transfer** instead (see "Inter-island transfer is the logistics
  layer").
