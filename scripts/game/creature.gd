class_name Creature
extends Node2D
## One living creature. All stats come from its database entry (`def`).
##
## Every creature runs a small life-routine brain instead of just wandering:
##   needs      hunger and energy that rise/fall over time
##   day/night  diurnal / nocturnal / crepuscular species sleep or feed on a schedule
##   feeding    carnivores hunt prey, grazers eat algae, filter feeders work plankton clouds,
##              scavengers clean up carrion and marine snow
##   danger     flee from anything that can eat them, schools bolt together (alarm calls)
##   home       reef fish shelter and defend a patch, ambushers lurk in a den,
##              open-water fish keep a home range and shift it when food runs out
##   quirks     vertical migration, dolphins leaping, seagulls diving for fish,
##              curious animals circling the player, boats anchoring at night
## `behavior` in the database still selects the body style (school, hunter, ambush, drift,
## bottom, static, fly, surface, shooter); `diet`, `activity`, ... drive the life routine.

const HURT_TIME := 0.25
const GRAVITY := 950.0
const HUNGRY := 0.55

var def: Dictionary = {}
var game: Node
var id := ""
var hp := 1.0
var max_hp := 1.0
var length := 20.0
var velocity := Vector2.ZERO
var heading := 1.0
var tilt := 0.0
var stun := 0.0
var flee_timer := 0.0
var flee_from := Vector2.ZERO
var contact_cd := 0.0
var ram_cd := 0.0
var shoot_cd := 2.0
var hurt_flash := 0.0
var dead := false
var leader: Creature = null
var follow_offset := Vector2.ZERO
var state := "idle"            # ambush sub-state: idle / lunge / rest
var state_timer := 0.0
var lunge_dir := Vector2.RIGHT
var phase := 0.0
var home_y := 0.0
var base_speed := 80.0
var color := Color.WHITE
var accent := Color.WHITE
var shape := "fish"
var behavior := "wander"
var upright := false
var sprites: SpriteSet = null
var wiggle := false
var attack_timer := 0.0

# ---- life routine
var diet := "none"
var activity := "any"
var rest_style := "open"
var prey_ratio := 0.5
var eats: Array = []
var territorial := false
var migrates := false
var leaps := false
var curious := false
var food_kinds: Array = []

var hunger := 0.4              # 0 = full, 1 = starving
var hunger_rate := 0.007
var energy := 1.0
var sprinting := false
var act_bias := 0.0
var mode := "roam"             # roam rest flee hunt forage graze defend curious leap school dive climb sail fish walk idle
var mode_timer := 0.0
var sleeping := false
var home := Vector2.ZERO
var home_r := 350.0
var rest_pos := Vector2.ZERO
var roam_target := Vector2.ZERO
var roam_hold := 0.0
var roam_kind := "swim"
var target: Creature = null
var target_food: Ecosystem.Food = null
var hunt_time := 0.0
var hunt_cd := 0.0
var eat_cd := 0.0
var strike_cd := 0.0
var shoo_cd := 0.0
var chew := 0.0
var perceive_cd := 0.0
var p_threat: Creature = null
var p_prey: Creature = null
var p_intruder: Creature = null
var p_food: Ecosystem.Food = null
var alarm_timer := 0.0
var alarm_from := Vector2.ZERO
var alarm_cd := 0.0
var curious_cd := 0.0
var leap_cd := 0.0
var airborne := false
var player_hunt := false       # true while chasing the player this frame


func setup(p_def: Dictionary, p_game: Node) -> void:
	def = p_def
	game = p_game
	id = str(def["id"])
	length = float(def["length"]) * randf_range(0.9, 1.15)
	max_hp = float(def["hp"])
	hp = max_hp
	base_speed = float(def["speed"]) * randf_range(0.9, 1.1)
	color = Color(str(def["color"]))
	accent = Color(str(def["accent"]))
	shape = str(def["shape"])
	behavior = str(def["behavior"])
	upright = CreatureArt.is_upright(shape)
	heading = 1.0 if randf() < 0.5 else -1.0
	phase = randf() * TAU
	home_y = position.y
	sprites = SpriteSet.for_def("creatures", def)
	wiggle = not upright and behavior != "static"
	if sprites != null:
		sprites.apply_filter(self)
	# life profile
	diet = str(def["diet"])
	activity = str(def["activity"])
	rest_style = str(def["rest_style"])
	prey_ratio = float(def["prey_ratio"])
	eats = def["eats"]
	territorial = bool(def["territorial"])
	migrates = bool(def["migrates"])
	leaps = bool(def["leaps"])
	curious = "curious" in def["tags"]
	food_kinds = game.eco.kinds_for(diet)
	hunger = randf_range(0.15, 0.75)
	hunger_rate = 1.0 / randf_range(120.0, 190.0) * (0.6 if diet == "scavenger" else 1.0)
	energy = randf_range(0.6, 1.0)
	act_bias = randf_range(-0.12, 0.12)
	home_r = 300.0 + length * 0.8
	state_timer = randf_range(0.5, 2.0)
	leap_cd = randf_range(10.0, 40.0)
	curious_cd = randf_range(5.0, 20.0)
	home = _find_home()
	roam_target = position
	add_to_group("creatures")


