class_name UI
extends RefCounted
## Shared UI theme + small helpers.

const C_TEXT := Color("#e6f4ff")
const C_DIM := Color("#8fb3cc")
const C_ACCENT := Color("#2fd1c5")
const C_WARN := Color("#ff6b5e")
const C_GOLD := Color("#ffd24a")
const C_PANEL := Color(0.04, 0.11, 0.19, 0.93)


static func _box(bg: Color, border: Color = Color(0, 0, 0, 0), bw: int = 0, radius: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 20
	t.set_color("font_color", "Label", C_TEXT)
	t.set_color("font_color", "Button", C_TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.6, 0.7, 0.7))
	t.set_color("font_color", "CheckButton", C_TEXT)
	t.set_font_size("font_size", "Button", 22)
	t.set_stylebox("normal", "Button", _box(Color(0.08, 0.2, 0.32, 0.92), Color(0.18, 0.5, 0.6), 2))
	t.set_stylebox("hover", "Button", _box(Color(0.1, 0.32, 0.45, 1.0), C_ACCENT, 2))
	t.set_stylebox("pressed", "Button", _box(Color(0.05, 0.5, 0.52, 1.0), Color.WHITE, 2))
	t.set_stylebox("disabled", "Button", _box(Color(0.06, 0.1, 0.16, 0.8), Color(0.2, 0.3, 0.35), 2))
	t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), C_ACCENT, 2))
	t.set_stylebox("panel", "PanelContainer", _box(C_PANEL, Color(0.18, 0.5, 0.6, 0.8), 2, 14))
	return t


static func label(text: String, size: int = 20, col: Color = C_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


static func button(text: String, cb: Callable, min_w: float = 300.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 48)
	b.pressed.connect(cb)
	b.pressed.connect(func(): Sfx.play("ui"))
	return b
