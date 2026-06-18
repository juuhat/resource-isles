# Postgame Leaderboards And One More Turn

Design notes for a later postgame layer: after the main rescue / ship-repair goal is complete,
the player can keep optimizing the archipelago for leaderboard-style challenges. This is a
future idea, not an implementation requirement for the core game.

## Core Idea

After the player launches the repaired ship or rescues K9-DA, the game should allow a
Civilization-style **one more turn** mode:

```text
Main goal complete -> keep playing -> optimize the archipelago -> chase rate records
```

This gives the game an endgame without needing endless story content. The player has already
"won"; now the question becomes how elegant, productive, compact, or specialized their island
network can become.

## Score Types

Prefer **rate-based scores** over lifetime totals. Lifetime totals reward waiting, while rates
reward building a better machine.

Good scoring windows:

- Best sustained 3-minute output.
- Average output over the last 5 minutes.
- Best post-launch production window.

Useful leaderboard categories:

- Wood per minute.
- Stone per minute.
- Planks per minute.
- Iron ingots per minute.
- Total power generated.
- Power surplus.
- Trade throughput between islands.
- Best single-island output.
- Best whole-archipelago output.
- Most efficient island: output per tile, output per MW, or output per building.
- Clean power ratio, if fuel/renewable distinction becomes a scoring theme.
- Fastest launch / rescue.
- Fewest buildings to launch.
- Smallest footprint launch.

Island-specialist categories fit Resource Isles especially well:

- Best Lumber Island.
- Best Stone Island.
- Best Power Island.
- Best Export Hub.
- Best Tiny Island.
- Best No-Fuel Grid.
- Best Ring 1 Economy.

## Local vs Global Leaderboards

For **local personal records**, no server is needed. The game can calculate production rates from
the local simulation and save best results in the save file.

For **global online leaderboards**, assume the client cannot be trusted. A real competitive
leaderboard needs one of these approaches:

1. **Server-side simulation / validation.** Upload the save, build layout, world seed, rules
   version, and scoring window; the server replays or validates the score.
2. **Server-authoritative scoring runs.** The server owns the run state and calculates production
   directly. This is strongest but much heavier and probably not a fit for this project early.
3. **Casual untrusted submissions.** Let the client submit scores directly. This is easy, but
   only suitable for friendly/non-serious leaderboards because scores can be modified.

Recommended path:

```text
Local personal records first.
Optional casual online leaderboard later.
Trusted online leaderboard only if the game grows enough to justify server work.
```

## Anti-Waiting Rules

If scoring is added, avoid scores that improve just because the player leaves the game running.

Useful rules:

- Score a fixed time window, not all-time accumulation.
- Require stable input stocks at the start and end of the scoring window, or track net output.
- Separate gross production from net export, so burning huge inputs is not automatically good.
- Pin scores to a `rules_version`, so balance changes do not mix old and new records.

## Why This Fits

Resource Isles already has the right ingredients:

- Small islands with scarce high-quality adjacency spots.
- Per-island inventories.
- Power as an island-wide budget.
- Future trade routes and inter-island throughput.
- Tall-vs-wide upgrades.
- A clear main goal that can transition into optimization.

The postgame fantasy is:

> You got home. Now build the best little island machine possible.
