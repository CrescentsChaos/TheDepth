class_name CreatureArt
extends RefCounted
## Procedural vector art for every creature "shape". Used by creatures, the player
## shark, the bestiary and the menu backdrop. All shapes face +X and are centered on
## the origin; L is the body length in pixels.

const UPRIGHT := ["jelly", "crab", "chest", "boat", "seahorse", "octopus"]
static var _dot: Texture2D


static func is_upright(shape: String) -> bool:
	return shape in UPRIGHT


static func soft_dot() -> Texture2D:
	if _dot == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.width = 32
		tex.height = 32
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		_dot = tex
	return _dot


static func ellipse(center: Vector2, rx: float, ry: float, n: int = 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


static func _ell(c: CanvasItem, center: Vector2, rx: float, ry: float, col: Color) -> void:
	c.draw_colored_polygon(ellipse(center, rx, ry), col)


static func _tri(c: CanvasItem, a: Vector2, b: Vector2, d: Vector2, col: Color) -> void:
	c.draw_colored_polygon(PackedVector2Array([a, b, d]), col)


static func _eye(c: CanvasItem, p: Vector2, r: float) -> void:
	var rr := maxf(r, 1.5)
	c.draw_circle(p, rr, Color.WHITE)
	c.draw_circle(p + Vector2(rr * 0.2, 0), rr * 0.55, Color.BLACK)


static func _dome(center: Vector2, rx: float, ry: float, n: int = 14) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var a := PI + PI * float(i) / float(n)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


static func draw(c: CanvasItem, shape: String, L: float, col: Color, acc: Color, t: float, open: float = 0.0) -> void:
	match shape:
		"shark": _shark(c, L, col, acc, t, open)
		"whale": _whale(c, L, col, acc, t)
		"eel": _eel(c, L, col, acc, t)
		"jelly": _jelly(c, L, col, acc, t)
		"crab": _crab(c, L, col, acc, t)
		"ray": _ray(c, L, col, acc, t)
		"turtle": _turtle(c, L, col, acc, t)
		"puffer": _puffer(c, L, col, acc, t)
		"squid": _squid(c, L, col, acc, t)
		"angler": _angler(c, L, col, acc, t)
		"chest": _chest(c, L, col, acc, t)
		"bird": _bird(c, L, col, acc, t)
		"boat": _boat(c, L, col, acc, t)
		"diver": _diver(c, L, col, acc, t)
		"croc": _croc(c, L, col, acc, t)
		"seahorse": _seahorse(c, L, col, acc, t)
		"octopus": _octopus(c, L, col, acc, t)
		_: _fish(c, L, col, acc, t)


static func _fish(c: CanvasItem, L: float, col: Color, acc: Color, t: float) -> void:
	var wag := sin(t * 9.0) * L * 0.07
	_tri(c, Vector2(-L * 0.30, 0), Vector2(-L * 0.52, -L * 0.20 + wag), Vector2(-L * 0.52, L * 0.20 + wag), acc)
	_ell(c, Vector2(L * 0.02, 0), L * 0.34, L * 0.20, col)
	_ell(c, Vector2(L * 0.04, L * 0.08), L * 0.27, L * 0.08, col.lightened(0.35))
	_tri(c, Vector2(-L * 0.05, -L * 0.17), Vector2(L * 0.08, -L * 0.17), Vector2(-L * 0.10, -L * 0.32), acc)
	_eye(c, Vector2(L * 0.20, -L * 0.04), L * 0.04)


static func _shark(c: CanvasItem, L: float, col: Color, belly: Color, t: float, open: float) -> void:
	var wag := sin(t * 6.0) * L * 0.05
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(-L * 0.38, 0), Vector2(-L * 0.60, -L * 0.20 + wag),
		Vector2(-L * 0.50, 0), Vector2(-L * 0.56, L * 0.14 + wag)]), col.darkened(0.1))
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(L * 0.50, L * 0.02), Vector2(L * 0.38, -L * 0.07), Vector2(L * 0.15, -L * 0.13),
		Vector2(-L * 0.12, -L * 0.12), Vector2(-L * 0.30, -L * 0.06), Vector2(-L * 0.42, 0),
		Vector2(-L * 0.30, L * 0.05), Vector2(-L * 0.10, L * 0.10), Vector2(L * 0.15, L * 0.11),
		Vector2(L * 0.36, L * 0.07)]), col)
	_ell(c, Vector2(L * 0.10, L * 0.075), L * 0.30, L * 0.035, belly)
	_tri(c, Vector2(L * 0.02, -L * 0.12), Vector2(-L * 0.14, -L * 0.12), Vector2(-L * 0.10, -L * 0.30), col.darkened(0.1))
	_tri(c, Vector2(L * 0.14, L * 0.09), Vector2(-L * 0.02, L * 0.10), Vector2(-L * 0.08, L * 0.24 + wag * 0.3), col.darkened(0.15))
	for i in 3:
		var gx := L * (0.19 - 0.03 * float(i))
		c.draw_line(Vector2(gx, -L * 0.05), Vector2(gx - L * 0.01, L * 0.04), Color(0, 0, 0, 0.25), maxf(L * 0.01, 1.0))
	var m := clampf(open, 0.0, 1.0)
	if m > 0.03:
		_tri(c, Vector2(L * 0.47, L * 0.04), Vector2(L * 0.24, L * 0.05), Vector2(L * 0.40, L * 0.05 + L * 0.17 * m), Color("#8a1c28"))
		for i in 4:
			var tx := L * (0.44 - 0.05 * float(i))
			_tri(c, Vector2(tx, L * 0.045), Vector2(tx - L * 0.02, L * 0.045), Vector2(tx - L * 0.01, L * 0.045 + L * 0.03), Color.WHITE)
	else:
		c.draw_line(Vector2(L * 0.47, L * 0.045), Vector2(L * 0.28, L * 0.06), Color(0, 0, 0, 0.5), maxf(L * 0.012, 1.0))
	_eye(c, Vector2(L * 0.31, -L * 0.03), L * 0.02)


