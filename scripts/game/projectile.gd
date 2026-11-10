class_name Projectile
extends Node2D
## Harpoon fired by divers.

var game: Node
var velocity := Vector2.ZERO
var damage := 12.0
var life := 4.0


func _physics_process(delta: float) -> void:
	life -= delta
	position += velocity * delta
	if life <= 0.0 or game.is_solid(position, 2.0):
		queue_free()
		return
	var s: Shark = game.shark
	if s.alive and position.distance_to(s.global_position) < s.length * 0.3:
		s.take_damage(damage, "a harpoon")
		queue_free()
		return
	rotation = velocity.angle()
	queue_redraw()


func _draw() -> void:
	draw_line(Vector2(-20, 0), Vector2(8, 0), Color("#c9d3dc"), 2.5)
	draw_colored_polygon(PackedVector2Array([Vector2(8, -4), Vector2(8, 4), Vector2(16, 0)]), Color("#e8eef2"))
