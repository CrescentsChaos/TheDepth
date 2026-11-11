class_name Shark
extends Node2D
## The player. Momentum swimming, boost stamina, bite with lunge, hunger, poison/stun,
## combo scoring, feeding frenzy, level-ups, surface leaps and pressure damage.
## The player can be a shark OR any playable creature (see Database.creature_as_player):
## `diet` decides what a bite can eat (creatures, plankton, algae, carrion ...).

signal died(cause: String)

const GRAVITY := 950.0
const HURT_TIME := 0.35
const BITE_TIME := 0.28

var game: Node
var def: Dictionary = {}
var velocity := Vector2.ZERO
var facing_angle := 0.0
var alive := true

var level := 1
var xp := 0.0
var xp_next := 40.0
var length := 70.0
var max_health := 100.0
var health := 100.0
var max_hunger := 100.0
var hunger := 100.0
var max_stamina := 100.0
var stamina := 100.0
var max_speed := 300.0
var accel := 900.0
var boost_mult := 1.6
var bite_dmg := 2.0
var bite_reach := 44.0

var boosting := false
var in_air := false
var stamina_delay := 0.0
var bite_cd := 0.0
var bite_anim := 0.0
var stun_time := 0.0
var poison_time := 0.0
var invuln := 0.0
var hurt_flash := 0.0
var combo := 0
var combo_timer := 0.0
var frenzy := 0.0
var frenzy_time := 0.0
var anim_t := 0.0
var swim_clock := 0.0

# --- species (shark or any creature)
var species_id := ""
var diet := "any"             # any (sharks) carnivore omnivore herbivore plankton filter scavenger
var prey_ratio := 99.0        # largest prey length as a multiple of our own length
var eats: Array = []
var shape_name := "shark"
var upright := false
var heading := 1.0
var ram_dmg := 0.0            # passive body traits: touching creatures hurts them
var thorn_dmg := 0.0
var ram_stun := 0.0
var _food_acc := 0.0

var _col := Color.WHITE
var _belly := Color.WHITE
var _bubbles: CPUParticles2D
var _sprites: SpriteSet = null


func setup(p_def: Dictionary) -> void:
	def = p_def
	_col = Color(str(def["color"]))
	_belly = Color(str(def["belly"]))
	species_id = str(def.get("species_id", def["id"]))
	diet = str(def.get("diet", "any"))
	prey_ratio = float(def.get("prey_ratio", 99.0))
	eats = def.get("eats", [])
	shape_name = str(def.get("shape", "shark"))
	upright = CreatureArt.is_upright(shape_name)
	ram_dmg = float(def.get("contact_damage", 0.0))
	thorn_dmg = float(def.get("thorns", 0.0))
	ram_stun = float(def.get("stun", 0.0))
	var kind := str(def.get("_kind", "sharks"))
	_sprites = SpriteSet.for_def(kind, def)
	if _sprites != null:
		_sprites.apply_filter(self)
	recalc(true)


func recalc(fill: bool = false) -> void:
	var lv := float(level - 1)
	length = float(def["length"]) * (1.0 + 0.10 * lv)
	max_health = float(def["max_health"]) * (1.0 + 0.10 * lv) * (1.0 + Database.upgrade_bonus("max_health"))
	max_hunger = float(def["max_hunger"]) * (1.0 + Database.upgrade_bonus("max_hunger"))
	max_stamina = float(def["stamina"]) * (1.0 + Database.upgrade_bonus("stamina"))
	# The camera keeps the player the same size on screen, so a bigger body must also swim faster in
	# world units, or growing would feel like slowing down. 70 px is the reference (starter shark).
	var size_k := pow(length / 70.0, 0.55)
	if length > 300.0:
		size_k *= pow(length / 300.0, 0.5)            # giants: a blue whale should still cross the map
	max_speed = float(def["speed"]) * size_k * (1.0 + Database.upgrade_bonus("speed"))
	accel = float(def["accel"]) * size_k
	boost_mult = float(def["boost_mult"])
	bite_dmg = float(def["bite_damage"]) * (1.0 + 0.12 * lv) * (1.0 + Database.upgrade_bonus("bite_damage"))
	bite_reach = float(def["bite_range"]) * (length / float(def["length"]))
	if fill:
		health = max_health
		hunger = max_hunger
		stamina = max_stamina


func _ready() -> void:
	_bubbles = CPUParticles2D.new()
	_bubbles.amount = 14
	_bubbles.lifetime = 1.3
	_bubbles.local_coords = false
	_bubbles.texture = CreatureArt.soft_dot()
	_bubbles.direction = Vector2.UP
	_bubbles.spread = 60.0
	_bubbles.gravity = Vector2(0, -50)
	_bubbles.initial_velocity_min = 8.0
	_bubbles.initial_velocity_max = 28.0
	_bubbles.scale_amount_min = 0.15
	_bubbles.scale_amount_max = 0.4
	_bubbles.color = Color(1, 1, 1, 0.55)
	_bubbles.position = Vector2(-length * 0.35, 0)
	_bubbles.emitting = false
	_bubbles.show_behind_parent = true
	add_child(_bubbles)


