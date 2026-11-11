class_name SpriteSet
extends RefCounted
## Artist-supplied sprites for ONE creature or shark, with a few animations.
##
## Drop PNGs into   res://assets/sprites/<kind>/<id>/      (kind = creatures | sharks,
## id = the "id" in data/creatures.json or data/sharks.json)
##
##   swim.png     looping, default animation (the only required one)
##   idle.png     used when (almost) standing still, falls back to swim
##   attack.png   bite / lunge / shoot,              falls back to swim
##   hurt.png     when damaged,                      falls back to swim
##   boost.png    sharks only, while boosting,       falls back to swim
##
## An animation is a HORIZONTAL STRIP of equally sized frames. Put the frame count in the
## file name: swim_4.png = 4 frames side by side. No number = a single image.
## A single image stays still unless you opt in to a tail wave with "sprite_wiggle" (e.g. 0.05).
## Sprites must face RIGHT (or set "sprite_faces_left": true in the JSON).
##
## AUTO SIZE: the game measures the visible (non-transparent) pixels of your frames and scales
## the sprite so that visible body width = the entry's `length`. Canvas size and empty padding
## therefore don't matter: the same 256x128 canvas for every fish still gives a small sardine
## and a big tuna. Keep all animations of one creature on the same canvas size.
##
## Optional JSON fields: sprite_fps (8), sprite_scale (1.0), sprite_faces_left (false),
## sprite_smooth (false), sprite_autosize (true), sprite_wiggle (0 = off), and the old single-image
## "sprite": "res://...png" + "sprite_frames".

const ROOT := "res://assets/sprites/"
const ANIMS := ["swim", "idle", "attack", "hurt", "boost"]
const MAX_FRAMES := 32
const WIGGLE_SPEED := 8.0
const WIGGLE_SLICES := 8

static var _cache := {}

var anims := {}
var fps := 8.0
var scale_mul := 1.0
var faces_left := false
var smooth := false
var autosize := true
var wiggle_amount := 0.0
## Texture filter the owning node should use (see apply_filter). Big hand-drawn art gets mipmaps so it
## stays smooth when shrunk to a few dozen pixels; small pixel art stays crisp.
var filter_mode := CanvasItem.TEXTURE_FILTER_NEAREST
## Visible area of the art as a 0..1 rectangle of one frame (union of all frames/animations).
var content := Rect2(0.0, 0.0, 1.0, 1.0)


## Returns the SpriteSet for this definition, or null if no art was supplied
## (the procedural vector art is used then).
static func for_def(kind: String, def: Dictionary) -> SpriteSet:
	if not def.has("id"):
		return null
	var key := "%s/%s" % [kind, str(def["id"])]
	if _cache.has(key):
		return _cache[key]
	var s := SpriteSet.new()
	s._read(kind, def)
	if s.anims.is_empty():
		s = null
	_cache[key] = s
	return s


static func clear_cache() -> void:
	_cache.clear()


func _read(kind: String, def: Dictionary) -> void:
	fps = maxf(float(def.get("sprite_fps", 8.0)), 0.1)
	scale_mul = maxf(float(def.get("sprite_scale", 1.0)), 0.01)
	faces_left = bool(def.get("sprite_faces_left", false))
	smooth = bool(def.get("sprite_smooth", false))
	autosize = bool(def.get("sprite_autosize", true))
	wiggle_amount = clampf(float(def.get("sprite_wiggle", 0.0)), 0.0, 0.3)
	var folder := "%s%s/%s/" % [ROOT, kind, str(def["id"])]
	for a in ANIMS:
		_find_anim(str(a), folder)
	# Old style: one explicit image path in the JSON (overrides the folder's swim).
	var legacy := str(def.get("sprite", ""))
	if legacy != "" and ResourceLoader.exists(legacy):
		_add("swim", load(legacy) as Texture2D, maxi(1, int(def.get("sprite_frames", 1))))
	content = _measure() if autosize else Rect2(0.0, 0.0, 1.0, 1.0)
	_prepare_textures()


## Big textures are shown much smaller than they are. Without mipmaps that aliases (shimmering,
## jagged, "distorted" art), so build them at load time. Pixel art (small frames) is left alone.
func _prepare_textures() -> void:
	var hires := false
	for k in anims.keys():
		var a: Dictionary = anims[k]
		var tex: Texture2D = a["tex"]
		var fw := float(tex.get_width()) / float(int(a["frames"]))
		if fw <= 256.0 and not smooth:
			continue
		hires = true
		var img := tex.get_image()
		if img == null:
			continue
		if img.is_compressed():
			img.decompress()
		img.generate_mipmaps()
		a["tex"] = ImageTexture.create_from_image(img)
	if smooth or hires:
		filter_mode = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC


func apply_filter(node: CanvasItem) -> void:
	node.texture_filter = filter_mode


