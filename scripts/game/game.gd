class_name Game
extends Node2D
## Main gameplay controller: spawning, interactions, camera, darkness, effects, run end.

const TILE := 32
const TARGET_CREATURES := 65
const DESPAWN_DIST := 2300.0

const DARK_SHADER := """
shader_type canvas_item;
uniform vec2 center = vec2(0.5, 0.5);
uniform float radius = 0.35;
uniform float darkness = 0.0;
uniform float aspect = 1.7778;
uniform vec4 tint : source_color = vec4(0.0, 0.02, 0.07, 1.0);
void fragment() {
	vec2 d = UV - center;
	d.x *= aspect;
	float dist = length(d);
	float a = smoothstep(radius, radius + 0.4, dist) * darkness;
	COLOR = vec4(tint.rgb, a);
}
"""

class Overlay extends Node2D:
	var game: Node
	func _process(_d: float) -> void:
		queue_redraw()
	func _draw() -> void:
		game.draw_overlay(self)

@onready var world: WorldGenerator = $World
@onready var terrain: TileMapLayer = $World/Terrain

var shark: Shark
var camera: Camera2D
var hud: Hud
var creatures_root: Node2D
var projectiles_root: Node2D
var fx_root: Node2D
var overlay: Overlay
var dark_rect: ColorRect
var dark_mat: ShaderMaterial

var world_w := 9600.0
var world_h := 3200.0
var score := 0
var coins_run := 0
var eaten_run := 0
var run_time := 0.0
var finished := false
var biome_id := ""
var shake_amt := 0.0

var _spawn_cd := 0.0
var _dark_cur := 0.0
var _counts := {}


func _ready() -> void:
	randomize()
	world.ensure_generated()
	var ws := world.world_size_tiles()
	world_w = float(ws.x * TILE)
	world_h = float(ws.y * TILE)

	creatures_root = Node2D.new()
	add_child(creatures_root)
	projectiles_root = Node2D.new()
	projectiles_root.z_index = 3
	add_child(projectiles_root)

	shark = Shark.new()
	shark.game = self
	shark.position = Vector2(world_w * 0.5, 260.0)
	shark.z_index = 5
	shark.setup(Database.shark(str(Save.data["selected_shark"])))
	add_child(shark)
	shark.died.connect(_on_shark_died)

	fx_root = Node2D.new()
	fx_root.z_index = 10
	add_child(fx_root)
	overlay = Overlay.new()
	overlay.game = self
	overlay.z_index = 20
	add_child(overlay)

	camera = Camera2D.new()
	camera.limit_left = 0
	camera.limit_right = int(world_w)
	camera.limit_top = -800
	camera.limit_bottom = int(world_h)
	camera.position = shark.position
	add_child(camera)
	camera.make_current()

	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	dark_rect = ColorRect.new()
	dark_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(dark_rect)
	dark_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sh := Shader.new()
	sh.code = DARK_SHADER
	dark_mat = ShaderMaterial.new()
	dark_mat.shader = sh
	dark_rect.material = dark_mat

	hud = Hud.new()
	hud.game = self
	add_child(hud)

	_populate_initial()


# ---------------------------------------------------------------- loop
func _physics_process(delta: float) -> void:
	if not finished:
		run_time += delta
	_spawn_cd -= delta
	if _spawn_cd <= 0.0:
		_spawn_cd = 0.25
		_spawn_tick()
	_interactions(delta)
	_update_camera(delta)
	_update_darkness(delta)
	_update_biome()


func _update_camera(delta: float) -> void:
	var target := shark.global_position + shark.velocity * 0.3
	camera.position = camera.position.lerp(target, 1.0 - exp(-6.0 * delta))
	var z := 1.0 / (1.0 + 0.035 * float(shark.level - 1))
	if shark.boosting:
		z *= 0.92
	camera.zoom = camera.zoom.lerp(Vector2(z, z), 1.0 - exp(-2.0 * delta))
	if shake_amt > 0.1 and bool(Save.setting("screen_shake")):
		camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake_amt
	else:
		camera.offset = Vector2.ZERO
	shake_amt = lerpf(shake_amt, 0.0, 1.0 - exp(-8.0 * delta))


func _update_darkness(delta: float) -> void:
	var biome := Database.biome_at(shark.global_position.y)
	_dark_cur = lerpf(_dark_cur, float(biome["darkness"]), 1.0 - exp(-1.5 * delta))
	var vp := get_viewport_rect().size
	var screen := get_viewport().get_canvas_transform() * shark.global_position
	var light := 1.0 + Database.upgrade_bonus("light")
	var world_r := 360.0 * light * (1.0 + 0.04 * float(shark.level - 1))
	dark_mat.set_shader_parameter("center", screen / vp)
	dark_mat.set_shader_parameter("aspect", vp.x / vp.y)
	dark_mat.set_shader_parameter("radius", world_r * camera.zoom.x / vp.y)
	dark_mat.set_shader_parameter("darkness", _dark_cur)


