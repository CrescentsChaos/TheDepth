@tool
class_name WorldGenerator
extends Node2D
## Owns the three tilemap layers (Background, Decor, Terrain) and the sky.
## - Paint the layers by hand in the editor, or tick "Bake Default World" to generate
##   a starting world you can then edit.
## - At runtime, if every layer is empty a default world is generated automatically.
## - ANY non-empty Terrain tile is solid for the player. World size = used Background rect.
##
## Tileset atlas (assets/tiles/world_tileset.png), tile index along the row:
##   0-3 water (shallow -> abyss)   4 sand   5 rock   6 coral (decor)   7 kelp (decor)
##
## ANIMATED TILES: make the PNG taller. Row 0 is the normal tile, every row below it is the
## next animation frame of the tile ABOVE it (same column). A tile animates automatically
## when the cell under it is not empty; leave the cells under a tile blank to keep it still.
## e.g. a 256x128 PNG = 8 tiles with up to 4 frames each. See assets/sprites/README.md.

const TILE := 32

@export var width_tiles := 300
@export var height_tiles := 100
@export var world_seed := 1337
## Row where each water tile (0..3) begins. Keep roughly in sync with data/biomes.json depths / 32.
@export var biome_rows := PackedInt32Array([0, 19, 47, 75])
@export var generate_if_empty := true
## Animation speed of animated tiles (frames per second).
@export var tile_animation_fps := 3.0
@export var sky_height := 1000
@export var bake_default_world := false:
	set(v):
		bake_default_world = false
		if v and Engine.is_editor_hint() and is_inside_tree():
			generate()
			queue_redraw()

var _floor_cache := {}


func _ready() -> void:
	queue_redraw()


func _layer(layer_name: String) -> TileMapLayer:
	return get_node_or_null(layer_name) as TileMapLayer


func ensure_generated() -> void:
	_floor_cache.clear()
	_setup_tile_animation()
	var bg := _layer("Background")
	var decor := _layer("Decor")
	var terrain := _layer("Terrain")
	if generate_if_empty and bg != null and terrain != null and decor != null:
		if bg.get_used_cells().is_empty() and terrain.get_used_cells().is_empty() and decor.get_used_cells().is_empty():
			generate()
	queue_redraw()


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
	var bg := _layer("Background")
	if bg != null:
		var r := bg.get_used_rect()
		if r.size != Vector2i.ZERO:
			return Vector2i(r.end.x, r.end.y)
	return Vector2i(width_tiles, height_tiles)


func _water_tile(row: int) -> int:
	var idx := 0
	for i in biome_rows.size():
		if row >= biome_rows[i]:
			idx = i
	return idx


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
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	var noise := FastNoiseLite.new()
	noise.seed = world_seed
	noise.frequency = 0.015
	noise.fractal_octaves = 3

	# Seabed heights (row of the first solid tile per column)
	var floors: Array[int] = []
	for x in width_tiles:
		var n := noise.get_noise_1d(float(x))
		floors.append(int(float(height_tiles) - 5.0 - (n * 0.5 + 0.5) * 14.0))
	# Rock pillars
	for i in int(width_tiles / 10.0):
		var cx := rng.randi_range(6, width_tiles - 8)
		var w := rng.randi_range(2, 5)
		var hgt := rng.randi_range(4, 12)
		for x in range(cx, mini(cx + w, width_tiles)):
			floors[x] = maxi(floors[x] - hgt, 8)

	for x in width_tiles:
		for y in height_tiles:
			bg.set_cell(Vector2i(x, y), 0, Vector2i(_water_tile(y), 0))
			if y >= floors[x]:
				var tile := 4 if y - floors[x] < 2 else 5
				terrain.set_cell(Vector2i(x, y), 0, Vector2i(tile, 0))

	# Floating rock ledges
	var mid := width_tiles / 2
	for i in int(width_tiles / 12.0):
		var lw := rng.randi_range(6, 16)
		var lx := rng.randi_range(4, width_tiles - 20)
		var ly := rng.randi_range(8, height_tiles - 25)
		if abs(lx + lw / 2 - mid) < 14 and ly < 20:
			continue
		var thick := rng.randi_range(2, 3)
		for x in range(lx, lx + lw):
			var th := thick - (1 if (x == lx or x == lx + lw - 1) else 0)
			for k in th:
				terrain.set_cell(Vector2i(x, ly + k), 0, Vector2i(4 if k == 0 else 5, 0))

	# Decor on every exposed terrain top
	for x in width_tiles:
		for y in range(1, height_tiles):
			if terrain.get_cell_source_id(Vector2i(x, y)) != -1 and terrain.get_cell_source_id(Vector2i(x, y - 1)) == -1:
				if rng.randf() < 0.22:
					decor.set_cell(Vector2i(x, y - 1), 0, Vector2i(7 if rng.randf() < 0.5 else 6, 0))


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


func _draw() -> void:
	var w := float(world_size_tiles().x * TILE)
	var bands := 14
	var bh := float(sky_height) / float(bands)
	for i in bands:
		var f := float(i) / float(bands - 1)
		var col := Color("#2f6fb8").lerp(Color("#ffe2b0"), f * f)
		draw_rect(Rect2(0.0, -float(sky_height) + float(i) * bh, w, bh + 1.0), col)
	draw_circle(Vector2(w * 0.8, -float(sky_height) * 0.55), 70.0, Color(1.0, 0.95, 0.7, 0.9))
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 7
	for i in int(w / 700.0):
		var cx := rng.randf_range(0.0, w)
		var cy := rng.randf_range(-float(sky_height) * 0.85, -float(sky_height) * 0.35)
		for k in 5:
			draw_circle(Vector2(cx + float(k) * 34.0, cy + sin(float(k) * 1.7) * 10.0), 30.0 + float(k % 3) * 8.0, Color(1, 1, 1, 0.55))
	draw_rect(Rect2(0.0, 0.0, w, 36.0), Color(0.75, 0.95, 1.0, 0.18))
	draw_line(Vector2(0.0, -1.5), Vector2(w, -1.5), Color(1, 1, 1, 0.7), 3.0)