static func _whale(c: CanvasItem, L: float, col: Color, acc: Color, t: float) -> void:
	var wag := sin(t * 2.0) * L * 0.03
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(-L * 0.36, 0), Vector2(-L * 0.54, -L * 0.17 + wag),
		Vector2(-L * 0.46, 0), Vector2(-L * 0.54, L * 0.17 + wag)]), col.darkened(0.1))
	_ell(c, Vector2.ZERO, L * 0.42, L * 0.20, col)
	_ell(c, Vector2(L * 0.05, L * 0.09), L * 0.36, L * 0.09, acc)
	_tri(c, Vector2(L * 0.08, L * 0.12), Vector2(-L * 0.06, L * 0.12), Vector2(-L * 0.14, L * 0.28), col.darkened(0.15))
	c.draw_line(Vector2(L * 0.40, L * 0.05), Vector2(L * 0.16, L * 0.10), Color(0, 0, 0, 0.4), maxf(L * 0.01, 1.5))
	_eye(c, Vector2(L * 0.30, -L * 0.01), L * 0.015)


static func _eel(c: CanvasItem, L: float, col: Color, acc: Color, t: float) -> void:
	var pts := PackedVector2Array()
	var n := 16
	for i in n + 1:
		var f := float(i) / float(n)
		pts.append(Vector2(lerpf(L * 0.5, -L * 0.5, f), sin(t * 5.0 + f * 5.0) * L * 0.06 * (0.3 + f)))
	var w := maxf(L * 0.085, 3.0)
	c.draw_polyline(pts, col, w, true)
	c.draw_polyline(pts, acc, maxf(w * 0.3, 1.0), true)
	c.draw_circle(pts[0], w * 0.75, col.lightened(0.1))
	_eye(c, pts[0] + Vector2(w * 0.2, -w * 0.2), w * 0.28)


