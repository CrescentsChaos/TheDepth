# Replacing sprites and tiles

No code changes needed. Save your PNGs, restart the game (or Settings -> *Reload database*).

## Fish / creatures / sharks

Put images in a folder named after the entry's `id` (from `data/creatures.json` or `data/sharks.json`):

```
assets/sprites/creatures/clownfish/swim_4.png
assets/sprites/creatures/clownfish/idle_2.png
assets/sprites/creatures/clownfish/attack_3.png
assets/sprites/creatures/clownfish/hurt_2.png
assets/sprites/sharks/great_white/swim_6.png
assets/sprites/sharks/great_white/attack_3.png      (bite)
assets/sprites/sharks/great_white/boost_4.png
```

| File | When it plays |
|---|---|
| `swim` | default, loops. The only required one |
| `idle` | (almost) standing still. Falls back to swim |
| `attack` | creature lunging / chasing / shooting, or the shark biting. Falls back to swim |
| `hurt` | taking damage, plays once. Falls back to swim |
| `boost` | sharks only, while boosting. Falls back to swim |

**Strips:** an animation is one PNG with all frames side by side, equal size. Put the frame count in the
file name: `swim_4.png` = 4 frames. No number = one image. A single image stays still; use `sprite_wiggle` for an optional tail wave.

**Size (automatic):** the game measures the visible, non-transparent pixels of your frames and scales
the sprite so that the visible body width = the entry's `length`. So the canvas size and transparent
padding don't matter: you can export every fish on the same 256x128 canvas and a sardine, a tuna and a
whale still come out at their own sizes. Keep all animations of one creature on the same canvas size,
and don't let the body get clipped by the canvas edge. Use `sprite_scale` to fine-tune one species, or
`"sprite_autosize": false` to scale the whole canvas instead.

**Rules:** sprites face **right**. A creature with no folder keeps its vector art, so you can
replace them one at a time.

**Optional JSON fields** (in the creature / shark entry):

| Field | Default | Meaning |
|---|---|---|
| `sprite_fps` | 8 | animation speed |
| `sprite_scale` | 1.0 | make the art bigger/smaller without changing hitbox/`length` |
| `sprite_wiggle` | 0 | optional tail wave for single-image sprites (try 0.03 to 0.08; 0 = off) |
| `sprite_autosize` | true | scale by the visible art instead of the whole canvas |
| `sprite_faces_left` | false | your art faces left |
| `sprite_smooth` | false | smooth (linear) filtering for hand-drawn art; leave off for pixel art |

The Bestiary, shark select and title screen use your sprites too.

Try it: copy everything in `_template/` into `assets/sprites/creatures/sardine/`.

## Background tiles

`assets/tiles/world_tileset.png` is 8 tiles of 32x32 in one row:
`0-3` water (shallow to abyss), `4` sand, `5` rock, `6` coral, `7` kelp. Overwrite it with your own,
keeping the slots (or add tiles to the TileSet in the editor).

**Animated tiles:** make the PNG taller. Row 0 is the normal tile; each row below is the next frame of the
tile above it. A tile animates automatically when the cell under it is not empty. Leave cells blank to
keep a tile still. Speed: `World -> Tile Animation Fps` (default 3).

Example: `assets/tiles/world_tileset_animated_example.png` (water + kelp, 4 frames). Copy it over
`world_tileset.png` to try it.
