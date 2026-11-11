@tool
class_name WorldGenerator
extends Node2D
## Owns the three tilemap layers (Background, Decor, Terrain), the sky and the regions.
##
## The world is a long side-view slice of ocean, west to east:
##   Sunny Coast -> Kelp Forest -> Coral Reef -> Open Ocean (shelf wall, abyssal plain,
##   trench, seamounts, vents) -> River Mouth & River -> Mangrove Swamp
## Each region has its own sea floor, materials, decor, water colour, creatures (see the
## `habitats` field in data/creatures.json) and fog / current (REGIONS below).
##
## - Paint the layers by hand in the editor, or tick "Bake Default World" to generate the
##   default world and then edit it.
## - At runtime, if every layer is empty a default world is generated automatically.
## - ANY non-empty Terrain tile is solid for the player. World size = used Background rect.
## - `bedrock_rows` (filled by the generator) marks where the generated rock ends: everything
##   below is solid but not stored as tiles, which keeps the huge world cheap.
##
## Tileset atlas (assets/tiles/world_tileset.png, tools/make_tiles.py): see TL below.
## ANIMATED TILES: make the PNG taller. Row 0 is the normal tile, every row below it is the
## next animation frame of the tile ABOVE it (same column). A tile animates automatically
## when the cell under it is not empty; leave the cells under a tile blank to keep it still.

const TILE := 32
const LAND_ROWS := 12          # rows above the waterline that may hold land (islands, beach)
const REF_W := 800.0           # the layout below is authored for 800 x 380 tiles and scaled
const REF_H := 380.0
const BLEND := 22.0            # tiles over which neighbouring regions blend
const GRAD_CELL := 4           # water colour texture resolution (tiles per texel)
const BEDROCK_COL := Color("#0f111c")

## tile name -> index along the tileset row
const TL := {
	"water_sunlit": 0, "water_twilight": 1, "water_midnight": 2, "water_abyss": 3, "sand": 4, "rock": 5,
	"coral": 6, "kelp": 7, "water_hadal": 8, "sand_top": 9, "rock_top": 10, "reef_rock": 11,
	"reef_rock_top": 12, "basalt": 13, "basalt_top": 14, "deep_rock": 15, "bedrock": 16, "mud": 17,
	"mud_top": 18, "swamp_mud": 19, "swamp_top": 20, "gravel": 21, "gravel_top": 22, "wood": 23,
	"wood_end": 24, "wood_v": 25, "vent_rock": 26, "dune_sand": 27, "dune_top": 28, "dirt": 29,
	"grass_top": 30, "seagrass": 31, "seagrass_tall": 32, "shell": 33, "starfish": 34, "urchin": 35,
	"mussels": 36, "driftwood": 37, "anemone_pink": 38, "kelp_base": 39, "kelp_mid": 40, "kelp_top": 41,
	"kelp_float": 42, "coral_brain": 43, "coral_fan": 44, "coral_stag": 45, "coral_table": 46,
	"coral_tube": 47, "anemone_mag": 48, "sponge_barrel": 49, "sponge_vase": 50, "coral_blue": 51,
	"coral_pillar_base": 52, "coral_pillar_top": 53, "clam": 54, "coral_glow": 55, "sea_pen": 56,
	"glass_sponge": 57, "tube_worm": 58, "crinoid": 59, "bio_coral": 60, "smoke": 61, "bubbles": 62,
	"whale_rib": 63, "nodules": 64, "reed_base": 65, "reed_top": 66, "water_plant": 67, "lily_pad": 68,
	"river_stone": 69, "hyacinth": 70, "root_arch": 71, "root_stem": 72, "root_hang": 73,
	"root_hang_end": 74, "swamp_grass": 75, "cypress_knee": 76, "moss_hang": 77, "methane": 78,
	"algae_scum": 79, "swamp_mushroom": 80,
}

## decor tiles that count as algae food (only the top tile of a stack does)
const ALGAE_NAMES := ["seagrass", "seagrass_tall", "kelp", "kelp_base", "kelp_mid", "kelp_top", "coral",
	"coral_brain", "coral_fan", "coral_stag", "coral_table", "coral_tube", "coral_blue",
	"coral_pillar_top", "water_plant", "swamp_grass", "reed_top"]

## water overlay tile for each depth zone (see biome_rows)
const WATER_TILES := [0, 1, 2, 3, 8]

## Regions, west to east. x0/x1 are fractions of the world width.
## fog = extra murkiness near the surface (0..1), vis = light radius multiplier,
## current = sideways water flow in px/s (negative = flows west), current_depth = px where it dies out.
const REGIONS := [
	{"id": "coast", "name": "Sunny Coast", "x0": 0.0, "x1": 0.0875, "tint": "#ffe08a",
		"fog": 0.0, "fog_tint": "#00060f", "vis": 1.0, "current": 0.0, "current_depth": 1.0},
	{"id": "kelp", "name": "Kelp Forest", "x0": 0.0875, "x1": 0.2125, "tint": "#7fe08a",
		"fog": 0.10, "fog_tint": "#001208", "vis": 0.95, "current": 0.0, "current_depth": 1.0},
	{"id": "reef", "name": "Coral Reef", "x0": 0.2125, "x1": 0.375, "tint": "#ff8fc0",
		"fog": 0.0, "fog_tint": "#00060f", "vis": 1.0, "current": 0.0, "current_depth": 1.0},
	{"id": "ocean", "name": "Open Ocean", "x0": 0.375, "x1": 0.70, "tint": "#6fb6ff",
		"fog": 0.0, "fog_tint": "#00020a", "vis": 1.0, "current": 0.0, "current_depth": 1.0},
	{"id": "river", "name": "River Mouth & River", "x0": 0.70, "x1": 0.85, "tint": "#c9c27a",
		"fog": 0.30, "fog_tint": "#1a1604", "vis": 0.85, "current": -75.0, "current_depth": 1300.0},
	{"id": "swamp", "name": "Mangrove Swamp", "x0": 0.85, "x1": 1.0, "tint": "#9bd06a",
		"fog": 0.45, "fog_tint": "#0a1404", "vis": 0.7, "current": -14.0, "current_depth": 900.0},
]

## Sea floor profile: [tile x, floor row] for an 800 x 380 world. Eased between points,
## so every point becomes a little terrace (the reef wall is a staircase of ledges).
const PROFILE := [
	[0.0, -7.0], [20.0, -4.0], [38.0, 2.0], [70.0, 22.0], [110.0, 33.0], [170.0, 40.0], [200.0, 45.0],
	[290.0, 52.0], [312.0, 66.0], [345.0, 190.0], [375.0, 300.0], [405.0, 342.0], [440.0, 372.0],
	[480.0, 346.0], [525.0, 336.0], [550.0, 298.0], [572.0, 115.0], [590.0, 52.0], [625.0, 40.0],
	[680.0, 30.0], [725.0, 20.0], [770.0, 12.0], [790.0, 3.0], [799.0, -5.0],
]

