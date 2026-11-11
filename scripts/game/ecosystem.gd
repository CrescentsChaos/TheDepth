class_name Ecosystem
extends Node2D
## The living-world layer shared by every creature and the player.
##  - Day/night clock (fish sleep, hunt and migrate by it).
##  - Food sources: plankton clouds (drift, rise at night), algae on coral/kelp tiles
##    (regrow), carrion left by kills, and deep-sea marine snow.
##  - Alarm calls so a whole school bolts when one fish sees a predator.

const DAY_LENGTH := 300.0     # seconds for one full day
const START_FRACTION := 0.33  # run starts in the morning (0 = midnight, 0.5 = noon)

const DIET_FOODS := {
	"plankton": ["plankton"],
	"filter": ["plankton"],
	"herbivore": ["algae"],
	"omnivore": ["algae", "plankton", "carrion"],
	"scavenger": ["carrion", "detritus"],
	"carnivore": ["carrion"],
	"any": ["carrion"],
}

## hunger points restored per unit eaten (before size scaling) and xp per unit
const FOOD_VALUE := {"plankton": 3.0, "algae": 3.5, "carrion": 6.0, "detritus": 4.0}

class Food extends RefCounted:
	var kind := "plankton"
	var pos := Vector2.ZERO
	var base_y := 0.0
	var amount := 10.0
	var max_amount := 10.0
	var radius := 48.0
	var seed := 0.0
	var temp := false     # temporary food (carrion) uses `life` as a countdown
	var life := 0.0
	var regrow := 0.0     # units per second (algae)

var game: Node
var clock := DAY_LENGTH * START_FRACTION
var foods: Array = []     # drifting / temporary Food
var algae: Array = []     # permanent Food on decor tiles
var _t := 0.0
var _tick := 0.0


func setup(p_game: Node) -> void:
	game = p_game
	z_index = 0
	var decor := game.world.get_node_or_null("Decor") as TileMapLayer
	if decor != null:
		for cell in decor.get_used_cells():
			var f := Food.new()
			f.kind = "algae"
			f.pos = decor.to_global(decor.map_to_local(cell)) + Vector2(0.0, 6.0)
			f.max_amount = 8.0
			f.amount = f.max_amount * randf_range(0.4, 1.0)
			f.regrow = 0.18
			f.radius = 22.0
			f.seed = randf() * TAU
			algae.append(f)
	_populate_initial()


# ------------------------------------------------------------------ clock
func day_fraction() -> float:
	return fposmod(clock / DAY_LENGTH, 1.0)


func day_number() -> int:
	return int(clock / DAY_LENGTH) + 1


## 0 = deep night, 1 = full daylight (smooth).
func daylight() -> float:
	var raw := 0.5 - 0.5 * cos(TAU * day_fraction())
	return smoothstep(0.12, 0.6, raw)


func night_amount() -> float:
	return 1.0 - daylight()


func phase_name() -> String:
	var f := day_fraction()
	if f < 0.2 or f >= 0.8:
		return "Night"
	if f < 0.3:
		return "Dawn"
	if f < 0.7:
		return "Day"
	return "Dusk"


func clock_text() -> String:
	var hours := day_fraction() * 24.0
	return "Day %d   %02d:%02d   %s" % [day_number(), int(hours), int(fmod(hours, 1.0) * 60.0), phase_name()]


## How awake a species is right now (0..1) for its activity pattern.
func activity_level(activity: String) -> float:
	match activity:
		"diurnal": return daylight()
		"nocturnal": return 1.0 - daylight()
		"crepuscular": return 1.0 - absf(daylight() - 0.5) * 2.0
	return 1.0


# ------------------------------------------------------------------ food queries
func kinds_for(diet: String) -> Array:
	return DIET_FOODS.get(diet, [])


## Nearest food of any of `kinds` within `radius` of `pos` (null if none).
func nearest(kinds: Array, pos: Vector2, radius: float) -> Food:
	var best: Food = null
	var best_d := radius * radius
	for list in [foods, algae]:
		for f: Food in list:
			if f.amount < 1.0 or not (f.kind in kinds):
				continue
			var d := pos.distance_squared_to(f.pos)
			if d < best_d:
				best_d = d
				best = f
	return best


