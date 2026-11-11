extends Control
## Title screen + Characters / Upgrades / Bestiary / Settings pages.

class Backdrop extends Control:
	var t := 0.0
	var fish: Array = []
	var bubbles: Array = []
	var shark_sprites: SpriteSet = null

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sel := Database.selected_def()
		shark_sprites = SpriteSet.for_def(str(sel.get("_kind", "sharks")), sel)
		var pool: Array = []
		for d in Database.creatures:
			if not (str(d["behavior"]) in ["surface", "fly", "static", "bottom"]):
				pool.append(d)
		if not pool.is_empty():
			for i in 16:
				var pick: Dictionary = pool[randi() % pool.size()]
				fish.append({
					"def": pick,
					"spr": SpriteSet.for_def("creatures", pick),
					"x": randf() * 1600.0 - 200.0, "y": randf_range(80.0, 700.0),
					"s": randf_range(0.5, 1.2),
					"v": randf_range(20.0, 70.0) * (1.0 if randf() < 0.5 else -1.0),
					"ph": randf() * TAU,
				})
		for i in 40:
			bubbles.append(Vector2(randf() * 1400.0, randf() * 800.0))

	func _process(delta: float) -> void:
		t += delta
		for f in fish:
			f["x"] = float(f["x"]) + float(f["v"]) * delta
			if float(f["x"]) > size.x + 300.0:
				f["x"] = -300.0
			elif float(f["x"]) < -300.0:
				f["x"] = size.x + 300.0
		for i in bubbles.size():
			var b: Vector2 = bubbles[i]
			b.y -= 30.0 * delta
			if b.y < -10.0:
				b = Vector2(randf() * size.x, size.y + 10.0)
			bubbles[i] = b
		queue_redraw()

	func _draw() -> void:
		var top := Color("#1d6fa8")
		var bot := Color("#04101e")
		draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]), PackedColorArray([top, top, bot, bot]))
		for i in 5:
			var x0 := size.x * (0.1 + 0.2 * float(i)) + sin(t * 0.3 + float(i)) * 40.0
			draw_colored_polygon(PackedVector2Array([Vector2(x0, 0), Vector2(x0 + 60, 0), Vector2(x0 + 260, size.y), Vector2(x0 + 120, size.y)]), Color(1, 1, 1, 0.035))
		for b in bubbles:
			draw_circle(b, 3.0, Color(1, 1, 1, 0.18))
		for f in fish:
			var d: Dictionary = f["def"]
			var dir := 1.0 if float(f["v"]) > 0.0 else -1.0
			var s := float(f["s"])
			draw_set_transform(Vector2(float(f["x"]), float(f["y"])), 0.0, Vector2(dir * s, s))
			var L := clampf(float(d["length"]), 24.0, 160.0)
			var dark := 0.4 + 0.3 * (1.0 - s)
			var spr: SpriteSet = f["spr"]
			if spr != null:
				spr.draw(self, L, t + float(f["ph"]), "swim", true, true, Color.WHITE.darkened(dark))
			else:
				CreatureArt.draw(self, str(d["shape"]), L, Color(str(d["color"])).darkened(dark), Color(str(d["accent"])).darkened(0.4), t + float(f["ph"]))
		# big shark silhouette
		var sx := fmod(t * 40.0, size.x + 900.0) - 450.0
		draw_set_transform(Vector2(sx, size.y * 0.3 + sin(t * 0.5) * 30.0), 0.0, Vector2.ONE)
		if shark_sprites != null:
			shark_sprites.draw(self, 420.0, t, "swim", true, true, Color(0.03, 0.08, 0.15, 0.85))
		else:
			CreatureArt.draw(self, str(Database.selected_def().get("shape", "shark")), 420.0, Color(0.03, 0.08, 0.15, 0.85), Color(0.05, 0.12, 0.2, 0.85), t)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

var _margin: MarginContainer
var _page: Control
var _backdrop: Backdrop


func _ready() -> void:
	theme = UI.make_theme()
	_backdrop = Backdrop.new()
	add_child(_backdrop)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_margin = MarginContainer.new()
	add_child(_margin)
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, 48)
	var page := Save.pending_page
	Save.pending_page = "main"
	_goto(page)


func _goto(page: String) -> void:
	match page:
		"sharks": _page_sharks()
		"shop": _page_shop()
		"bestiary": _page_bestiary()
		"settings": _page_settings()
		_: _page_main()


