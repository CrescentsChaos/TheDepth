# Database reference

Each file is a JSON array of objects. `id` is required and unique. Omitted fields use the defaults shown.
Override/extend at runtime by placing a same-named file in `user://data/` (entries merge by `id`; `"disabled": true` removes one).

## creatures.json
| field | default | meaning |
|---|---|---|
| id, name, description | - | identity / bestiary text |
| length | 24 | body length in px (the shark starts at 70) |
| shape | fish | fish shark whale eel jelly crab ray turtle puffer squid angler chest bird boat diver |
| color, accent | #88aacc, #fff | hex colors |
| sprite | "" | optional single `res://...png` replacing the drawn shape (prefer the `assets/sprites/creatures/<id>/` folder, see assets/sprites/README.md) |
| sprite_frames | 1 | frames in the `sprite` strip |
| sprite_fps, sprite_scale | 8, 1.0 | animation speed / art size multiplier |
| sprite_faces_left, sprite_smooth | false | art faces left / linear filtering for hand-drawn art |
| sprite_wiggle | 0 | tail wave strength for single-image sprites (0 = off) |
| sprite_autosize | true | measure the visible pixels and scale them to `length`, ignoring canvas padding |
| min_depth, max_depth | 0, 3200 | spawn depth in px below surface (10 px = 1 m on the HUD). Ignored for fly/surface/bottom/static, which spawn on their own rules |
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
id, name, min_depth, max_depth (px), darkness (0..1, 1 = nearly black outside your light), pressure (damage/s, reduced by Deep Hull), tint (banner color). If you change depths, also update `World -> biome_rows` (row = depth / 32) so the water tile colors match.

## upgrades.json
id, name, description, stat, per_level, max_level, base_cost, cost_growth (cost = base * growth^level).
Stats: bite_damage, speed, stamina, max_health, max_hunger, hunger_efficiency, light, pressure_resist, coin_bonus, pull. To add a *new* stat, read it in code with `Database.upgrade_bonus("your_stat")`.
