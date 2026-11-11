# Abyss Hunter  (Godot 4.3+ project)

A Hungry Shark-style survival game: hunt, grow, dive deeper, buy upgrades and unlock bigger sharks.

## Run it
1. Install **Godot 4.3 or newer** (standard build; GL Compatibility renderer is used).
2. Godot Project Manager -> *Import* -> select `project.godot` -> *Edit* -> press **F5**.

## Controls
| Action | Keys |
|---|---|
| Swim | WASD / arrows / left stick / **mouse cursor** (toggle in Settings) |
| Bite (hold to keep chomping) | Left mouse / Space / gamepad A |
| Boost | Right mouse / Shift / gamepad RB |
| Pause | Esc / P / Start |

## Mechanics
- **Momentum swimming**, boost with a stamina bar, bite with a lunge and an open-jaw animation.
- **Hunger** drains constantly (faster while boosting); at zero you take damage. Eating restores hunger and a bit of health.
- **Growth**: XP -> levels -> bigger shark, more health/damage/speed, camera zooms out.
- **Bite power vs. creature HP**: big creatures need several bites; hit ratio depends on relative size. Hurt prey flees.
- **Hazards**: contact damage (barracuda, rival sharks, krakens...), **thorns** (pufferfish, stingray), **poison**, **electric stun** (electric eel), divers that fire **harpoons**, ambush predators that lunge (moray, anglerfish).
- **Combo** (eat within 3.2 s) multiplies score up to x5. Taking damage breaks it.
- **Feeding Frenzy**: fill the purple meter -> 10 s of +speed, +bite damage, x2 score/coins, half damage taken.
- **Surface leaps**: swim up fast to launch out of the water (gravity applies) and catch seagulls or chew through boats.
- **Depth biomes** (data/biomes.json): darkness (you only see a light circle; Bioluminescence upgrade widens it) and **pressure damage** below 1500 m (Deep Hull upgrade reduces it).
- **Persistent meta**: coins -> 10 upgrades, 6 sharks, Bestiary that fills as you meet creatures. Save is `user://save.json`.
- Danger icon (red !) appears over anything that hurts on contact.

## Add creatures, sharks, biomes, upgrades (the database)
All content lives in `data/*.json` (see `data/DATABASE.md` for every field):

- `creatures.json`, `sharks.json`, `biomes.json`, `upgrades.json`

Add a new object with a unique `"id"` and save. Missing fields use defaults. No code changes needed: the spawner, bestiary and menus pick it up on next launch (or press *Reload database* in Settings).

Minimal example, a new fish:
```json
{ "id": "lionfish", "name": "Lionfish", "length": 48, "shape": "puffer",
  "color": "#e0603a", "accent": "#ffffff", "min_depth": 100, "max_depth": 700,
  "behavior": "wander", "speed": 60, "hp": 2, "xp": 25, "hunger": 12,
  "coins": 6, "score": 80, "thorns": 6, "poison": 3 }
```
**Exported builds:** Settings -> *Export database files + open folder* copies the JSON to `user://data/`. Anything there overrides or adds to the shipped data by `id` (and `"disabled": true` removes an entry), so players/modders can edit without Godot. When exporting from the editor, add `*.json` to Export -> Resources -> *Filters to export non-resource files*.

You can also give a creature or shark your own art with a few animations (swim, idle, attack, hurt, boost):
drop strips like `swim_4.png` into `assets/sprites/creatures/<id>/` (or `sharks/<id>/`). See `assets/sprites/README.md`.
The older `"sprite": "res://path/to/image.png"` field still works (single image, or a strip with `"sprite_frames"`).

## Tilemap backgrounds
`scenes/game.tscn` contains `World` with three **TileMapLayer** nodes sharing `assets/tiles/world_tileset.tres`:

| Layer | Purpose |
|---|---|
| Background | water tiles (tile 0-3 = shallow -> abyss) |
| Decor | coral / kelp, drawn behind creatures |
| Terrain | **solid** sand/rock; anything painted here blocks the player and creatures; crabs walk on it |

- Select `World` in the editor and tick **Bake Default World** to generate the procedural world into the layers, then paint over it with the TileMap tools.
- Or paint all layers yourself. The playable world size = the used rect of Background (start at cell 0,0). If all layers are empty at runtime, a world is generated automatically.
- Replace `assets/tiles/world_tileset.png` with your own 32x32 tiles (keep the same 8 slots in one row) or add tiles to the TileSet.
- Animated tiles: add more rows to the PNG, each row below a tile is its next frame (see `assets/sprites/README.md`).
- Biome *gameplay* (darkness, pressure, spawn depths) is by depth in pixels from the surface (y=0), set in `biomes.json` / creature `min_depth`/`max_depth`.

