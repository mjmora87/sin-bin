extends Resource
class_name CharacterStats

@export var character_name: String = ""
@export var move_speed: float = 220.0
@export var depth_speed: float = 160.0
@export var max_hp: int = 100
@export var combo_damage: Array[int] = [10, 10, 16]
@export var combo_window_sec: float = 0.6
@export var knockback_force: float = 220.0
@export var finisher_knockback_force: float = 420.0
@export var special_cooldown_sec: float = 4.0
@export var special_behavior: SpecialBehavior
@export var iframe_duration_sec: float = 0.6
@export var display_color: Color = Color.WHITE
