extends Node2D
class_name TestDummy

var hits_taken: int = 0
var last_hit_amount: int = 0
var last_knockback_force: float = 0.0

@onready var hurtbox: Hurtbox = $Hurtbox

func _ready() -> void:
	hurtbox.owner_body = self

func take_damage(amount: int, knockback_force: float, source_position: Vector2) -> void:
	hits_taken += 1
	last_hit_amount = amount
	last_knockback_force = knockback_force
	print("TestDummy hit #%d for %d dmg (kb=%.1f) from %s" % [hits_taken, amount, knockback_force, source_position])
