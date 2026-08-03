class_name DamageDispatch

static func try_deal_damage(area: Area2D, damage: int, knockback_force: float, source: Node, source_position: Vector2, exclude: Node = null) -> bool:
	if area == exclude:
		return false
	if not (area.is_in_group("hurtbox") and area.has_method("take_damage")):
		return false
	if source is PlayerController and area.get("owner_body") is PlayerController:
		return false
	area.take_damage(damage, knockback_force, source_position)
	return true