## Food the mouth at `pos` can reach with a bite of `reach` pixels.
func in_reach(kinds: Array, pos: Vector2, reach: float) -> Food:
	var best: Food = null
	var best_d := INF
	for list in [foods, algae]:
		for f: Food in list:
			if f.amount < 1.0 or not (f.kind in kinds):
				continue
			var d := pos.distance_to(f.pos)
			if d <= reach + f.radius and d < best_d:
				best_d = d
				best = f
	return best


func take(f: Food, units: float) -> float:
	var got := minf(units, f.amount)
	f.amount -= got
	return got


func add_carrion(pos: Vector2, body_length: float) -> void:
	if body_length < 55.0:
		return
	var f := Food.new()
	f.kind = "carrion"
	f.pos = pos
	f.max_amount = clampf(body_length / 12.0, 3.0, 30.0)
	f.amount = f.max_amount
	f.radius = clampf(body_length * 0.3, 16.0, 70.0)
	f.temp = true
	f.life = 75.0
	f.seed = randf() * TAU
	foods.append(f)


## A fish screams: everyone of the same species nearby bolts away from `from_pos`.
func raise_alarm(origin: Vector2, species: String, from_pos: Vector2) -> void:
	for node in game.creatures_root.get_children():
		var c := node as Creature
		if c == null or c.dead or c.id != species:
			continue
		if c.position.distance_squared_to(origin) < 340.0 * 340.0:
			c.alarm_timer = 1.8
			c.alarm_from = from_pos


# ------------------------------------------------------------------ simulation
func _physics_process(delta: float) -> void:
	if game == null:
		return
	clock += delta
	_t += delta
	var night := night_amount()
	for f: Food in algae:
		if f.amount < f.max_amount:
			f.amount = minf(f.amount + f.regrow * delta, f.max_amount)
	var i := foods.size() - 1
	while i >= 0:
		var f: Food = foods[i]
		if f.temp:
			f.life -= delta
		if f.amount < 1.0 or (f.temp and f.life <= 0.0):
			foods.remove_at(i)
			i -= 1
			continue
		match f.kind:
			"plankton":
				# clouds drift sideways and rise toward the surface at night
				var ty := maxf(f.base_y - night * 260.0, 55.0)
				var np := Vector2(f.pos.x + sin(_t * 0.15 + f.seed) * 7.0 * delta, lerpf(f.pos.y, ty, 1.0 - exp(-0.5 * delta)))
				if not game.is_solid(np, 8.0):
					f.pos = np
			"detritus":
				f.pos.y += 5.0 * delta
				if game.is_solid(f.pos + Vector2(0.0, 6.0), 4.0):
					f.pos.y -= 5.0 * delta
			"carrion":
				var np2 := f.pos + Vector2(0.0, 22.0 * delta)
				if not game.is_solid(np2 + Vector2(0.0, 6.0), 6.0):
					f.pos = np2
		i -= 1
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.5
		_maintain()
	queue_redraw()


func _count(kind: String) -> int:
	var n := 0
	for f: Food in foods:
		if f.kind == kind:
			n += 1
	return n


func _maintain() -> void:
	var around: Vector2 = game.shark.global_position
	var i := foods.size() - 1
	while i >= 0:
		if foods[i].pos.distance_to(around) > 2400.0 and foods[i].kind != "carrion":
			foods.remove_at(i)
		i -= 1
	for k in 2:
		if _count("plankton") < 18:
			_spawn_plankton(around)
		if _count("detritus") < 9:
			_spawn_detritus(around)


func _populate_initial() -> void:
	var around: Vector2 = game.shark.global_position if game.shark != null else Vector2(game.world_w * 0.5, 300.0)
	for k in 40:
		if _count("plankton") < 18:
			_spawn_plankton(around)
		if _count("detritus") < 9:
			_spawn_detritus(around)