func remove() -> void:
	dead = true
	remove_from_group("creatures")
	queue_free()


## Returns true if this hit killed the creature.
func hurt(dmg: float, from_pos: Vector2, _attacker: Creature = null) -> bool:
	hp -= dmg
	hurt_flash = HURT_TIME
	var away := (global_position - from_pos).normalized()
	velocity += away * 260.0 / maxf(1.0, length / 60.0)
	stun = maxf(stun, 0.25)
	sleeping = false
	if not (behavior in ["hunter", "ambush", "static", "surface"]):
		flee_timer = 3.0
		flee_from = from_pos
		if alarm_cd <= 0.0:
			alarm_cd = 0.8
			game.eco.raise_alarm(global_position, id, from_pos)
	return hp <= 0.0


## Somebody bigger told us to get lost (territory defence).
func receive_threat(from_pos: Vector2, seconds: float) -> void:
	if behavior in ["hunter", "ambush", "static", "surface"]:
		return
	flee_timer = maxf(flee_timer, seconds)
	flee_from = from_pos
	sleeping = false


# ---------------------------------------------------------------- relationships
## Could this creature eat `o`? (food chain: size, diet, explicit "eats" list)
func can_eat(o: Creature) -> bool:
	if o == self or o.dead or o.id == id or not bool(o.def["edible"]):
		return false
	if o.id in eats:
		return true
	if not (diet in ["carnivore", "omnivore", "filter"]):
		return false
	if o.behavior in ["static", "fly", "surface"]:
		return false
	if float(o.def["thorns"]) > 0.0 or float(o.def["poison"]) > 0.0:
		return false
	return o.length <= length * prey_ratio


func can_eat_player(s: Shark) -> bool:
	if not s.alive:
		return false
	if s.species_id in eats:
		return true
	if not (diet in ["carnivore", "omnivore"]):
		return false
	return s.length <= length * prey_ratio


## Damage this creature deals to the player on touching it (0 = harmless).
func attack_damage_vs(s: Shark) -> float:
	var cd := float(def["contact_damage"])
	if cd > 0.0:
		return cd                                   # hazards hurt on touch
	if player_hunt and can_eat_player(s):
		return maxf(4.0, length * 0.12)             # a predator's bite
	return 0.0


func fear_range_for(o: Creature) -> float:
	var r := clampf(150.0 + length * 0.55, 180.0, 460.0)
	if mode == "hunt" and target == o:
		r *= 1.3
	return r


func _sight() -> float:
	return clampf(320.0 + length * 1.2, 320.0, 900.0) * (0.5 if sleeping else 1.0)


func _is_active() -> bool:
	if diet != "none" and hunger > 0.93:
		return true
	return game.eco.activity_level(activity) + act_bias > 0.38


func _wants_prey() -> bool:
	return (diet in ["carnivore", "omnivore", "filter"] or not eats.is_empty()) \
		and hunger > HUNGRY and eat_cd <= 0.0 and hunt_cd <= 0.0 and _is_active()


# ---------------------------------------------------------------- main loop
func _physics_process(delta: float) -> void:
	if dead or game == null:
		return
	phase += delta * (0.25 if sleeping else 1.0)
	contact_cd = maxf(contact_cd - delta, 0.0)
	ram_cd = maxf(ram_cd - delta, 0.0)
	flee_timer = maxf(flee_timer - delta, 0.0)
	stun = maxf(stun - delta, 0.0)
	hurt_flash = maxf(hurt_flash - delta, 0.0)
	attack_timer = maxf(attack_timer - delta, 0.0)
	alarm_timer = maxf(alarm_timer - delta, 0.0)
	alarm_cd = maxf(alarm_cd - delta, 0.0)
	hunt_cd = maxf(hunt_cd - delta, 0.0)
	eat_cd = maxf(eat_cd - delta, 0.0)
	strike_cd = maxf(strike_cd - delta, 0.0)
	shoo_cd = maxf(shoo_cd - delta, 0.0)
	curious_cd = maxf(curious_cd - delta, 0.0)
	leap_cd = maxf(leap_cd - delta, 0.0)
	mode_timer -= delta
	sprinting = false
	player_hunt = false
	if airborne:
		_air(delta)
		_update_visual(delta)
		return
	var desired := Vector2.ZERO
	if stun <= 0.0:
		desired = _think(delta)
	var accel := base_speed * 3.0 / maxf(1.0, length / 120.0)
	velocity = velocity.move_toward(desired, accel * delta)
	position += velocity * delta
	_tick_needs(delta)
	_check_strike()
	_constrain(delta)
	_update_visual(delta)


