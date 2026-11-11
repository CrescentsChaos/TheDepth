"""Generates assets/tiles/world_tileset.png + world_tileset.tres for Abyss Hunter.
Sheet layout: one column per tile; row 0 = the tile, rows 1..3 = animation frames
(blank rows = static tile). The first 8 slots keep their old meaning (0-3 water, 4 sand,
5 rock, 6 coral, 7 kelp) so old painted maps still load."""
import random, math, sys

from PIL import Image, ImageDraw

T = 32
FR = 4
OUT = sys.argv[1] if len(sys.argv) > 1 else "."


def clamp(v, a=0, b=255):
    return max(a, min(b, int(v)))


def H(h, a=255):
    h = h.lstrip('#')
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def shade(c, f):
    return (clamp(c[0] * f), clamp(c[1] * f), clamp(c[2] * f), c[3] if len(c) > 3 else 255)


def mix(a, b, t):
    return tuple(clamp(a[i] * (1 - t) + b[i] * t) for i in range(3)) + (255,)


class Tile:
    def __init__(self):
        self.im = Image.new('RGBA', (T, T), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.im)

    def px(self, x, y, c):
        if 0 <= x < T and 0 <= y < T:
            self.im.putpixel((int(x), int(y)), c)

    def rect(self, x0, y0, x1, y1, c):
        self.d.rectangle([min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1)], fill=c)

    def ell(self, x0, y0, x1, y1, c):
        self.d.ellipse([min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1)], fill=c)

    def poly(self, pts, c):
        self.d.polygon(pts, fill=c)

    def line(self, pts, c, w=1):
        self.d.line(pts, fill=c, width=w)


SHEET = {}
ORDER = []


def add(name, frames):
    if isinstance(frames, Tile):
        frames = [frames.im]
    elif isinstance(frames, Image.Image):
        frames = [frames]
    else:
        frames = [f.im if isinstance(f, Tile) else f for f in frames]
    SHEET[name] = frames
    if name not in ORDER:
        ORDER.append(name)


def anim(fn):
    out = []
    for f in range(FR):
        t = Tile()
        fn(t, f)
        out.append(t.im)
    return out


def static(fn):
    t = Tile()
    fn(t)
    return t


def sw(f, y, amp=1.5, k=0.22):
    """horizontal sway offset for frame f at pixel row y"""
    return round(math.sin(f / FR * math.tau + y * k) * amp)


# ====================================================================== water
def water_detail(seed, rays, sparkle):
    frames = []
    for f in range(FR):
        r = random.Random(seed)
        t = Tile()
        if rays:
            for y in range(T):
                for x in range(T):
                    v = math.sin((x + f * 8) * math.pi / 16.0 + math.sin(y * 0.2) * 1.5)
                    a = max(0.0, v) * rays
                    if a > 1:
                        t.px(x, y, (255, 255, 255, clamp(a)))
        for i in range(sparkle):
            sx, sy = r.randrange(T), r.randrange(T)
            if i % FR == f:
                t.px(sx, sy, (255, 255, 255, 120))
                t.px(sx + 1, sy, (255, 255, 255, 60))
        frames.append(t)
    return frames


add('water_sunlit', water_detail(1, 30, 8))
add('water_twilight', water_detail(2, 12, 4))
add('water_midnight', water_detail(3, 0, 5)[:1])
add('water_abyss', water_detail(4, 0, 5)[:1])
add('water_hadal', water_detail(5, 0, 5)[:1])


