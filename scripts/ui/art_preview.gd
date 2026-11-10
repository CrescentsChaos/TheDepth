class_name ArtPreview
extends Control
## Control that draws a creature/shark shape scaled to fit (bestiary, shark select).

var shape := "fish"
var color := Color.WHITE
var accent := Color.WHITE
var body_len := 40.0
var silhouette := false
var sprites: SpriteSet = null
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if sprites != null and sprites.smooth:
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var k := minf(size.x * 0.8, size.y * 1.6) / maxf(body_len, 1.0)
	if sprites != null:
		# fit by the real sprite proportions so tall art doesn't overflow
		var h := body_len * sprites.scale_mul * sprites.aspect()
		k = minf(size.x * 0.8 / maxf(body_len * sprites.scale_mul, 1.0), size.y * 0.9 / maxf(h, 1.0))
	draw_set_transform(size * 0.5, 0.0, Vector2(k, k))
	var c := Color(0.02, 0.05, 0.1, 0.9) if silhouette else color
	var a := Color(0.02, 0.05, 0.1, 0.9) if silhouette else accent
	if sprites != null:
		sprites.draw(self, body_len, _t, "swim", true, true, c if silhouette else Color.WHITE)
	else:
		CreatureArt.draw(self, shape, body_len, c, a, _t)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