## Water colour by depth in px for each region: [depth, colour]. Below 2600 px every region
## uses the open-ocean palette.
const PALETTES := [
	[[0, "#62e6dc"], [300, "#33b9d2"], [900, "#2080b6"], [2600, "#0c2f62"]],
	[[0, "#4fc9a6"], [400, "#2d9ca2"], [1200, "#1b6b8a"], [2600, "#0c2f62"]],
	[[0, "#3ad6f2"], [500, "#2aaae0"], [1400, "#1c70ba"], [2600, "#0c2f62"]],
	[[0, "#33a0e6"], [700, "#1f6fc4"], [1600, "#144c96"], [2600, "#0c2f62"], [5000, "#070f33"],
		[8200, "#04061a"], [12000, "#02020a"]],
	[[0, "#a4b063"], [300, "#74904f"], [900, "#4a623d"], [2600, "#0c2f62"]],
	[[0, "#86a14a"], [300, "#587239"], [900, "#35492b"], [2600, "#0c2f62"]],
]

@export var width_tiles := 800
@export var height_tiles := 380
@export var world_seed := 1337
## Row where each water overlay tile begins (sunlit, twilight, midnight, abyss, hadal).
## Keep roughly in sync with data/biomes.json depths / 32.
@export var biome_rows := PackedInt32Array([0, 28, 81, 156, 256])
@export var generate_if_empty := true
## Animation speed of animated tiles (frames per second).
@export var tile_animation_fps := 3.0
@export var sky_height := 1000
## Per column: first row that is solid "bedrock" (filled by the generator; leave empty for hand painted worlds).
@export var bedrock_rows := PackedInt32Array()
@export var bake_default_world := false:
	set(v):
		bake_default_world = false
		if v and Engine.is_editor_hint() and is_inside_tree():
			generate()
			_redraw_all()

var _floor_cache := {}
var _land_cache := {}
var _ws := Vector2i.ZERO
var _col_w: Array = []
var _pal: Array = []
var _grad_tex: ImageTexture = null
var _back: Node2D = null
var _mid: Node2D = null
var _algae_ids := {}


## Draws one layer of scenery for the world (back = sky + water colour, mid = trees & piers).
class Painter extends Node2D:
	var gen: Node
	var mode := "back"

	func _draw() -> void:
		if gen != null:
			gen.paint(self, mode)


func _ready() -> void:
	_make_painters()
	queue_redraw()


func _make_painters() -> void:
	if _back != null:
		return
	_back = Painter.new()
	_back.gen = self
	_back.mode = "back"
	_back.z_index = -20
	_back.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_back, false, Node.INTERNAL_MODE_FRONT)
	_mid = Painter.new()
	_mid.gen = self
	_mid.mode = "mid"
	_mid.z_index = -2
	add_child(_mid, false, Node.INTERNAL_MODE_FRONT)


func _redraw_all() -> void:
	_grad_tex = null
	queue_redraw()
	if _back != null:
		_back.queue_redraw()
	if _mid != null:
		_mid.queue_redraw()


func _layer(layer_name: String) -> TileMapLayer:
	return get_node_or_null(layer_name) as TileMapLayer


func ensure_generated() -> void:
	_floor_cache.clear()
	_land_cache.clear()
	_ws = Vector2i.ZERO
	_make_painters()
	_setup_tile_animation()
	var bg := _layer("Background")
	var decor := _layer("Decor")
	var terrain := _layer("Terrain")
	if generate_if_empty and bg != null and terrain != null and decor != null:
		if bg.get_used_cells().is_empty() and terrain.get_used_cells().is_empty() and decor.get_used_cells().is_empty():
			generate()
	_redraw_all()


## Turns extra PNG rows under a tile into a native TileSet animation (runtime only, so the
## .tres on disk is never rewritten).
func _setup_tile_animation() -> void:
	if Engine.is_editor_hint():
		return
	var layer := _layer("Background")
	if layer == null or layer.tile_set == null:
		return
	var ts := layer.tile_set
	for i in ts.get_source_count():
		var src := ts.get_source(ts.get_source_id(i)) as TileSetAtlasSource
		if src != null and src.texture != null:
			_animate_source(src)


func _animate_source(src: TileSetAtlasSource) -> void:
	var img := src.texture.get_image()
	if img == null:
		return
	if img.is_compressed():
		img.decompress()
	var rs := src.texture_region_size
	var rows := img.get_height() / rs.y
	if rows < 2:
		return
	var frame_time := 1.0 / maxf(tile_animation_fps, 0.1)
	for ti in src.get_tiles_count():
		var coords := src.get_tile_id(ti)
		var frames := 1
		while frames < 16 and coords.y + frames < rows:
			var cell := Vector2i(coords.x, coords.y + frames)
			if src.get_tile_at_coords(cell) != Vector2i(-1, -1):
				break
			var part := img.get_region(Rect2i(cell.x * rs.x, cell.y * rs.y, rs.x, rs.y))
			if part.is_invisible():
				break
			frames += 1
		if frames < 2:
			continue
		src.set_tile_animation_columns(coords, 1)
		src.set_tile_animation_frames_count(coords, frames)
		src.set_tile_animation_speed(coords, 1.0)
		for k in frames:
			src.set_tile_animation_frame_duration(coords, k, frame_time)


func world_size_tiles() -> Vector2i:
	if _ws != Vector2i.ZERO and not Engine.is_editor_hint():
		return _ws
	var bg := _layer("Background")
	if bg != null:
		var r := bg.get_used_rect()
		if r.size != Vector2i.ZERO:
			_ws = Vector2i(r.end.x, r.end.y)
			return _ws
	return Vector2i(width_tiles, height_tiles)


# ------------------------------------------------------------------ regions & queries
func region_index_at(px: float) -> int:
	var w := float(world_size_tiles().x * TILE)
	var f := clampf(px / maxf(w, 1.0), 0.0, 0.99999)
	for i in REGIONS.size():
		if f < float(REGIONS[i]["x1"]):
			return i
	return REGIONS.size() - 1


func region_at(px: float) -> Dictionary:
	return REGIONS[region_index_at(px)]


func region_id_at(px: float) -> String:
	return str(REGIONS[region_index_at(px)]["id"])


func region_center_x(id: String) -> float:
	var w := float(world_size_tiles().x * TILE)
	for r in REGIONS:
		if str(r["id"]) == id:
			return (float(r["x0"]) + float(r["x1"])) * 0.5 * w
	return w * 0.5


