extends Area2D
class_name Hitbox

var damage: int = 0
var knockback_force: float = 0.0
var source: Node2D = null
var exclude: Node = null

func _ready() -> void:
	monitoring = false
	area_entered.connect(_on_area_entered)

func activate(p_damage: int, p_knockback_force: float, p_source: Node2D, p_exclude: Node = null) -> void:
	damage = p_damage
	knockback_force = p_knockback_force
	source = p_source
	exclude = p_exclude
	monitoring = true

func deactivate() -> void:
	monitoring = false

func _on_area_entered(area: Area2D) -> void:
	var source_pos: Vector2 = source.global_position if source else global_position
	DamageDispatch.try_deal_damage(area, damage, knockback_force, source, source_pos, exclude)