static func _jelly(c: CanvasItem, L: float, col: Color, acc: Color, t: float) -> void:
	var pulse := 1.0 + sin(t * 3.0) * 0.07
	var rx := L * 0.38
	var ry := L * 0.30 * pulse
	c.draw_colored_polygon(_dome(Vector2(0, -L * 0.05), rx, ry), Color(col.r, col.g, col.b, 0.8))
	c.draw_colored_polygon(ellipse(Vector2(0, -L * 0.15), rx * 0.55, ry * 0.45), Color(acc.r, acc.g, acc.b, 0.35))
	for i in 6:
		var x := lerpf(-rx * 0.8, rx * 0.8, float(i) / 5.0)
		var tp := PackedVector2Array()
		for j in 7:
			tp.append(Vector2(x + sin(t * 4.0 + float(i) + float(j)) * L * 0.03, -L * 0.05 + float(j) * L * 0.10))
		c.draw_polyline(tp, Color(acc.r, acc.g, acc.b, 0.7), maxf(L * 0.02, 1.0), true)


static func _crab(c: CanvasItem, L: float, col: Color, acc: Color, t: float) -> void:
	for s in [-1.0, 1.0]:
		for i in 3:
			var k := float(i)
			c.draw_line(Vector2(s * L * 0.22, k * L * 0.05), Vector2(s * L * 0.46, L * 0.18 + sin(t * 8.0 + k) * L * 0.03), col.darkened(0.2), maxf(L * 0.03, 1.5))
		c.draw_line(Vector2(s * L * 0.26, -L * 0.05), Vector2(s * L * 0.40, -L * 0.22), col, maxf(L * 0.04, 2.0))
		c.draw_circle(Vector2(s * L * 0.40, -L * 0.26), L * 0.09, acc)
	_ell(c, Vector2.ZERO, L * 0.30, L * 0.20, col)
	_ell(c, Vector2(0, -L * 0.03), L * 0.22, L * 0.12, col.lightened(0.15))
	c.draw_circle(Vector2(-L * 0.08, -L * 0.22), L * 0.035, Color.WHITE)
	c.draw_circle(Vector2(L * 0.08, -L * 0.22), L * 0.035, Color.WHITE)


static func _ray(c: CanvasItem, L: float, col: Color, acc: Color, t: float) -> void:
	var flap := 0.65 + 0.35 * sin(t * 3.0)
	c.draw_line(Vector2(-L * 0.28, 0), Vector2(-L * 0.62, sin(t * 3.0) * L * 0.05), col.darkened(0.2), maxf(L * 0.02, 1.5))
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(L * 0.45, 0), Vector2(L * 0.05, -L * 0.30 * flap),
		Vector2(-L * 0.32, 0), Vector2(L * 0.05, L * 0.30 * flap)]), col)
	_ell(c, Vector2(L * 0.05, 0), L * 0.18, L * 0.09 * flap, acc)
	c.draw_circle(Vector2(L * 0.30, -L * 0.04), maxf(L * 0.015, 1.5), Color.BLACK)
	c.draw_circle(Vector2(L * 0.30, L * 0.04), maxf(L * 0.015, 1.5), Color.BLACK)


static func _turtle(c: CanvasItem, L: float, col: Color, acc: Color, t: float) -> void:
	var fl := sin(t * 3.0) * L * 0.05
	_tri(c, Vector2(L * 0.12, L * 0.05), Vector2(-L * 0.05, L * 0.05), Vector2(L * 0.05, L * 0.28 + fl), col.darkened(0.15))
	_tri(c, Vector2(-L * 0.22, L * 0.05), Vector2(-L * 0.34, L * 0.05), Vector2(-L * 0.38, L * 0.18 - fl), col.darkened(0.15))
	c.draw_circle(Vector2(L * 0.36, L * 0.0), L * 0.09, col.lightened(0.1))
	_eye(c, Vector2(L * 0.39, -L * 0.02), L * 0.02)
	_ell(c, Vector2(0, L * 0.06), L * 0.28, L * 0.05, acc)
	c.draw_colored_polygon(_dome(Vector2(0, L * 0.06), L * 0.30, L * 0.26), col)
	for i in 3:
		var x := L * (0.12 - 0.12 * float(i))
		c.draw_line(Vector2(x, L * 0.05), Vector2(x - L * 0.03, -L * 0.15), col.darkened(0.3), maxf(L * 0.01, 1.0))