func _tick_needs(delta: float) -> void:
	if diet != "none":
		hunger = minf(hunger + hunger_rate * delta * (0.4 if sleeping else 1.0), 1.0)
	if sleeping:
		energy = minf(energy + delta / 6.0, 1.0)
	elif sprinting:
		energy = maxf(energy - delta / 13.0, 0.0)
	else:
		energy = minf(energy + delta / 20.0, 1.0)


func _set_mode(m: String) -> void:
	if mode == m:
		return
	mode = m
	if m == "hunt" or m == "dive":
		hunt_time = 0.0
	if m == "rest":
		rest_pos = position if rest_style == "open" else home
	elif sleeping and m != "school":
		sleeping = false


func _think(delta: float) -> Vector2:
	if behavior == "static":
		return Vector2.ZERO
	var shark: Shark = game.shark
	var to_p := shark.global_position - global_position
	var dist := to_p.length()
	_perceive(delta, shark)
	match behavior:
		"fly": return _brain_bird(delta, shark, to_p, dist)
		"surface": return _brain_boat(delta)
		"bottom": return _brain_bottom(delta, shark, to_p, dist)
	return _brain_fish(delta, shark, to_p, dist)


# ---------------------------------------------------------------- perception
func _perceive(delta: float, _shark: Shark) -> void:
	perceive_cd -= delta
	if perceive_cd > 0.0:
		return
	perceive_cd = randf_range(0.25, 0.4)
	var sight := _sight()
	var want_prey := _wants_prey()
	var threat: Creature = null
	var td := INF
	var prey: Creature = null
	var pd := INF
	var intruder: Creature = null
	var idist := INF
	var cand_leader: Creature = null
	for node in game.creatures_root.get_children():
		var o := node as Creature
		if o == null or o == self or o.dead:
			continue
		var d := position.distance_to(o.position)
		if d > sight:
			continue
		if d < td and o.can_eat(self) and (o.hunger > 0.5 or o.mode == "hunt" or d < 90.0):
			td = d
			threat = o
		if want_prey and d < pd and can_eat(o):
			if not (behavior == "fly" and o.position.y > 60.0):
				pd = d
				prey = o
		if territorial and d < idist and d < home_r + 80.0 and o.id != id and o.length <= length * 1.4 \
				and not (o.behavior in ["static", "fly", "surface", "bottom"]) and not o.can_eat(self):
			idist = d
			intruder = o
		if behavior == "school" and leader == null and o.id == id and o.leader == null \
				and o.get_instance_id() < get_instance_id() and d < 420.0:
			cand_leader = o
	p_threat = threat
	p_prey = prey
	p_intruder = intruder
	if cand_leader != null:
		leader = cand_leader
		follow_offset = Vector2(randf_range(-70.0, 70.0), randf_range(-45.0, 45.0))
	p_food = null
	if diet != "none" and hunger > HUNGRY - 0.05 and not food_kinds.is_empty():
		p_food = game.eco.nearest(food_kinds, position, sight * 1.15)
		if p_food != null and behavior == "bottom":
			var fy: float = game.world.floor_y_at(position.x)
			if p_food.pos.y < fy - 140.0:
				p_food = null


func _find_home() -> Vector2:
	var lo := maxf(float(def["min_depth"]), 40.0)
	var hi := minf(float(def["max_depth"]), game.world_h - 80.0)
	if rest_style != "open":
		var best := Vector2.ZERO
		var best_d := 1400.0 * 1400.0
		var found := false
		for f in game.eco.algae:
			if f.pos.y < lo or f.pos.y > hi:
				continue
			var d := position.distance_squared_to(f.pos)
			if d < best_d:
				best_d = d
				best = f.pos
				found = true
		if found:
			return best + Vector2(randf_range(-20.0, 20.0), -length * (0.3 if rest_style == "reef" else 0.15))
		if rest_style == "floor":
			return Vector2(position.x, hi - length * 0.2)
	return position


func _home_now() -> Vector2:
	if migrates:
		var amp := minf(450.0, home.y * 0.5)
		return Vector2(home.x, maxf(60.0, home.y - amp * game.eco.night_amount()))
	return home


func _clamp_pos(p: Vector2) -> Vector2:
	var lo := 50.0 if migrates else maxf(float(def["min_depth"]), 40.0)
	return Vector2(clampf(p.x, 60.0, game.world_w - 60.0), clampf(p.y, lo, minf(float(def["max_depth"]), game.world_h - 80.0)))