## Water flow at a world position (rivers push you toward the sea).
func current_at(p: Vector2) -> Vector2:
	var r: Dictionary = REGIONS[region_index_at(p.x)]
	var s := float(r["current"])
	if s == 0.0 or p.y < 0.0:
		return Vector2.ZERO
	var depth_f := clampf(1.0 - p.y / float(r["current_depth"]), 0.0, 1.0)
	var w := float(world_size_tiles().x * TILE)
	var edge := clampf(minf(p.x - float(r["x0"]) * w, float(r["x1"]) * w - p.x) / 700.0, 0.0, 1.0)
	return Vector2(s * depth_f * edge, 0.0)


## Pixel Y of the top of the first solid terrain tile in the column under px.
func floor_y_at(px: float) -> float:
	var col := int(floor(px / TILE))
	if _floor_cache.has(col):
		return _floor_cache[col]
	var terrain := _layer("Terrain")
	var ws := world_size_tiles()
	var result := float(ws.y * TILE)
	if terrain != null:
		for y in ws.y:
			if terrain.get_cell_source_id(Vector2i(col, y)) != -1:
				result = float(y * TILE)
				break
	_floor_cache[col] = result
	return result


## True below the generated rock (solid, but not stored as tiles).
func below_bedrock(px: float, py: float) -> bool:
	if bedrock_rows.is_empty():
		return false
	var col := clampi(int(floor(px / TILE)), 0, bedrock_rows.size() - 1)
	return py >= float(bedrock_rows[col] * TILE)


func _land_top_row(col: int) -> int:
	if _land_cache.has(col):
		return _land_cache[col]
	var terrain := _layer("Terrain")
	var res := 0
	if terrain != null:
		for y in range(-LAND_ROWS, 1):
			if terrain.get_cell_source_id(Vector2i(col, y)) != -1:
				res = y
				break
	_land_cache[col] = res
	return res


func _ids_of(names: Array) -> Dictionary:
	var d := {}
	for n in names:
		d[int(TL[n])] = true
	return d


## World positions of food-bearing decor (seagrass, kelp tops, corals...). One per plant.
func algae_positions() -> PackedVector2Array:
	var out := PackedVector2Array()
	var decor := _layer("Decor")
	if decor == null:
		return out
	if _algae_ids.is_empty():
		_algae_ids = _ids_of(ALGAE_NAMES)
	for cell in decor.get_used_cells():
		if cell.y < 1:
			continue
		var a := decor.get_cell_atlas_coords(cell)
		if not _algae_ids.has(a.x):
			continue
		var above := cell + Vector2i(0, -1)
		if decor.get_cell_source_id(above) != -1 and _algae_ids.has(decor.get_cell_atlas_coords(above).x):
			continue
		out.append(decor.to_global(decor.map_to_local(cell)))
	return out