static func _puffer(c: CanvasItem, L: float, col: Color, acc: Color, t: float) -> void:
	var r := L * 0.38
	for i in 16:
		var a := TAU * float(i) / 16.0
		c.draw_line(Vector2(cos(a), sin(a)) * r * 0.92, Vector2(cos(a), sin(a)) * r * 1.22, acc, maxf(L * 0.03, 1.5))
	_tri(c, Vector2(-r * 0.8, 0), Vector2(-r * 1.3, -r * 0.4 + sin(t * 8.0) * r * 0.1), Vector2(-r * 1.3, r * 0.4 + sin(t * 8.0) * r * 0.1), acc)
	_ell(c, Vector2.ZERO, r, r * 0.92, col)
	_ell(c, Vector2(L * 0.02, r * 0.4), r * 0.75, r * 0.4, col.lightened(0.4))
	_eye(c, Vector2(r * 0.5, -r * 0.2), r * 0.18)


static func _squid(c: CanvasItem, L: float, col: Color, acc: Color, t: float) -> void:
	for i in 6:
		var y := lerpf(-L * 0.06, L * 0.06, float(i) / 5.0)
		var tp := PackedVector2Array()
		for j in 6:
			var f := float(j) / 5.0
			tp.append(Vector2(L * 0.08 + f * L * 0.42, y * (1.0 + f * 2.0) + sin(t * 5.0 + float(i) + f * 4.0) * L * 0.03))
		c.draw_polyline(tp, acc, maxf(L * 0.015, 1.0), true)
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(-L * 0.50, 0), Vector2(-L * 0.30, -L * 0.13), Vector2(-L * 0.05, -L * 0.10),
		Vector2(L * 0.08, -L * 0.07), Vector2(L * 0.08, L * 0.07), Vector2(-L * 0.05, L * 0.10),
		Vector2(-L * 0.30, L * 0.13)]), col)
	_tri(c, Vector2(-L * 0.38, 0), Vector2(-L * 0.52, -L * 0.14), Vector2(-L * 0.46, 0), acc)
	_tri(c, Vector2(-L * 0.38, 0), Vector2(-L * 0.52, L * 0.14), Vector2(-L * 0.46, 0), acc)
	_eye(c, Vector2(L * 0.0, -L * 0.03), L * 0.04)


static func _angler(c: CanvasItem, L: float, col: Color, acc: Color, t: float) -> void:
	var wag := sin(t * 6.0) * L * 0.05
	_tri(c, Vector2(-L * 0.28, 0), Vector2(-L * 0.50, -L * 0.18 + wag), Vector2(-L * 0.50, L * 0.18 + wag), col.darkened(0.2))
	_ell(c, Vector2.ZERO, L * 0.36, L * 0.26, col)
	var stalk := PackedVector2Array([Vector2(L * 0.15, -L * 0.20), Vector2(L * 0.28, -L * 0.42), Vector2(L * 0.44, -L * 0.30)])
	c.draw_polyline(stalk, col.lightened(0.2), maxf(L * 0.015, 1.0), true)
	c.draw_circle(stalk[2], L * 0.11, Color(acc.r, acc.g, acc.b, 0.22))
	c.draw_circle(stalk[2], L * 0.05, acc)
	c.draw_line(Vector2(L * 0.34, L * 0.04), Vector2(L * 0.10, L * 0.12), Color.BLACK, maxf(L * 0.02, 1.5))
	for i in 5:
		var x := L * (0.32 - 0.05 * float(i))
		_tri(c, Vector2(x, L * 0.05 + (0.32 - x / L) * L * 0.1), Vector2(x - L * 0.02, L * 0.06 + (0.32 - x / L) * L * 0.1), Vector2(x - L * 0.01, -L * 0.02), Color.WHITE)
	_eye(c, Vector2(L * 0.22, -L * 0.08), L * 0.045)


static func _chest(c: CanvasItem, L: float, col: Color, acc: Color, t: float) -> void:
	c.draw_rect(Rect2(-L * 0.5, -L * 0.18, L, L * 0.38), col)
	c.draw_rect(Rect2(-L * 0.5, -L * 0.30, L, L * 0.14), col.darkened(0.2))
	c.draw_rect(Rect2(-L * 0.07, -L * 0.30, L * 0.14, L * 0.50), acc)
	c.draw_circle(Vector2(0, -L * 0.04), L * 0.05, Color("#3a2410"))
	var s := fmod(t * 0.7, 1.0)
	c.draw_circle(Vector2(lerpf(-L * 0.4, L * 0.4, s), -L * 0.34), maxf(L * 0.03, 1.5), Color(1, 1, 0.7, 1.0 - s))


