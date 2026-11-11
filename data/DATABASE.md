# Database reference

Each file is a JSON array of objects. `id` is required and unique. Omitted fields use the defaults shown.
Override/extend at runtime by placing a same-named file in `user://data/` (entries merge by `id`; `"disabled": true` removes one).

## creatures.json
| field | default | meaning |
|---|---|---|
| id, name, description | - | identity / bestiary text |
| length | 24 | body length in px (the shark starts at 70) |
| shape | fish | fish shark whale eel jelly crab ray turtle puffer squid angler chest bird boat diver croc seahorse octopus |
| color, accent | #88aacc, #fff | hex colors |
| sprite | "" | optional single `res://...png` replacing the drawn shape (prefer the `assets/sprites/creatures/<id>/` folder, see assets/sprites/README.md) |
| sprite_frames | 1 | frames in the `sprite` strip |
| sprite_fps, sprite_scale | 8, 1.0 | animation speed / art size multiplier |
| sprite_faces_left, sprite_smooth | false | art faces left / linear filtering for hand-drawn art |
| sprite_wiggle | 0 | tail wave strength for single-image sprites (0 = off) |
| sprite_autosize | true | measure the visible pixels and scale them to `length`, ignoring canvas padding |
| min_depth, max_depth | 0, 12000 | spawn depth in px below surface (10 px = 1 m on the HUD; the world is ~1216 m deep). Ignored for fly/surface, which spawn on their own rules; bottom/static spawn on the sea floor inside this range |
| habitats | [] | regions where it spawns: `coast` `kelp` `reef` `ocean` `river` `swamp` (empty = everywhere). Only `ocean` is deep; the others are shelves up to ~200 m |
| weight | 10 | relative spawn chance |
| max_count | 10 | max alive at once |
| school_size | 1 | group size for `school` behavior |
| behavior | wander | wander, school, hunter (chases when you're small enough), ambush (waits, then lunges), drift (jellyfish), bottom (walks on terrain), static (chests), fly (above water), surface (boats), shooter (fires harpoons) |
| speed | 70 | px/s |
| hp | 1 | bite damage needed to kill it |
| xp, hunger, coins, score | 5, 6, 1, 10 | rewards when eaten (`hunger` = food restored) |
| contact_damage | 0 | damage dealt when touching you (1 s cooldown) |
| thorns | 0 | damage you take when you bite it |
| poison | 0 | seconds of poison after eating it |
| stun | 0 | seconds you are stunned by touching or biting it |
| edible | true | false = cannot be bitten |
| flee_range | 0 | runs away when you are within this many px and bigger than 60% of its length |
| aggro_range | 0 | detection range for hunter / ambush / shooter |
| projectile_damage | 12 | harpoon damage for shooters |
| tags | [] | free-form |

## sharks.json
id, name, description, color, belly, length (70), sprite fields (same as creatures; folder `assets/sprites/sharks/<id>/`), speed (300), accel (900), boost_mult (1.6), bite_damage (2), bite_range (44), max_health (100), max_hunger (100), hunger_drain (2.6/s), stamina (100), cost (0 = free), stun_resist (0..1).

## biomes.json
id, name, min_depth, max_depth (px), darkness (0..1, 1 = nearly black outside your light), pressure (damage/s, reduced by Deep Hull), tint (banner color). These are the **depth zones** (sunlit, twilight, midnight, abyss, hadal). If you change depths, also update `World -> biome_rows` (row = depth / 32) so the water overlay tiles match.

The **regions** (west to east: coast, kelp, reef, ocean, river, swamp) are defined in `scripts/game/world_generator.gd` (`REGIONS`: name, x range, fog, light radius, current; `PALETTES`: water colours; `PROFILE`: the sea-floor shape).

## upgrades.json
id, name, description, stat, per_level, max_level, base_cost, cost_growth (cost = base * growth^level).
Stats: bite_damage, speed, stamina, max_health, max_hunger, hunger_efficiency, light, pressure_resist, coin_bonus, pull. To add a *new* stat, read it in code with `Database.upgrade_bonus("your_stat")`.


## Life routine & ecosystem fields (creatures.json)

Every creature runs a life-routine brain (see `scripts/game/creature.gd`) driven by these
optional fields. `behavior` still picks the body style; these pick what the animal *does*.

| field | values | meaning |
|---|---|---|
| `diet` | `carnivore` `omnivore` `herbivore` `plankton` `filter` `scavenger` `none` | what it eats. Carnivores hunt creatures, herbivores graze algae on coral/kelp tiles, plankton/filter feeders work drifting plankton clouds, scavengers eat carrion and deep-sea marine snow |
| `prey_ratio` | number (default 0.5) | a carnivore hunts creatures up to `length * prey_ratio` (never toxic/spiny ones) |
| `eats` | list of ids | always-edible prey regardless of size (turtle eats `jellyfish`, gulls dive for `sardine`...) |
| `activity` | `diurnal` `nocturnal` `crepuscular` `any` | when it is awake. Others sleep (you see "z Z") and are easy prey |
| `rest_style` | `open` `reef` `floor` | where it sleeps: right where it is, in a coral/kelp den, or on the sea floor |
| `territorial` | bool | defends its home patch and chases smaller intruders away |
| `migrates` | bool | daily vertical migration: rises toward the surface at night, sinks by day |
| `leaps` | bool | jumps out of the water now and then (dolphin) |
| tag `curious` | in `tags` | circles the player to have a look when not afraid |

Day length is `Ecosystem.DAY_LENGTH` (300 s). A creature's day: sleep at its quiet hours, wake,
get hungry (needs rise over time), look for food (hunt / graze / scavenge), flee from anything
that can eat it (schools bolt together via alarm calls), otherwise roam its home range,
visit food patches, hover, patrol, or lurk. Predators that eat get full and leave prey alone for a while.
Press **F3** in game for the AI debug view (state, hunger, energy, targets).

## Playing as any creature

Every creature is playable unless it has `"playable": false` (gull, diver, boat, chest).
`Database.creature_as_player()` derives the player stats from the creature entry
(speed, health, bite, reach, hunger drain by diet, deep-sea pressure/light immunity,
start depth...). To hand-tune one species add a `"player"` object whose keys override the
derived values, e.g. `"player": {"speed": 380, "bite_damage": 3.0, "max_health": 140}`.
Add `"cost": 500` to make a species cost coins in the character menu (default 0 = free).

What a bite can eat depends on the diet: carnivores/omnivores bite creatures up to
`length * prey_ratio`; plankton/filter eaters bite plankton clouds; herbivores bite algae;
scavengers bite carrion and marine snow. Body traits carry over: `contact_damage`
(electric eel shocks what it touches), `thorns`, `stun`.