## Project layout
```
data/                 editable JSON database
assets/tiles/         tileset image + TileSet resource
scenes/               main_menu.tscn (title), game.tscn
scripts/autoload/     Save, Database, Sfx (procedural sounds), Boot (input + settings)
scripts/game/         game.gd, shark.gd, creature.gd, creature_art.gd, world_generator.gd, projectile.gd
scripts/ui/           main_menu.gd (title, sharks, upgrades, bestiary, settings), hud.gd (HUD, pause, game over)
```
Creature visuals are procedural vector shapes (`shape`: fish, shark, whale, eel, jelly, crab, ray, turtle, puffer, squid, angler, chest, bird, boat, diver). To add a new shape, add a draw function in `creature_art.gd`.


## New: living ocean + play as any fish

- **Smarter creatures**: hunger/energy needs, day & night (fish sleep, nocturnal hunters wake up,
  plankton and migrating fish rise at night), real predator-prey food chain, schools that flee
  together, territories and dens, dolphins leaping, gulls diving for fish, boats anchoring at night.
- **Play as any fish**: main menu -> CHOOSE FISH -> "ANY FISH / CREATURE" tab. Your diet decides how
  you eat (plankton, algae, carrion or smaller fish). F3 toggles an AI debug overlay.
- Fields and tuning: see the "Life routine & ecosystem" and "Playing as any creature" sections in `data/DATABASE.md`.

## Camera & sizes

- The camera zooms so **your character is always about the same size on screen** (`PLAYER_SCREEN_LEN`
  = 72 px at 1280x720 in `scripts/game/game.gd`), whatever species or level. Everything else keeps its
  true size relative to you, so a blue whale is ~7x a starter shark and a sardine is a speck.
  Giants are limited by `MIN_ZOOM` (0.27) so the view never becomes the whole ocean; tiny fish by `MAX_ZOOM`.
- Spawn/despawn distance, plankton, particles, texts, hp bars and the light circle all scale with the
  zoom, so every species sees a lively ocean with UI of constant size. Swim speed grows with body size.
- Large sprites (frames wider than 256 px, or `sprite_smooth: true`) get mipmaps + smooth filtering at
  load time, so big art that is shown small no longer shimmers or looks jagged. Small pixel-art stays crisp.


## New: big world with six regions

The map is now 800 x 380 tiles (25,600 x 12,160 px, ~1.2 km deep) instead of 300 x 100:

| Region | What is there |
|---|---|
| **Sunny Coast** | beach island with palms, lighthouse and pier, sandy shallows, seagrass, shells, tide-pool life |
| **Kelp Forest** | tall swaying kelp up to the surface canopy, rocky outcrops, sea stacks |
| **Coral Reef** | a dozen coral types, bommies and arches you can swim through, sandy cays, caves in the reef wall |
| **Open Ocean** | the reef wall drops to an abyssal plain, seamounts, hydrothermal vents with tube worms, a hadal trench (down to ~1190 m) |
| **River Mouth & River** | murky water with a **current** that pushes you to the sea, sandbars, reeds, lily pads, logs, a bridge |
| **Mangrove Swamp** | dark murky water (short sight range), mangrove islets with prop roots, scum, methane bubbles, alligators |

- Depth zones: Sunlit 0-90 m, Twilight to 260 m, Midnight to 500 m, Abyss to 820 m, **Hadal Trench** below.
- ~50 new creatures; each species has `habitats` (regions) and a depth range. See `data/DATABASE.md`.
- The HUD shows the region + zone and a **minimap** (Settings: "Show minimap").
- **Characters are bigger on screen**: the camera keeps you ~170 px long (was 72). Change it in Settings -> *Character size*.
- `tools/make_tiles.py` regenerates `assets/tiles/world_tileset.png` and the `.tres` (81 tiles; run `python3 tools/make_tiles.py assets/tiles`). New species have no sprites yet, so they use the vector art until you add `assets/sprites/creatures/<id>/swim.png`.
- Not tested in the Godot editor here: if anything looks off, check the Output panel and tell me what it says.