func _spawn_plankton(around: Vector2) -> void:
	var y := clampf(around.y + randf_range(-800.0, 800.0), 90.0, 2400.0)
	# thinner with depth
	if randf() < y / 3600.0:
		return
	var x := clampf(around.x + randf_range(-1700.0, 1700.0), 80.0, game.world_w - 80.0)
	if game.is_solid(Vector2(x, y), 20.0):
		return
	var f := Food.new()
	f.kind = "plankton"
	f.pos = Vector2(x, y)
	f.base_y = y
	f.max_amount = randf_range(8.0, 14.0)
	f.amount = f.max_amount
	f.radius = randf_range(40.0, 65.0)
	f.seed = randf() * TAU
	foods.append(f)


func _spawn_detritus(around: Vector2) -> void:
	var y := clampf(around.y + randf_range(-900.0, 900.0), 800.0, game.world_h - 120.0)
	if y < 800.0:
		return
	var x := clampf(around.x + randf_range(-1700.0, 1700.0), 80.0, game.world_w - 80.0)
	if game.is_solid(Vector2(x, y), 14.0):
		return
	var f := Food.new()
	f.kind = "detritus"
	f.pos = Vector2(x, y)
	f.max_amount = randf_range(5.0, 9.0)
	f.amount = f.max_amount
	f.radius = 26.0
	f.seed = randf() * TAU
	foods.append(f)


# ------------------------------------------------------------------ drawing
func _draw() -> void:
	if game == null or game.shark == null:
		return
	var sp: Vector2 = game.shark.global_position
	for f: Food in foods:
		if f.pos.distance_squared_to(sp) > 1500.0 * 1500.0:
			continue
		_draw_food(f)
	# algae: a little green shimmer on tiles that still have food
	for f: Food in algae:
		if f.amount >= 1.0 and f.pos.distance_squared_to(sp) < 1100.0 * 1100.0:
			var k := f.amount / f.max_amount
			var s := 0.5 + 0.5 * sin(_t * 1.5 + f.seed)
			draw_circle(f.pos + Vector2(0.0, -10.0), 2.0 + 2.0 * k, Color(0.55, 1.0, 0.55, 0.22 + 0.2 * s * k))


func _draw_food(f: Food) -> void:
	var k := clampf(f.amount / f.max_amount, 0.15, 1.0)
	match f.kind:
		"plankton":
			draw_circle(f.pos, f.radius * (0.8 + 0.2 * k), Color(0.7, 1.0, 0.85, 0.05))
			var n := 6 + int(10.0 * k)
			for i in n:
				var a := f.seed + float(i) * 2.399 + _t * (0.25 + 0.05 * float(i % 4))
				var r := f.radius * (0.25 + 0.75 * fposmod(float(i) * 0.618, 1.0)) * (0.7 + 0.3 * k)
				var p := f.pos + Vector2(cos(a) * r, sin(a * 1.3) * r * 0.7)
				draw_circle(p, 1.6 + float(i % 3) * 0.5, Color(0.85, 1.0, 0.9, 0.55))
		"detritus":
			for i in 5:
				var a2 := f.seed + float(i) * 1.7
				draw_circle(f.pos + Vector2(cos(a2) * 14.0, sin(a2 * 1.4 + _t * 0.4) * 10.0), 1.8, Color(0.9, 0.92, 1.0, 0.5))
		"carrion":
			var s := clampf(f.radius * 0.4, 6.0, 26.0) * (0.6 + 0.4 * k)
			draw_colored_polygon(PackedVector2Array([f.pos + Vector2(-s, 0.0), f.pos + Vector2(-s * 0.2, -s * 0.5), f.pos + Vector2(s, -s * 0.1), f.pos + Vector2(s * 0.3, s * 0.5)]), Color(0.78, 0.3, 0.3, 0.9))
			draw_circle(f.pos + Vector2(s * 0.2, -s * 0.1), s * 0.18, Color(0.95, 0.85, 0.8))