func combo_mult() -> float:
	return minf(1.0 + 0.2 * float(combo - 1), 5.0) if combo > 0 else 1.0


func gain_xp(amount: float) -> void:
	xp += amount
	while xp >= xp_next:
		xp -= xp_next
		level += 1
		xp_next = 40.0 * float(level) * 1.25
		recalc()
		health = minf(max_health, health + max_health * 0.30)
		game.on_level_up(level)


func _physics_process(delta: float) -> void:
	anim_t += delta
	swim_clock += delta * (1.8 if boosting else 1.0)
	if not alive:
		velocity = velocity.move_toward(Vector2(0, -30), 200.0 * delta)
		position += velocity * delta
		facing_angle = lerp_angle(facing_angle, PI, 1.0 - exp(-3.0 * delta))
		rotation = facing_angle
		scale = Vector2.ONE
		queue_redraw()
		return
	_timers(delta)
	_move(delta, _input_dir())
	_survival(delta)
	_bite()
	queue_redraw()


func _timers(delta: float) -> void:
	bite_cd = maxf(bite_cd - delta, 0.0)
	bite_anim = maxf(bite_anim - delta, 0.0)
	stun_time = maxf(stun_time - delta, 0.0)
	poison_time = maxf(poison_time - delta, 0.0)
	invuln = maxf(invuln - delta, 0.0)
	hurt_flash = maxf(hurt_flash - delta, 0.0)
	if combo_timer > 0.0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			combo = 0
	if frenzy_time > 0.0:
		frenzy_time -= delta
	else:
		frenzy = maxf(frenzy - 0.025 * delta, 0.0)
	modulate = Color(0.7, 1.0, 0.7) if poison_time > 0.0 else Color.WHITE
	modulate.a = 0.55 if (invuln > 0.0 and int(anim_t * 20.0) % 2 == 0) else 1.0


func _input_dir() -> Vector2:
	var v := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if v.length() > 0.1:
		return v
	if bool(Save.setting("mouse_steer")):
		var vp := get_viewport()
		var d := vp.get_mouse_position() - (vp.get_canvas_transform() * global_position)
		var dead := 40.0
		if d.length() > dead:
			return d.normalized() * clampf((d.length() - dead) / 200.0, 0.15, 1.0)
	return Vector2.ZERO


func _move(delta: float, dir_in: Vector2) -> void:
	var dir := dir_in
	var stunned := stun_time > 0.0
	if stunned:
		dir = Vector2.ZERO
	boosting = Input.is_action_pressed("boost") and stamina > 4.0 and not stunned and (dir.length() > 0.1 or velocity.length() > 80.0)
	var spd := max_speed * (1.25 if frenzy_time > 0.0 else 1.0)
	if boosting:
		spd *= boost_mult
		stamina -= (35.0 if frenzy_time <= 0.0 else 12.0) * delta
		stamina_delay = 0.8
	else:
		stamina_delay -= delta
		if stamina_delay <= 0.0:
			stamina = minf(stamina + 22.0 * delta, max_stamina)

	# Don't flicker across the surface unless moving up fast enough to leap
	if position.y < 0.0 and not in_air and velocity.y > -170.0:
		position.y = 0.0
		velocity.y = maxf(velocity.y, 0.0)

	if position.y < 0.0:
		if not in_air:
			in_air = true
			velocity.y *= 1.3
			game.splash(Vector2(position.x, 0.0))
		velocity.y += GRAVITY * delta
		velocity.x = move_toward(velocity.x, dir.x * spd * 0.7, 260.0 * delta)
	else:
		if in_air:
			in_air = false
			velocity.y *= 0.6
			game.splash(Vector2(position.x, 0.0))
			game.shake(4.0)
		var a := accel * (0.35 if stunned else 1.0)
		if dir.length() > 0.05:
			velocity = velocity.move_toward(dir * spd, a * delta)
		else:
			velocity = velocity.move_toward(Vector2.ZERO, a * 0.55 * delta)

	# Terrain collision (any painted Terrain tile is solid), axis-separated
	var r := length * 0.22
	if game.is_solid(position, r):
		position.y -= 200.0 * delta
	var step := velocity * delta
	var np := position + Vector2(step.x, 0.0)
	if game.is_solid(np, r):
		velocity.x *= -0.25
	else:
		position.x = np.x
	np = position + Vector2(0.0, step.y)
	if game.is_solid(np, r):
		velocity.y *= -0.25
	else:
		position.y = np.y
	position.x = clampf(position.x, 40.0, game.world_w - 40.0)
	if position.y > game.world_h - 40.0:
		position.y = game.world_h - 40.0
		velocity.y = 0.0

	var target_angle := facing_angle
	if velocity.length() > 35.0:
		target_angle = velocity.angle()
	facing_angle = lerp_angle(facing_angle, target_angle, 1.0 - exp(-9.0 * delta))
	if absf(velocity.x) > 8.0:
		heading = 1.0 if velocity.x > 0.0 else -1.0
	if upright:
		# jellyfish / crabs stay upright and just turn left or right
		rotation = 0.0
		scale = Vector2(heading, 1.0)
	else:
		rotation = facing_angle
		scale = Vector2(1.0, -1.0 if absf(wrapf(facing_angle, -PI, PI)) > PI * 0.5 else 1.0)
	_bubbles.emitting = (not in_air) and velocity.length() > 80.0
	var ub: float = game.ui_k()
	_bubbles.scale_amount_min = 0.15 * ub
	_bubbles.scale_amount_max = 0.4 * ub
	_bubbles.initial_velocity_min = 8.0 * ub
	_bubbles.initial_velocity_max = 28.0 * ub
	_bubbles.gravity = Vector2(0, -50) * ub