static func _bird(c: CanvasItem, L: float, col: Color, acc: Color, t: float) -> void:
	var flap := sin(t * 10.0)
	_tri(c, Vector2(-L * 0.28, 0), Vector2(-L * 0.46, -L * 0.04), Vector2(-L * 0.46, L * 0.05), acc)
	_ell(c, Vector2.ZERO, L * 0.30, L * 0.13, col)
	_tri(c, Vector2(L * 0.08, -L * 0.05), Vector2(-L * 0.20, -L * 0.05), Vector2(-L * 0.10, -L * 0.05 - L * 0.40 * flap), acc)
	c.draw_circle(Vector2(L * 0.30, -L * 0.04), L * 0.07, col)
	_tri(c, Vector2(L * 0.36, -L * 0.06), Vector2(L * 0.36, -L * 0.01), Vector2(L * 0.48, -L * 0.03), Color("#ff9a2b"))
	c.draw_circle(Vector2(L * 0.32, -L * 0.06), maxf(L * 0.015, 1.0), Color.BLACK)


static func _boat(c: CanvasItem, L: float, col: Color, acc: Color, t: float) -> void:
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(-L * 0.5, -L * 0.05), Vector2(L * 0.5, -L * 0.05),
		Vector2(L * 0.36, L * 0.16), Vector2(-L * 0.40, L * 0.16)]), col)
	c.draw_rect(Rect2(-L * 0.46, -L * 0.02, L * 0.92, L * 0.03), acc)
	c.draw_rect(Rect2(-L * 0.14, -L * 0.28, L * 0.26, L * 0.23), acc)
	c.draw_rect(Rect2(-L * 0.10, -L * 0.24, L * 0.06, L * 0.07), Color("#4a7fa0"))
	c.draw_rect(Rect2(L * 0.0, -L * 0.24, L * 0.06, L * 0.07), Color("#4a7fa0"))
	c.draw_rect(Rect2(-L * 0.02, -L * 0.40, L * 0.06, L * 0.12), Color("#c83030"))
	c.draw_line(Vector2(L * 0.30, -L * 0.05), Vector2(L * 0.30, -L * 0.36), Color("#5a3a20"), maxf(L * 0.012, 1.5))
	_tri(c, Vector2(L * 0.30, -L * 0.36), Vector2(L * 0.30, -L * 0.26), Vector2(L * 0.40, -L * 0.31), Color("#e84a3a"))


static func _diver(c: CanvasItem, L: float, col: Color, acc: Color, t: float) -> void:
	var kick := sin(t * 6.0) * L * 0.05
	_tri(c, Vector2(-L * 0.28, 0), Vector2(-L * 0.52, -L * 0.10 + kick), Vector2(-L * 0.52, L * 0.04 + kick), Color("#222a33"))
	_ell(c, Vector2.ZERO, L * 0.30, L * 0.10, col)
	c.draw_rect(Rect2(-L * 0.06, -L * 0.16, L * 0.20, L * 0.08), Color("#9aa5ad"))
	c.draw_circle(Vector2(L * 0.33, -L * 0.03), L * 0.085, acc)
	c.draw_rect(Rect2(L * 0.35, -L * 0.07, L * 0.07, L * 0.05), Color("#7fe0ff"))
	c.draw_line(Vector2(L * 0.30, L * 0.03), Vector2(L * 0.60, L * 0.03), Color("#8a8f94"), maxf(L * 0.03, 1.5))