func _set_page(node: Control) -> void:
	if _page != null:
		# Remove immediately (not just queue_free) so the old and new page are never both
		# laid out under the cursor for a frame, which left the hover on the wrong button.
		_margin.remove_child(_page)
		_page.queue_free()
	_page = node
	_margin.add_child(node)
	_refresh_hover.call_deferred()


## After a page change the button under a still mouse should light up without wiggling.
func _refresh_hover() -> void:
	await get_tree().process_frame
	var vp := get_viewport()
	if vp != null and vp.has_method("update_mouse_cursor_state"):
		vp.call("update_mouse_cursor_state")


## Standard sub-page: header (title, coins, back) + returns the VBox to fill.
func _sub_page(title: String) -> VBoxContainer:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 20)
	var t := UI.label(title, 48)
	t.add_theme_color_override("font_outline_color", Color("#04101e"))
	t.add_theme_constant_override("outline_size", 8)
	head.add_child(t)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(UI.label("Coins: %d" % Save.coins(), 26, UI.C_GOLD))
	head.add_child(UI.button("BACK", func(): _goto("main"), 140.0))
	outer.add_child(head)
	_set_page(outer)
	return outer


# ---------------------------------------------------------------- main
func _page_main() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var title := UI.label("ABYSS HUNTER", 92)
	title.add_theme_color_override("font_outline_color", Color("#04101e"))
	title.add_theme_constant_override("outline_size", 14)
	box.add_child(title)
	box.add_child(UI.label("Hunt   ·   Grow   ·   Descend", 28, UI.C_ACCENT))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 20)
	box.add_child(gap)
	box.add_child(UI.button("PLAY", func(): get_tree().change_scene_to_file("res://scenes/game.tscn")))
	box.add_child(UI.button("CHOOSE FISH", func(): _goto("sharks")))
	box.add_child(UI.button("UPGRADES", func(): _goto("shop")))
	box.add_child(UI.button("BESTIARY", func(): _goto("bestiary")))
	box.add_child(UI.button("SETTINGS", func(): _goto("settings")))
	box.add_child(UI.button("QUIT", func(): get_tree().quit()))
	var foot := UI.label("Coins %d    Best score %d    Creatures eaten %d" % [Save.coins(), int(Save.data["best_score"]), int(Save.data["total_eaten"])], 20, UI.C_DIM)
	box.add_child(foot)
	_set_page(box)


# ---------------------------------------------------------------- sharks
var _char_tab := "sharks"


func _page_sharks() -> void:
	var outer := _sub_page("CHOOSE YOUR CHARACTER")
	# the tab starts on whatever you are currently playing
	if _char_tab == "" or (str(Save.data.get("selected_fish", "")) != "" and not _tab_touched):
		_char_tab = "fish" if str(Save.data.get("selected_fish", "")) != "" else "sharks"
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 12)
	var b1 := UI.button("SHARKS", _set_tab.bind("sharks"), 260.0)
	b1.disabled = _char_tab == "sharks"
	var b2 := UI.button("ANY FISH / CREATURE", _set_tab.bind("fish"), 360.0)
	b2.disabled = _char_tab == "fish"
	tabs.add_child(b1)
	tabs.add_child(b2)
	outer.add_child(tabs)
	if _char_tab == "fish":
		_fish_tab(outer)
		return
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	scroll.add_child(row)
	var playing_fish := str(Save.data.get("selected_fish", "")) != ""
	for s in Database.sharks:
		var id := str(s["id"])
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(260, 0)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 8)
		card.add_child(cv)
		var pv := ArtPreview.new()
		pv.custom_minimum_size = Vector2(230, 110)
		pv.shape = "shark"
		pv.body_len = float(s["length"])
		pv.color = Color(str(s["color"]))
		pv.accent = Color(str(s["belly"]))
		pv.sprites = SpriteSet.for_def("sharks", s)
		cv.add_child(pv)
		cv.add_child(UI.label(str(s["name"]), 26, UI.C_ACCENT))
		var desc := UI.label(str(s["description"]), 17, UI.C_DIM)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(220, 70)
		cv.add_child(desc)
		cv.add_child(UI.label("Bite %.1f   Reach %d\nSpeed %d   Boost x%.1f\nHealth %d   Stamina %d" % [float(s["bite_damage"]), int(s["bite_range"]), int(s["speed"]), float(s["boost_mult"]), int(s["max_health"]), int(s["stamina"])], 17))
		if str(Save.data["selected_shark"]) == id and not playing_fish:
			var b := UI.button("SELECTED", _noop, 220.0)
			b.disabled = true
			cv.add_child(b)
		elif Save.has_shark(id):
			cv.add_child(UI.button("SELECT", _select_shark.bind(id), 220.0))
		else:
			var cost := int(s["cost"])
			var b := UI.button("UNLOCK  (%d)" % cost, _unlock_shark.bind(id, cost), 220.0)
			b.disabled = Save.coins() < cost
			cv.add_child(b)
		row.add_child(card)


