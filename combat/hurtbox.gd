extends Area2D
class_name Hurtbox

@export var owner_body = null

func _ready() -> void:
	add_to_group("hurtbox")

func take_damage(amount: int, knockback_force: float, source_position: Vector2) -> void:
	if owner_body and owner_body.has_method("take_damage"):
		owner_body.take_damage(amount, knockback_force, source_position)
