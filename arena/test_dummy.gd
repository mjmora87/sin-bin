extends Node2D
class_name TestDummy

@export var auto_attack_enabled: bool = false
@export var auto_attack_interval_sec: float = 2.0
@export var auto_attack_damage: int = 10
@export var auto_attack_knockback: float = 260.0

var hits_taken: int = 0
var last_hit_amount: int = 0
var last_knockback_force: float = 0.0
var _attack_cycle_timer: float = 0.0

@onready var hurtbox: Hurtbox = $Hurtbox
@onready var attack_hitbox: Hitbox = $AttackHitbox

func _ready() -> void:
	hurtbox.owner_body = self

func _physics_process(delta: float) -> void:
	if not auto_attack_enabled:
		return
	_attack_cycle_timer -= delta
	if _attack_cycle_timer <= 0.0:
		_attack_cycle_timer = auto_attack_interval_sec
		attack_hitbox.activate(auto_attack_damage, auto_attack_knockback, self, hurtbox)
	elif _attack_cycle_timer <= auto_attack_interval_sec - 0.2:
		attack_hitbox.deactivate()

func take_damage(amount: int, knockback_force: float, source_position: Vector2) -> void:
	hits_taken += 1
	last_hit_amount = amount
	last_knockback_force = knockback_force
	print("TestDummy hit #%d for %d dmg (kb=%.1f) from %s" % [hits_taken, amount, knockback_force, source_position])