var _tab_touched := false


func _set_tab(tab: String) -> void:
	_char_tab = tab
	_tab_touched = true
	_goto("sharks")


## Every creature in the database that can be played, as a scrolling grid of cards.
func _fish_tab(outer: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(grid)
	var cur := str(Save.data.get("selected_fish", ""))
	for c in Database.creatures:
		if not Database.is_playable(c):
			continue
		var p := Database.creature_as_player(c)
		var id := str(c["id"])
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(300, 0)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 6)
		card.add_child(cv)
		var pv := ArtPreview.new()
		pv.custom_minimum_size = Vector2(260, 90)
		pv.shape = str(c["shape"])
		pv.body_len = minf(float(c["length"]), 260.0)
		pv.color = Color(str(c["color"]))
		pv.accent = Color(str(c["accent"]))
		pv.sprites = SpriteSet.for_def("creatures", c)
		cv.add_child(pv)
		cv.add_child(UI.label(str(c["name"]), 24, UI.C_ACCENT))
		var diet := UI.label(Database.diet_text(p), 15, UI.C_GOLD)
		diet.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cv.add_child(diet)
		cv.add_child(UI.label("Size %d   Speed %d   Health %d\nBite %.1f   Lives at %d-%d m" % [int(c["length"]), int(p["speed"]), int(p["max_health"]), float(p["bite_damage"]), int(float(c["min_depth"]) / 10.0), int(float(c["max_depth"]) / 10.0)], 15))
		var cost := int(c["cost"])
		if cur == id:
			var b := UI.button("SELECTED", _noop, 260.0)
			b.disabled = true
			cv.add_child(b)
		elif cost <= 0 or Save.data.get("fish_unlocked", []).has(id):
			cv.add_child(UI.button("PLAY AS THIS", _select_fish.bind(id), 260.0))
		else:
			var b := UI.button("UNLOCK  (%d)" % cost, _unlock_fish.bind(id, cost), 260.0)
			b.disabled = Save.coins() < cost
			cv.add_child(b)
		grid.add_child(card)


# ---------------------------------------------------------------- shop
func _page_shop() -> void:
	var outer := _sub_page("UPGRADES")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for u in Database.upgrades:
		var id := str(u["id"])
		var lv := Save.upgrade_level(id)
		var maxlv := int(u["max_level"])
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 16)
		panel.add_child(h)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UI.label(str(u["name"]), 24, UI.C_ACCENT))
		info.add_child(UI.label(str(u["description"]), 17, UI.C_DIM))
		h.add_child(info)
		h.add_child(UI.label("Lv %d / %d" % [lv, maxlv], 22))
		if lv >= maxlv:
			var b := UI.button("MAXED", _noop, 180.0)
			b.disabled = true
			h.add_child(b)
		else:
			var cost := Database.upgrade_cost(u, lv)
			var b := UI.button("BUY  (%d)" % cost, _buy_upgrade.bind(id, cost, lv), 180.0)
			b.disabled = Save.coins() < cost
			h.add_child(b)
		list.add_child(panel)


# ---------------------------------------------------------------- bestiary
func _page_bestiary() -> void:
	var outer := _sub_page("BESTIARY")
	var found := 0
	for d in Database.creatures:
		if Save.is_discovered(str(d["id"])):
			found += 1
	outer.add_child(UI.label("Discovered %d / %d  -  creatures appear here once you meet them. Add your own in data/creatures.json" % [found, Database.creatures.size()], 18, UI.C_DIM))
	var detail := UI.label("Select a creature's Info button.", 18)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size = Vector2(900, 60)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	for d in Database.creatures:
		var known := Save.is_discovered(str(d["id"]))
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(200, 0)
		var cv := VBoxContainer.new()
		cell.add_child(cv)
		var pv := ArtPreview.new()
		pv.custom_minimum_size = Vector2(170, 80)
		pv.shape = str(d["shape"])
		pv.body_len = float(d["length"])
		pv.color = Color(str(d["color"]))
		pv.accent = Color(str(d["accent"]))
		pv.silhouette = not known
		pv.sprites = SpriteSet.for_def("creatures", d)
		cv.add_child(pv)
		var nm := UI.label(str(d["name"]) if known else "???", 18)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(nm)
		var info := Button.new()
		info.text = "Info"
		info.disabled = not known
		info.pressed.connect(func(): detail.text = _creature_text(d))
		cv.add_child(info)
		grid.add_child(cell)
	outer.add_child(detail)