func _update_biome() -> void:
	var b := Database.biome_at(shark.global_position.y)
	if str(b["id"]) != biome_id:
		biome_id = str(b["id"])
		hud.show_banner(str(b["name"]), Color(str(b["tint"])).lightened(0.3))


# ---------------------------------------------------------------- queries
func is_solid(p: Vector2, r: float) -> bool:
	for o in [Vector2.ZERO, Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
		var cell := terrain.local_to_map(terrain.to_local(p + o))
		if terrain.get_cell_source_id(cell) != -1:
			return true
	return false


func clamp_to_water(pos: Vector2, d: Dictionary) -> Vector2:
	return Vector2(
		clampf(pos.x, 60.0, world_w - 60.0),
		clampf(pos.y, maxf(float(d["min_depth"]), 40.0), minf(float(d["max_depth"]), world_h - 80.0)))


func creatures_in_radius(pos: Vector2, r: float) -> Array:
	var out: Array = []
	for node in creatures_root.get_children():
		var cr := node as Creature
		if cr == null or cr.dead:
			continue
		if pos.distance_to(cr.global_position) <= r + cr.length * 0.35:
			out.append(cr)
	return out


# ---------------------------------------------------------------- spawning
func _populate_initial() -> void:
	_counts.clear()
	var total := 0
	var tries := 0
	while total < 55 and tries < 200:
		tries += 1
		total += _spawn_random(false)


func _spawn_tick() -> void:
	_counts.clear()
	var total := 0
	for node in creatures_root.get_children():
		var cr := node as Creature
		if cr == null or cr.dead:
			continue
		if cr.global_position.distance_to(shark.global_position) > DESPAWN_DIST:
			cr.remove()
			continue
		total += 1
		_counts[cr.id] = int(_counts.get(cr.id, 0)) + 1
	for i in 3:
		if total < TARGET_CREATURES:
			total += _spawn_random(true)


func _is_floor_type(d: Dictionary) -> bool:
	var b := str(d["behavior"])
	return b == "bottom" or b == "static"


func _is_surface_type(d: Dictionary) -> bool:
	var b := str(d["behavior"])
	return b == "fly" or b == "surface"


func _pick_def(y: float, surface_roll: bool) -> Dictionary:
	var pool: Array = []
	var total := 0.0
	for d in Database.creatures:
		if _is_surface_type(d) != surface_roll:
			continue
		if not surface_roll and not _is_floor_type(d):
			if y < float(d["min_depth"]) or y > float(d["max_depth"]):
				continue
		if int(_counts.get(str(d["id"]), 0)) >= int(d["max_count"]):
			continue
		pool.append(d)
		total += float(d["weight"])
	if pool.is_empty():
		return {}
	var r := randf() * total
	for d in pool:
		r -= float(d["weight"])
		if r <= 0.0:
			return d
	return pool[pool.size() - 1]


func _spawn_position(d: Dictionary, around: Vector2, offscreen: bool) -> Vector2:
	var dx := randf_range(-1400.0, 1400.0)
	if offscreen:
		dx = randf_range(550.0, 1100.0) * (1.0 if randf() < 0.5 else -1.0)
	var x := clampf(around.x + dx, 60.0, world_w - 60.0)
	match str(d["behavior"]):
		"fly":
			return Vector2(x, randf_range(-420.0, -140.0))
		"surface":
			return Vector2(x, -float(d["length"]) * 0.12)
		"bottom", "static":
			return Vector2(x, world.floor_y_at(x) - float(d["length"]) * 0.3)
	var y := clampf(around.y + randf_range(-700.0, 700.0), maxf(float(d["min_depth"]), 50.0), minf(float(d["max_depth"]), world_h - 120.0))
	return Vector2(x, y)


## Returns how many creatures were spawned.
func _spawn_random(offscreen: bool) -> int:
	var around := shark.global_position
	var surface_roll := randf() < 0.10 and around.y < 900.0
	var y_ref := clampf(around.y + randf_range(-700.0, 700.0), 50.0, world_h - 120.0)
	var d := _pick_def(y_ref, surface_roll)
	if d.is_empty():
		return 0
	var pos := _spawn_position(d, around, offscreen)
	if _is_floor_type(d):
		if pos.y < float(d["min_depth"]) or pos.y > float(d["max_depth"]) or absf(pos.y - around.y) > 1000.0:
			return 0
	if pos.distance_to(around) < (400.0 if not offscreen else 0.0):
		return 0
	if is_solid(pos, 12.0):
		return 0
	var n := 1
	if str(d["behavior"]) == "school":
		n = maxi(1, int(float(d["school_size"]) * randf_range(0.6, 1.2)))
	var lead: Creature = null
	for i in n:
		var cr := Creature.new()
		cr.position = pos + (Vector2.ZERO if i == 0 else Vector2(randf_range(-60.0, 60.0), randf_range(-40.0, 40.0)))
		cr.setup(d, self)
		creatures_root.add_child(cr)
		if i == 0:
			lead = cr
		else:
			cr.leader = lead
			cr.follow_offset = Vector2(randf_range(-70.0, 70.0), randf_range(-45.0, 45.0))
	_counts[str(d["id"])] = int(_counts.get(str(d["id"]), 0)) + n
	return n


func spawn_projectile(from: Vector2, dir: Vector2, dmg: float) -> void:
	var p := Projectile.new()
	p.game = self
	p.position = from
	p.velocity = dir * 420.0
	p.damage = dmg
	projectiles_root.add_child(p)


# ---------------------------------------------------------------- interactions
func _interactions(delta: float) -> void:
	if not shark.alive:
		return
	var sp := shark.global_position
	var pull := Database.upgrade_bonus("pull")
	for node in creatures_root.get_children():
		var cr := node as Creature
		if cr == null or cr.dead:
			continue
		var d := sp.distance_to(cr.global_position)
		if d < 650.0:
			Save.discover(cr.id)
		if pull > 0.0 and d < pull and bool(cr.def["edible"]) and cr.length < shark.length * 0.6 and cr.hp <= shark.bite_dmg:
			cr.position += (sp - cr.global_position).normalized() * 110.0 * delta
		var contact_r := (shark.length + cr.length) * 0.28
		if d < contact_r and cr.contact_cd <= 0.0:
			var dmg := float(cr.def["contact_damage"])
			if dmg > 0.0 and cr.stun <= 0.0:
				cr.contact_cd = 1.0
				shark.hit_by(cr, dmg)


func on_eaten(cr: Creature, sc: int, coins: int, mult: float) -> void:
	score += sc
	coins_run += coins
	eaten_run += 1
	var txt := "+%d" % sc
	if mult > 1.01:
		txt += "  x%.1f" % mult
	floating_text(cr.global_position, txt, UI.C_GOLD)
	burst(cr.global_position, cr.color.lerp(Color("#d03030"), 0.5), 12)
	shake(2.5)
	cr.remove()


func on_level_up(lv: int) -> void:
	hud.show_banner("LEVEL UP!  Lv %d" % lv, UI.C_ACCENT)
	floating_text(shark.global_position + Vector2(0, -shark.length), "LEVEL %d" % lv, UI.C_ACCENT, 30)
	Sfx.play("levelup")


func on_frenzy() -> void:
	hud.show_banner("FEEDING FRENZY!", UI.C_GOLD)
	Sfx.play("frenzy")
	shake(6.0)


func _on_shark_died(cause: String) -> void:
	finished = true
	coins_run += int(score / 250.0)
	var best_before := int(Save.data["best_score"])
	var new_best := score > best_before
	Save.data["coins"] = Save.coins() + coins_run
	Save.data["total_eaten"] = int(Save.data["total_eaten"]) + eaten_run
	Save.data["runs"] = int(Save.data["runs"]) + 1
	if new_best:
		Save.data["best_score"] = score
	Save.save_game()
	var info := {
		"cause": cause, "score": score, "best": maxi(score, best_before), "new_best": new_best,
		"coins": coins_run, "eaten": eaten_run, "time": run_time, "level": shark.level,
	}
	await get_tree().create_timer(1.4).timeout
	hud.show_game_over(info)


# ---------------------------------------------------------------- effects
func shake(a: float) -> void:
	shake_amt = maxf(shake_amt, a)


func splash(pos: Vector2) -> void:
	burst(pos, Color(0.85, 0.95, 1.0), 16)
	Sfx.play("splash")


func floating_text(pos: Vector2, text: String, col: Color = Color.WHITE, font_size: int = 22) -> void:
	var l := Label.new()
	l.text = text
	l.modulate = col
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	l.position = pos - Vector2(30, 20)
	l.z_index = 30
	fx_root.add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", l.position.y - 70.0, 0.9)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.9)
	tw.tween_callback(l.queue_free)


func burst(pos: Vector2, col: Color, amount: int) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.7
	p.texture = CreatureArt.soft_dot()
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 220.0
	p.scale_amount_min = 0.3
	p.scale_amount_max = 0.7
	p.gravity = Vector2(0, 40)
	p.color = col
	fx_root.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.3).timeout.connect(p.queue_free)


func draw_overlay(c: Node2D) -> void:
	var font := ThemeDB.fallback_font
	var sp := shark.global_position
	for node in creatures_root.get_children():
		var cr := node as Creature
		if cr == null or cr.dead:
			continue
		var top := cr.position + Vector2(0.0, -cr.length * 0.45 - 12.0)
		if cr.hp < cr.max_hp and cr.max_hp > 1.5:
			var w := maxf(cr.length * 0.5, 30.0)
			c.draw_rect(Rect2(top.x - w * 0.5, top.y, w, 5.0), Color(0, 0, 0, 0.6))
			c.draw_rect(Rect2(top.x - w * 0.5, top.y, w * cr.hp / cr.max_hp, 5.0), Color("#ff5a4a"))
		if shark.alive and float(cr.def["contact_damage"]) > 0.0 and cr.stun <= 0.0 and sp.distance_to(cr.position) < 650.0:
			var p := top + Vector2(0.0, -20.0)
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -13), p + Vector2(13, 11), p + Vector2(-13, 11)]), Color("#ff4a3a"))
			c.draw_string(font, p + Vector2(-4, 9), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