func _check(cause: String) -> void:
	if health <= 0.0 and alive:
		die(cause)


func _survival(delta: float) -> void:
	var drain := float(def["hunger_drain"]) * (1.0 - minf(Database.upgrade_bonus("hunger_efficiency"), 0.7))
	if boosting:
		drain *= 1.6
	hunger = maxf(hunger - drain * delta, 0.0)
	if hunger <= 0.0:
		health -= 7.0 * delta
		_check("Starvation")
	elif hunger > max_hunger * 0.5 and poison_time <= 0.0:
		health = minf(health + 1.2 * delta, max_health)
	if poison_time > 0.0:
		health -= 4.0 * delta
		_check("Poison")
	if not in_air:
		var p := float(Database.biome_at(position.y)["pressure"])
		if p > 0.0:
			var resist := minf(Database.upgrade_bonus("pressure_resist") + float(def.get("innate_pressure_resist", 0.0)), 0.95)
			health -= p * (1.0 - resist) * delta
			_check("Crushing pressure")


func _bite() -> void:
	if not Input.is_action_pressed("bite") or bite_cd > 0.0 or stun_time > 0.0:
		return
	bite_cd = 0.42
	bite_anim = 0.28
	var fwd := Vector2.from_angle(facing_angle)
	velocity += fwd * 240.0
	Sfx.play("bite")
	game.shake(1.5)
	var mouth := global_position + fwd * length * 0.42
	var hit_creature := false
	for cr in game.creatures_in_radius(mouth, bite_reach):
		if _bite_creature(cr):
			hit_creature = true
	# plankton / algae / carrion / marine snow, depending on the diet
	if not hit_creature:
		_bite_food(mouth)


## What can this character sink its teeth into?
func can_eat_creature(cr: Creature) -> bool:
	if cr.dead or not bool(cr.def["edible"]):
		return false
	if cr.behavior == "static":
		return true                                   # treasure chests are for everybody
	if diet == "any":
		return true                                   # sharks: anything, big prey takes more bites
	if cr.id in eats:
		return true
	if not (diet in ["carnivore", "omnivore", "filter"]):
		return false
	if cr.behavior in ["fly", "surface"] and diet == "filter":
		return false
	return cr.length <= length * prey_ratio


func _bite_creature(cr: Creature) -> bool:
	if not can_eat_creature(cr):
		return false
	var ratio := clampf(length / cr.length, 0.3, 1.6)
	var dmg := bite_dmg * ratio * (1.5 if frenzy_time > 0.0 else 1.0)
	var killed := cr.hurt(dmg, global_position)
	if float(cr.def["thorns"]) > 0.0:
		take_damage(float(cr.def["thorns"]), str(cr.def["name"]))
	if float(cr.def["stun"]) > 0.0:
		apply_stun(float(cr.def["stun"]))
	if killed:
		eat(cr)
	return true


func _add_frenzy(amount: float) -> void:
	if frenzy_time > 0.0:
		return
	frenzy += amount
	if frenzy >= 1.0:
		frenzy = 0.0
		frenzy_time = 10.0
		game.on_frenzy()


func _bite_food(mouth: Vector2) -> void:
	var kinds: Array = game.eco.kinds_for(diet)
	if kinds.is_empty():
		return
	var f: Ecosystem.Food = game.eco.in_reach(kinds, mouth, bite_reach)
	if f == null:
		return
	var got: float = game.eco.take(f, clampf(length / 35.0, 1.0, 8.0))
	if got <= 0.0:
		return
	var gain := float(Ecosystem.FOOD_VALUE[f.kind]) * got / maxf(1.0, length / 60.0)
	hunger = minf(hunger + gain, max_hunger)
	health = minf(health + gain * 0.3, max_health)
	_food_acc += got
	var coins := 0
	while _food_acc >= 6.0:
		_food_acc -= 6.0
		coins += 1
	_add_frenzy(0.012 * got)
	gain_xp(got * 0.9)
	Sfx.play("eat")
	game.on_food_eaten(f, int(got * 6.0), coins)


