extends Area2D
class_name Puck

const THROW_SPEED := 480.0
const DAMAGE := 12
const STUN_KNOCKBACK := 60.0

var is_thrown: bool = false
var velocity: Vector2 = Vector2.ZERO

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func _physics_process(delta: float) -> void:
	if is_thrown:
		global_position += velocity * delta

func _on_body_entered(body: Node) -> void:
	if is_thrown:
		return
	if body.has_method("pick_up_puck"):
		body.pick_up_puck(self)

func _on_area_entered(area: Area2D) -> void:
	if is_thrown and area.is_in_group("hurtbox") and area.has_method("take_damage"):
		area.take_damage(DAMAGE, STUN_KNOCKBACK, global_position)
		queue_free()

func attach_to_carrier(carrier: Node) -> void:
	monitoring = false
	monitorable = false

func throw(direction: Vector2, new_parent: Node, from_global_position: Vector2) -> void:
	var old_parent := get_parent()
	if old_parent:
		old_parent.remove_child(self)
	new_parent.add_child(self)
	global_position = from_global_position
	monitoring = true
	monitorable = true
	is_thrown = true
	velocity = direction.normalized() * THROW_SPEED
