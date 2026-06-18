# Island Visual Variety

Design notes for making many islands feel distinct without requiring a large amount of bespoke
art. This is the visual companion to [Island Generation, Biomes, and Resources](island-generation.md):
the gameplay profile decides what an island *does*, while the visual profile decides what it
*feels like*.

## Core Idea

Use procedural recombination for visuals the same way the generator uses procedural variation
for island layout:

> **A small authored visual vocabulary can produce many island moods when layered, tinted, and
> recombined by biome profiles.**

Do not make every island type a fully custom art set. Instead, define a few reusable layers:

- Terrain palettes
- Shoreline palettes
- Shape rules
- Scatter props
- Decals
- Resource skins
- One strong landmark
- Optional ambience such as particles, fog, or water tint

The result should feel authored, but be cheap to extend.

## Visual Layers

### 1. Terrain palette swaps

Use the same terrain geometry and tile masks, but change the color ramps per biome or visual
skin.

Examples:

- Grassy starter: soft greens, warm sand, clear water.
- Volcanic: dark basalt, ash grey, warm lava accents.
- Atoll: pale coral, white sand, turquoise lagoon.
- Dry island: ochre sand, sun-bleached stone, sparse grass.
- Swamp: moss green, dark mud, muted water.
- Cold rock: blue-grey stone, pale grass, dark sea.

This is one of the cheapest high-impact tools because it reuses almost all geometry and art.

### 2. Scatter props from small sets

A biome only needs a handful of small props to read differently.

Examples:

- Volcanic: black rocks, lava cracks, steam vents, ash shrubs.
- Atoll: coral chunks, palms, shells, tide pools.
- Pine: conifers, mossy rocks, fallen logs.
- Swamp: reeds, dead trees, puddles, mushrooms.
- Ruin island: broken tiles, pillars, scrap, old machine parts.

Props should be placed by noise, terrain rules, and local context. A prop set with 5-10 items can
carry a whole biome if silhouettes are clear.

### 3. Shape rules

Island silhouette can do as much as color. The same resource contract can be expressed through
different land shapes.

Examples:

- Atoll: ring-shaped land around a lagoon.
- Volcanic: compact island with a rocky cone or crater center.
- Marsh: fragmented blobs with many water cuts.
- Cliff island: dense stone mass with thin shoreline.
- Sandbar: long crescent or narrow strip.
- Mini-archipelago: several tiny blobs close together.

These are generator parameters, not necessarily new art.

### 4. One landmark per biome

One recognizable centerpiece makes an island memorable.

Examples:

- Volcano crater
- Lighthouse ruin
- Giant tree stump
- Coral lagoon
- Crashed satellite piece
- Hot spring
- Abandoned mine entrance

Landmarks should be rare enough to matter and visually strong enough that the player can say
"the volcano island" or "the lighthouse island" from memory.

### 5. Resource silhouettes and skins

Keep resource mechanics stable, but let the visual treatment change by biome.

Examples:

- Stone on grass: rounded boulders.
- Stone on volcanic: basalt columns.
- Stone on dry island: pale limestone.
- Coal: black seams or dark chunks.
- Iron: rusty red outcrops.
- Wood on grass: leafy trees.
- Wood on atoll: palms or driftwood.
- Wood on swamp: deadwood or wet roots.

This lets a biome feel fresh without inventing a new resource every time.

### 6. Decal overlays

Small decals add richness without changing the gameplay grid.

Examples:

- Cracks
- Moss patches
- Shells
- Pebbles
- Flowers
- Soot
- Puddles
- Grass tufts
- Reeds

Decals should be context-sensitive: shells near beaches, soot near volcanic stone, moss on damp
rock, cracks on dry or volcanic terrain.

## Proposed Data Shape

```text
IslandVisualProfile:
  base_palette
  shoreline_palette
  water_palette
  silhouette_rule
  prop_set
  decal_set
  landmark_pool
  resource_skin_overrides
  ambient_effects
```

The generation flow becomes:

```text
pick gameplay profile
pick compatible visual profile
generate island shape from silhouette_rule
paint terrain using palette and subtle noise
place gameplay resources from the contract
skin resources based on visual profile
scatter props by density, terrain, and noise
place one landmark
add decals around terrain/resource edges
apply ambient effects
```

## Gameplay Biome vs. Visual Skin

Separate gameplay identity from visual identity, but let them influence each other.

For example, a `STONE` gameplay island could visually appear as:

- Basalt island
- Limestone island
- Slate island
- Red desert rock island
- Cold granite island

Mechanically, all can provide stone, iron, and coal. Visually, each feels like a different place.
This keeps progression understandable while giving the world more texture.

## Low-Art Starting Set

A useful first pass could be:

- 3-5 terrain palettes
- 3 shoreline palettes
- 10 generic rocks
- 10 plants or trees
- 10 decals
- 1 landmark per island family

That is enough to produce many island moods through recombination. Prioritize assets with strong
silhouettes and broad reuse over narrowly specific decorations.

## Early Island Families

Good candidates for Resource Isles:

| Family | Visual hook | Cheap procedural trick |
| --- | --- | --- |
| Grass / starter | Soft green, readable, cozy | Existing blob island + forest/stone props |
| Stone / mining | Grey rock, ore deposits, sparse plants | Stone palette + denser rock/ore scatter |
| Volcanic | Dark basalt, lava cracks, steam | Dark palette + crater landmark + crack decals |
| Atoll | Pale sand, coral, lagoon | Ring silhouette + turquoise inner water |
| Swamp | Mud, reeds, deadwood, puddles | Broken silhouette + water cuts + reed decals |
| Pine / cold | Conifers, blue-grey stone, cold water | Pine props + cooler palette |
| Ruins / scrap | Broken structures, old machinery | Landmark pool + scattered ruin decals |

## Implementation Notes

- Add visual variety as data first, not hard-coded one-off branches.
- Let `IslandProfile` keep the gameplay contract: resources, terrain base, size, dockability.
- Add a companion visual profile or visual skin field once multiple looks exist.
- Reuse the current terrain renderer and resource placement rules as much as possible.
- Start with palette changes and decals before making many new models.
- Treat landmarks as the highest-value bespoke art; they do the most memory work per asset.

