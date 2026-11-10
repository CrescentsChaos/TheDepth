class_name Hud
extends CanvasLayer
## In-game HUD, biome banner, pause menu and game-over screen.

class HudBar extends Control:
	var value := 1.0
	var col := Color.RED
	var shown := ""

	func set_state(v: float, text: String) -> void:
		value = v
		shown = text
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(2, 2, (size.x - 4) * clampf(value, 0.0, 1.0), size.y - 4), col)
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.35), false, 2.0)
		draw_string(ThemeDB.fallback_font, Vector2(8, size.y - 6), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)

var game: Node
var _root: Control
var _left: VBoxContainer
var _right: VBoxContainer
var _hp: HudBar
var _hunger: HudBar
var _stamina: HudBar
var _xp: HudBar
var _frenzy: HudBar
var _score: Label
var _coins: Label
var _depth: Label
var _combo: Label
var _banner: Label
var _hint: Label
var _pause_root: Control
var _over_root: Control
var _banner_tween: Tween


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UI.make_theme()
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_left = VBoxContainer.new()
	_left.position = Vector2(20, 16)
	_left.add_theme_constant_override("separation", 6)
	_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_left)
	_hp = _bar(Color("#e0483c"))
	_hunger = _bar(Color("#e69a2e"))
	_stamina = _bar(Color("#3aa0e6"))
	_xp = _bar(Color("#4fd18a"))
	_frenzy = _bar(Color("#b06be0"))

	_right = VBoxContainer.new()
	_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_right)
	_score = _rlabel("Score 0", 30)
	_coins = _rlabel("Coins 0", 22)
	_depth = _rlabel("Depth 0 m", 20)
	_combo = _rlabel("", 26)
	_combo.add_theme_color_override("font_color", UI.C_GOLD)

	_banner = UI.label("", 48, UI.C_TEXT)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.custom_minimum_size = Vector2(800, 0)
	_banner.add_theme_constant_override("outline_size", 10)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_banner.modulate.a = 0.0
	_root.add_child(_banner)

	_hint = UI.label("WASD / mouse: swim   •   LMB / Space: bite   •   RMB / Shift: boost   •   Esc: pause\nEat smaller creatures, avoid bigger ones (watch for the red !). Leap out of the water to catch gulls.", 18, UI.C_DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.custom_minimum_size = Vector2(1000, 0)
	_root.add_child(_hint)


func _bar(col: Color) -> HudBar:
	var b := HudBar.new()
	b.custom_minimum_size = Vector2(300, 22)
	b.col = col
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left.add_child(b)
	return b


func _rlabel(text: String, size: int) -> Label:
	var l := UI.label(text, size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.custom_minimum_size = Vector2(300, 0)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_right.add_child(l)
	return l


func _process(_delta: float) -> void:
	var s: Shark = game.shark
	if s == null:
		return
	var vp := get_viewport().get_visible_rect().size
	_right.position = Vector2(vp.x - 320.0, 16.0)
	_banner.position = Vector2((vp.x - _banner.size.x) * 0.5, 110.0)
	_hint.position = Vector2((vp.x - _hint.size.x) * 0.5, vp.y - 90.0)
	_hint.visible = bool(Save.setting("show_hints"))
	_hint.modulate.a = clampf(16.0 - game.run_time, 0.0, 1.0)

	_hp.set_state(s.health / s.max_health, "HEALTH  %d / %d" % [int(s.health), int(s.max_health)])
	_hunger.set_state(s.hunger / s.max_hunger, "HUNGER")
	_stamina.set_state(s.stamina / s.max_stamina, "BOOST")
	_xp.set_state(s.xp / s.xp_next, "LEVEL %d" % s.level)
	if s.frenzy_time > 0.0:
		_frenzy.set_state(s.frenzy_time / 10.0, "FRENZY  %ds" % ceili(s.frenzy_time))
	else:
		_frenzy.set_state(s.frenzy, "FRENZY")
	_score.text = "Score %s" % _commas(game.score)
	_coins.text = "Coins %d  (bank %d)" % [game.coins_run, Save.coins()]
	_depth.text = "Depth %d m" % int(maxf(s.global_position.y, 0.0) / 10.0)
	if s.combo >= 2:
		_combo.text = "COMBO x%d   score x%.1f" % [s.combo, s.combo_mult()]
		_combo.modulate.a = clampf(s.combo_timer, 0.25, 1.0)
	else:
		_combo.text = ""


func _commas(n: int) -> String:
	var s := str(n)
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return out


func show_banner(text: String, col: Color = UI.C_TEXT) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", col)
	_banner.modulate.a = 1.0
	if _banner_tween != null:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_interval(1.6)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 1.0)


# ---------------------------------------------------------------- modals
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and game.shark.alive and _over_root == null:
		_toggle_pause()


func _modal(title: String, title_col: Color) -> Array:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0.03, 0.08, 0.7)
	root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var t := UI.label(title, 44, title_col)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	return [root, box]


func _toggle_pause() -> void:
	if _pause_root != null:
		get_tree().paused = false
		_pause_root.queue_free()
		_pause_root = null
		return
	get_tree().paused = true
	var m := _modal("PAUSED", UI.C_TEXT)
	_pause_root = m[0]
	var box: VBoxContainer = m[1]
	box.add_child(UI.button("RESUME", _toggle_pause))
	box.add_child(UI.button("RESTART RUN", _restart))
	box.add_child(UI.button("QUIT TO MENU", _to_menu))


func show_game_over(info: Dictionary) -> void:
	if _over_root != null:
		return
	var m := _modal("YOU WERE DEVOURED", UI.C_WARN)
	_over_root = m[0]
	var box: VBoxContainer = m[1]
	var c := UI.label("Cause: %s" % str(info["cause"]), 22, UI.C_DIM)
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(c)
	var secs := int(info["time"])
	var lines := [
		"Score: %s%s" % [_commas(int(info["score"])), "   NEW BEST!" if bool(info["new_best"]) else "   (best %s)" % _commas(int(info["best"]))],
		"Creatures eaten: %d" % int(info["eaten"]),
		"Shark level: %d" % int(info["level"]),
		"Time: %d:%02d" % [secs / 60, secs % 60],
		"Coins earned: %d" % int(info["coins"]),
	]
	for line in lines:
		var l := UI.label(str(line), 24)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)
	box.add_child(UI.button("PLAY AGAIN", _restart))
	box.add_child(UI.button("UPGRADES", _to_shop))
	box.add_child(UI.button("MAIN MENU", _to_menu))


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _to_shop() -> void:
	Save.pending_page = "shop"
	_to_menu()
