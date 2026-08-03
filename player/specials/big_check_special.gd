extends SpecialBehavior
class_name BigCheckSpecial

const RANGE := 70.0
const DAMAGE := 24

func execute(controller) -> void:
	var space_state: PhysicsDirectSpaceState2D = controller.get_world_2d().direct_space_state
	var shape := CircleShape2D.new()
	shape.radius = RANGE

	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.transform = Transform2D(0, controller.global_position + Vector2(RANGE * controller.facing_dir, 0))
	params.collide_with_areas = true
	params.collide_with_bodies = false

	var hits: Array = space_state.intersect_shape(params)
	for hit in hits:
		var area: Area2D = hit["collider"]
		if area == controller.hurtbox:
			continue
		if area.is_in_group("hurtbox") and area.has_method("take_damage"):
			area.take_damage(DAMAGE, controller.character_stats.finisher_knockback_force, controller.global_position)
