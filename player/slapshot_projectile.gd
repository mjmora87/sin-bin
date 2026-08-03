extends Area2D
class_name SlapshotProjectile

var velocity: Vector2 = Vector2.ZERO
var damage: int = 0
var knockback_force: float = 0.0
var caster_hurtbox: Node = null

func setup(p_velocity: Vector2, p_damage: int, p_knockback_force: float) -> void:
	velocity = p_velocity
	damage = p_damage
	knockback_force = p_knockback_force

func _physics_process(delta: float) -> void:
	global_position += velocity * delta

func _on_area_entered(area: Area2D) -> void:
	if area == caster_hurtbox:
		return
	if area.is_in_group("hurtbox") and area.has_method("take_damage"):
		area.take_damage(damage, knockback_force, global_position)
		queue_free()

func _on_screen_exited() -> void:
	queue_free()