# ====================================================================== terrain
def noise_tile(base, var, seed, speck=None, speck_n=0, post=None):
    r = random.Random(seed)
    t = Tile()
    blocks = [[r.uniform(-1, 1) for _ in range(8)] for _ in range(8)]
    for y in range(T):
        for x in range(T):
            b = blocks[(y // 4) % 8][(x // 4) % 8]
            j = r.uniform(-1, 1)
            c = shade(base, 1 + var * (0.65 * b + 0.35 * j))
            t.px(x, y, (c[0], c[1], c[2], 255))
    if speck:
        for _ in range(speck_n):
            t.px(r.randrange(T), r.randrange(T), speck)
    if post:
        post(t, r)
    return t


def top_of(t, col, depth=3, seed=0, drip=None):
    """copy of a terrain tile with a lit / vegetated top edge"""
    r = random.Random(seed)
    o = Tile()
    o.im = t.im.copy()
    o.d = ImageDraw.Draw(o.im)
    for x in range(T):
        h = depth + r.choice([0, 0, 1, -1])
        for y in range(max(h, 1)):
            f = 1.0 - 0.18 * y / max(h, 1)
            o.px(x, y, shade(col, f))
        if drip and r.random() < 0.35:
            o.px(x, h, drip)
            if r.random() < 0.4:
                o.px(x, h + 1, drip)
    return o


def sand_post(t, r):
    for _ in range(5):  # ripple lines
        x, y = r.randrange(T), r.randrange(T)
        for i in range(5):
            t.px(x + i, y + (i // 2), shade(H('#c9a867'), 1.0))


sand = noise_tile(H('#e4c985'), 0.07, 11, H('#b08a4c'), 14, sand_post)
add('sand', sand)  # slot 4 (legacy)
rock = noise_tile(H('#666a7a'), 0.14, 12, H('#3c3f4c'), 10)
add('rock', rock)  # slot 5 (legacy)

# ---- legacy slots 6 / 7 (decor) kept in the old look
def coral_legacy(t):
    for cx, h, col in ((7, 14, '#f0568f'), (16, 22, '#ff9a60'), (25, 16, '#f0568f')):
        t.rect(cx - 1, 31 - h, cx + 1, 31, H(col))
        t.rect(cx - 3, 31 - h + 6, cx + 3, 31 - h + 8, H(col))
        t.rect(cx - 2, 31 - h + 12, cx + 2, 31 - h + 14, H(col))
add('coral', static(coral_legacy))


def kelp_legacy(t):
    for y in range(32):
        x = 16 + round(math.sin(y * 0.4) * 4)
        t.rect(x - 1, y, x + 1, y, H('#2faa5a'))
        if y % 7 == 3:
            t.rect(x + 2, y, x + 6, y, H('#2faa5a'))
        if y % 7 == 6:
            t.rect(x - 6, y, x - 2, y, H('#2faa5a'))
add('kelp', static(kelp_legacy))

# ---- new terrain
add('sand_top', top_of(sand, H('#f4dea0'), 3, 21, H('#d4b673')))
add('rock_top', top_of(rock, H('#8a90a2'), 2, 22, H('#4d6a52')))

reef_rock = noise_tile(H('#b99a86'), 0.13, 13, H('#7d5f52'), 18,
                       lambda t, r: [t.ell(x, y, x + 2, y + 1, H('#6b5044')) for x, y in
                                     [(r.randrange(28), r.randrange(30)) for _ in range(5)]])
add('reef_rock', reef_rock)
add('reef_rock_top', top_of(reef_rock, H('#e3739a'), 3, 23, H('#c25a82')))

basalt = noise_tile(H('#2b3045'), 0.16, 14, H('#171a28'), 14)
add('basalt', basalt)
add('basalt_top', top_of(basalt, H('#4d5778'), 2, 24, None))
add('deep_rock', noise_tile(H('#1d2033'), 0.14, 15, H('#10121f'), 12))
add('bedrock', noise_tile(H('#0f111c'), 0.10, 16, H('#07080f'), 10))

mud = noise_tile(H('#6a5238'), 0.12, 17, H('#44331f'), 16)
add('mud', mud)
add('mud_top', top_of(mud, H('#7f8a4a'), 3, 25, H('#566033')))
swamp_mud = noise_tile(H('#3f3a26'), 0.14, 18, H('#26231a'), 18)
add('swamp_mud', swamp_mud)
add('swamp_top', top_of(swamp_mud, H('#5c7a36'), 4, 26, H('#3e5a26')))

def gravel_post(t, r):
    for _ in range(14):
        x, y = r.randrange(T - 3), r.randrange(T - 3)
        c = shade(H('#8b8f96'), r.uniform(0.7, 1.2))
        t.ell(x, y, x + 3, y + 2, c)
        t.px(x + 1, y, shade(c, 1.2))
gravel = noise_tile(H('#6f737a'), 0.10, 19, None, 0, gravel_post)
add('gravel', gravel)
add('gravel_top', top_of(gravel, H('#a8adb5'), 2, 27, None))


def wood_h(t):
    base = H('#6b4a2a')
    t.rect(0, 0, 31, 31, base)
    r = random.Random(31)
    for y in range(0, 32, 4):
        t.rect(0, y, 31, y, shade(base, 0.75))
    for _ in range(30):
        x, y = r.randrange(T), r.randrange(T)
        t.rect(x, y, min(x + r.randint(3, 9), 31), y, shade(base, r.uniform(0.85, 1.2)))
    t.rect(0, 0, 31, 2, shade(base, 1.25))
    t.rect(0, 29, 31, 31, shade(base, 0.7))
add('wood', static(wood_h))


def wood_end(t):
    wood_h(t)
    t.ell(4, 4, 27, 27, H('#c9a066'))
    for r_ in (10, 6, 3):
        t.d.ellipse([16 - r_, 16 - r_, 16 + r_, 16 + r_], outline=H('#8c6a3e'))
add('wood_end', static(wood_end))


def wood_v(t):
    base = H('#5f4226')
    t.rect(0, 0, 31, 31, base)
    r = random.Random(32)
    for x in range(0, 32, 4):
        t.rect(x, 0, x, 31, shade(base, 0.75))
    for _ in range(30):
        x, y = r.randrange(T), r.randrange(T)
        t.rect(x, y, x, min(y + r.randint(3, 9), 31), shade(base, r.uniform(0.85, 1.2)))
    t.rect(0, 0, 2, 31, shade(base, 1.2))
    t.rect(29, 0, 31, 31, shade(base, 0.7))
add('wood_v', static(wood_v))


def vent_rock(t, f):
    t.im.paste(noise_tile(H('#16141c'), 0.16, 33, H('#0a090e'), 10).im)
    r = random.Random(34)
    for _ in range(9):
        x, y = r.randrange(2, 28), r.randrange(2, 28)
        a = 0.6 + 0.4 * math.sin(f / FR * math.tau + x)
        t.px(x, y, (255, clamp(120 + 100 * a), 30, 255))
        t.px(x + 1, y, (255, clamp(70 + 70 * a), 20, 255))
        t.px(x, y + 1, (200, 60, 20, 255))
add('vent_rock', anim(lambda t, f: vent_rock(t, f)))

dune = noise_tile(H('#f0dfae'), 0.05, 41, H('#d6bf86'), 10)
add('dune_sand', dune)
add('dune_top', top_of(dune, H('#f8ecc4'), 2, 42, None))
dirt = noise_tile(H('#6e4e30'), 0.12, 43, H('#4a331c'), 16)
add('dirt', dirt)


def grass_top_fn(t, r):
    pass
grass = top_of(dirt, H('#4c9a3c'), 5, 44, H('#3a7a2e'))
for x in range(0, 32, 3):
    grass.px(x, 0, H('#7fd05a'))
    grass.px(x + 1, 1, H('#62b445'))
add('grass_top', grass)

# ====================================================================== decor: helpers
def blade(t, x, y0, y1, col, f, amp=2.0, k=0.25):
    for y in range(y1, y0 - 1, -1):
        off = round(math.sin(f / FR * math.tau + y * k) * amp * (y1 - y) / max(y1 - y0, 1))
        t.px(x + off, y, col)

# ----- coast
def seagrass(t, f):
    for x, h in ((6, 10), (10, 14), (14, 9), (19, 13), (23, 11), (27, 8)):
        blade(t, x, 31 - h, 31, H('#3da845'), f, 2.0)
        blade(t, x + 1, 31 - h + 1, 31, H('#5cc860'), f, 2.0)
add('seagrass', anim(seagrass))

def seagrass_base(t, f):
    for x in (7, 12, 17, 22, 26):
        blade(t, x, 0, 31, H('#3da845'), f, 1.5)
        blade(t, x + 1, 2, 31, H('#6fd070'), f, 1.5)
add('seagrass_tall', anim(seagrass_base))

def shell(t):
    t.ell(9, 20, 23, 31, H('#f5d9c4'))
    for i in range(5):
        t.line([(16, 30), (10 + i * 3, 21)], H('#d9a98c'))
    t.rect(13, 28, 18, 31, H('#e8bfa4'))
add('shell', static(shell))

def starfish(t):
    cx, cy = 16, 27
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        rr = 8 if i % 2 == 0 else 3.5
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr * 0.7))
    t.poly(pts, H('#f07a3a'))
    for dx, dy in ((0, -3), (-3, 0), (3, 0), (0, 2)):
        t.px(cx + dx, cy + dy, H('#ffc27a'))
add('starfish', static(starfish))

def urchin(t):
    t.ell(10, 21, 22, 31, H('#3a2a52'))
    for i in range(14):
        a = math.pi + i * math.pi / 13
        t.line([(16 + math.cos(a) * 5, 28 + math.sin(a) * 5), (16 + math.cos(a) * 11, 27 + math.sin(a) * 10)], H('#6a4a8a'))
add('urchin', static(urchin))

def mussels(t):
    r = random.Random(51)
    for _ in range(7):
        x, y = r.randrange(3, 26), r.randrange(23, 29)
        t.ell(x, y, x + 5, y + 4, H('#2e3548'))
        t.px(x + 2, y + 1, H('#5a6688'))
add('mussels', static(mussels))

def driftwood(t):
    t.rect(2, 26, 29, 30, H('#8a6a46'))
    t.rect(2, 26, 29, 27, H('#a88660'))
    t.rect(8, 20, 10, 26, H('#8a6a46'))
    t.rect(22, 22, 24, 26, H('#8a6a46'))
    t.ell(0, 26, 4, 30, H('#d1b280'))
add('driftwood', static(driftwood))

def anemone_pink(t, f):
    t.rect(13, 25, 19, 31, H('#a63a6a'))
    for i in range(9):
        x = 9 + i * 2
        sy = sw(f, 20 + i, 1.5, 0.7)
        t.line([(x, 26), (x + sy, 17 + (i % 3))], H('#ff7ab5'))
        t.px(x + sy, 16 + (i % 3), H('#ffd0e6'))
add('anemone_pink', anim(anemone_pink))

# ----- kelp forest
def kelp_base(t, f):
    t.ell(10, 27, 22, 32, H('#5a4a32'))
    for x0 in (13, 19):
        for y in range(31, -1, -1):
            x = x0 + sw(f, y, 1.8, 0.2) + round(math.sin(y * 0.3 + x0) * 1.5)
            t.rect(x, y, x + 1, y, H('#4a7a2a'))
        for y in range(28, 4, -7):
            x = x0 + sw(f, y, 1.8, 0.2)
            t.rect(x + 2, y, x + 6, y - 1, H('#5aa832'))
add('kelp_base', anim(kelp_base))

def kelp_mid(t, f):
    for x0, col in ((12, '#4a7a2a'), (20, '#3f6e25')):
        for y in range(32):
            x = x0 + sw(f, y, 2.0, 0.2)
            t.rect(x, y, x + 1, y, H(col))
        for y in range(3, 32, 8):
            x = x0 + sw(f, y, 2.0, 0.2)
            t.poly([(x, y), (x + 7 + sw(f, y, 2, .5), y - 2), (x + 8 + sw(f, y, 2, .5), y + 2)], H('#62b83a'))
        for y in range(7, 32, 8):
            x = x0 + sw(f, y, 2.0, 0.2)
            t.poly([(x, y), (x - 7 + sw(f, y, 2, .5), y - 2), (x - 8 + sw(f, y, 2, .5), y + 2)], H('#56a632'))
add('kelp_mid', anim(kelp_mid))

def kelp_top(t, f):
    for x0 in (12, 20):
        for y in range(32, 14, -1):
            x = x0 + sw(f, y, 2.0, 0.2)
            t.rect(x, y, x + 1, y, H('#4a7a2a'))
        for k, dx in enumerate((-8, -4, 0, 4, 8)):
            sx = x0 + sw(f, 14, 2.0, .2)
            t.poly([(sx, 16), (sx + dx + sw(f, k * 3, 2.5, 1), 2 + abs(dx) // 3), (sx + dx + 3 + sw(f, k * 3, 2.5, 1), 4 + abs(dx) // 3)], H('#7ad048'))
add('kelp_top', anim(kelp_top))

def kelp_float(t, f):
    for x in range(0, 32, 5):
        y = 4 + round(math.sin(f / FR * math.tau + x * 0.4) * 1.5)
        t.ell(x, y, x + 8, y + 5, H('#6ab83a'))
        t.line([(x + 1, y + 2), (x + 7, y + 3)], H('#4a8a2a'))
    t.rect(0, 9, 31, 9, (70, 130, 60, 120))
add('kelp_float', anim(kelp_float))

# ----- reef
def coral_brain(t):
    t.ell(5, 14, 27, 33, H('#e8a85a'))
    for y in range(17, 31, 3):
        for x in range(8, 25, 2):
            if (x + y) % 3 != 0:
                t.px(x + ((y // 3) % 2), y, H('#b6702a'))
    t.ell(8, 15, 14, 18, H('#f6cf8a'))
add('coral_brain', static(coral_brain))

def coral_fan(t, f):
    t.rect(15, 24, 17, 31, H('#6a2a8a'))
    for i in range(13):
        a = math.pi + (i + 0.5) * math.pi / 13
        ex = 16 + math.cos(a) * 15 + sw(f, i, 1.2, 0.5)
        ey = 25 + math.sin(a) * 22
        t.line([(16, 25), (ex, ey)], H('#b04fd6'))
    for yy in (10, 15, 20):
        t.line([(16 - yy // 2 - 3, yy + 6), (16 + yy // 2 + 3, yy + 6)], H('#d58af0'))
add('coral_fan', anim(coral_fan))

def coral_stag(t, f):
    def branch(x, y, a, ln, d):
        if d == 0 or ln < 2:
            return
        ex, ey = x + math.cos(a) * ln, y + math.sin(a) * ln
        t.line([(x, y), (ex, ey)], H('#ff7a3a') if d > 1 else H('#ffb36a'), 2 if d > 2 else 1)
        branch(ex, ey, a - 0.5, ln * 0.7, d - 1)
        branch(ex, ey, a + 0.5, ln * 0.7, d - 1)
    branch(16, 31, -math.pi / 2, 9, 4)
    t.px(16, 30, H('#ffd2a0'))
add('coral_stag', static(lambda t: coral_stag(t, 0)))

def coral_table(t):
    t.rect(14, 18, 18, 31, H('#2f8f8a'))
    t.ell(1, 10, 31, 20, H('#39b3a8'))
    t.ell(3, 10, 29, 15, H('#6fe0cc'))
    for x in range(5, 28, 3):
        t.px(x, 16, H('#1f7f78'))
add('coral_table', static(coral_table))

def coral_tube(t, f):
    for x, h in ((7, 12), (12, 19), (17, 15), (22, 22), (26, 10)):
        t.rect(x - 1, 31 - h, x + 1, 31, H('#e8c22a'))
        t.rect(x - 1, 31 - h, x + 1, 31 - h + 1, H('#7a5a12'))
        if f % 2 == 0:
            t.px(x, 31 - h - 1, H('#fff4a0'))
add('coral_tube', anim(coral_tube))

def anemone_mag(t, f):
    t.rect(11, 23, 21, 31, H('#8a1f6a'))
    for i in range(11):
        x = 6 + i * 2
        sy = sw(f, i * 2, 2.0, 0.9)
        t.line([(x, 25), (x + sy, 12 + abs(i - 5))], H('#e83ab0'))
        t.px(x + sy, 11 + abs(i - 5), H('#ffb0e6'))
add('anemone_mag', anim(anemone_mag))

def sponge_barrel(t):
    t.rect(8, 14, 23, 31, H('#e67a3a'))
    t.ell(8, 11, 23, 18, H('#b4552a'))
    t.ell(10, 12, 21, 16, H('#6a2a14'))
    for y in range(18, 31, 3):
        t.px(10, y, H('#b4552a'))
        t.px(15, y + 1, H('#b4552a'))
        t.px(20, y, H('#b4552a'))
add('sponge_barrel', static(sponge_barrel))

def sponge_vase(t):
    t.poly([(12, 31), (20, 31), (26, 8), (6, 8)], H('#8a5ad6'))
    t.ell(6, 5, 26, 12, H('#5a3aa0'))
    t.ell(9, 7, 23, 11, H('#2a1a60'))
    for y in range(14, 30, 4):
        t.line([(11, y), (21, y)], H('#a47ae8'))
add('sponge_vase', static(sponge_vase))

def coral_blue(t, f):
    def branch(x, y, a, ln, d):
        if d == 0:
            return
        ex, ey = x + math.cos(a) * ln, y + math.sin(a) * ln
        t.line([(x, y), (ex, ey)], H('#3a7ae8'), 2 if d > 2 else 1)
        branch(ex, ey, a - 0.6, ln * 0.72, d - 1)
        branch(ex, ey, a + 0.6, ln * 0.72, d - 1)
        if d == 1:
            t.px(ex, ey, H('#a8d4ff'))
    branch(16, 31, -math.pi / 2, 8, 4)
add('coral_blue', static(lambda t: coral_blue(t, 0)))

def coral_pillar_base(t):
    t.poly([(7, 31), (25, 31), (22, 0), (10, 0)], H('#d8567a'))
    r = random.Random(61)
    for _ in range(22):
        t.px(r.randrange(9, 23), r.randrange(0, 31), H('#a8365a'))
    for _ in range(14):
        t.px(r.randrange(9, 23), r.randrange(0, 31), H('#f08aa8'))
add('coral_pillar_base', static(coral_pillar_base))

def coral_pillar_top(t):
    t.poly([(10, 31), (22, 31), (24, 12), (16, 5), (8, 12)], H('#d8567a'))
    for x, y in ((9, 10), (23, 10), (16, 4), (12, 7), (20, 7)):
        t.ell(x - 2, y - 2, x + 2, y + 2, H('#f08aa8'))
    r = random.Random(62)
    for _ in range(14):
        t.px(r.randrange(10, 22), r.randrange(10, 31), H('#a8365a'))
add('coral_pillar_top', static(coral_pillar_top))

def clam(t, f):
    t.ell(3, 20, 28, 33, H('#cfc3a6'))
    t.ell(6, 22, 25, 29, H('#2a8ad6'))
    t.ell(9, 24, 22, 28, H('#5ad0f0'))
    for x in range(4, 28, 3):
        t.line([(x, 31), (x + (x - 16) // 4, 22)], H('#9a8e72'))
    if f % 2 == 0:
        t.px(14, 25, H('#d8f8ff'))
        t.px(18, 26, H('#d8f8ff'))
add('clam', anim(clam))

def coral_glow(t, f):
    a = 0.6 + 0.4 * math.sin(f / FR * math.tau)
    def branch(x, y, ang, ln, d):
        if d == 0:
            return
        ex, ey = x + math.cos(ang) * ln, y + math.sin(ang) * ln
        t.line([(x, y), (ex, ey)], (60, clamp(170 * a + 60), clamp(200 * a + 40), 255), 1)
        branch(ex, ey, ang - 0.55, ln * 0.7, d - 1)
        branch(ex, ey, ang + 0.55, ln * 0.7, d - 1)
        if d == 1:
            t.px(ex, ey, (200, 255, 255, 255))
    branch(16, 31, -math.pi / 2, 8, 4)
add('coral_glow', anim(coral_glow))

# ----- open ocean / deep
def sea_pen(t, f):
    t.rect(15, 20, 16, 31, H('#e8e0d0'))
    for y in range(4, 22, 2):
        w = 7 - abs(13 - y) // 2
        s = sw(f, y, 1.0, 0.4)
        t.line([(16 + s, y), (16 + s - w, y - 2)], H('#f0c6a0'))
        t.line([(16 + s, y), (16 + s + w, y - 2)], H('#f0c6a0'))
add('sea_pen', anim(sea_pen))

def glass_sponge(t):
    t.poly([(12, 31), (20, 31), (25, 6), (7, 6)], (220, 240, 250, 190))
    t.ell(7, 3, 25, 10, (240, 250, 255, 210))
    t.ell(10, 5, 22, 9, (120, 150, 170, 220))
    for y in range(11, 30, 3):
        for x in range(10 + (y % 2), 24, 3):
            t.px(x, y, (255, 255, 255, 230))
add('glass_sponge', static(glass_sponge))

def tube_worm(t, f):
    for x, h in ((8, 14), (13, 22), (18, 17), (23, 24), (27, 11)):
        t.rect(x - 1, 31 - h, x, 31, H('#f0ece4'))
        t.rect(x - 2, 31 - h - 3, x + 1, 31 - h, H('#e83a3a'))
        if f % 2:
            t.px(x - 1, 31 - h - 4, H('#ff9a9a'))
add('tube_worm', anim(tube_worm))

def crinoid(t, f):
    t.rect(15, 18, 16, 31, H('#9a6ad0'))
    for i in range(12):
        a = -math.pi + (i + 0.5) * math.pi / 12 * 1.0
        s = sw(f, i, 1.2, 0.6)
        t.line([(16, 18), (16 + math.cos(a) * 13 + s, 18 + math.sin(a) * 14)], H('#c49af0'))
add('crinoid', anim(crinoid))

def bio_coral(t, f):
    a = 0.5 + 0.5 * math.sin(f / FR * math.tau)
    t.rect(15, 18, 16, 31, (30, 90, 110, 255))
    for x, y in ((8, 12), (16, 6), (24, 12), (12, 16), (20, 16)):
        t.ell(x - 3, y - 3, x + 3, y + 3, (20, clamp(160 + 80 * a), clamp(190 + 60 * a), 255))
        t.px(x, y, (220, 255, 255, 255))
        t.line([(x, y + 3), (16, 22)], (30, 120, 140, 255))
add('bio_coral', anim(bio_coral))

def smoke(t, f):
    for i in range(7):
        y = 31 - ((i * 5 + f * 3) % 32)
        w = 2 + (31 - y) // 6
        a = clamp(190 - (31 - y) * 5)
        t.ell(16 - w + sw(f, y, 1.5, 0.3), y - w, 16 + w + sw(f, y, 1.5, 0.3), y + w, (30, 28, 34, a))
add('smoke', anim(smoke))

def bubbles(t, f):
    for i, x in enumerate((9, 15, 21, 12, 19)):
        y = 31 - ((i * 7 + f * 8) % 34)
        t.d.ellipse([x - 1, y - 1, x + 1 + (i % 2), y + 1 + (i % 2)], outline=(230, 250, 255, 220))
        t.px(x - 1, y - 1, (255, 255, 255, 255))
add('bubbles', anim(bubbles))

def whale_rib(t):
    for i in range(4):
        x = 5 + i * 7
        t.line([(x, 31), (x + 3, 14), (x + 8, 5)], H('#d9d2bc'), 2)
add('whale_rib', static(whale_rib))

def nodules(t):
    r = random.Random(71)
    for _ in range(6):
        x, y = r.randrange(2, 26), r.randrange(24, 29)
        t.ell(x, y, x + 5, y + 4, H('#2a2530'))
        t.px(x + 1, y + 1, H('#5a4f66'))
add('nodules', static(nodules))

# ----- river
def reed_base(t, f):
    for x in (7, 12, 17, 22, 26):
        for y in range(32):
            xx = x + sw(f, y, 1.2, 0.15) + (y // 16) * ((x % 3) - 1)
            t.px(xx, y, H('#6aa83a'))
            t.px(xx + 1, y, H('#4e8a2c'))
add('reed_base', anim(reed_base))

def reed_top(t, f):
    for x in (9, 15, 22):
        for y in range(32):
            xx = x + sw(f, y - 14, 1.6, 0.18)
            t.px(xx, y, H('#6aa83a'))
    for x, top in ((9, 8), (15, 4), (22, 10)):
        xx = x + sw(f, top - 14, 1.6, 0.18)
        t.rect(xx - 1, top, xx + 1, top + 6, H('#7a4a22'))
        t.px(xx, top - 1, H('#9a6a3a'))
add('reed_top', anim(reed_top))

def water_plant(t, f):
    for x in (9, 15, 21):
        for y in range(8, 32):
            xx = x + sw(f, y, 2.0, 0.25)
            t.px(xx, y, H('#4aa05a'))
            if y % 5 == 0:
                t.line([(xx, y), (xx + 4 + sw(f, y, 1, 1), y - 2)], H('#6ac07a'))
                t.line([(xx, y), (xx - 4 + sw(f, y, 1, 1), y - 2)], H('#6ac07a'))
add('water_plant', anim(water_plant))

def lily(t, f):
    y = 5 + round(math.sin(f / FR * math.tau))
    for x0 in (2, 18):
        t.ell(x0, y, x0 + 11, y + 4, H('#3e9a3a'))
        t.line([(x0 + 5, y + 2), (x0 + 11, y + 1)], H('#2a6a2a'))
    t.ell(11, y - 2, 15, y + 1, H('#f4a8d6'))
    t.px(13, y - 2, H('#fff0a0'))
add('lily_pad', anim(lily))

def river_stone(t):
    t.ell(3, 17, 18, 31, H('#7d828c'))
    t.ell(13, 21, 29, 32, H('#6a6f78'))
    t.ell(6, 19, 11, 23, H('#a5aab4'))
add('river_stone', static(river_stone))

def hyacinth(t, f):
    y = 6 + round(math.sin(f / FR * math.tau + 1))
    t.ell(4, y + 2, 26, y + 6, H('#5ab04a'))
    t.rect(14, y - 4, 16, y + 2, H('#b88af0'))
    t.rect(12, y - 2, 18, y - 1, H('#d4b0ff'))
add('hyacinth', anim(hyacinth))

# ----- swamp
def root_arch(t, f):
    base = H('#5a3f24')
    for x0, lean in ((4, 1), (26, -1)):
        for y in range(31, 0, -1):
            x = x0 + lean * (31 - y) // 3
            t.rect(x - 1, y, x + 1, y, base)
    t.rect(10, 1, 22, 4, base)
    for x in (9, 12, 19, 22):
        t.px(x, 4, H('#7a5a38'))
add('root_arch', anim(lambda t, f: root_arch(t, f))[:1])

def root_stem(t):
    r = random.Random(81)
    x = 14
    for y in range(32):
        x += r.choice([-1, 0, 0, 0, 1]) if 6 < x < 24 else (1 if x <= 6 else -1)
        t.rect(x, y, x + 3, y, H('#5a3f24'))
        t.px(x, y, H('#7a5a38'))
        if r.random() < 0.12:
            t.line([(x + 3, y), (x + 8, y - 4)], H('#5a3f24'))
add('root_stem', static(root_stem))

def root_hang(t, f):
    for x0 in (8, 16, 24):
        for y in range(32):
            x = x0 + sw(f, y, 1.5, 0.15)
            t.rect(x, y, x + 1, y, H('#5a3f24'))
            t.px(x, y, H('#7a5a38'))
add('root_hang', anim(root_hang))

def root_hang_end(t, f):
    for x0 in (8, 16, 24):
        for y in range(0, 20):
            x = x0 + sw(f, y, 1.5, 0.15)
            t.rect(x, y, x + 1, y, H('#5a3f24'))
        t.px(x0 + sw(f, 20, 1.5, 0.15), 20, H('#7a5a38'))
        t.px(x0 + sw(f, 21, 1.5, 0.15), 21, H('#9a7a54'))
add('root_hang_end', anim(root_hang_end))

def swamp_grass(t, f):
    for x, h in ((5, 12), (9, 18), (14, 14), (19, 20), (23, 13), (27, 16)):
        blade(t, x, 31 - h, 31, H('#4f7a2a'), f, 2.0)
        blade(t, x + 1, 31 - h + 2, 31, H('#6a9a3a'), f, 2.0)
add('swamp_grass', anim(swamp_grass))

def cypress_knee(t):
    t.poly([(8, 31), (24, 31), (19, 14), (16, 6), (13, 14)], H('#6a4a2e'))
    t.poly([(13, 31), (18, 31), (16, 10)], H('#7a5a3a'))
    t.px(16, 5, H('#8a6a46'))
add('cypress_knee', static(cypress_knee))

def moss_hang(t, f):
    for x0 in (6, 12, 18, 24):
        ln = 12 + (x0 * 7) % 15
        for y in range(ln):
            x = x0 + sw(f, y, 1.8, 0.3)
            t.px(x, y, H('#8aa86a'))
            if y % 3 == 0:
                t.px(x + 1, y, H('#a6c286'))
add('moss_hang', anim(moss_hang))

def methane(t, f):
    for i, x in enumerate((8, 14, 20, 25, 11)):
        y = 31 - ((i * 6 + f * 9) % 34)
        t.d.ellipse([x - 2, y - 2, x + 2, y + 2], outline=(200, 230, 150, 200))
        t.px(x - 1, y - 1, (240, 255, 200, 255))
add('methane', anim(methane))

def scum(t, f):
    r = random.Random(91)
    for _ in range(26):
        x, y = r.randrange(32), 2 + r.randrange(6)
        s = round(math.sin(f / FR * math.tau + x) * 0.6)
        t.px(x + s, y, (100, 150, 50, 235))
        t.px(x + 1 + s, y, (130, 180, 70, 200))
add('algae_scum', anim(scum))

def swamp_mushroom(t):
    t.rect(14, 22, 17, 31, H('#d8c8a0'))
    t.ell(8, 14, 24, 25, H('#a8402e'))
    for x, y in ((12, 18), (16, 16), (20, 19)):
        t.px(x, y, H('#f0e8d0'))
add('swamp_mushroom', static(swamp_mushroom))

# ====================================================================== write out
LEGACY = ['water_sunlit', 'water_twilight', 'water_midnight', 'water_abyss', 'sand', 'rock', 'coral', 'kelp']
names = LEGACY + [n for n in ORDER if n not in LEGACY]
W = len(names) * T
sheet = Image.new('RGBA', (W, T * FR), (0, 0, 0, 0))
for i, n in enumerate(names):
    for k, fr in enumerate(SHEET[n]):
        sheet.paste(fr, (i * T, k * T))
sheet.save(f"{OUT}/world_tileset.png")

lines = ['[gd_resource type="TileSet" load_steps=3 format=3]', '',
         '[ext_resource type="Texture2D" path="res://assets/tiles/world_tileset.png" id="1_tex"]', '',
         '[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_1"]', 'texture = ExtResource("1_tex")',
         'texture_region_size = Vector2i(32, 32)']
for i in range(len(names)):
    lines.append(f'{i}:0/0 = 0')
lines += ['', '[resource]', 'tile_size = Vector2i(32, 32)', 'sources/0 = SubResource("TileSetAtlasSource_1")', '']
open(f"{OUT}/world_tileset.tres", 'w').write('\n'.join(lines))

with open(f"{OUT}/tile_ids.txt", 'w') as fh:
    for i, n in enumerate(names):
        fh.write(f"{n} {i}\n")
print(len(names), 'tiles ->', W, 'x', T * FR)
