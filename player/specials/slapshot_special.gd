extends SpecialBehavior
class_name SlapshotSpecial

const PROJECTILE_SCENE := preload("res://player/slapshot_projectile.tscn")
const DAMAGE := 18
const SPEED := 520.0

func execute(controller) -> void:
	var projectile := PROJECTILE_SCENE.instantiate()
	controller.get_tree().current_scene.add_child(projectile)
	projectile.global_position = controller.global_position
	projectile.setup(Vector2(controller.facing_dir, 0) * SPEED, DAMAGE, controller.character_stats.knockback_force)