func eat(cr: Creature) -> void:
	var d := cr.def
	hunger = minf(hunger + float(d["hunger"]), max_hunger)
	health = minf(health + float(d["hunger"]) * 0.35, max_health)
	if float(d["poison"]) > 0.0:
		poison_time = maxf(poison_time, float(d["poison"]))
	combo += 1
	combo_timer = 3.2
	var cm := combo_mult()
	var fm := 2.0 if frenzy_time > 0.0 else 1.0
	var sc := int(float(d["score"]) * cm * fm)
	var coins := int(round(float(d["coins"]) * (1.0 + Database.upgrade_bonus("coin_bonus")) * fm))
	_add_frenzy(0.04 + minf(float(d["hunger"]) / 400.0, 0.1))
	gain_xp(float(d["xp"]))
	Sfx.play("eat")
	game.on_eaten(cr, sc, coins, cm)


func apply_stun(t: float) -> void:
	stun_time = maxf(stun_time, t * (1.0 - float(def["stun_resist"])))


func take_damage(amount: float, source: String) -> void:
	if not alive or invuln > 0.0:
		return
	if frenzy_time > 0.0:
		amount *= 0.5
	health -= amount
	invuln = 0.7
	hurt_flash = 0.35
	combo = 0
	combo_timer = 0.0
	game.shake(clampf(amount * 0.5, 3.0, 14.0))
	game.floating_text(global_position + Vector2(0, -length * 0.5), "-%d" % int(amount), Color("#ff6b5e"))
	Sfx.play("hurt")
	_check(source)


func hit_by(cr: Creature, dmg: float) -> void:
	if invuln > 0.0 or not alive:
		return
	take_damage(dmg, str(cr.def["name"]))
	var st := float(cr.def["stun"])
	if st > 0.0:
		apply_stun(st)
	if thorn_dmg > 0.0:
		cr.hurt(thorn_dmg, global_position)       # spines hurt whatever bit us
	velocity += (global_position - cr.global_position).normalized() * 320.0


func die(cause: String) -> void:
	alive = false
	health = 0.0
	_bubbles.emitting = false
	game.shake(16.0)
	Sfx.play("hurt")
	died.emit(cause)


func _draw() -> void:
	var col := _col
	if hurt_flash > 0.0 and int(anim_t * 30.0) % 2 == 0:
		col = col.lerp(Color.RED, 0.6)
	if frenzy_time > 0.0:
		draw_circle(Vector2.ZERO, length * 0.7, Color(1.0, 0.75, 0.2, 0.10 + 0.05 * sin(anim_t * 12.0)))
	var open := 0.0
	if bite_anim > 0.0:
		open = sin(PI * (1.0 - bite_anim / 0.28))
	if stun_time > 0.0:
		for i in 3:
			draw_line(Vector2(randf_range(-length * 0.4, length * 0.4), -length * 0.2), Vector2(randf_range(-length * 0.4, length * 0.4), length * 0.2), Color(1, 1, 0.4), 2.0)
	if _sprites != null:
		_draw_sprite()
		return
	var squash := open if shape_name != "shark" else 0.0
	if squash > 0.0:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0 + 0.14 * squash, 1.0 - 0.08 * squash))
	CreatureArt.draw(self, shape_name, length, col, _belly, anim_t * (1.8 if boosting else 1.0), open)
	if squash > 0.0:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Artist sprite path: hurt > attack(bite) > boost > idle > swim.
func _draw_sprite() -> void:
	var anim := "swim"
	var t := swim_clock
	var loop := true
	if hurt_flash > 0.0 and _sprites.has_anim("hurt"):
		anim = "hurt"
		t = _sprites.progress_time("hurt", 1.0 - hurt_flash / HURT_TIME)
		loop = false
	elif bite_anim > 0.0 and _sprites.has_anim("attack"):
		anim = "attack"
		t = _sprites.progress_time("attack", 1.0 - bite_anim / BITE_TIME)
		loop = false
	elif boosting and _sprites.has_anim("boost"):
		anim = "boost"
	elif velocity.length() < 40.0 and _sprites.has_anim("idle"):
		anim = "idle"
	var tint := Color.WHITE
	if hurt_flash > 0.0 and int(anim_t * 30.0) % 2 == 0:
		tint = Color(1.0, 0.55, 0.55)
	_sprites.draw(self, length, t, anim, loop, true, tint)