# ---------------------------------------------------------------- swimming brain
func _brain_fish(delta: float, shark: Shark, to_p: Vector2, dist: float) -> Vector2:
	var active := _is_active()
	# 1. danger beats everything
	var flee := _danger_vector(shark, to_p, dist)
	if flee != Vector2.ZERO:
		_set_mode("flee")
		sprinting = true
		return flee
	if mode == "flee":
		_set_mode("roam")
		roam_hold = 0.0
	# 2. ambushers finish their lunge / cool-down
	if behavior == "ambush" and state != "idle":
		return _ambush_state(delta)
	# 3. schooling followers do what their leader does
	if leader != null:
		if not is_instance_valid(leader) or leader.dead:
			leader = null
		else:
			return _follower(delta)
	# 4. divers shoot
	if behavior == "shooter":
		var fire := _shooter_fire(delta, shark, to_p, dist)
		if fire != Vector2.ZERO:
			return fire
	# 5. go for the player when it is prey / a rival
	var chase := _player_chase(shark, to_p, dist, active)
	if chase != Vector2.ZERO:
		return chase
	if mode == "hunt" and target == null:
		_set_mode("roam")
	# 6. night / siesta
	if not active:
		return _rest(delta)
	if sleeping:
		sleeping = false
		_set_mode("roam")
	# 7. dolphin acrobatics
	if leaps and mode != "leap" and leap_cd <= 0.0 and position.y < 800.0 and hunger < 0.6:
		_set_mode("leap")
		mode_timer = 9.0
		leap_cd = randf_range(35.0, 80.0)
	if mode == "leap":
		return _leap()
	# 8. hunting
	if mode != "hunt" and p_prey != null and is_instance_valid(p_prey) and _wants_prey():
		if position.distance_to(p_prey.position) < _sight() * 0.7 or p_food == null:
			target = p_prey
			_set_mode("hunt")
	if mode == "hunt" and target != null:
		return _hunt(delta)
	# 9. feeding
	if p_food != null and hunger > HUNGRY - 0.05 and mode != "graze" and mode != "forage":
		target_food = p_food
		_set_mode("forage")
	if (mode == "forage" or mode == "graze"):
		return _forage(delta)
	# 10. defend the territory
	if territorial and p_intruder != null and is_instance_valid(p_intruder) and shoo_cd <= 0.0:
		var di := p_intruder.position - position
		if di.length() < length * 0.5 + p_intruder.length * 0.4 + 10.0:
			p_intruder.receive_threat(global_position, 2.5)
			shoo_cd = randf_range(4.0, 7.0)
			attack_timer = 0.25
		else:
			_set_mode("defend")
			sprinting = true
			return di.normalized() * base_speed * 1.25
	if mode == "defend":
		_set_mode("roam")
	# 11. a look at the player
	if curious and curious_cd <= 0.0 and mode == "roam" and shark.alive and dist > 240.0 and dist < 650.0 \
			and hunger < HUNGRY:
		_set_mode("curious")
		mode_timer = randf_range(5.0, 9.0)
		curious_cd = randf_range(25.0, 50.0)
	if mode == "curious":
		if mode_timer <= 0.0 or not shark.alive:
			_set_mode("roam")
		else:
			var orbit := shark.global_position + Vector2.from_angle(phase * 0.5 + float(get_instance_id() % 7)) * (150.0 + length * 0.6)
			return _steer(orbit, 0.8)
	# 12. just live in the home range
	return _roam(delta)


## Combined escape direction from the player, predators, alarm calls and recent damage.
func _danger_vector(shark: Shark, to_p: Vector2, dist: float) -> Vector2:
	var away := Vector2.ZERO
	var wake := 0.45 if sleeping else 1.0
	var real := false              # a real threat (not just a neighbour's alarm call)
	if flee_timer > 0.0:
		away += (global_position - flee_from).normalized()
		real = true
	if _player_scare(shark, dist, wake):
		away += (-to_p).normalized() * 1.2
		real = true
	if p_threat != null and is_instance_valid(p_threat) and not p_threat.dead:
		var td := global_position.distance_to(p_threat.global_position)
		var fr := p_threat.fear_range_for(self) * wake
		if p_threat.mode != "hunt":
			fr *= 0.55             # an idle predator is not worth panicking about
		if td < fr:
			away += (global_position - p_threat.global_position).normalized() * 1.4
			real = true
	if alarm_timer > 0.0 and not sleeping:
		away += (global_position - alarm_from).normalized()
	if away == Vector2.ZERO:
		return Vector2.ZERO
	sleeping = false
	var dir := away.normalized()
	if real and alarm_cd <= 0.0 and behavior == "school":
		alarm_cd = 0.8
		game.eco.raise_alarm(global_position, id, global_position - dir * 160.0)
	var perp := Vector2(-dir.y, dir.x) * sin(phase * 6.0 + float(get_instance_id() % 13)) * 0.35
	var v := (dir + perp).normalized()
	if behavior == "bottom":
		v = Vector2(1.0 if dir.x >= 0.0 else -1.0, 0.0)
	return v * base_speed * (1.65 if energy > 0.15 else 1.1)