static func _croc(c: CanvasItem, L: float, col: Color, acc: Color, t: float) -> void:
	var wag := sin(t * 3.5) * L * 0.04
	# tail
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(-L * 0.10, -L * 0.07), Vector2(-L * 0.52, wag - L * 0.01), Vector2(-L * 0.10, L * 0.07)]), col.darkened(0.1))
	# legs
	for lx in [-0.14, 0.14]:
		_ell(c, Vector2(L * lx, L * 0.09), L * 0.05, L * 0.03, col.darkened(0.25))
	# body
	_ell(c, Vector2(L * 0.0, 0.0), L * 0.30, L * 0.095, col)
	_ell(c, Vector2(L * 0.02, L * 0.05), L * 0.26, L * 0.04, acc)
	# back ridge
	for i in 7:
		var rx := -L * 0.2 + L * 0.065 * float(i)
		_tri(c, Vector2(rx - L * 0.02, -L * 0.08), Vector2(rx + L * 0.02, -L * 0.08), Vector2(rx, -L * 0.125), col.darkened(0.3))
	# head and jaws
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(L * 0.22, -L * 0.07), Vector2(L * 0.52, -L * 0.03), Vector2(L * 0.52, L * 0.0), Vector2(L * 0.22, L * 0.02)]), col.lightened(0.05))
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(L * 0.22, L * 0.02), Vector2(L * 0.50, L * 0.0), Vector2(L * 0.48, L * 0.035), Vector2(L * 0.22, L * 0.07)]), acc)
	for i in 5:
		var tx := L * (0.28 + 0.045 * float(i))
		_tri(c, Vector2(tx, L * 0.0), Vector2(tx + L * 0.015, L * 0.0), Vector2(tx + L * 0.007, L * 0.025), Color.WHITE)
	_ell(c, Vector2(L * 0.25, -L * 0.075), L * 0.025, L * 0.022, col.darkened(0.15))
	_eye(c, Vector2(L * 0.25, -L * 0.078), L * 0.014)


static func _seahorse(c: CanvasItem, L: float, col: Color, acc: Color, t: float) -> void:
	var sway := sin(t * 3.0) * L * 0.04
	# curled tail
	for i in 11:
		var k := float(i) / 10.0
		var p := Vector2(sin(k * 3.2 + t * 1.2) * L * 0.07 + L * 0.02 * k, L * 0.12 + k * L * 0.34)
		_ell(c, p, lerpf(L * 0.1, L * 0.03, k), lerpf(L * 0.1, L * 0.03, k), col.darkened(0.08 * k))
	# body
	_ell(c, Vector2(0.0, -L * 0.08), L * 0.15, L * 0.28, col)
	_ell(c, Vector2(L * 0.04, -L * 0.04), L * 0.08, L * 0.2, acc)
	# dorsal fin
	_tri(c, Vector2(-L * 0.12, -L * 0.16 + sway), Vector2(-L * 0.12, L * 0.02 - sway), Vector2(-L * 0.26, -L * 0.07), acc.darkened(0.1))
	# head, snout, crest
	_ell(c, Vector2(L * 0.07, -L * 0.37), L * 0.12, L * 0.11, col)
	c.draw_colored_polygon(PackedVector2Array([Vector2(L * 0.14, -L * 0.40), Vector2(L * 0.34, -L * 0.37), Vector2(L * 0.34, -L * 0.34), Vector2(L * 0.14, -L * 0.33)]), col.lightened(0.1))
	_tri(c, Vector2(-L * 0.03, -L * 0.45), Vector2(L * 0.06, -L * 0.47), Vector2(-L * 0.1, -L * 0.57), col.darkened(0.2))
	_eye(c, Vector2(L * 0.1, -L * 0.39), L * 0.03)


static func _octopus(c: CanvasItem, L: float, col: Color, acc: Color, t: float) -> void:
	for i in 8:
		var x0 := (float(i) - 3.5) * L * 0.075
		var pts := PackedVector2Array()
		for j in 9:
			var k := float(j) / 8.0
			pts.append(Vector2(x0 * (1.0 + k * 1.1) + sin(t * 3.0 + float(i) + k * 5.0) * L * 0.05 * k, L * 0.0 + k * L * 0.5))
		c.draw_polyline(pts, col.darkened(0.12), maxf(L * 0.07, 1.5))
		c.draw_polyline(pts, acc, maxf(L * 0.015, 1.0))
	_ell(c, Vector2(0.0, -L * 0.12), L * 0.30, L * 0.28, col)
	_ell(c, Vector2(-L * 0.06, -L * 0.2), L * 0.14, L * 0.1, col.lightened(0.2))
	_eye(c, Vector2(L * 0.1, -L * 0.07), L * 0.05)
	_eye(c, Vector2(-L * 0.08, -L * 0.07), L * 0.045)
