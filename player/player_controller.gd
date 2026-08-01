extends CharacterBody2D
class_name PlayerController

enum State { IDLE, WALK, ATTACK, HURT }

@export var character_stats: CharacterStats
@export var input_prefix: String = "p1"
@export var depth_bounds: Vector2 = Vector2(-40.0, 40.0)

var state: State = State.IDLE
var facing_dir: float = 1.0

@onready var visual: Polygon2D = $Visual
@onready var facing_indicator: Polygon2D = $FacingIndicator
@onready var hitbox: Hitbox = $Hitbox
@onready var hurtbox: Hurtbox = $Hurtbox

func _ready() -> void:
	if character_stats:
		visual.color = character_stats.display_color
	hurtbox.owner_body = self

func _physics_process(delta: float) -> void:
	velocity = Vector2.ZERO
	_process_movement(delta)
	move_and_slide()
	position.y = clamp(position.y, depth_bounds.x, depth_bounds.y)
	_update_visual()

func _process_movement(delta: float) -> void:
	var input_dir := Vector2(
		Input.get_action_strength(input_prefix + "_move_right", true) - Input.get_action_strength(input_prefix + "_move_left", true),
		Input.get_action_strength(input_prefix + "_move_down", true) - Input.get_action_strength(input_prefix + "_move_up", true)
	)
	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()

	velocity.x = input_dir.x * character_stats.move_speed
	velocity.y = input_dir.y * character_stats.depth_speed

	if input_dir.x != 0.0:
		facing_dir = sign(input_dir.x)

	state = State.WALK if input_dir.length() > 0.01 else State.IDLE

func _update_visual() -> void:
	facing_indicator.position.x = 14.0 * facing_dir