func _player_scare(shark: Shark, dist: float, wake: float) -> bool:
	if not shark.alive:
		return false
	var fr := float(def["flee_range"])
	if shark.diet == "any":
		return fr > 0.0 and dist < fr * wake and shark.length > length * 0.6
	if shark.can_eat_creature(self):
		return dist < maxf(fr, 200.0) * wake
	return false


## Chasing the player: legacy aggro hunters, plus any predator that can eat the player.
func _player_chase(shark: Shark, to_p: Vector2, dist: float, active: bool) -> Vector2:
	if not shark.alive:
		return Vector2.ZERO
	var go := false
	var aggro := float(def["aggro_range"])
	if aggro > 0.0 and behavior in ["hunter", "ambush"]:
		var ratio := 1.5 if behavior == "ambush" else 1.4
		go = dist < aggro * (0.45 if sleeping else 1.0) and shark.length < length * ratio
	elif active and can_eat_player(shark) and (hunger > 0.45 or dist < 140.0) and dist < _sight() * 0.8:
		go = true
	if not go:
		return Vector2.ZERO
	sleeping = false
	_set_mode("hunt")
	target = null
	player_hunt = true
	if behavior == "ambush":
		_start_lunge(to_p.normalized())
		return lunge_dir * base_speed * 3.0
	var boost := 1.0 + clampf(1.0 - dist / maxf(aggro, 400.0), 0.0, 1.0) * 0.5
	attack_timer = 0.2
	sprinting = dist < 300.0
	return to_p.normalized() * base_speed * boost


func _start_lunge(dir: Vector2) -> void:
	state = "lunge"
	state_timer = 0.9
	lunge_dir = dir
	attack_timer = 0.9


func _ambush_state(delta: float) -> Vector2:
	state_timer -= delta
	match state:
		"lunge":
			if state_timer <= 0.0:
				state = "rest"
				state_timer = 2.2
			return lunge_dir * base_speed * 3.0
		"rest":
			if state_timer <= 0.0:
				state = "idle"
			return Vector2.ZERO
	return Vector2.ZERO


func _hunt(delta: float) -> Vector2:
	hunt_time += delta
	if target == null or not is_instance_valid(target) or target.dead or not can_eat(target) \
			or hunt_time > 10.0 or energy < 0.08:
		_end_hunt(true)
		return Vector2.ZERO
	var d := target.position - position
	var dist := d.length()
	if dist > _sight() * 1.4:
		_end_hunt(true)
		return Vector2.ZERO
	if behavior == "ambush":
		if state == "idle" and dist < maxf(float(def["aggro_range"]), 260.0):
			_start_lunge(d.normalized())
			return lunge_dir * base_speed * 3.0
		return d.normalized() * base_speed * 0.35        # creeping closer
	var close := dist < 260.0
	sprinting = close
	if close:
		attack_timer = 0.2
	var spd := base_speed * (1.65 if close else 0.85)
	var lead := target.velocity * clampf(dist / maxf(spd, 1.0), 0.0, 0.8)
	return (d + lead).normalized() * spd


func _end_hunt(failed: bool) -> void:
	if failed:
		hunt_cd = randf_range(5.0, 10.0)
	target = null
	_set_mode("roam")
	roam_hold = 0.0
	if behavior == "ambush":
		state = "idle"


func _check_strike() -> void:
	if strike_cd > 0.0 or target == null or not is_instance_valid(target) or target.dead:
		return
	if mode != "hunt" and mode != "dive":
		return
	var reach := length * 0.45 + target.length * 0.35
	if global_position.distance_to(target.global_position) <= reach:
		_strike(target)


func _strike(t: Creature) -> void:
	strike_cd = 0.7
	attack_timer = 0.3
	if t.hurt(maxf(1.0, length / 28.0), global_position, self):
		_on_kill(t)


func _on_kill(t: Creature) -> void:
	hunger = maxf(0.0, hunger - clampf(t.length / length * 1.8, 0.25, 1.0))
	eat_cd = randf_range(10.0, 20.0)
	energy = maxf(energy - 0.1, 0.0)
	target = null
	game.on_predation(self, t)
	if behavior == "fly":
		_set_mode("climb")
		mode_timer = 1.4
	else:
		_set_mode("roam")
		roam_hold = 0.0
	if behavior == "ambush":
		state = "rest"
		state_timer = 2.0