# ------------------------------------------------------------------ region maths
func _region_weights(xt: float, wt: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var sum := 0.0
	var b := BLEND * float(wt) / REF_W
	for r in REGIONS:
		var x0 := float(r["x0"]) * float(wt)
		var x1 := float(r["x1"]) * float(wt)
		var v := smoothstep(x0 - b, x0 + b, xt) * (1.0 - smoothstep(x1 - b, x1 + b, xt))
		out.append(v)
		sum += v
	if sum < 0.0001:
		out[0] = 1.0
		sum = 1.0
	for i in out.size():
		out[i] = out[i] / sum
	return out


func _pick_by_weight(w: PackedFloat32Array, roll: float) -> int:
	var acc := 0.0
	for i in w.size():
		acc += w[i]
		if roll <= acc:
			return i
	return w.size() - 1


func _profile(xt: float) -> float:
	var n := PROFILE.size()
	if xt <= float(PROFILE[0][0]):
		return float(PROFILE[0][1])
	for i in range(1, n):
		var x1 := float(PROFILE[i][0])
		if xt <= x1:
			var x0 := float(PROFILE[i - 1][0])
			var t := (xt - x0) / maxf(x1 - x0, 0.001)
			var e := lerpf(t, t * t * (3.0 - 2.0 * t), 0.65)
			return lerpf(float(PROFILE[i - 1][1]), float(PROFILE[i][1]), e)
	return float(PROFILE[n - 1][1])


func _water_tile(row: int) -> int:
	var idx := 0
	for i in biome_rows.size():
		if row >= biome_rows[i]:
			idx = i
	return int(WATER_TILES[mini(idx, WATER_TILES.size() - 1)])


func _ensure_pal() -> void:
	if not _pal.is_empty():
		return
	for p in PALETTES:
		var stops: Array = []
		for s in p:
			stops.append([float(s[0]), Color(str(s[1]))])
		_pal.append(stops)


func _pal_color(i: int, depth: float) -> Color:
	var stops: Array = _pal[i]
	if depth >= 2600.0:
		stops = _pal[3]
	if depth <= float(stops[0][0]):
		return stops[0][1]
	for k in range(1, stops.size()):
		var d1 := float(stops[k][0])
		if depth <= d1:
			var d0 := float(stops[k - 1][0])
			return (stops[k - 1][1] as Color).lerp(stops[k][1], (depth - d0) / maxf(d1 - d0, 0.001))
	return stops[stops.size() - 1][1]


func _water_color(w: PackedFloat32Array, depth: float) -> Color:
	var c := Color(0, 0, 0, 1)
	for i in w.size():
		if w[i] > 0.001:
			var pc := _pal_color(i, depth)
			c.r += pc.r * w[i]
			c.g += pc.g * w[i]
			c.b += pc.b * w[i]
	return c


# ------------------------------------------------------------------ generation
func _set_tile(layer: TileMapLayer, x: int, y: int, tile: int) -> void:
	layer.set_cell(Vector2i(x, y), 0, Vector2i(tile, 0))


func _mound(floors: PackedInt32Array, over: Dictionary, cx: int, hw: int, h: int, min_row: int, mat: int, rng: RandomNumberGenerator) -> void:
	for x in range(maxi(cx - hw, 1), mini(cx + hw + 1, floors.size() - 1)):
		var dx := float(x - cx) / float(maxi(hw, 1))
		var k := 1.0 - dx * dx
		if k <= 0.0:
			continue
		var rise := int(round(float(h) * k)) + rng.randi_range(-1, 0)
		var new_row := maxi(floors[x] - rise, min_row)
		if new_row < floors[x]:
			if mat != -1:
				for y in range(new_row, floors[x]):
					if mat == -2:
						over[Vector2i(x, y)] = TL["dune_top"] if y == new_row and y < 2 else (TL["dune_sand"] if y < 2 else TL["sand"])
					else:
						over[Vector2i(x, y)] = mat
			floors[x] = new_row


func _material(reg: int, e: int, top: bool, y: int, patch: float, fl: int) -> int:
	if y < 2 and fl < 3:  # land above the waterline
		match reg:
			0, 2:
				return TL["dune_top"] if top else TL["dune_sand"]
			4, 5:
				return TL["swamp_top"] if top else TL["swamp_mud"]
			_:
				return TL["rock_top"] if top else TL["rock"]
	if e >= 14:
		return TL["bedrock"]
	if e >= 9:
		return TL["deep_rock"]
	match reg:
		0:
			if e < 6:
				return TL["sand_top"] if top else TL["sand"]
			return TL["rock"]
		1:
			if patch > 0.25 and e < 5:
				return TL["sand_top"] if top else TL["sand"]
			if e < 5:
				return TL["rock_top"] if top else TL["rock"]
			return TL["basalt"]
		2:
			if patch > 0.38 and e < 4:
				return TL["sand_top"] if top else TL["sand"]
			if e < 6:
				return TL["reef_rock_top"] if top else TL["reef_rock"]
			return TL["rock"]
		3:
			if fl < 110:
				if e < 5:
					return TL["sand_top"] if top else TL["sand"]
				return TL["rock"]
			if fl < 230:
				if e < 5:
					return TL["rock_top"] if top else TL["rock"]
				return TL["basalt"]
			if e < 5:
				return TL["basalt_top"] if top else TL["basalt"]
			return TL["deep_rock"]
		4:
			if patch > 0.1 and e < 5:
				return TL["gravel_top"] if top else TL["gravel"]
			if e < 5:
				return TL["mud_top"] if top else TL["mud"]
			return TL["swamp_mud"]
		_:
			if patch > 0.3 and e < 5:
				return TL["mud_top"] if top else TL["mud"]
			if e < 6:
				return TL["swamp_top"] if top else TL["swamp_mud"]
			return TL["swamp_mud"]
	return TL["rock"]


func generate() -> void:
	var bg := _layer("Background")
	var decor := _layer("Decor")
	var terrain := _layer("Terrain")
	if bg == null or decor == null or terrain == null:
		push_warning("WorldGenerator needs child TileMapLayers named Background, Decor and Terrain.")
		return
	bg.clear()
	decor.clear()
	terrain.clear()
	_floor_cache.clear()
	_land_cache.clear()
	_ws = Vector2i.ZERO
	_grad_tex = null
	var ww := width_tiles
	var hh := height_tiles
	var sx := float(ww) / REF_W
	var sy := float(hh) / REF_H
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	var n_low := FastNoiseLite.new()
	n_low.seed = world_seed
	n_low.frequency = 0.012
	var n_mid := FastNoiseLite.new()
	n_mid.seed = world_seed + 1
	n_mid.frequency = 0.045
	var n_high := FastNoiseLite.new()
	n_high.seed = world_seed + 2
	n_high.frequency = 0.14
	var n_patch := FastNoiseLite.new()
	n_patch.seed = world_seed + 3
	n_patch.frequency = 0.03

	# soft region membership per column (drives noise, materials and decor)
	_col_w = []
	var col_reg := PackedInt32Array()
	col_reg.resize(ww)
	for x in ww:
		var w := _region_weights(float(x), ww)
		_col_w.append(w)
		col_reg[x] = _pick_by_weight(w, rng.randf())

	# ---- sea floor heights (row of the first solid tile per column)
	var floors := PackedInt32Array()
	floors.resize(ww)
	for x in ww:
		var xt := float(x) / sx
		var base := _profile(xt) * sy
		var w: PackedFloat32Array = _col_w[x]
		var a := float(x)
		var nl := n_low.get_noise_1d(a)
		var nm := n_mid.get_noise_1d(a + 500.0)
		var nh := n_high.get_noise_1d(a + 900.0)
		var deep := clampf((base - 70.0 * sy) / (150.0 * sy), 0.0, 1.0)
		var add := 0.0
		add += w[0] * (nh * 1.0)
		add += w[1] * (nm * 4.0 + nh * 1.5)
		add += w[2] * (sin(a * TAU / 15.0) * 2.0 + sin(a * TAU / 6.3 + 1.0) * 0.8 + nm * 2.0)
		add += w[3] * (nl * 16.0 * deep + nm * 3.0 * deep + nh * 1.0)
		add += w[4] * (nm * 2.0 + nh * 1.0)
		add += w[5] * (nm * 1.5 + nh * 0.8)
		# river: the main channel is deeper in the middle
		var rc := float(REGIONS[4]["x0"]) * float(ww)
		var rw := (float(REGIONS[4]["x1"]) - float(REGIONS[4]["x0"])) * float(ww)
		if a > rc and a < rc + rw:
			add += sin((a - rc) / rw * PI) * 6.0 * sy
		floors[x] = clampi(int(round(base + add)), -LAND_ROWS + 2, hh - 6)

	# ---- landforms (mounds raise the floor; `over` remembers special materials)
	var over := {}
	var fx := func(v: float) -> int: return int(round(v * sx))
	# coast: two sea stacks
	_mound(floors, over, fx.call(52.0), 3, 24, -6, TL["rock"], rng)
	_mound(floors, over, fx.call(61.0), 2, 18, -4, TL["rock"], rng)
	# kelp forest: rocky outcrops and two rock islets
	for i in 5:
		_mound(floors, over, fx.call(rng.randf_range(80.0, 165.0)), rng.randi_range(4, 8), rng.randi_range(7, 13), 8, -1, rng)
	_mound(floors, over, fx.call(104.0), 4, 48, -5, TL["rock"], rng)
	_mound(floors, over, fx.call(146.0), 3, 44, -4, TL["rock"], rng)
	# reef: coral bommies (some become arches) and two sandy cays
	var bommies: Array = []
	for i in 14:
		var cx: int = fx.call(rng.randf_range(176.0, 296.0))
		var hw := rng.randi_range(3, 7)
		var hgt := rng.randi_range(6, 13)
		bommies.append([cx, hw, hgt, floors[clampi(cx, 0, ww - 1)]])
		_mound(floors, over, cx, hw, hgt, 6, -1, rng)
	_mound(floors, over, fx.call(238.0), 9, 52, -3, -2, rng)
	_mound(floors, over, fx.call(272.0), 7, 50, -2, -2, rng)
	# open ocean: seamounts and hydrothermal vent cones
	for i in 7:
		var smx: int = fx.call(rng.randf_range(352.0, 540.0))
		var f0 := floors[clampi(smx, 0, ww - 1)]
		_mound(floors, over, smx, rng.randi_range(12, 26), rng.randi_range(40, 130), 22, TL["basalt"] if f0 > 200 else -1, rng)
	var vents: Array = []
	for vx in [396.0, 412.0, 486.0, 503.0, 452.0]:
		var vcx: int = fx.call(vx)
		_mound(floors, over, vcx, 3, 7, 22, TL["vent_rock"], rng)
		vents.append(vcx)
	# river: sandbars at the mouth and boulders in the channel
	for bx in [598.0, 612.0, 628.0]:
		_mound(floors, over, fx.call(bx), rng.randi_range(5, 8), rng.randi_range(10, 15), 5, -1, rng)
	for i in 6:
		_mound(floors, over, fx.call(rng.randf_range(600.0, 675.0)), rng.randi_range(2, 3), rng.randi_range(3, 6), 8, TL["rock"] if i % 2 == 0 else TL["gravel"], rng)
	# swamp: mud mounds and mangrove islets
	for i in 6:
		_mound(floors, over, fx.call(rng.randf_range(690.0, 780.0)), rng.randi_range(4, 8), rng.randi_range(3, 8), 5, -1, rng)
	var islets: Array = []
	for ix in [700.0, 724.0, 748.0, 770.0]:
		var icx: int = fx.call(ix + rng.randf_range(-4.0, 4.0))
		islets.append(icx)
		_mound(floors, over, icx, 5, 26, -3, -1, rng)
	# fallen logs in the river and the swamp
	for i in 11:
		var lx: int = fx.call(rng.randf_range(600.0, 790.0))
		var ln := rng.randi_range(7, 13)
		if lx + ln >= ww - 2:
			continue
		var f_hi := -1000
		var f_lo := 100000
		for k in range(lx, lx + ln):
			f_hi = maxi(f_hi, floors[k])
			f_lo = mini(f_lo, floors[k])
		if f_hi - f_lo > 1 or f_hi < 8:
			continue
		for k in range(lx, lx + ln):
			var tile_id: int = TL["wood_end"] if (k == lx or k == lx + ln - 1) else TL["wood"]
			for y in range(f_hi - 2, floors[k]):
				over[Vector2i(k, y)] = tile_id
			floors[k] = mini(floors[k], f_hi - 2)

	# ---- rock fill: every column is solid from its floor down to "bedrock"
	var bed := PackedInt32Array()
	bed.resize(ww)
	for x in ww:
		var deepest := floors[x]
		for k in range(maxi(x - 48, 0), mini(x + 49, ww)):
			deepest = maxi(deepest, floors[k])
		bed[x] = mini(hh, deepest + 14)
	bedrock_rows = bed
	for x in ww:
		var f := floors[x]
		var reg := col_reg[x]
		var patch := n_patch.get_noise_1d(float(x))
		for y in range(f, bed[x]):
			var d := y - f
			var e := d
			if d > 9:
				for dx in range(1, 7):
					if floors[maxi(x - dx, 0)] > y or floors[mini(x + dx, ww - 1)] > y:
						e = dx
						break
			var key := Vector2i(x, y)
			var tile: int = over[key] if over.has(key) else _material(reg, e, d == 0, y, patch, f)
			_set_tile(terrain, x, y, tile)
		# water overlay; deep water is sparse (it only adds a faint sparkle)
		for y in range(0, f):
			if y < 81 or ((x + y) & 1) == 0:
				_set_tile(bg, x, y, _water_tile(y))
	_set_tile(bg, ww - 1, hh - 1, TL["water_hadal"])  # makes the used rect span the whole world
	_set_tile(bg, 0, hh - 1, TL["water_hadal"])

	# ---- caves, arches, tunnels
	for bm in bommies:
		if int(bm[1]) >= 5 and int(bm[2]) >= 8:
			var bx: int = bm[0]
			var base_row: int = bm[3]
			_carve(terrain, bg, decor, float(bx), float(base_row), float(bm[1]) * 0.55, minf(float(bm[2]) * 0.45, 4.5), base_row - 1)
	var wall_x0 := int(305.0 * sx)
	for i in 7:
		var row := int(lerpf(96.0, 262.0, float(i) / 6.0) * sy) + rng.randi_range(-4, 4)
		var face := -1
		for x in range(wall_x0, ww - 1):
			if floors[x] > row:
				face = x
				break
		if face < 0:
			continue
		var tx := float(face) - rng.randf_range(15.0, 26.0)
		var ty := float(row) + rng.randf_range(-5.0, 5.0)
		_carve_tunnel(terrain, bg, decor, Vector2(float(face) + 2.0, float(row)), Vector2(tx, ty), 3.2)
		_carve(terrain, bg, decor, tx, ty, 7.0, 5.0, 100000)
		for k in 4:
			var gx := int(tx + rng.randf_range(-5.0, 5.0))
			var gy := int(ty + 4.0)
			for yy in range(int(ty), int(ty) + 7):
				if terrain.get_cell_source_id(Vector2i(gx, yy)) != -1:
					_set_tile(decor, gx, yy - 1, TL["bio_coral"] if k % 2 == 0 else TL["coral_glow"])
					break

	# ---- decor
	_decorate(floors, col_reg, vents, islets, rng, terrain, decor)
	_redraw_all()


func _open_cell(terrain: TileMapLayer, bg: TileMapLayer, decor: TileMapLayer, x: int, y: int) -> void:
	var v := Vector2i(x, y)
	if terrain.get_cell_source_id(v) != -1:
		terrain.erase_cell(v)
		bg.set_cell(v, 0, Vector2i(int(TL["water_midnight"]), 0))
		decor.erase_cell(v)


func _carve(terrain: TileMapLayer, bg: TileMapLayer, decor: TileMapLayer, cx: float, cy: float, rx: float, ry: float, max_y: int) -> void:
	for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
		if y > max_y:
			continue
		for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
			var nx := (float(x) - cx) / maxf(rx, 0.5)
			var ny := (float(y) - cy) / maxf(ry, 0.5)
			if nx * nx + ny * ny <= 1.0:
				_open_cell(terrain, bg, decor, x, y)


func _carve_tunnel(terrain: TileMapLayer, bg: TileMapLayer, decor: TileMapLayer, a: Vector2, b: Vector2, r: float) -> void:
	var steps := int(a.distance_to(b) * 2.0) + 1
	for i in steps + 1:
		var t := float(i) / float(steps)
		var p := a.lerp(b, t)
		_carve(terrain, bg, decor, p.x, p.y + sin(t * 9.0) * 0.8, r * 1.35, r, 100000)


func _d(decor: TileMapLayer, x: int, y: int, name: String) -> void:
	decor.set_cell(Vector2i(x, y), 0, Vector2i(int(TL[name]), 0))


func _stack(decor: TileMapLayer, x: int, y_bottom: int, n: int, base: String, mid: String, top: String) -> void:
	for i in n:
		var y := y_bottom - i
		if y < 1:
			break
		var nm := mid
		if i == 0:
			nm = base
		elif i == n - 1:
			nm = top
		_d(decor, x, y, nm)


func _pick_weighted(table: Array, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for t in table:
		total += float(t[1])
	var r := rng.randf() * total
	for t in table:
		r -= float(t[1])
		if r <= 0.0:
			return str(t[0])
	return str(table[table.size() - 1][0])


func _decorate(floors: PackedInt32Array, col_reg: PackedInt32Array, vents: Array, islets: Array, rng: RandomNumberGenerator, terrain: TileMapLayer, decor: TileMapLayer) -> void:
	var ww := floors.size()
	var hh := height_tiles
	var reef_table := [["coral_brain", 14], ["coral_fan", 12], ["coral_stag", 12], ["coral_table", 8],
		["coral_tube", 10], ["anemone_mag", 8], ["sponge_barrel", 6], ["sponge_vase", 6],
		["coral_blue", 10], ["clam", 4], ["pillar", 6], ["seagrass", 4]]
	for x in range(2, ww - 2):
		var f := floors[x]
		if f < 2 or f > hh - 4:
			continue
		if absi(floors[x + 1] - floors[x - 1]) > 3:
			continue
		var r := rng.randf()
		match col_reg[x]:
			0:
				if r < 0.20:
					_d(decor, x, f - 1, "seagrass")
				elif r < 0.27:
					_stack(decor, x, f - 1, rng.randi_range(2, 3), "seagrass_tall", "seagrass_tall", "seagrass_tall")
				elif r < 0.31:
					_d(decor, x, f - 1, "shell")
				elif r < 0.35:
					_d(decor, x, f - 1, "starfish")
				elif r < 0.38:
					_d(decor, x, f - 1, "urchin")
				elif r < 0.41:
					_d(decor, x, f - 1, "mussels")
				elif r < 0.44:
					_d(decor, x, f - 1, "anemone_pink")
				elif r < 0.455:
					_d(decor, x, f - 1, "driftwood")
			1:
				if r < 0.30:
					var maxh := f - 1
					var h := maxh if rng.randf() < 0.35 else mini(rng.randi_range(5, 16), maxh)
					if h < 3:
						_d(decor, x, f - 1, "seagrass")
					else:
						for i in h:
							var y := f - 1 - i
							var nm := "kelp_mid"
							if i == 0:
								nm = "kelp_base"
							elif i == h - 1 and h != maxh:
								nm = "kelp_top"
							_d(decor, x, y, nm)
						if h == maxh:
							_d(decor, x, 0, "kelp_float")
				elif r < 0.40:
					_d(decor, x, f - 1, "seagrass")
				elif r < 0.43:
					_d(decor, x, f - 1, "urchin")
				elif r < 0.46:
					_d(decor, x, f - 1, "starfish")
				elif r < 0.48:
					_d(decor, x, f - 1, "shell")
			2:
				if r < 0.58:
					var kind := _pick_weighted(reef_table, rng)
					if kind == "pillar":
						var k := mini(rng.randi_range(2, 6), f - 2)
						for i in k:
							_d(decor, x, f - 1 - i, "coral_pillar_base")
						_d(decor, x, f - 1 - k, "coral_pillar_top")
					else:
						_d(decor, x, f - 1, kind)
			3:
				if f < 120:
					if r < 0.10:
						_d(decor, x, f - 1, "sea_pen")
					elif r < 0.16:
						_d(decor, x, f - 1, "crinoid")
					elif r < 0.20:
						_d(decor, x, f - 1, "sponge_vase")
					elif r < 0.23:
						_d(decor, x, f - 1, "urchin")
				elif f < 250:
					if r < 0.09:
						_d(decor, x, f - 1, "sea_pen")
					elif r < 0.15:
						_d(decor, x, f - 1, "glass_sponge")
					elif r < 0.21:
						_d(decor, x, f - 1, "crinoid")
					elif r < 0.26:
						_d(decor, x, f - 1, "bio_coral")
					elif r < 0.29:
						_d(decor, x, f - 1, "nodules")
					elif r < 0.295:
						_d(decor, x, f - 1, "whale_rib")
				else:
					if r < 0.06:
						_d(decor, x, f - 1, "glass_sponge")
					elif r < 0.12:
						_d(decor, x, f - 1, "sea_pen")
					elif r < 0.17:
						_d(decor, x, f - 1, "bio_coral")
					elif r < 0.25:
						_d(decor, x, f - 1, "nodules")
					elif r < 0.255:
						_d(decor, x, f - 1, "whale_rib")
			4:
				if f <= 14:
					if r < 0.35:
						_stack(decor, x, f - 1, rng.randi_range(2, 4), "reed_base", "reed_base", "reed_top")
					elif r < 0.50:
						_d(decor, x, f - 1, "river_stone")
					elif r < 0.60:
						_d(decor, x, f - 1, "water_plant")
				else:
					if r < 0.18:
						_stack(decor, x, f - 1, rng.randi_range(2, 3), "water_plant", "water_plant", "water_plant")
					elif r < 0.26:
						_d(decor, x, f - 1, "river_stone")
					elif r < 0.30:
						_d(decor, x, f - 1, "mussels")
			_:
				if r < 0.20:
					_d(decor, x, f - 1, "swamp_grass")
				elif r < 0.27:
					_d(decor, x, f - 1, "cypress_knee")
				elif r < 0.32:
					_stack(decor, x, f - 1, rng.randi_range(2, 3), "water_plant", "water_plant", "water_plant")
				elif r < 0.35:
					_stack(decor, x, f - 1, rng.randi_range(2, 4), "methane", "methane", "methane")
		# things floating on the surface
		if f > 3 and decor.get_cell_source_id(Vector2i(x, 0)) == -1:
			var s := rng.randf()
			if col_reg[x] == 4:
				if s < 0.20:
					_d(decor, x, 0, "lily_pad")
				elif s < 0.28:
					_d(decor, x, 0, "hyacinth")
			elif col_reg[x] == 5:
				if s < 0.45:
					_d(decor, x, 0, "algae_scum")
				elif s < 0.55:
					_d(decor, x, 0, "lily_pad")
				elif s < 0.61:
					_d(decor, x, 0, "hyacinth")
	# hydrothermal vents: smoke, bubbles and tube worms
	for vx in vents:
		var vf := floors[vx]
		for i in 8:
			_d(decor, vx, vf - 1 - i, "smoke")
		for dx in [-3, 4]:
			if vx + dx > 1 and vx + dx < ww - 2:
				_d(decor, vx + dx, floors[vx + dx] - 1, "tube_worm")
		_d(decor, vx - 1, vf - 2, "bubbles")
		_d(decor, vx + 2, vf - 3, "bubbles")
	# mangrove islets: prop roots in the water, hanging roots and moss
	for ic in islets:
		for x in range(ic - 8, ic + 9):
			if x < 2 or x >= ww - 2:
				continue
			var fl := floors[x]
			if fl < 3:
				_d(decor, x, -1, "moss_hang")
				continue
			if rng.randf() < 0.55:
				var hh2 := mini(fl - 1, rng.randi_range(6, 20))
				for i in hh2:
					_d(decor, x, fl - 1 - i, "root_stem")
				_d(decor, x, fl - 1 - hh2, "root_hang_end")
			if rng.randf() < 0.5:
				_d(decor, x, 1, "root_hang")
				_d(decor, x, 2, "root_hang_end")
			if rng.randf() < 0.5:
				_d(decor, x, -1, "moss_hang")


# ------------------------------------------------------------------ painting
func paint(c: CanvasItem, mode: String) -> void:
	if mode == "back":
		_paint_back(c)
	else:
		_paint_mid(c)


func _hills(c: CanvasItem, x0: float, x1: float, col: Color, base_h: float, amp: float, seed_v: int) -> void:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = 0.0022
	var pts := PackedVector2Array()
	var x := x0
	while x < x1:
		pts.append(Vector2(x, -base_h - (n.get_noise_1d(x) * 0.5 + 0.5) * amp))
		x += 48.0
	pts.append(Vector2(x1, -base_h - (n.get_noise_1d(x1) * 0.5 + 0.5) * amp))
	pts.append(Vector2(x1, 2.0))
	pts.append(Vector2(x0, 2.0))
	c.draw_colored_polygon(pts, col)


func _tree_line(c: CanvasItem, x0: float, x1: float, col: Color, h: float, seed_v: int, pines: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var x := x0
	while x < x1:
		var th := h * rng.randf_range(0.6, 1.3)
		var tw := th * 0.45
		if pines:
			c.draw_colored_polygon(PackedVector2Array([Vector2(x - tw, 0), Vector2(x, -th), Vector2(x + tw, 0)]), col)
		else:
			c.draw_rect(Rect2(x - 3.0, -th * 0.5, 6.0, th * 0.5), col)
			c.draw_circle(Vector2(x, -th * 0.6), th * 0.42, col)
		x += rng.randf_range(24.0, 46.0)


func _haze(c: CanvasItem, x0: float, x1: float, col: Color, h: float) -> void:
	var b := minf((x1 - x0) * 0.3, 1200.0)
	var clear := Color(col.r, col.g, col.b, 0.0)
	var xs := [x0, x0 + b, x1 - b, x1]
	var cols := [clear, col, col, clear]
	for i in 3:
		c.draw_polygon(PackedVector2Array([Vector2(xs[i], -h), Vector2(xs[i + 1], -h), Vector2(xs[i + 1], 0), Vector2(xs[i], 0)]),
			PackedColorArray([Color(cols[i].r, cols[i].g, cols[i].b, 0.0), Color(cols[i + 1].r, cols[i + 1].g, cols[i + 1].b, 0.0), cols[i + 1], cols[i]]))


func _paint_back(c: CanvasItem) -> void:
	_ensure_pal()
	var ws := world_size_tiles()
	var w := float(ws.x * TILE)
	var h := float(ws.y * TILE)
	# sky
	var bands := 16
	var bh := float(sky_height) / float(bands)
	for i in bands:
		var f := float(i) / float(bands - 1)
		var col := Color("#2f6fb8").lerp(Color("#ffe2b0"), f * f)
		c.draw_rect(Rect2(0.0, -float(sky_height) + float(i) * bh, w, bh + 1.0), col)
	c.draw_circle(Vector2(w * 0.55, -float(sky_height) * 0.58), 70.0, Color(1.0, 0.95, 0.7, 0.9))
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 7
	for i in int(w / 700.0):
		var cx := rng.randf_range(0.0, w)
		var cy := rng.randf_range(-float(sky_height) * 0.85, -float(sky_height) * 0.35)
		for k in 5:
			c.draw_circle(Vector2(cx + float(k) * 34.0, cy + sin(float(k) * 1.7) * 10.0), 30.0 + float(k % 3) * 8.0, Color(1, 1, 1, 0.55))
	# distant land per region
	var rx := func(i: int, key: String) -> float: return float(REGIONS[i][key]) * w
	_hills(c, 0.0, rx.call(0, "x1") + 500.0, Color("#6f8fb0"), 20.0, 420.0, world_seed + 11)
	_hills(c, 0.0, rx.call(0, "x1") + 300.0, Color("#4f7d6c"), 10.0, 240.0, world_seed + 12)
	_hills(c, rx.call(1, "x0"), rx.call(1, "x1"), Color("#86a6b8"), 6.0, 110.0, world_seed + 13)
	_hills(c, rx.call(4, "x0") - 300.0, rx.call(4, "x1"), Color("#5a8a62"), 12.0, 320.0, world_seed + 14)
	_tree_line(c, rx.call(4, "x0"), rx.call(4, "x1"), Color("#2f5a3a"), 90.0, world_seed + 15, true)
	_hills(c, rx.call(5, "x0") - 200.0, w, Color("#6b8250"), 8.0, 170.0, world_seed + 16)
	_tree_line(c, rx.call(5, "x0"), w, Color("#2a4226"), 70.0, world_seed + 17, false)
	_haze(c, rx.call(4, "x0") - 400.0, w, Color(0.72, 0.78, 0.5, 0.35), 320.0)
	# bedrock + smooth water colour (alpha masked where the sea floor is)
	c.draw_rect(Rect2(0.0, 0.0, w, h), BEDROCK_COL)
	if _grad_tex == null:
		_build_gradient(ws)
	c.draw_texture_rect(_grad_tex, Rect2(0.0, 0.0, float(ceili(float(ws.x) / GRAD_CELL) * GRAD_CELL * TILE), float(ceili(float(ws.y) / GRAD_CELL) * GRAD_CELL * TILE)), false)


func _build_gradient(ws: Vector2i) -> void:
	var cw := ceili(float(ws.x) / float(GRAD_CELL))
	var ch := ceili(float(ws.y) / float(GRAD_CELL))
	var img := Image.create(cw, ch, false, Image.FORMAT_RGBA8)
	for cx in cw:
		var xt := (float(cx) + 0.5) * float(GRAD_CELL)
		var wgt := _region_weights(xt, ws.x)
		var fmax := 0
		for k in GRAD_CELL:
			fmax = maxi(fmax, int(floor_y_at(float((cx * GRAD_CELL + k) * TILE)) / float(TILE)))
		for cy in ch:
			var depth := (float(cy) + 0.5) * float(GRAD_CELL * TILE)
			var col := _water_color(wgt, depth)
			col.a = 1.0 if cy * GRAD_CELL < fmax else 0.0
			img.set_pixel(cx, cy, col)
	_grad_tex = ImageTexture.create_from_image(img)


func _land_segments() -> Array:
	var segs: Array = []
	var ws := world_size_tiles()
	var start := -1
	for x in range(0, ws.x + 1):
		var land := x < ws.x and _land_top_row(x) < 0
		if land and start < 0:
			start = x
		elif not land and start >= 0:
			segs.append([start, x - 1])
			start = -1
	return segs


func _palm(c: CanvasItem, base: Vector2, h: float, lean: float, rng: RandomNumberGenerator) -> void:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in 9:
		var t := float(i) / 8.0
		var p := base + Vector2(lean * t * t * h, -h * t)
		var wd := lerpf(10.0, 5.0, t)
		left.append(p + Vector2(-wd * 0.5, 0.0))
		right.append(p + Vector2(wd * 0.5, 0.0))
	right.reverse()
	left.append_array(right)
	c.draw_colored_polygon(left, Color("#7a5a38"))
	var top := base + Vector2(lean * h, -h)
	for k in 8:
		var a := -PI * 0.5 + (float(k) - 3.5) * 0.46 + rng.randf_range(-0.08, 0.08)
		var ln := h * rng.randf_range(0.5, 0.62)
		var prev := top
		for j in range(1, 8):
			var t2 := float(j) / 7.0
			var p2 := top + Vector2(cos(a) * ln * t2, sin(a) * ln * t2 + ln * 0.6 * t2 * t2)
			c.draw_line(prev, p2, Color("#3e9a3a") if k % 2 == 0 else Color("#2f7f30"), lerpf(8.0, 2.0, t2))
			prev = p2
	c.draw_circle(top + Vector2(-5.0, 6.0), 5.0, Color("#6a4a2a"))
	c.draw_circle(top + Vector2(5.0, 7.0), 5.0, Color("#6a4a2a"))


func _mangrove(c: CanvasItem, base: Vector2, h: float, rng: RandomNumberGenerator) -> void:
	var trunk := Color("#4a3624")
	var lean := rng.randf_range(-0.2, 0.2)
	var top := base + Vector2(lean * h, -h * 0.75)
	c.draw_line(base, top, trunk, 12.0)
	for s in [-1.0, 1.0]:
		c.draw_line(base + Vector2(0.0, -h * 0.25), base + Vector2(s * h * 0.28, 8.0), trunk, 4.0)
		c.draw_line(base + Vector2(0.0, -h * 0.15), base + Vector2(s * h * 0.16, 8.0), trunk, 3.0)
	for i in 10:
		var a := rng.randf() * TAU
		var rr := rng.randf() * h * 0.42
		var g := rng.randf_range(0.0, 0.1)
		c.draw_circle(top + Vector2(cos(a) * rr * 1.4, sin(a) * rr * 0.55 - h * 0.1), rng.randf_range(0.2, 0.36) * h, Color(0.14 + g, 0.32 + g, 0.15, 1.0))


func _lighthouse(c: CanvasItem, base: Vector2, h: float) -> void:
	var bw := h * 0.2
	var tw := h * 0.12
	c.draw_colored_polygon(PackedVector2Array([base + Vector2(-bw, 0), base + Vector2(bw, 0), base + Vector2(tw, -h), base + Vector2(-tw, -h)]), Color("#f2f2f2"))
	for i in 3:
		var y0 := -h * (0.12 + 0.3 * float(i))
		var y1 := y0 - h * 0.14
		var w0 := lerpf(bw, tw, -y0 / h)
		var w1 := lerpf(bw, tw, -y1 / h)
		c.draw_colored_polygon(PackedVector2Array([base + Vector2(-w0, y0), base + Vector2(w0, y0), base + Vector2(w1, y1), base + Vector2(-w1, y1)]), Color("#d23a32"))
	c.draw_rect(Rect2(base.x - tw * 1.3, base.y - h - h * 0.1, tw * 2.6, h * 0.1), Color("#fff1a0"))
	c.draw_colored_polygon(PackedVector2Array([base + Vector2(-tw * 1.5, -h * 1.1), base + Vector2(tw * 1.5, -h * 1.1), base + Vector2(0, -h * 1.3)]), Color("#d23a32"))


func _paint_mid(c: CanvasItem) -> void:
	var ws := world_size_tiles()
	var w := float(ws.x * TILE)
	var first := true
	for seg in _land_segments():
		var a: int = seg[0]
		var b: int = seg[1]
		var reg := region_index_at(float(a + b) * 0.5 * float(TILE))
		var rng := RandomNumberGenerator.new()
		rng.seed = world_seed + 100 + a
		var x := a + 3
		while x < b - 2:
			var top_y := float(_land_top_row(x) * TILE)
			var base := Vector2(float(x * TILE) + 16.0, top_y + 4.0)
			if reg == 0 or reg == 2:
				_palm(c, base, rng.randf_range(110.0, 170.0), rng.randf_range(-0.35, 0.35), rng)
				x += rng.randi_range(6, 10)
			elif reg == 4 or reg == 5:
				_mangrove(c, base, rng.randf_range(130.0, 200.0), rng)
				x += rng.randi_range(4, 7)
			else:
				c.draw_circle(base + Vector2(0.0, -10.0), rng.randf_range(10.0, 18.0), Color("#4f7a3a"))
				x += rng.randi_range(2, 4)
		if first and reg == 0 and b - a > 20:
			var lx := a + 8
			_lighthouse(c, Vector2(float(lx * TILE), float(_land_top_row(lx) * TILE) + 6.0), 230.0)
		first = false
	# pier posts (the deck is drawn in front, see _draw)
	var coast_end := _first_land_end()
	if coast_end > 0:
		var px := float(coast_end + 1) * TILE
		for i in 7:
			c.draw_rect(Rect2(px + float(i) * 128.0 + 40.0, -34.0, 12.0, 200.0), Color("#5a4228"))
	var bx := float(REGIONS[4]["x0"]) * w + (float(REGIONS[4]["x1"]) - float(REGIONS[4]["x0"])) * w * 0.45
	for i in 6:
		c.draw_rect(Rect2(bx + float(i) * 160.0, -96.0, 14.0, 96.0 + 220.0), Color("#5a4228"))


func _first_land_end() -> int:
	var segs := _land_segments()
	if segs.is_empty():
		return -1
	return int(segs[0][1])


## Front layer: water surface, pier deck and bridge deck.
func _draw() -> void:
	var w := float(world_size_tiles().x * TILE)
	c_surface(w)
	var coast_end := _first_land_end()
	if coast_end > 0:
		var px := float(coast_end + 1) * TILE
		draw_rect(Rect2(px, -38.0, 7.0 * 128.0 + 40.0, 12.0), Color("#8a6a46"))
		draw_rect(Rect2(px, -26.0, 7.0 * 128.0 + 40.0, 4.0), Color("#5a4228"))
	var bx := float(REGIONS[4]["x0"]) * w + (float(REGIONS[4]["x1"]) - float(REGIONS[4]["x0"])) * w * 0.45
	draw_rect(Rect2(bx - 20.0, -108.0, 5.0 * 160.0 + 54.0, 14.0), Color("#8a6a46"))
	draw_rect(Rect2(bx - 20.0, -134.0, 5.0 * 160.0 + 54.0, 4.0), Color("#5a4228"))
	for i in 7:
		draw_rect(Rect2(bx - 20.0 + float(i) * 142.0, -134.0, 5.0, 28.0), Color("#5a4228"))


func c_surface(w: float) -> void:
	draw_rect(Rect2(0.0, 0.0, w, 36.0), Color(0.75, 0.95, 1.0, 0.18))
	draw_line(Vector2(0.0, -1.5), Vector2(w, -1.5), Color(1, 1, 1, 0.7), 3.0)