func _creature_text(d: Dictionary) -> String:
	var danger := ""
	if float(d["contact_damage"]) > 0.0:
		danger += "  Contact damage %d." % int(d["contact_damage"])
	if float(d["thorns"]) > 0.0:
		danger += "  Spiny (%d)." % int(d["thorns"])
	if float(d["poison"]) > 0.0:
		danger += "  Poisonous."
	if float(d["stun"]) > 0.0:
		danger += "  Shocks."
	return "%s - %s\nLength %d   HP %d   Behavior: %s   Depth %d-%d m\nXP %d   Hunger +%d   Coins %d   Score %d.%s" % [
		str(d["name"]), str(d["description"]), int(d["length"]), int(d["hp"]), str(d["behavior"]),
		int(float(d["min_depth"]) / 10.0), int(minf(float(d["max_depth"]), 3200.0) / 10.0),
		int(d["xp"]), int(d["hunger"]), int(d["coins"]), int(d["score"]), danger]


# ---------------------------------------------------------------- settings
func _page_settings() -> void:
	var outer := _sub_page("SETTINGS")
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	outer.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)

	var vol_row := HBoxContainer.new()
	vol_row.add_child(UI.label("Master volume   ", 22))
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = float(Save.setting("master_volume"))
	slider.custom_minimum_size = Vector2(300, 28)
	slider.value_changed.connect(_on_volume)
	vol_row.add_child(slider)
	v.add_child(vol_row)

	v.add_child(_check("Fullscreen", "fullscreen"))
	v.add_child(_check("Mouse steering (swim toward the cursor)", "mouse_steer"))
	v.add_child(_check("Screen shake", "screen_shake"))
	v.add_child(_check("Show hints at start of a run", "show_hints"))

	v.add_child(UI.label("Controls:  WASD / arrows / left stick / mouse = swim   •   LMB / Space / A = bite (hold to chomp)\n                 RMB / Shift / RB = boost   •   Esc / P / Start = pause", 17, UI.C_DIM))

	v.add_child(UI.button("EXPORT DATABASE FILES + OPEN FOLDER", _export_db, 520.0))
	v.add_child(UI.button("RELOAD DATABASE", Database.reload, 520.0))
	var reset_btn := UI.button("RESET ALL PROGRESS", _noop, 520.0)
	reset_btn.pressed.connect(_reset_pressed.bind(reset_btn))
	v.add_child(reset_btn)


func _noop() -> void:
	pass


func _check(text: String, key: String) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = bool(Save.setting(key))
	c.toggled.connect(_on_check.bind(key))
	return c


func _on_check(on: bool, key: String) -> void:
	Save.set_setting(key, on)
	Boot.apply_settings()


func _on_volume(val: float) -> void:
	Save.set_setting("master_volume", val)
	Boot.apply_settings()


func _export_db() -> void:
	Database.export_defaults()
	OS.shell_open(ProjectSettings.globalize_path("user://data"))


var _reset_armed := false


func _reset_pressed(btn: Button) -> void:
	if _reset_armed:
		_reset_armed = false
		Save.reset()
		Boot.apply_settings()
		_goto("settings")
	else:
		_reset_armed = true
		btn.text = "CLICK AGAIN TO CONFIRM RESET"


func _select_fish(id: String) -> void:
	Save.data["selected_fish"] = id
	Save.save_game()
	_goto("sharks")


func _unlock_fish(id: String, cost: int) -> void:
	if Save.spend(cost):
		var list: Array = Save.data.get("fish_unlocked", [])
		list.append(id)
		Save.data["fish_unlocked"] = list
		Save.data["selected_fish"] = id
		Save.save_game()
	_goto("sharks")


func _select_shark(id: String) -> void:
	Save.data["selected_fish"] = ""
	Save.data["selected_shark"] = id
	Save.save_game()
	_goto("sharks")


func _unlock_shark(id: String, cost: int) -> void:
	if Save.spend(cost):
		Save.unlock_shark(id)
		Save.data["selected_fish"] = ""
		Save.data["selected_shark"] = id
		Save.save_game()
	_goto("sharks")


func _buy_upgrade(id: String, cost: int, lv: int) -> void:
	if Save.spend(cost):
		Save.set_upgrade_level(id, lv + 1)
	_goto("shop")
