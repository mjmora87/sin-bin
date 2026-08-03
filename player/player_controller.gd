extends CharacterBody2D
class_name PlayerController

enum State { IDLE, WALK, ATTACK, HURT }

@export var character_stats: CharacterStats
@export var input_prefix: String = "p1"
@export var depth_bounds: Vector2 = Vector2(-40.0, 40.0)

var state: State = State.IDLE
var facing_dir: float = 1.0
var combo_state: ComboState
var current_attack_hit: int = 0
var attack_timer: float = 0.0
var special_cooldown_remaining: float = 0.0
var iframe_remaining: float = 0.0
var knockback_velocity: Vector2 = Vector2.ZERO
var carried_puck: Puck = null

const ATTACK_ACTIVE_DURATION := 0.18
const KNOCKBACK_DECAY := 800.0

@onready var visual: Polygon2D = $Visual
@onready var facing_indicator: Polygon2D = $FacingIndicator
@onready var hitbox: Hitbox = $Hitbox
@onready var hurtbox: Hurtbox = $Hurtbox

func _ready() -> void:
	combo_state = ComboState.new()
	if character_stats:
		visual.color = character_stats.display_color
	hurtbox.owner_body = self

func _physics_process(delta: float) -> void:
	combo_state.tick(delta)
	special_cooldown_remaining = max(0.0, special_cooldown_remaining - delta)
	iframe_remaining = max(0.0, iframe_remaining - delta)
	velocity = Vector2.ZERO

	match state:
		State.IDLE, State.WALK:
			_process_movement(delta)
			_process_attack_input()
			_process_special_input()
		State.ATTACK:
			_process_attack_timer(delta)

	knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	velocity += knockback_velocity

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

func _process_attack_input() -> void:
	if not Input.is_action_just_pressed(input_prefix + "_attack", true):
		return

	if carried_puck:
		var puck := carried_puck
		carried_puck = null
		var throw_pos := global_position + Vector2(20.0 * facing_dir, 0.0)
		puck.throw(Vector2(facing_dir, 0.0), get_tree().current_scene, throw_pos)
		return

	current_attack_hit = combo_state.register_attack_press(character_stats.combo_window_sec)
	attack_timer = ATTACK_ACTIVE_DURATION
	state = State.ATTACK
	var damage: int = character_stats.combo_damage[current_attack_hit - 1]
	var knockback: float = character_stats.finisher_knockback_force if combo_state.is_finisher() else character_stats.knockback_force
	hitbox.position.x = 20.0 * facing_dir
	hitbox.activate(damage, knockback, self, hurtbox)

func _process_attack_timer(delta: float) -> void:
	attack_timer -= delta
	if attack_timer <= 0.0:
		hitbox.deactivate()
		state = State.IDLE

func _process_special_input() -> void:
	if special_cooldown_remaining > 0.0:
		return
	if not Input.is_action_just_pressed(input_prefix + "_special", true):
		return
	special_cooldown_remaining = character_stats.special_cooldown_sec
	if character_stats.special_behavior:
		character_stats.special_behavior.execute(self)

func take_damage(amount: int, knockback_force: float, source_position: Vector2) -> void:
	if iframe_remaining > 0.0:
		return
	iframe_remaining = character_stats.iframe_duration_sec
	var away := global_position - source_position
	if away.length() < 0.01:
		away = Vector2(-facing_dir, 0.0)
	knockback_velocity = away.normalized() * knockback_force

func pick_up_puck(puck: Puck) -> void:
	if carried_puck:
		return
	carried_puck = puck
	_attach_carried_puck.call_deferred(puck)

func _attach_carried_puck(puck: Puck) -> void:
	puck.get_parent().remove_child(puck)
	add_child(puck)
	puck.position = Vector2(10.0, -6.0)
	puck.attach_to_carrier(self)

func _update_visual() -> void:
	facing_indicator.position.x = 14.0 * facing_dir
	visual.modulate.a = 0.5 if iframe_remaining > 0.0 and int(iframe_remaining * 10) % 2 == 0 else 1.0