func _forage(delta: float) -> Vector2:
	var f := target_food
	if f == null or f.amount < 1.0 or hunger < 0.12:
		target_food = null
		_set_mode("roam")
		roam_hold = 0.0
		return Vector2.ZERO
	var d := f.pos - global_position
	var dist := d.length()
	if dist > length * 0.4 + f.radius * 0.5 + 8.0:
		_set_mode("forage")
		return _steer(f.pos, 0.8)
	_set_mode("graze")
	chew -= delta
	if chew <= 0.0:
		chew = randf_range(0.45, 0.8)
		attack_timer = 0.15
		var got: float = game.eco.take(f, clampf(length / 40.0, 1.0, 8.0))
		hunger = maxf(0.0, hunger - float(Ecosystem.FOOD_VALUE[f.kind]) / 100.0 * got / maxf(1.0, length / 60.0) * 1.8)
	return Vector2(sin(phase * 3.0) * base_speed * 0.12, cos(phase * 2.0) * base_speed * 0.08) + d.normalized() * 6.0


func _rest(delta: float) -> Vector2:
	_set_mode("rest")
	var d := rest_pos - position
	if d.length() > 22.0 and not (sleeping and d.length() < 60.0):
		sleeping = false
		return d.normalized() * base_speed * clampf(d.length() / 80.0, 0.25, 0.6)
	sleeping = true
	return Vector2(0.0, sin(phase * 0.8) * 3.0)


func _follower(delta: float) -> Vector2:
	var lead := leader
	var off := follow_offset + Vector2(sin(phase * 0.7 + follow_offset.x), cos(phase * 0.5 + follow_offset.y)) * 14.0
	var d := lead.global_position + off - global_position
	if lead.mode == "rest" or lead.sleeping:
		_set_mode("rest")
		if d.length() < 18.0:
			sleeping = true
			return Vector2(0.0, sin(phase * 0.8) * 3.0)
		sleeping = false
		return d.normalized() * base_speed * 0.4
	sleeping = false
	if lead.mode == "graze" and d.length() < 170.0:
		hunger = maxf(0.0, hunger - delta * 0.05)
		_set_mode("graze")
	else:
		_set_mode("school")
	if d.length() < 8.0:
		return Vector2.ZERO
	return d.normalized() * base_speed * clampf(d.length() / 40.0, 0.35, 1.6)


func _shooter_fire(delta: float, shark: Shark, to_p: Vector2, dist: float) -> Vector2:
	shoot_cd -= delta
	var aggro := float(def["aggro_range"])
	if shark.alive and dist < aggro and not sleeping:
		if shoot_cd <= 0.0:
			shoot_cd = 2.5
			attack_timer = 0.5
			game.spawn_projectile(global_position, to_p.normalized(), float(def["projectile_damage"]))
		if dist < aggro * 0.4:
			return -to_p.normalized() * base_speed
	return Vector2.ZERO


## Dolphin jump: swim up, break the surface, arc through the air, splash down.
func _leap() -> Vector2:
	if mode_timer <= 0.0:
		_set_mode("roam")
		return Vector2.ZERO
	if position.y < 62.0 and velocity.y < -40.0:
		airborne = true
		velocity = Vector2(heading * base_speed * 1.3, -620.0)
		game.splash(Vector2(position.x, 0.0))
		return Vector2.ZERO
	sprinting = true
	return Vector2(heading * base_speed * 0.5, -base_speed * 2.4)


func _air(delta: float) -> void:
	velocity.y += GRAVITY * delta
	position += velocity * delta
	if position.y > 0.0 and velocity.y > 0.0:
		airborne = false
		velocity.y *= 0.4
		game.splash(Vector2(position.x, 0.0))
		_set_mode("roam")
		roam_hold = 0.0


## Go to a point, slowing down on arrival. Jellyfish pulse instead of gliding.
func _steer(target_pos: Vector2, mult: float) -> Vector2:
	var d := target_pos - global_position
	var l := d.length()
	if l < 4.0:
		return Vector2.ZERO
	var s := base_speed * mult * clampf(l / 60.0, 0.3, 1.0)
	if behavior == "drift":
		s *= 0.25 + 0.75 * pow(maxf(sin(phase * 2.0), 0.0), 1.5)
	return d / l * s