## Union of the visible pixels over every frame of every animation, as 0..1 of one frame.
func _measure() -> Rect2:
	var total := Rect2()
	var have := false
	for a in anims.values():
		var tex: Texture2D = a["tex"]
		var n := int(a["frames"])
		var img := tex.get_image()
		if img == null:
			continue
		if img.is_compressed():
			img.decompress()
		var fw := img.get_width() / n
		var fh := img.get_height()
		if fw < 1 or fh < 1:
			continue
		for f in n:
			var r := img.get_region(Rect2i(f * fw, 0, fw, fh)).get_used_rect()
			if r.size.x < 1 or r.size.y < 1:
				continue
			var nr := Rect2(float(r.position.x) / float(fw), float(r.position.y) / float(fh),
				float(r.size.x) / float(fw), float(r.size.y) / float(fh))
			total = nr if not have else total.merge(nr)
			have = true
	if not have or total.size.x <= 0.01 or total.size.y <= 0.01:
		return Rect2(0.0, 0.0, 1.0, 1.0)
	return total


func _find_anim(anim: String, folder: String) -> void:
	var base := folder + anim
	if ResourceLoader.exists(base + ".png"):
		_add(anim, load(base + ".png") as Texture2D, 1)
		return
	for n in range(2, MAX_FRAMES + 1):
		var p := "%s_%d.png" % [base, n]
		if ResourceLoader.exists(p):
			_add(anim, load(p) as Texture2D, n)
			return


func _add(anim: String, tex: Texture2D, frames: int) -> void:
	if tex == null:
		return
	anims[anim] = {"tex": tex, "frames": frames}


func has_anim(anim: String) -> bool:
	return anims.has(anim)


func _pick(anim: String) -> Dictionary:
	if anims.has(anim):
		return anims[anim]
	if anims.has("swim"):
		return anims["swim"]
	if anims.is_empty():
		return {}
	return anims.values()[0]


## Height / width of the visible art (used to fit previews).
func aspect(anim: String = "swim") -> float:
	var a := _pick(anim)
	if a.is_empty():
		return 0.5
	var tex: Texture2D = a["tex"]
	var fw := float(tex.get_width()) / float(int(a["frames"]))
	return float(tex.get_height()) * content.size.y / maxf(fw * content.size.x, 1.0)


## For one-shot animations (hurt, attack): converts progress 0..1 into a time so the
## whole strip plays exactly once, whatever the frame count / fps.
func progress_time(anim: String, progress: float) -> float:
	var a := _pick(anim)
	if a.is_empty():
		return 0.0
	return clampf(progress, 0.0, 0.999) * float(int(a["frames"])) / fps


## Draws the frame for `anim` at time `t`, centred on the canvas origin, body length L.
## Does NOT touch the canvas transform, so previews can set their own.
## wiggle: allows the optional tail wave (needs sprite_wiggle > 0; single-image sprites only).
func draw(c: CanvasItem, L: float, t: float, anim: String = "swim", loop: bool = true, wiggle: bool = true, tint: Color = Color.WHITE) -> void:
	var a := _pick(anim)
	if a.is_empty():
		return
	var tex: Texture2D = a["tex"]
	var n := int(a["frames"])
	var frame := 0
	if n > 1:
		var f := int(floor(maxf(t, 0.0) * fps))
		frame = (f % n) if loop else mini(f, n - 1)
	var fw := float(tex.get_width()) / float(n)
	# w/h = size of the WHOLE frame, chosen so the visible art is L * scale_mul wide.
	var w := L * scale_mul / content.size.x
	var h := w * float(tex.get_height()) / maxf(fw, 1.0)
	var left := -content.get_center().x * w
	var top := -content.get_center().y * h
	var u0 := float(frame) / float(n)
	var u1 := float(frame + 1) / float(n)
	if faces_left:
		var tmp := u0
		u0 = u1
		u1 = tmp
	# more slices for bigger art so the tail wave stays smooth instead of stair-stepped
	var slices := clampi(int(L / 14.0), WIGGLE_SLICES, 40) if (wiggle and n == 1 and wiggle_amount > 0.0) else 1
	var cols := PackedColorArray([tint, tint, tint, tint])
	for s in slices:
		var k0 := float(s) / float(slices)
		var k1 := float(s + 1) / float(slices)
		var x0 := left + w * k0
		var x1 := left + w * k1
		var o0 := 0.0
		var o1 := 0.0
		if slices > 1:
			# 0 at the head, 1 at the tail (tail is on the left unless the art faces left)
			var tail0 := _tail(k0)
			var tail1 := _tail(k1)
			o0 = sin(t * WIGGLE_SPEED + tail0 * 4.0) * tail0 * h * wiggle_amount
			o1 = sin(t * WIGGLE_SPEED + tail1 * 4.0) * tail1 * h * wiggle_amount
		var pts := PackedVector2Array([
			Vector2(x0, top + o0), Vector2(x1, top + o1),
			Vector2(x1, top + h + o1), Vector2(x0, top + h + o0)])
		var uv := PackedVector2Array([
			Vector2(lerpf(u0, u1, k0), 0.0), Vector2(lerpf(u0, u1, k1), 0.0),
			Vector2(lerpf(u0, u1, k1), 1.0), Vector2(lerpf(u0, u1, k0), 1.0)])
		c.draw_primitive(pts, cols, uv, tex)


## 0 at the head, 1 at the tail, measured over the visible art (k = 0..1 across the frame).
func _tail(k: float) -> float:
	if faces_left:
		return clampf((k - content.position.x) / content.size.x, 0.0, 1.0)
	return clampf((content.end.x - k) / content.size.x, 0.0, 1.0)
