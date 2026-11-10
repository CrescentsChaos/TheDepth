class_name Creature
extends Node2D
## One living creature. All stats come from its database entry (`def`).
## behaviors: wander, school, hunter, ambush, drift, bottom, static, fly, surface, shooter

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
var contact_cd := 0.0
var shoot_cd := 2.0
var hurt_flash := 0.0
var dead := false
var leader: Creature = null
var follow_offset := Vector2.ZERO
var wander_target := Vector2.ZERO
var wander_timer := 0.0
var state := "idle"
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
const HURT_TIME := 0.25
var sprites: SpriteSet = null
var wiggle := false
var attack_timer := 0.0


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
	wander_target = position
	state_timer = randf_range(0.5, 2.0)
	sprites = SpriteSet.for_def("creatures", def)
	wiggle = not upright and behavior != "static"
	if sprites != null and sprites.smooth:
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_to_group("creatures")


func remove() -> void:
	dead = true
	remove_from_group("creatures")
	queue_free()


## Returns true if this hit killed the creature.
func hurt(dmg: float, from_pos: Vector2) -> bool:
	hp -= dmg
	hurt_flash = 0.25
	var away := (global_position - from_pos).normalized()
	velocity += away * 260.0 / maxf(1.0, length / 60.0)
	stun = maxf(stun, 0.25)
	if not (behavior in ["hunter", "ambush", "static", "surface"]):
		flee_timer = 3.0
	return hp <= 0.0


func _physics_process(delta: float) -> void:
	if dead or game == null:
		return
	phase += delta
	contact_cd = maxf(contact_cd - delta, 0.0)
	flee_timer = maxf(flee_timer - delta, 0.0)
	stun = maxf(stun - delta, 0.0)
	hurt_flash = maxf(hurt_flash - delta, 0.0)
	attack_timer = maxf(attack_timer - delta, 0.0)
	var desired := Vector2.ZERO
	if stun <= 0.0:
		desired = _think(delta)
	var accel := base_speed * 3.0 / maxf(1.0, length / 120.0)
	velocity = velocity.move_toward(desired, accel * delta)
	position += velocity * delta
	_constrain(delta)
	_update_visual(delta)


func _think(delta: float) -> Vector2:
	var shark: Shark = game.shark
	var to_p := shark.global_position - global_position
	var dist := to_p.length()
	var flee_range := float(def["flee_range"])
	if shark.alive and behavior != "static":
		var scared := flee_timer > 0.0 or (flee_range > 0.0 and dist < flee_range and shark.length > length * 0.6)
		if scared:
			var away := (-to_p).normalized()
			if behavior == "bottom":
				away = Vector2(1.0 if away.x >= 0.0 else -1.0, 0.0)
			return away * base_speed * 1.6
	match behavior:
		"hunter": return _hunter(delta, to_p, dist, shark)
		"ambush": return _ambush(delta, to_p, dist, shark)
		"school": return _school(delta)
		"drift": return Vector2(cos(phase * 0.4) * base_speed * 0.4, sin(phase * 1.2) * base_speed)
		"bottom": return _bottom(delta)
		"static": return Vector2.ZERO
		"fly": return _fly()
		"surface": return _surface()
		"shooter": return _shooter(delta, to_p, dist, shark)
	return _wander(delta)


func _wander(delta: float) -> Vector2:
	wander_timer -= delta
	if wander_timer <= 0.0 or global_position.distance_to(wander_target) < 20.0:
		wander_timer = randf_range(2.0, 5.0)
		var r := 250.0 + length
		wander_target = game.clamp_to_water(global_position + Vector2(randf_range(-r, r), randf_range(-r * 0.5, r * 0.5)), def)
	return (wander_target - global_position).normalized() * base_speed * 0.6


func _school(delta: float) -> Vector2:
	if leader == null or not is_instance_valid(leader) or leader.dead:
		leader = null
		return _wander(delta)
	var d := leader.global_position + follow_offset - global_position
	return d.normalized() * base_speed * clampf(d.length() / 40.0, 0.5, 1.6)


func _hunter(delta: float, to_p: Vector2, dist: float, shark: Shark) -> Vector2:
	var aggro := float(def["aggro_range"])
	if shark.alive and dist < aggro and shark.length < length * 1.4:
		var boost := 1.0 + clampf(1.0 - dist / aggro, 0.0, 1.0) * 0.5
		attack_timer = 0.2
		return to_p.normalized() * base_speed * boost
	return _wander(delta)


func _ambush(delta: float, to_p: Vector2, dist: float, shark: Shark) -> Vector2:
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
	if shark.alive and dist < float(def["aggro_range"]) and shark.length < length * 1.5:
		state = "lunge"
		state_timer = 0.9
		lunge_dir = to_p.normalized()
	return Vector2(0.0, sin(phase * 1.5) * 6.0)


func _bottom(delta: float) -> Vector2:
	wander_timer -= delta
	if wander_timer <= 0.0:
		wander_timer = randf_range(2.0, 5.0)
		heading = 1.0 if randf() < 0.5 else -1.0
	var fy: float = game.world.floor_y_at(position.x) - length * 0.25
	position.y = lerpf(position.y, fy, 1.0 - exp(-8.0 * delta))
	return Vector2(heading * base_speed * 0.7, 0.0)


func _fly() -> Vector2:
	if position.x < 100.0:
		heading = 1.0
	elif position.x > game.world_w - 100.0:
		heading = -1.0
	return Vector2(heading * base_speed, sin(phase * 1.5) * 40.0 + (home_y - position.y) * 0.5)


func _surface() -> Vector2:
	if position.x < 150.0:
		heading = 1.0
	elif position.x > game.world_w - 150.0:
		heading = -1.0
	position.y = -length * 0.12 + sin(phase * 1.2) * 3.0
	return Vector2(heading * base_speed, 0.0)


func _shooter(delta: float, to_p: Vector2, dist: float, shark: Shark) -> Vector2:
	shoot_cd -= delta
	var aggro := float(def["aggro_range"])
	if shark.alive and dist < aggro:
		if shoot_cd <= 0.0:
			shoot_cd = 2.5
			attack_timer = 0.5
			game.spawn_projectile(global_position, to_p.normalized(), float(def["projectile_damage"]))
		if dist < aggro * 0.4:
			return -to_p.normalized() * base_speed
	return _wander(delta) * 0.5


func _constrain(delta: float) -> void:
	position.x = clampf(position.x, 40.0, game.world_w - 40.0)
	if behavior == "fly":
		position.y = minf(position.y, -30.0)
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
	elif velocity.length() < 12.0 and sprites.has_anim("idle"):
		anim = "idle"
	sprites.draw(self, length, t, anim, loop, wiggle)