func _roam(delta: float) -> Vector2:
	if mode != "roam":
		_set_mode("roam")
		roam_hold = 0.0
	roam_hold -= delta
	var hp_now := _home_now()
	# ambushers lurk in their den and relocate now and then
	if behavior == "ambush":
		if roam_hold <= 0.0:
			roam_hold = randf_range(30.0, 60.0)
			home = _clamp_pos(position + Vector2(randf_range(-600.0, 600.0), randf_range(-250.0, 250.0)))
		if position.distance_to(hp_now) > 30.0:
			return _steer(hp_now, 0.5)
		return Vector2(0.0, sin(phase * 1.5) * 6.0)
	if roam_hold <= 0.0 or (roam_kind == "swim" and position.distance_to(roam_target) < 24.0):
		_pick_roam(hp_now)
	if roam_kind == "hover":
		return Vector2(sin(phase * 0.9) * base_speed * 0.12, cos(phase * 0.7) * base_speed * 0.1)
	if behavior == "drift":
		return _steer(roam_target, 0.6) + Vector2(0.0, sin(phase * 1.2) * base_speed * 0.25)
	return _steer(roam_target, 0.6)


func _pick_roam(hp_now: Vector2) -> void:
	var r := home_r
	var roll := randf()
	var starving := hunger > 0.7 and not food_kinds.is_empty()
	if starving:
		# no food around: search a wider area and move house
		r *= 2.5
		home = _clamp_pos(position + Vector2(randf_range(-r, r), randf_range(-r * 0.4, r * 0.4)))
		hp_now = home
	elif roll < 0.22:
		roam_kind = "hover"
		roam_hold = randf_range(2.0, 5.0)
		return
	if behavior == "hunter":
		r *= 1.8
	if territorial or rest_style != "open":
		r = minf(r, 300.0)
	roam_kind = "swim"
	roam_hold = randf_range(4.0, 9.0)
	if roll < 0.5 and not starving and diet != "none":
		# visit something interesting: a food patch (reef fish browse coral)
		var kinds: Array = food_kinds if not food_kinds.is_empty() else ["plankton"]
		var f: Ecosystem.Food = game.eco.nearest(kinds, position, 600.0)
		if f != null:
			roam_target = _clamp_pos(f.pos + Vector2(randf_range(-40.0, 40.0), randf_range(-40.0, 10.0)))
			return
	roam_target = _clamp_pos(hp_now + Vector2(randf_range(-r, r), randf_range(-r * 0.5, r * 0.5)))
	# open-water fish slowly shift their home range with them
	if rest_style == "open" and not migrates and position.distance_to(home) > home_r * 2.0:
		home = home.lerp(position, 0.5)


# ---------------------------------------------------------------- seagull
func _brain_bird(delta: float, shark: Shark, to_p: Vector2, dist: float) -> Vector2:
	var flee := _danger_vector(shark, to_p, dist)
	if flee != Vector2.ZERO:
		_set_mode("flee")
		return Vector2(flee.x, minf(flee.y, 0.0) - base_speed * 0.5)
	if mode == "flee":
		_set_mode("roam")
	if not _is_active():
		_set_mode("rest")             # float on the waves at night
		sleeping = true
		return Vector2(heading * base_speed * 0.05, base_speed * 0.8)
	if sleeping:
		sleeping = false
		_set_mode("climb")
		mode_timer = 1.5
	if mode == "dive":
		hunt_time += delta
		if target == null or not is_instance_valid(target) or target.dead or hunt_time > 3.0 or position.y > 70.0:
			_set_mode("climb")
			mode_timer = 1.4
			hunt_cd = randf_range(6.0, 12.0)
		else:
			return (target.global_position - global_position).normalized() * base_speed * 2.4
	if mode == "climb":
		if mode_timer <= 0.0:
			_set_mode("roam")
		else:
			return Vector2(heading * base_speed, -base_speed * 2.0)
	if p_prey != null and is_instance_valid(p_prey) and _wants_prey():
		target = p_prey
		_set_mode("dive")
		return (target.global_position - global_position).normalized() * base_speed * 2.4
	_set_mode("roam")
	if position.x < 100.0:
		heading = 1.0
	elif position.x > game.world_w - 100.0:
		heading = -1.0
	return Vector2(heading * base_speed, sin(phase * 1.5) * 40.0 + (home_y - position.y) * 0.5)


# ---------------------------------------------------------------- fishing boat
func _brain_boat(delta: float) -> Vector2:
	if position.x < 150.0:
		heading = 1.0
	elif position.x > game.world_w - 150.0:
		heading = -1.0
	position.y = -length * 0.12 + sin(phase * 1.2) * 3.0
	if game.eco.night_amount() > 0.7:
		_set_mode("rest")             # anchored for the night
		sleeping = true
		return Vector2.ZERO
	sleeping = false
	if mode != "sail" and mode != "fish":
		_set_mode("sail")
		mode_timer = randf_range(20.0, 40.0)
	if mode_timer <= 0.0:
		if mode == "sail":
			_set_mode("fish")
			mode_timer = randf_range(8.0, 14.0)
		else:
			_set_mode("sail")
			mode_timer = randf_range(25.0, 45.0)
	if mode == "fish":
		return Vector2.ZERO           # stopped to fish
	return Vector2(heading * base_speed, 0.0)


# ---------------------------------------------------------------- crabs, isopods
func _brain_bottom(delta: float, shark: Shark, to_p: Vector2, dist: float) -> Vector2:
	var fy: float = game.world.floor_y_at(position.x) - length * 0.25
	position.y = lerpf(position.y, fy, 1.0 - exp(-8.0 * delta))
	var flee := _danger_vector(shark, to_p, dist)
	if flee != Vector2.ZERO:
		_set_mode("flee")
		sprinting = true
		return Vector2(flee.x, 0.0)
	if mode == "flee":
		_set_mode("idle")
		mode_timer = 1.0
	if not _is_active():
		_set_mode("rest")             # tuck into a crevice
		var dx := home.x - position.x
		if absf(dx) > 30.0 and not sleeping:
			heading = 1.0 if dx > 0.0 else -1.0
			return Vector2(heading * base_speed * 0.5, 0.0)
		sleeping = true
		return Vector2.ZERO
	if sleeping:
		sleeping = false
		_set_mode("idle")
		mode_timer = 0.5
	if p_food != null and hunger > HUNGRY - 0.05:
		var dxf := p_food.pos.x - position.x
		if absf(dxf) > 18.0 + p_food.radius * 0.4:
			_set_mode("forage")
			target_food = p_food
			heading = 1.0 if dxf > 0.0 else -1.0
			return Vector2(heading * base_speed * 0.8, 0.0)
		target_food = p_food
		_set_mode("graze")
		chew -= delta
		if chew <= 0.0:
			chew = randf_range(0.5, 0.9)
			var got: float = game.eco.take(p_food, 1.5)
			hunger = maxf(0.0, hunger - float(Ecosystem.FOOD_VALUE[p_food.kind]) / 100.0 * got * 1.8)
		return Vector2.ZERO
	if mode == "graze" or mode == "forage":
		_set_mode("idle")
		mode_timer = 0.0
	if mode_timer <= 0.0:
		if randf() < 0.55:
			_set_mode("walk")
			heading = 1.0 if randf() < 0.5 else -1.0
			mode_timer = randf_range(2.0, 5.0)
		else:
			_set_mode("idle")
			mode_timer = randf_range(1.5, 4.0)
	if mode == "walk":
		return Vector2(heading * base_speed * 0.7, 0.0)
	return Vector2.ZERO


# ---------------------------------------------------------------- physics helpers
func _constrain(delta: float) -> void:
	position.x = clampf(position.x, 40.0, game.world_w - 40.0)
	if behavior == "fly":
		var ymax := -30.0
		if mode == "dive":
			ymax = 90.0
		elif mode == "rest":
			ymax = -length * 0.08
		position.y = minf(position.y, ymax)
	elif behavior != "surface":
		position.y = clampf(position.y, 20.0 + length * 0.15, game.world_h - 30.0)
		if behavior != "bottom" and behavior != "static" and game.is_solid(position, length * 0.15):
			position.y -= 140.0 * delta
			velocity.y = minf(velocity.y, 0.0)


func _update_visual(delta: float) -> void:
	if absf(velocity.x) > 8.0:
		heading = 1.0 if velocity.x > 0.0 else -1.0
	if upright:
		rotation = 0.0
		scale.x = 1.0
	else:
		scale.x = heading
		var t := clampf(velocity.y / maxf(absf(velocity.x), 40.0), -1.0, 1.0) * 0.6
		tilt = lerpf(tilt, t, 1.0 - exp(-6.0 * delta))
		rotation = tilt * heading
	modulate = Color(1.0, 0.55, 0.55) if hurt_flash > 0.0 else Color.WHITE
	queue_redraw()


func _draw() -> void:
	if sprites == null:
		CreatureArt.draw(self, shape, length, color, accent, phase)
		return
	# Pick the animation: hurt > attack > idle > swim (missing ones fall back to swim).
	var anim := "swim"
	var t := phase
	var loop := true
	if hurt_flash > 0.0 and sprites.has_anim("hurt"):
		anim = "hurt"
		t = sprites.progress_time("hurt", 1.0 - hurt_flash / HURT_TIME)
		loop = false
	elif (attack_timer > 0.0 or state == "lunge") and sprites.has_anim("attack"):
		anim = "attack"
	elif (sleeping or velocity.length() < 12.0) and sprites.has_anim("idle"):
		anim = "idle"
	sprites.draw(self, length, t, anim, loop, wiggle)
